defmodule Bibbidi.Integration.EventsTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.BrowsingContext.Navigate
  alias Bibbidi.Commands.Script.Evaluate
  alias Bibbidi.Commands.Session.{Subscribe, Unsubscribe}

  describe "function API" do
    test "subscribe and receive log event", %{conn: conn, context: context} do
      {:ok, _} = Session.subscribe(conn, ["log.entryAdded"])
      :ok = Connection.subscribe(conn, "log.entryAdded")

      {:ok, _} =
        Script.evaluate(conn, ~s[console.log("hello from test")], %{context: context}, true)

      assert_receive {:bibbidi_event, "log.entryAdded", params}, 5_000
      assert params.type == "console"
      assert is_binary(params.text)
    end

    test "unsubscribe stops delivery", %{conn: conn, context: context} do
      {:ok, _} = Session.subscribe(conn, ["log.entryAdded"])
      :ok = Connection.subscribe(conn, "log.entryAdded")

      # Verify events arrive first
      {:ok, _} =
        Script.evaluate(conn, ~s[console.log("before unsub")], %{context: context}, true)

      assert_receive {:bibbidi_event, "log.entryAdded", _}, 5_000

      # Unsubscribe both server and client side
      {:ok, _} = Session.unsubscribe(conn, ["log.entryAdded"])
      :ok = Connection.unsubscribe(conn, "log.entryAdded")

      {:ok, _} =
        Script.evaluate(conn, ~s[console.log("after unsub")], %{context: context}, true)

      refute_receive {:bibbidi_event, "log.entryAdded", _}, 1_000
    end

    test "navigation events", %{conn: conn, context: context} do
      {:ok, _} = Session.subscribe(conn, ["browsingContext.load"])
      :ok = Connection.subscribe(conn, "browsingContext.load")

      {:ok, _} =
        BrowsingContext.navigate(conn, context, "data:text/html,<h1>Nav Event</h1>",
          wait: "complete"
        )

      assert_receive {:bibbidi_event, "browsingContext.load", params}, 5_000
      assert params.context == context
    end

    test "multiple event types", %{conn: conn, context: context, base_url: base_url} do
      {:ok, _} = Session.subscribe(conn, ["log.entryAdded", "browsingContext.load"])
      :ok = Connection.subscribe(conn, "log.entryAdded")
      :ok = Connection.subscribe(conn, "browsingContext.load")

      {:ok, _} =
        BrowsingContext.navigate(conn, context, "#{base_url}/console-log", wait: "complete")

      assert_receive {:bibbidi_event, "browsingContext.load", _}, 5_000
      assert_receive {:bibbidi_event, "log.entryAdded", _}, 5_000
    end
  end

  describe "struct API via Connection.execute/2" do
    test "subscribe and receive log event", %{conn: conn, context: context} do
      {:ok, _} = Connection.execute(conn, %Subscribe{events: ["log.entryAdded"]})
      :ok = Connection.subscribe(conn, "log.entryAdded")

      {:ok, _} =
        Connection.execute(conn, %Evaluate{
          expression: ~s[console.log("hello from struct test")],
          target: %{context: context},
          await_promise: false
        })

      assert_receive {:bibbidi_event, "log.entryAdded", params}, 5_000
      assert params.type == "console"
      assert is_binary(params.text)
    end

    test "unsubscribe stops delivery", %{conn: conn, context: context} do
      {:ok, _} = Connection.execute(conn, %Subscribe{events: ["log.entryAdded"]})
      :ok = Connection.subscribe(conn, "log.entryAdded")

      {:ok, _} =
        Connection.execute(conn, %Evaluate{
          expression: ~s[console.log("before struct unsub")],
          target: %{context: context},
          await_promise: false
        })

      assert_receive {:bibbidi_event, "log.entryAdded", _}, 5_000

      {:ok, _} = Connection.execute(conn, %Unsubscribe{events: ["log.entryAdded"]})
      :ok = Connection.unsubscribe(conn, "log.entryAdded")

      {:ok, _} =
        Connection.execute(conn, %Evaluate{
          expression: ~s[console.log("after struct unsub")],
          target: %{context: context},
          await_promise: false
        })

      refute_receive {:bibbidi_event, "log.entryAdded", _}, 1_000
    end

    test "navigation events", %{conn: conn, context: context} do
      {:ok, _} = Connection.execute(conn, %Subscribe{events: ["browsingContext.load"]})
      :ok = Connection.subscribe(conn, "browsingContext.load")

      {:ok, _} =
        Connection.execute(conn, %Navigate{
          context: context,
          url: "data:text/html,<h1>Nav Event Struct</h1>",
          wait: "complete"
        })

      assert_receive {:bibbidi_event, "browsingContext.load", params}, 5_000
      assert params.context == context
    end
  end
end
