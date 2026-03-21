defmodule Bibbidi.Commands.StorageTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.Storage

  describe "get_cookies/2" do
    test "sends storage.getCookies command" do
      expect_execute(fn _conn, cmd ->
        assert %Storage.GetCookies{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "storage.getCookies"
      end)

      assert {:ok, %{}} = Storage.get_cookies(:conn, connection_mod: MockConnection)
    end

    test "includes filter and partition options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.filter == %{name: "session_id"}
        assert cmd.partition == %{type: "context", context: "ctx-1"}
      end)

      Storage.get_cookies(:conn,
        filter: %{name: "session_id"},
        partition: %{type: "context", context: "ctx-1"},
        connection_mod: MockConnection
      )
    end
  end

  describe "set_cookie/3" do
    test "sends storage.setCookie command" do
      cookie = %{
        name: "session_id",
        value: %{type: "string", value: "abc123"},
        domain: "example.com"
      }

      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "storage.setCookie"
        assert cmd.cookie == cookie
      end)

      assert {:ok, %{}} = Storage.set_cookie(:conn, cookie, connection_mod: MockConnection)
    end

    test "includes partition option" do
      cookie = %{
        name: "test",
        value: %{type: "string", value: "val"},
        domain: "example.com"
      }

      expect_execute(fn _conn, cmd ->
        assert cmd.partition == %{type: "storageKey", sourceOrigin: "https://example.com"}
      end)

      Storage.set_cookie(:conn, cookie,
        partition: %{type: "storageKey", sourceOrigin: "https://example.com"},
        connection_mod: MockConnection
      )
    end
  end

  describe "delete_cookies/2" do
    test "sends storage.deleteCookies command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "storage.deleteCookies"
      end)

      assert {:ok, %{}} = Storage.delete_cookies(:conn, connection_mod: MockConnection)
    end

    test "includes filter option" do
      expect_execute(fn _conn, cmd ->
        assert cmd.filter == %{name: "old_cookie"}
      end)

      Storage.delete_cookies(:conn,
        filter: %{name: "old_cookie"},
        connection_mod: MockConnection
      )
    end
  end
end
