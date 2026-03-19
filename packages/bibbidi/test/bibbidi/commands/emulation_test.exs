defmodule Bibbidi.Commands.EmulationTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.Emulation
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

  describe "set_forced_colors_mode_theme_override/3" do
    test "sends emulation.setForcedColorsModeThemeOverride command", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_forced_colors_mode_theme_override(conn, "dark")
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setForcedColorsModeThemeOverride"
      assert decoded["params"]["theme"] == "dark"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "sends null to reset", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_forced_colors_mode_theme_override(conn, nil)
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["theme"] == nil

      reply(conn, decoded["id"])
      Task.await(task)
    end

    test "includes contexts option", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_forced_colors_mode_theme_override(conn, "light", contexts: ["ctx-1"])
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["contexts"] == ["ctx-1"]

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "set_geolocation_override/2" do
    test "sends command with no options", %{conn: conn} do
      task =
        Task.async(fn -> Emulation.set_geolocation_override(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setGeolocationOverride"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "includes contexts option", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_geolocation_override(conn, contexts: ["ctx-1"])
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["contexts"] == ["ctx-1"]

      reply(conn, decoded["id"])
      Task.await(task)
    end

    test "includes user_contexts option", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_geolocation_override(conn, user_contexts: ["user-ctx-1"])
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["userContexts"] == ["user-ctx-1"]

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "set_locale_override/3" do
    test "sends emulation.setLocaleOverride command", %{conn: conn} do
      task = Task.async(fn -> Emulation.set_locale_override(conn, "en-US") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setLocaleOverride"
      assert decoded["params"]["locale"] == "en-US"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_network_conditions/3" do
    test "sends emulation.setNetworkConditions command", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_network_conditions(conn, %{type: "offline"})
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setNetworkConditions"
      assert decoded["params"]["networkConditions"]["type"] == "offline"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_screen_orientation_override/3" do
    test "sends emulation.setScreenOrientationOverride command", %{conn: conn} do
      orientation = %{natural: "portrait", type: "portrait-primary"}

      task =
        Task.async(fn ->
          Emulation.set_screen_orientation_override(conn, orientation)
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setScreenOrientationOverride"
      assert decoded["params"]["screenOrientation"]["natural"] == "portrait"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_screen_settings_override/3" do
    test "sends emulation.setScreenSettingsOverride command", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_screen_settings_override(conn, %{width: 1920, height: 1080})
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setScreenSettingsOverride"
      assert decoded["params"]["screenArea"]["width"] == 1920
      assert decoded["params"]["screenArea"]["height"] == 1080

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_scripting_enabled/3" do
    test "sends emulation.setScriptingEnabled command", %{conn: conn} do
      task = Task.async(fn -> Emulation.set_scripting_enabled(conn, false) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setScriptingEnabled"
      assert decoded["params"]["enabled"] == false

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_scrollbar_type_override/3" do
    test "sends emulation.setScrollbarTypeOverride command", %{conn: conn} do
      task = Task.async(fn -> Emulation.set_scrollbar_type_override(conn, "overlay") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setScrollbarTypeOverride"
      assert decoded["params"]["scrollbarType"] == "overlay"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_timezone_override/3" do
    test "sends emulation.setTimezoneOverride command", %{conn: conn} do
      task = Task.async(fn -> Emulation.set_timezone_override(conn, "America/New_York") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setTimezoneOverride"
      assert decoded["params"]["timezone"] == "America/New_York"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_touch_override/3" do
    test "sends emulation.setTouchOverride command", %{conn: conn} do
      task = Task.async(fn -> Emulation.set_touch_override(conn, 5) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setTouchOverride"
      assert decoded["params"]["maxTouchPoints"] == 5

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_user_agent_override/3" do
    test "sends emulation.setUserAgentOverride command", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_user_agent_override(conn, "Custom Agent/1.0")
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "emulation.setUserAgentOverride"
      assert decoded["params"]["userAgent"] == "Custom Agent/1.0"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "includes user_contexts option", %{conn: conn} do
      task =
        Task.async(fn ->
          Emulation.set_user_agent_override(conn, "Bot/1.0", user_contexts: ["user-ctx-1"])
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["userContexts"] == ["user-ctx-1"]

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end
end
