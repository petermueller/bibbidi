defmodule Bibbidi.Commands.SessionTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.Session
  alias Bibbidi.Connection

  setup do
    {:ok, conn} =
      Connection.start_link(
        url: "ws://localhost:1234",
        transport: Bibbidi.MockTransport,
        transport_opts: [owner: self()]
      )

    %{conn: conn}
  end

  defp reply(conn, id, result \\ %{}) do
    send(conn, {:mock_transport_receive, [{:text, JSON.encode!(%{id: id, result: result})}]})
  end

  describe "new/2" do
    test "sends session.new command with default capabilities", %{conn: conn} do
      task = Task.async(fn -> Session.new(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "session.new"
      assert decoded["params"]["capabilities"] == %{}

      reply(conn, decoded["id"], %{sessionId: "session-1", capabilities: %{}})
      assert {:ok, %{"sessionId" => "session-1"}} = Task.await(task)
    end

    test "sends session.new command with custom capabilities", %{conn: conn} do
      caps = %{alwaysMatch: %{browserName: "chrome"}}
      task = Task.async(fn -> Session.new(conn, caps) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["capabilities"] == %{"alwaysMatch" => %{"browserName" => "chrome"}}

      reply(conn, decoded["id"], %{sessionId: "session-1", capabilities: %{}})
      Task.await(task)
    end
  end

  describe "end_session/1" do
    test "sends session.end command", %{conn: conn} do
      task = Task.async(fn -> Session.end_session(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "session.end"
      assert decoded["params"] == %{}

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "status/1" do
    test "sends session.status command", %{conn: conn} do
      task = Task.async(fn -> Session.status(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "session.status"
      assert decoded["params"] == %{}

      reply(conn, decoded["id"], %{ready: true, message: "ready"})
      assert {:ok, %{"ready" => true}} = Task.await(task)
    end
  end

  describe "subscribe/3" do
    test "sends session.subscribe command", %{conn: conn} do
      task = Task.async(fn -> Session.subscribe(conn, ["browsingContext.load"]) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "session.subscribe"
      assert decoded["params"]["events"] == ["browsingContext.load"]
      refute Map.has_key?(decoded["params"], "contexts")

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "includes contexts option", %{conn: conn} do
      task =
        Task.async(fn ->
          Session.subscribe(conn, ["log.entryAdded"], contexts: ["ctx-1"])
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["contexts"] == ["ctx-1"]

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "unsubscribe/3" do
    test "sends session.unsubscribe command", %{conn: conn} do
      task = Task.async(fn -> Session.unsubscribe(conn, ["browsingContext.load"]) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "session.unsubscribe"
      assert decoded["params"]["events"] == ["browsingContext.load"]

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end
end
