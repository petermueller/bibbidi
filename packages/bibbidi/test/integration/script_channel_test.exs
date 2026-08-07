defmodule Bibbidi.Integration.ScriptChannelTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.Script.AddPreloadScript
  alias Bibbidi.Events.Script.Message

  describe "script.message channel mechanism" do
    test "preload script can emit to a registered channel", %{conn: conn, context: context} do
      {:ok, _} = Session.subscribe(conn, ["script.message"])
      :ok = Connection.subscribe(conn, "script.message")

      channel_id = "test-channel-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Connection.execute(conn, %AddPreloadScript{
          function_declaration: """
          (channel) => {
            channel({hello: "world", n: 42});
          }
          """,
          arguments: [
            %{type: "channel", value: %{channel: channel_id}}
          ],
          contexts: [context]
        })

      # Preload scripts run on every new document — navigate to trigger.
      {:ok, _} =
        BrowsingContext.navigate(conn, context, "data:text/html,<h1>hi</h1>", wait: "complete")

      assert_receive %Message{channel: ^channel_id, data: data, source: source}, 5_000

      # `data` is a RemoteValue; for the primitive object literal above this
      # serialises as {type: "object", value: [["hello", {...}], ["n", {...}]]}.
      assert data["type"] == "object"

      pairs = Map.new(data["value"], fn [k, v] -> {k, v} end)
      assert pairs["hello"]["type"] == "string"
      assert pairs["hello"]["value"] == "world"
      assert pairs["n"]["type"] == "number"
      assert pairs["n"]["value"] == 42

      # `source` carries the realm/context the message came from.
      assert source["context"] == context
      assert is_binary(source["realm"])
    end

    test "ownership: :root yields a stable handle for the delivered object",
         %{conn: conn, context: context} do
      {:ok, _} = Session.subscribe(conn, ["script.message"])
      :ok = Connection.subscribe(conn, "script.message")

      channel_id = "root-channel-#{System.unique_integer([:positive])}"

      {:ok, _} =
        Connection.execute(conn, %AddPreloadScript{
          function_declaration: """
          (channel) => {
            const helpers = { ping: () => "pong" };
            channel(helpers);
          }
          """,
          arguments: [
            %{
              type: "channel",
              value: %{channel: channel_id, ownership: "root"}
            }
          ],
          contexts: [context]
        })

      {:ok, _} =
        BrowsingContext.navigate(conn, context, "data:text/html,<h1>hi</h1>", wait: "complete")

      assert_receive %Message{channel: ^channel_id, data: data}, 5_000

      # With ownership: "root", the emitted object carries a server-side handle.
      assert data["type"] == "object"
      assert is_binary(data["handle"]), "expected a stable handle on the RemoteValue"
    end
  end
end
