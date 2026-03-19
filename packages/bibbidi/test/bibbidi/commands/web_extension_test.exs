defmodule Bibbidi.Commands.WebExtensionTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.WebExtension
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

  describe "install/2" do
    test "sends webExtension.install with path", %{conn: conn} do
      task =
        Task.async(fn ->
          WebExtension.install(conn, %{type: "path", path: "/path/to/extension"})
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "webExtension.install"
      assert decoded["params"]["extensionData"]["type"] == "path"
      assert decoded["params"]["extensionData"]["path"] == "/path/to/extension"

      reply(conn, decoded["id"], %{extension: "ext-1"})
      assert {:ok, %{"extension" => "ext-1"}} = Task.await(task)
    end

    test "sends webExtension.install with base64", %{conn: conn} do
      task =
        Task.async(fn ->
          WebExtension.install(conn, %{type: "base64", value: "base64data..."})
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["extensionData"]["type"] == "base64"
      assert decoded["params"]["extensionData"]["value"] == "base64data..."

      reply(conn, decoded["id"], %{extension: "ext-2"})
      Task.await(task)
    end

    test "sends webExtension.install with archivePath", %{conn: conn} do
      task =
        Task.async(fn ->
          WebExtension.install(conn, %{type: "archivePath", path: "/path/to/ext.zip"})
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["extensionData"]["type"] == "archivePath"

      reply(conn, decoded["id"], %{extension: "ext-3"})
      Task.await(task)
    end
  end

  describe "uninstall/2" do
    test "sends webExtension.uninstall command", %{conn: conn} do
      task = Task.async(fn -> WebExtension.uninstall(conn, "ext-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "webExtension.uninstall"
      assert decoded["params"]["extension"] == "ext-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end
end
