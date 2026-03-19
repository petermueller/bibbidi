defmodule Bibbidi.Commands.StorageTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.Storage
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

  defp reply(conn, id, result) do
    send(conn, {:mock_transport_receive, [{:text, JSON.encode!(%{id: id, result: result})}]})
  end

  describe "get_cookies/2" do
    test "sends storage.getCookies command", %{conn: conn} do
      task = Task.async(fn -> Storage.get_cookies(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "storage.getCookies"
      assert decoded["params"] == %{}

      reply(conn, decoded["id"], %{cookies: [], partitionKey: %{}})
      assert {:ok, %{"cookies" => []}} = Task.await(task)
    end

    test "includes filter and partition options", %{conn: conn} do
      task =
        Task.async(fn ->
          Storage.get_cookies(conn,
            filter: %{name: "session_id"},
            partition: %{type: "context", context: "ctx-1"}
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["filter"] == %{"name" => "session_id"}
      assert decoded["params"]["partition"]["type"] == "context"

      reply(conn, decoded["id"], %{cookies: [], partitionKey: %{}})
      Task.await(task)
    end
  end

  describe "set_cookie/3" do
    test "sends storage.setCookie command", %{conn: conn} do
      cookie = %{
        name: "session_id",
        value: %{type: "string", value: "abc123"},
        domain: "example.com"
      }

      task = Task.async(fn -> Storage.set_cookie(conn, cookie) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "storage.setCookie"
      assert decoded["params"]["cookie"]["name"] == "session_id"
      assert decoded["params"]["cookie"]["domain"] == "example.com"

      reply(conn, decoded["id"], %{partitionKey: %{}})
      assert {:ok, _} = Task.await(task)
    end

    test "includes partition option", %{conn: conn} do
      cookie = %{
        name: "test",
        value: %{type: "string", value: "val"},
        domain: "example.com"
      }

      task =
        Task.async(fn ->
          Storage.set_cookie(conn, cookie,
            partition: %{type: "storageKey", sourceOrigin: "https://example.com"}
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["partition"]["type"] == "storageKey"

      reply(conn, decoded["id"], %{partitionKey: %{}})
      Task.await(task)
    end
  end

  describe "delete_cookies/2" do
    test "sends storage.deleteCookies command", %{conn: conn} do
      task = Task.async(fn -> Storage.delete_cookies(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "storage.deleteCookies"
      assert decoded["params"] == %{}

      reply(conn, decoded["id"], %{partitionKey: %{}})
      assert {:ok, _} = Task.await(task)
    end

    test "includes filter option", %{conn: conn} do
      task =
        Task.async(fn ->
          Storage.delete_cookies(conn, filter: %{name: "old_cookie"})
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["filter"] == %{"name" => "old_cookie"}

      reply(conn, decoded["id"], %{partitionKey: %{}})
      Task.await(task)
    end
  end
end
