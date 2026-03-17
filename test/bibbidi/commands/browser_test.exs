defmodule Bibbidi.Commands.BrowserTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.Browser
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

  describe "close/1" do
    test "sends browser.close command", %{conn: conn} do
      task = Task.async(fn -> Browser.close(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browser.close"
      assert decoded["params"] == %{}

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "create_user_context/2" do
    test "sends browser.createUserContext command", %{conn: conn} do
      task = Task.async(fn -> Browser.create_user_context(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browser.createUserContext"
      assert decoded["params"] == %{}

      reply(conn, decoded["id"], %{userContext: "user-ctx-1"})
      assert {:ok, %{"userContext" => "user-ctx-1"}} = Task.await(task)
    end

    test "includes options", %{conn: conn} do
      task =
        Task.async(fn ->
          Browser.create_user_context(conn, accept_insecure_certs: true)
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["acceptInsecureCerts"] == true

      reply(conn, decoded["id"], %{userContext: "user-ctx-1"})
      Task.await(task)
    end
  end

  describe "get_client_windows/1" do
    test "sends browser.getClientWindows command", %{conn: conn} do
      task = Task.async(fn -> Browser.get_client_windows(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browser.getClientWindows"
      assert decoded["params"] == %{}

      reply(conn, decoded["id"], %{clientWindows: []})
      assert {:ok, %{"clientWindows" => []}} = Task.await(task)
    end
  end

  describe "get_user_contexts/1" do
    test "sends browser.getUserContexts command", %{conn: conn} do
      task = Task.async(fn -> Browser.get_user_contexts(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browser.getUserContexts"
      assert decoded["params"] == %{}

      reply(conn, decoded["id"], %{userContexts: []})
      assert {:ok, %{"userContexts" => []}} = Task.await(task)
    end
  end

  describe "remove_user_context/2" do
    test "sends browser.removeUserContext command", %{conn: conn} do
      task = Task.async(fn -> Browser.remove_user_context(conn, "user-ctx-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browser.removeUserContext"
      assert decoded["params"]["userContext"] == "user-ctx-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_client_window_state/2" do
    test "sends browser.setClientWindowState command", %{conn: conn} do
      task =
        Task.async(fn ->
          Browser.set_client_window_state(conn, "window-1")
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browser.setClientWindowState"
      assert decoded["params"]["clientWindow"] == "window-1"

      reply(conn, decoded["id"], %{clientWindow: "window-1", state: "maximized"})
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_download_behavior/3" do
    test "sends browser.setDownloadBehavior command", %{conn: conn} do
      behavior = %{type: "allowed", destinationFolder: "/tmp/downloads"}

      task = Task.async(fn -> Browser.set_download_behavior(conn, behavior) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browser.setDownloadBehavior"
      assert decoded["params"]["downloadBehavior"]["type"] == "allowed"
      assert decoded["params"]["downloadBehavior"]["destinationFolder"] == "/tmp/downloads"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "sends null download behavior", %{conn: conn} do
      task = Task.async(fn -> Browser.set_download_behavior(conn, nil) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["downloadBehavior"] == nil

      reply(conn, decoded["id"])
      Task.await(task)
    end

    test "includes user_contexts option", %{conn: conn} do
      task =
        Task.async(fn ->
          Browser.set_download_behavior(conn, %{type: "denied"}, user_contexts: ["user-ctx-1"])
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["userContexts"] == ["user-ctx-1"]

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end
end
