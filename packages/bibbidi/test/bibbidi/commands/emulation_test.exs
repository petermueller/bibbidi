defmodule Bibbidi.Commands.EmulationTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.Emulation

  describe "set_forced_colors_mode_theme_override/3" do
    test "sends emulation.setForcedColorsModeThemeOverride command" do
      expect_execute(fn _conn, cmd ->
        assert %Emulation.SetForcedColorsModeThemeOverride{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "emulation.setForcedColorsModeThemeOverride"
        assert cmd.theme == "dark"
      end)

      assert {:ok, %{}} =
               Emulation.set_forced_colors_mode_theme_override(:conn, "dark",
                 connection_mod: MockConnection
               )
    end

    test "sends null to reset" do
      expect_execute(fn _conn, cmd ->
        assert cmd.theme == nil
      end)

      assert {:ok, %{}} =
               Emulation.set_forced_colors_mode_theme_override(:conn, nil,
                 connection_mod: MockConnection
               )
    end

    test "includes contexts option" do
      expect_execute(fn _conn, cmd ->
        assert cmd.contexts == ["ctx-1"]
      end)

      Emulation.set_forced_colors_mode_theme_override(:conn, "light",
        contexts: ["ctx-1"],
        connection_mod: MockConnection
      )
    end
  end

  describe "set_geolocation_override/2" do
    test "sends command with no options" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setGeolocationOverride"
      end)

      assert {:ok, %{}} =
               Emulation.set_geolocation_override(:conn, connection_mod: MockConnection)
    end

    test "includes contexts option" do
      expect_execute(fn _conn, cmd ->
        assert cmd.contexts == ["ctx-1"]
      end)

      Emulation.set_geolocation_override(:conn,
        contexts: ["ctx-1"],
        connection_mod: MockConnection
      )
    end

    test "includes user_contexts option" do
      expect_execute(fn _conn, cmd ->
        assert cmd.user_contexts == ["user-ctx-1"]
      end)

      Emulation.set_geolocation_override(:conn,
        user_contexts: ["user-ctx-1"],
        connection_mod: MockConnection
      )
    end
  end

  describe "set_locale_override/3" do
    test "sends emulation.setLocaleOverride command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setLocaleOverride"
        assert cmd.locale == "en-US"
      end)

      assert {:ok, %{}} =
               Emulation.set_locale_override(:conn, "en-US", connection_mod: MockConnection)
    end
  end

  describe "set_network_conditions/3" do
    test "sends emulation.setNetworkConditions command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setNetworkConditions"
        assert cmd.network_conditions == %{type: "offline"}
      end)

      assert {:ok, %{}} =
               Emulation.set_network_conditions(:conn, %{type: "offline"},
                 connection_mod: MockConnection
               )
    end
  end

  describe "set_screen_orientation_override/3" do
    test "sends emulation.setScreenOrientationOverride command" do
      orientation = %{natural: "portrait", type: "portrait-primary"}

      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setScreenOrientationOverride"
        assert cmd.screen_orientation == orientation
      end)

      assert {:ok, %{}} =
               Emulation.set_screen_orientation_override(:conn, orientation,
                 connection_mod: MockConnection
               )
    end
  end

  describe "set_screen_settings_override/3" do
    test "sends emulation.setScreenSettingsOverride command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setScreenSettingsOverride"
        assert cmd.screen_area == %{width: 1920, height: 1080}
      end)

      assert {:ok, %{}} =
               Emulation.set_screen_settings_override(:conn, %{width: 1920, height: 1080},
                 connection_mod: MockConnection
               )
    end
  end

  describe "set_scripting_enabled/3" do
    test "sends emulation.setScriptingEnabled command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setScriptingEnabled"
        assert cmd.enabled == false
      end)

      assert {:ok, %{}} =
               Emulation.set_scripting_enabled(:conn, false, connection_mod: MockConnection)
    end
  end

  describe "set_scrollbar_type_override/3" do
    test "sends emulation.setScrollbarTypeOverride command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setScrollbarTypeOverride"
        assert cmd.scrollbar_type == "overlay"
      end)

      assert {:ok, %{}} =
               Emulation.set_scrollbar_type_override(:conn, "overlay",
                 connection_mod: MockConnection
               )
    end
  end

  describe "set_timezone_override/3" do
    test "sends emulation.setTimezoneOverride command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setTimezoneOverride"
        assert cmd.timezone == "America/New_York"
      end)

      assert {:ok, %{}} =
               Emulation.set_timezone_override(:conn, "America/New_York",
                 connection_mod: MockConnection
               )
    end
  end

  describe "set_touch_override/3" do
    test "sends emulation.setTouchOverride command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setTouchOverride"
        assert cmd.max_touch_points == 5
      end)

      assert {:ok, %{}} =
               Emulation.set_touch_override(:conn, 5, connection_mod: MockConnection)
    end
  end

  describe "set_user_agent_override/3" do
    test "sends emulation.setUserAgentOverride command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "emulation.setUserAgentOverride"
        assert cmd.user_agent == "Custom Agent/1.0"
      end)

      assert {:ok, %{}} =
               Emulation.set_user_agent_override(:conn, "Custom Agent/1.0",
                 connection_mod: MockConnection
               )
    end

    test "includes user_contexts option" do
      expect_execute(fn _conn, cmd ->
        assert cmd.user_contexts == ["user-ctx-1"]
      end)

      Emulation.set_user_agent_override(:conn, "Bot/1.0",
        user_contexts: ["user-ctx-1"],
        connection_mod: MockConnection
      )
    end
  end
end
