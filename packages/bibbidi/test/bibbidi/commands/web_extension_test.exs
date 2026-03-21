defmodule Bibbidi.Commands.WebExtensionTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.WebExtension

  describe "install/2" do
    test "sends webExtension.install with path" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "webExtension.install"
        params = Bibbidi.Encodable.params(cmd)
        assert params[:extensionData][:type] == "path"
        assert params[:extensionData][:path] == "/path/to/extension"
      end)

      assert {:ok, %{}} =
               WebExtension.install(:conn, %{type: "path", path: "/path/to/extension"},
                 connection_mod: MockConnection
               )
    end

    test "sends webExtension.install with base64" do
      expect_execute(fn _conn, cmd ->
        params = Bibbidi.Encodable.params(cmd)
        assert params[:extensionData][:type] == "base64"
        assert params[:extensionData][:value] == "base64data..."
      end)

      WebExtension.install(:conn, %{type: "base64", value: "base64data..."},
        connection_mod: MockConnection
      )
    end

    test "sends webExtension.install with archivePath" do
      expect_execute(fn _conn, cmd ->
        params = Bibbidi.Encodable.params(cmd)
        assert params[:extensionData][:type] == "archivePath"
      end)

      WebExtension.install(:conn, %{type: "archivePath", path: "/path/to/ext.zip"},
        connection_mod: MockConnection
      )
    end
  end

  describe "uninstall/2" do
    test "sends webExtension.uninstall command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "webExtension.uninstall"
        assert cmd.extension == "ext-1"
      end)

      assert {:ok, %{}} =
               WebExtension.uninstall(:conn, "ext-1", connection_mod: MockConnection)
    end
  end
end
