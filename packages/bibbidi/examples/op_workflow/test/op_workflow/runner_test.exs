defmodule OpWorkflow.RunnerTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Connection
  alias Bibbidi.Commands.BrowsingContext
  alias OpWorkflow.{Op, Runner}

  setup do
    {:ok, conn} =
      Connection.start_link(
        url: "ws://localhost:1234",
        transport: OpWorkflow.MockTransport,
        transport_opts: [owner: self()]
      )

    %{conn: conn}
  end

  defp mock_reply(conn, result) do
    assert_receive {:mock_transport_send, json}
    decoded = JSON.decode!(json)

    send(
      conn,
      {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: result})}]}
    )

    decoded
  end

  defp mock_error(conn, error, message) do
    assert_receive {:mock_transport_send, json}
    decoded = JSON.decode!(json)

    send(
      conn,
      {:mock_transport_receive,
       [{:text, JSON.encode!(%{id: decoded["id"], error: error, message: message})}]}
    )

    decoded
  end

  describe "static sends" do
    test "runs a single send step", %{conn: conn} do
      op = Op.new() |> Op.send(:activate, %BrowsingContext.Activate{context: "ctx-1"})

      task = Task.async(fn -> Runner.execute(conn, op) end)

      decoded = mock_reply(conn, %{})
      assert decoded["method"] == "browsingContext.activate"

      assert {:ok, results, operation} = Task.await(task)
      assert {:ok, %{}} = results[:activate]
      assert operation.status == :completed
      assert length(operation.steps) == 1
    end

    test "runs multiple sends in order", %{conn: conn} do
      op =
        Op.new()
        |> Op.send(:nav, %BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"})
        |> Op.send(:tree, %BrowsingContext.GetTree{})

      task = Task.async(fn -> Runner.execute(conn, op) end)

      d1 = mock_reply(conn, %{navigation: "nav-1"})
      assert d1["method"] == "browsingContext.navigate"

      d2 = mock_reply(conn, %{contexts: []})
      assert d2["method"] == "browsingContext.getTree"

      assert {:ok, results, operation} = Task.await(task)
      assert {:ok, %{"navigation" => "nav-1"}} = results[:nav]
      assert {:ok, %{"contexts" => []}} = results[:tree]
      assert operation.status == :completed
      assert length(operation.steps) == 2
    end

    test "stops on first error", %{conn: conn} do
      op =
        Op.new()
        |> Op.send(:nav, %BrowsingContext.Navigate{context: "ctx-1", url: "https://bad.com"})
        |> Op.send(:tree, %BrowsingContext.GetTree{})

      task = Task.async(fn -> Runner.execute(conn, op) end)
      mock_error(conn, "navigation failed", "bad url")

      assert {:error, {:nav, _reason}, operation} = Task.await(task)
      assert operation.status == :failed
      assert length(operation.steps) == 1
    end
  end

  describe "dynamic sends" do
    test "send_fn can build a command from results", %{conn: conn} do
      op =
        Op.new()
        |> Op.send(:tree, %BrowsingContext.GetTree{})
        |> Op.send(:activate, fn %{tree: {:ok, %{"contexts" => [%{"context" => ctx} | _]}}} ->
          {:send, %BrowsingContext.Activate{context: ctx}}
        end)

      task = Task.async(fn -> Runner.execute(conn, op) end)

      mock_reply(conn, %{contexts: [%{context: "ctx-99"}]})
      decoded = mock_reply(conn, %{})
      assert decoded["params"]["context"] == "ctx-99"

      assert {:ok, results, _} = Task.await(task)
      assert {:ok, _} = results[:activate]
    end

    test "send_fn can short-circuit with {:ok, value}", %{conn: conn} do
      op =
        Op.new()
        |> Op.send(:cached, fn _results -> {:ok, :from_cache} end)

      task = Task.async(fn -> Runner.execute(conn, op) end)

      assert {:ok, results, _} = Task.await(task)
      assert results[:cached] == {:ok, :from_cache}
    end
  end

  describe "run steps" do
    test "run step receives conn and results", %{conn: conn} do
      op =
        Op.new()
        |> Op.run(:custom, fn conn_arg, _results, _opts ->
          # Just execute a command directly
          Bibbidi.Connection.execute(conn_arg, %BrowsingContext.Activate{context: "ctx-1"})
        end)

      task = Task.async(fn -> Runner.execute(conn, op) end)

      mock_reply(conn, %{})

      assert {:ok, results, _} = Task.await(task)
      assert {:ok, %{}} = results[:custom]
    end
  end

  describe "branch steps" do
    test "branch can send a command based on results", %{conn: conn} do
      op =
        Op.new()
        |> Op.send(:nav, %BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"})
        |> Op.branch(:maybe_tree, fn
          %{nav: {:ok, _}} -> {:send, %BrowsingContext.GetTree{}}
          %{nav: {:error, _}} -> {:error, :skipped}
        end)

      task = Task.async(fn -> Runner.execute(conn, op) end)

      mock_reply(conn, %{navigation: "nav-1"})
      mock_reply(conn, %{contexts: []})

      assert {:ok, results, _} = Task.await(task)
      assert {:ok, %{"contexts" => []}} = results[:maybe_tree]
    end

    test "branch can short-circuit with ok", %{conn: conn} do
      op = Op.new() |> Op.branch(:decision, fn _ -> {:ok, :done} end)

      task = Task.async(fn -> Runner.execute(conn, op) end)

      assert {:ok, results, _} = Task.await(task)
      assert results[:decision] == {:ok, :done}
    end

    test "branch can short-circuit with error", %{conn: conn} do
      op = Op.new() |> Op.branch(:decision, fn _ -> {:error, :nope} end)

      task = Task.async(fn -> Runner.execute(conn, op) end)

      assert {:error, {:decision, :nope}, _} = Task.await(task)
    end
  end

  describe "operation metadata" do
    test "generates unique IDs", %{conn: conn} do
      op = Op.new() |> Op.send(:a, %BrowsingContext.Activate{context: "c"})

      task1 = Task.async(fn -> Runner.execute(conn, op) end)
      mock_reply(conn, %{})
      {:ok, _, op1} = Task.await(task1)

      task2 = Task.async(fn -> Runner.execute(conn, op) end)
      mock_reply(conn, %{})
      {:ok, _, op2} = Task.await(task2)

      assert op1.id != op2.id
      assert String.starts_with?(op1.id, "op_")
    end

    test "records timing", %{conn: conn} do
      op = Op.new() |> Op.send(:a, %BrowsingContext.Activate{context: "c"})

      task = Task.async(fn -> Runner.execute(conn, op) end)
      mock_reply(conn, %{})
      {:ok, _, operation} = Task.await(task)

      assert operation.started_at <= operation.ended_at
    end

    test "records every step with command and result", %{conn: conn} do
      op =
        Op.new()
        |> Op.send(:a, %BrowsingContext.Activate{context: "c"})
        |> Op.send(:b, %BrowsingContext.GetTree{})

      task = Task.async(fn -> Runner.execute(conn, op) end)
      mock_reply(conn, %{})
      mock_reply(conn, %{contexts: []})
      {:ok, _, operation} = Task.await(task)

      assert [step_a, step_b] = operation.steps
      assert step_a.name == :a
      assert step_a.command == %BrowsingContext.Activate{context: "c"}
      assert {:ok, _} = step_a.result

      assert step_b.name == :b
      assert {:ok, %{"contexts" => []}} = step_b.result
    end

    test "partial results available on error", %{conn: conn} do
      op =
        Op.new()
        |> Op.send(:a, %BrowsingContext.Activate{context: "c"})
        |> Op.send(:b, %BrowsingContext.GetTree{})

      task = Task.async(fn -> Runner.execute(conn, op) end)
      mock_reply(conn, %{})
      mock_error(conn, "fail", "oops")

      {:error, {:b, _}, operation} = Task.await(task)
      assert {:ok, _} = operation.results[:a]
      assert operation.results[:b] == nil
    end
  end
end
