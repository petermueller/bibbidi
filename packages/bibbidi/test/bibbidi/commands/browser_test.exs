defmodule Bibbidi.Commands.BrowserTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.Browser

  describe "close/1" do
    test "sends browser.close command" do
      expect_execute(fn _conn, cmd ->
        assert %Browser.Close{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "browser.close"
        assert Bibbidi.Encodable.params(cmd) == %{}
      end)

      assert {:ok, %{}} = Browser.close(:conn, connection_mod: MockConnection)
    end
  end

  describe "create_user_context/2" do
    test "sends browser.createUserContext command" do
      expect_execute(fn _conn, cmd ->
        assert %Browser.CreateUserContext{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "browser.createUserContext"
      end)

      assert {:ok, %{}} = Browser.create_user_context(:conn, connection_mod: MockConnection)
    end

    test "includes options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.accept_insecure_certs == true
      end)

      Browser.create_user_context(:conn,
        accept_insecure_certs: true,
        connection_mod: MockConnection
      )
    end
  end

  describe "get_client_windows/1" do
    test "sends browser.getClientWindows command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browser.getClientWindows"
      end)

      assert {:ok, %{}} = Browser.get_client_windows(:conn, connection_mod: MockConnection)
    end
  end

  describe "get_user_contexts/1" do
    test "sends browser.getUserContexts command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browser.getUserContexts"
      end)

      assert {:ok, %{}} = Browser.get_user_contexts(:conn, connection_mod: MockConnection)
    end
  end

  describe "remove_user_context/2" do
    test "sends browser.removeUserContext command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browser.removeUserContext"
        assert Bibbidi.Encodable.params(cmd) == %{userContext: "user-ctx-1"}
      end)

      Browser.remove_user_context(:conn, "user-ctx-1", connection_mod: MockConnection)
    end
  end

  describe "set_client_window_state/2" do
    test "sends browser.setClientWindowState command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browser.setClientWindowState"
        assert cmd.client_window == "window-1"
      end)

      Browser.set_client_window_state(:conn, "window-1", connection_mod: MockConnection)
    end
  end

  describe "set_download_behavior/3" do
    test "sends browser.setDownloadBehavior command" do
      behavior = %{type: "allowed", destinationFolder: "/tmp/downloads"}

      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browser.setDownloadBehavior"
        params = Bibbidi.Encodable.params(cmd)
        assert params[:downloadBehavior][:type] == "allowed"
        assert params[:downloadBehavior][:destinationFolder] == "/tmp/downloads"
      end)

      Browser.set_download_behavior(:conn, behavior, connection_mod: MockConnection)
    end

    test "sends null download behavior" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.params(cmd)[:downloadBehavior] == nil
      end)

      Browser.set_download_behavior(:conn, nil, connection_mod: MockConnection)
    end

    test "includes user_contexts option" do
      expect_execute(fn _conn, cmd ->
        params = Bibbidi.Encodable.params(cmd)
        assert params[:userContexts] == ["user-ctx-1"]
      end)

      Browser.set_download_behavior(:conn, %{type: "denied"},
        user_contexts: ["user-ctx-1"],
        connection_mod: MockConnection
      )
    end
  end
end
