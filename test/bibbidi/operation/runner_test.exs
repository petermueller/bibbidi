defmodule Bibbidi.Operation.RunnerTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Connection
  alias Bibbidi.Operation.Runner
  alias Bibbidi.Commands.BrowsingContext
  alias Bibbidi.Test.{NavigateAndGetTree, LocateAndActivate}

  setup do
    {:ok, conn} =
      Connection.start_link(
        url: "ws://localhost:1234",
        transport: Bibbidi.MockTransport,
        transport_opts: [owner: self()]
      )

    %{conn: conn}
  end

  defp mock_reply(conn, result) do
    assert_receive {:mock_transport_send, json}
    decoded = JSON.decode!(json)

    send(
      conn,
      {:mock_transport_receive,
       [{:text, JSON.encode!(%{id: decoded["id"], result: result})}]}
    )

    decoded
  end

  describe "execute/3 with a single leaf command" do
    test "sends command and returns result with operation", %{conn: conn} do
      cmd = %BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}

      task = Task.async(fn -> Runner.execute(conn, cmd) end)

      decoded = mock_reply(conn, %{navigation: "nav-1", url: "https://example.com"})

      assert decoded["method"] == "browsingContext.navigate"
      assert decoded["params"]["context"] == "ctx-1"

      assert {:ok, result, op} = Task.await(task)
      assert result == %{"navigation" => "nav-1", "url" => "https://example.com"}
      assert op.status == :completed
      assert op.intent == cmd
      assert length(op.steps) == 1

      [step] = op.steps
      assert step.command == cmd
      assert step.response == result
      assert step.sent_at <= step.received_at
      assert op.started_at <= op.ended_at
    end

    test "returns error with operation on failure", %{conn: conn} do
      cmd = %BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"}

      task = Task.async(fn -> Runner.execute(conn, cmd) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)

      send(
        conn,
        {:mock_transport_receive,
         [
           {:text,
            JSON.encode!(%{
              id: decoded["id"],
              error: "unknown error",
              message: "something went wrong"
            })}
         ]}
      )

      assert {:error, _reason, op} = Task.await(task)
      assert op.status == :failed
      assert length(op.steps) == 1
    end
  end

  describe "execute/3 with a sequence" do
    test "runs all commands in order", %{conn: conn} do
      # Define a custom expandable that produces a sequence
      cmd = %NavigateAndGetTree{context: "ctx-1", url: "https://example.com"}

      task = Task.async(fn -> Runner.execute(conn, cmd) end)

      # First command: navigate
      decoded1 = mock_reply(conn, %{navigation: "nav-1", url: "https://example.com"})
      assert decoded1["method"] == "browsingContext.navigate"

      # Second command: getTree
      decoded2 = mock_reply(conn, %{contexts: []})
      assert decoded2["method"] == "browsingContext.getTree"

      assert {:ok, result, op} = Task.await(task)
      assert result == %{"contexts" => []}
      assert op.status == :completed
      assert length(op.steps) == 2
    end

    test "stops on first error in sequence", %{conn: conn} do
      cmd = %NavigateAndGetTree{context: "ctx-1", url: "https://bad.com"}

      task = Task.async(fn -> Runner.execute(conn, cmd) end)

      # First command fails
      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)

      send(
        conn,
        {:mock_transport_receive,
         [
           {:text,
            JSON.encode!(%{id: decoded["id"], error: "navigation failed", message: "bad url"})}
         ]}
      )

      assert {:error, _reason, op} = Task.await(task)
      assert op.status == :failed
      assert length(op.steps) == 1
    end
  end

  describe "execute/3 with continuations" do
    test "handles dynamic branching", %{conn: conn} do
      cmd = %LocateAndActivate{context: "ctx-1", selector: "h1"}

      task = Task.async(fn -> Runner.execute(conn, cmd) end)

      # First: locateNodes
      decoded1 = mock_reply(conn, %{nodes: [%{type: "node", value: %{}}]})
      assert decoded1["method"] == "browsingContext.locateNodes"

      # Continuation returns activate
      decoded2 = mock_reply(conn, %{})
      assert decoded2["method"] == "browsingContext.activate"

      assert {:ok, _result, op} = Task.await(task)
      assert op.status == :completed
      assert length(op.steps) == 2
    end

    test "handles halt from continuation", %{conn: conn} do
      cmd = %LocateAndActivate{context: "ctx-1", selector: "h1"}

      task = Task.async(fn -> Runner.execute(conn, cmd) end)

      # locateNodes returns empty — handler halts
      mock_reply(conn, %{nodes: []})

      assert {:ok, {:error, :not_found}, op} = Task.await(task)
      assert op.status == :completed
      assert length(op.steps) == 1
    end
  end

  describe "operation metadata" do
    test "generates unique operation IDs", %{conn: conn} do
      cmd = %BrowsingContext.Activate{context: "ctx-1"}

      task1 = Task.async(fn -> Runner.execute(conn, cmd) end)
      mock_reply(conn, %{})
      {:ok, _, op1} = Task.await(task1)

      task2 = Task.async(fn -> Runner.execute(conn, cmd) end)
      mock_reply(conn, %{})
      {:ok, _, op2} = Task.await(task2)

      assert op1.id != op2.id
      assert String.starts_with?(op1.id, "op_")
    end
  end
end
