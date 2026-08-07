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

  describe "subscribe/4 and events" do
    test "delivers parsed event struct directly (default wrap is identity)", %{conn: conn} do
      :ok = Connection.subscribe(conn, "browsingContext.load")

      event =
        JSON.encode!(%{
          method: "browsingContext.load",
          params: %{context: "ctx-1", url: "https://example.com"}
        })

      send(conn, {:mock_transport_receive, [{:text, event}]})

      assert_receive %Bibbidi.Events.BrowsingContext.Load{
        context: "ctx-1",
        url: "https://example.com"
      }
    end

    test "per-subscribe wrap: fn re-shapes the message", %{conn: conn} do
      :ok =
        Connection.subscribe(conn, "browsingContext.load", self(),
          wrap: fn ev -> {:my_tag, ev} end
        )

      event =
        JSON.encode!(%{method: "browsingContext.load", params: %{context: "ctx-1"}})

      send(conn, {:mock_transport_receive, [{:text, event}]})

      assert_receive {:my_tag, %Bibbidi.Events.BrowsingContext.Load{context: "ctx-1"}}
    end

    test "per-subscribe wrap: {m, f, args} prepends event to args", %{conn: conn} do
      :ok =
        Connection.subscribe(conn, "browsingContext.load", self(),
          wrap: {__MODULE__.WrapHelper, :tag, [:from_mfa, :extra]}
        )

      event =
        JSON.encode!(%{method: "browsingContext.load", params: %{context: "ctx-1"}})

      send(conn, {:mock_transport_receive, [{:text, event}]})

      # WrapHelper.tag/3 is called as: tag(event, :from_mfa, :extra)
      assert_receive {:from_mfa, %Bibbidi.Events.BrowsingContext.Load{}, :extra}
    end

    test "Application :default_event_wrapper applies when no per-subscribe wrap", %{conn: conn} do
      Application.put_env(
        :bibbidi,
        :default_event_wrapper,
        {__MODULE__.WrapHelper, :tag, [:app_default]}
      )

      on_exit(fn -> Application.delete_env(:bibbidi, :default_event_wrapper) end)

      :ok = Connection.subscribe(conn, "browsingContext.load")

      event =
        JSON.encode!(%{method: "browsingContext.load", params: %{context: "ctx-1"}})

      send(conn, {:mock_transport_receive, [{:text, event}]})

      assert_receive {:app_default, %Bibbidi.Events.BrowsingContext.Load{}}
    end

    test "per-subscribe wrap overrides Application :default_event_wrapper", %{conn: conn} do
      Application.put_env(
        :bibbidi,
        :default_event_wrapper,
        {__MODULE__.WrapHelper, :tag, [:app_default]}
      )

      on_exit(fn -> Application.delete_env(:bibbidi, :default_event_wrapper) end)

      :ok =
        Connection.subscribe(conn, "browsingContext.load", self(),
          wrap: fn ev -> {:per_subscribe, ev} end
        )

      event =
        JSON.encode!(%{method: "browsingContext.load", params: %{context: "ctx-1"}})

      send(conn, {:mock_transport_receive, [{:text, event}]})

      assert_receive {:per_subscribe, %Bibbidi.Events.BrowsingContext.Load{}}
      refute_receive {:app_default, _}, 50
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

      refute_receive %Bibbidi.Events.BrowsingContext.Load{}, 100
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
      assert_receive %Bibbidi.Events.BrowsingContext.Load{}

      send(conn, {:mock_transport_receive, [{:text, event2}]})
      assert_receive %Bibbidi.Events.BrowsingContext.DomContentLoaded{}
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
      refute_receive %Bibbidi.Events.BrowsingContext.Load{}, 100
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

  defmodule WrapHelper do
    @moduledoc false
    # Helper used by the wrap: {m, f, args} tests above. Lives in the test
    # module's namespace so it doesn't pollute the public surface.
    def tag(event, label), do: {label, event}
    def tag(event, label, extra), do: {label, event, extra}
  end
end
