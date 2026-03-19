defmodule Bibbidi.ConnectionTest do
  use ExUnit.Case, async: true

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

  describe "send_command/3" do
    test "sends JSON and correlates response", %{conn: conn} do
      # Send command in a task so we can intercept and reply
      task =
        Task.async(fn ->
          Connection.send_command(conn, "session.status", %{})
        end)

      # Wait for the transport to receive the encoded command
      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "session.status"
      id = decoded["id"]

      # Simulate server response
      response = JSON.encode!(%{id: id, result: %{ready: true, message: "ok"}})
      send(conn, {:mock_transport_receive, [{:text, response}]})

      assert {:ok, %{"ready" => true}} = Task.await(task)
    end

    test "returns error for error responses", %{conn: conn} do
      task =
        Task.async(fn ->
          Connection.send_command(conn, "bad.command", %{})
        end)

      assert_receive {:mock_transport_send, json}
      id = JSON.decode!(json)["id"]

      response = JSON.encode!(%{id: id, error: "unknown command", message: "nope"})
      send(conn, {:mock_transport_receive, [{:text, response}]})

      assert {:error, %{error: "unknown command"}} = Task.await(task)
    end
  end

  describe "subscribe/3 and events" do
    test "dispatches events to subscribers", %{conn: conn} do
      :ok = Connection.subscribe(conn, "browsingContext.load")

      event =
        JSON.encode!(%{
          method: "browsingContext.load",
          params: %{context: "ctx-1", url: "https://example.com"}
        })

      send(conn, {:mock_transport_receive, [{:text, event}]})

      assert_receive {:bibbidi_event, "browsingContext.load", %{"context" => "ctx-1"}}
    end

    test "does not dispatch after unsubscribe", %{conn: conn} do
      :ok = Connection.subscribe(conn, "browsingContext.load")
      :ok = Connection.unsubscribe(conn, "browsingContext.load")

      event =
        JSON.encode!(%{
          method: "browsingContext.load",
          params: %{context: "ctx-1"}
        })

      send(conn, {:mock_transport_receive, [{:text, event}]})

      refute_receive {:bibbidi_event, _, _}, 100
    end
  end

  describe "ping handling" do
    test "responds with pong when a ping frame is received", %{conn: conn} do
      send(conn, {:mock_transport_receive, [:ping]})
      assert_receive :mock_transport_pong
    end
  end

  describe "monitor dedup" do
    test "subscribing same pid to multiple events does not leak monitors", %{conn: conn} do
      :ok = Connection.subscribe(conn, "browsingContext.load")
      :ok = Connection.subscribe(conn, "browsingContext.domContentLoaded")

      # Both events should be dispatched
      event1 =
        JSON.encode!(%{method: "browsingContext.load", params: %{context: "ctx-1"}})

      event2 =
        JSON.encode!(%{
          method: "browsingContext.domContentLoaded",
          params: %{context: "ctx-1"}
        })

      send(conn, {:mock_transport_receive, [{:text, event1}]})
      assert_receive {:bibbidi_event, "browsingContext.load", _}

      send(conn, {:mock_transport_receive, [{:text, event2}]})
      assert_receive {:bibbidi_event, "browsingContext.domContentLoaded", _}
    end

    test "subscriber DOWN cleans up all method subscriptions", %{conn: conn} do
      subscriber = spawn(fn -> Process.sleep(:infinity) end)

      :ok = Connection.subscribe(conn, "browsingContext.load", subscriber)
      :ok = Connection.subscribe(conn, "script.message", subscriber)

      Process.exit(subscriber, :kill)
      # Give connection time to process the DOWN message
      Process.sleep(50)

      event =
        JSON.encode!(%{method: "browsingContext.load", params: %{context: "ctx-1"}})

      send(conn, {:mock_transport_receive, [{:text, event}]})
      refute_receive {:bibbidi_event, _, _}, 100
    end
  end

  describe "remote close" do
    test "replies error to pending commands when remote closes", %{conn: conn} do
      task =
        Task.async(fn ->
          Connection.send_command(conn, "session.status", %{})
        end)

      assert_receive {:mock_transport_send, _json}

      # Simulate remote close
      send(conn, {:mock_transport_receive, [{:close, 1000, "normal"}]})

      assert {:error, :connection_closed} = Task.await(task)
    end
  end

  describe "close/1" do
    test "closes the transport", %{conn: conn} do
      ref = Process.monitor(conn)
      :ok = Connection.close(conn)
      assert_receive {:DOWN, ^ref, :process, ^conn, :normal}
      assert_receive :mock_transport_closed
    end
  end
end
