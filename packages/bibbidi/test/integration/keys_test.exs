defmodule Bibbidi.Integration.KeysTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.BrowsingContext
  alias Bibbidi.Commands.Input
  alias Bibbidi.Commands.Script
  alias Bibbidi.Keys

  @moduletag :integration

  @keydown_page """
  <html>
  <body>
    <input id="target" autofocus />
    <script>
      document.getElementById("target").addEventListener("keydown", (e) => {
        console.log("KEY:" + e.key);
      });
    </script>
  </body>
  </html>
  """

  defp navigate_to_keydown_page(conn, context) do
    data_url = "data:text/html," <> URI.encode(@keydown_page)
    {:ok, _} = BrowsingContext.navigate(conn, context, data_url, wait: "complete")

    # Explicitly focus the input element (autofocus is unreliable in headless/BiDi)
    {:ok, _} =
      Script.evaluate(
        conn,
        ~s[document.getElementById("target").focus()],
        %{context: context},
        true
      )
  end

  defp send_key(conn, context, key_value) do
    actions = [
      %{
        type: "key",
        id: "keys-test",
        actions: [
          %{type: "keyDown", value: key_value},
          %{type: "keyUp", value: key_value}
        ]
      }
    ]

    {:ok, _} = Input.perform_actions(conn, context, actions)
  end

  setup %{conn: conn} do
    {:ok, _} = Session.subscribe(conn, ["log.entryAdded"])
    :ok = Connection.subscribe(conn, "log.entryAdded")
    :ok
  end

  test "Enter key produces correct DOM event", %{conn: conn, context: context} do
    navigate_to_keydown_page(conn, context)
    send_key(conn, context, Keys.key(:enter))

    assert_receive {:bibbidi_event, "log.entryAdded", params}, 5_000
    assert params.text =~ "KEY:Enter"
  end

  test "arrow keys produce correct DOM events", %{conn: conn, context: context} do
    navigate_to_keydown_page(conn, context)

    for {atom, expected_dom_key} <- [
          {:arrow_up, "ArrowUp"},
          {:arrow_down, "ArrowDown"},
          {:arrow_left, "ArrowLeft"},
          {:arrow_right, "ArrowRight"}
        ] do
      send_key(conn, context, Keys.key(atom))

      assert_receive {:bibbidi_event, "log.entryAdded", params}, 5_000
      assert params.text =~ "KEY:#{expected_dom_key}"
    end
  end

  test "Tab key produces correct DOM event", %{conn: conn, context: context} do
    navigate_to_keydown_page(conn, context)
    send_key(conn, context, Keys.key(:tab))

    assert_receive {:bibbidi_event, "log.entryAdded", params}, 5_000
    assert params.text =~ "KEY:Tab"
  end

  test "regular character key produces correct DOM event", %{conn: conn, context: context} do
    navigate_to_keydown_page(conn, context)
    send_key(conn, context, Keys.key("a"))

    assert_receive {:bibbidi_event, "log.entryAdded", params}, 5_000
    assert params.text =~ "KEY:a"
  end
end
