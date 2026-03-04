defmodule Bibbidi.Commands.BrowsingContextTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.BrowsingContext
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

  describe "navigate/4" do
    test "sends browsingContext.navigate command", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.navigate(conn, "ctx-1", "https://example.com") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.navigate"
      assert decoded["params"]["context"] == "ctx-1"
      assert decoded["params"]["url"] == "https://example.com"
      refute Map.has_key?(decoded["params"], "wait")

      send(
        conn,
        {:mock_transport_receive,
         [
           {:text,
            JSON.encode!(%{
              id: decoded["id"],
              result: %{navigation: "nav-1", url: "https://example.com"}
            })}
         ]}
      )

      assert {:ok, _} = Task.await(task)
    end

    test "includes wait option", %{conn: conn} do
      task =
        Task.async(fn ->
          BrowsingContext.navigate(conn, "ctx-1", "https://example.com", wait: "complete")
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["wait"] == "complete"

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      Task.await(task)
    end
  end

  describe "get_tree/2" do
    test "sends browsingContext.getTree command", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.get_tree(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.getTree"
      assert decoded["params"] == %{}

      send(
        conn,
        {:mock_transport_receive,
         [{:text, JSON.encode!(%{id: decoded["id"], result: %{contexts: []}})}]}
      )

      assert {:ok, %{"contexts" => []}} = Task.await(task)
    end

    test "includes max_depth and root options", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.get_tree(conn, max_depth: 2, root: "ctx-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["maxDepth"] == 2
      assert decoded["params"]["root"] == "ctx-1"

      send(
        conn,
        {:mock_transport_receive,
         [{:text, JSON.encode!(%{id: decoded["id"], result: %{contexts: []}})}]}
      )

      Task.await(task)
    end
  end

  describe "create/3" do
    test "sends browsingContext.create command", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.create(conn, "tab") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.create"
      assert decoded["params"]["type"] == "tab"

      send(
        conn,
        {:mock_transport_receive,
         [{:text, JSON.encode!(%{id: decoded["id"], result: %{context: "new-ctx"}})}]}
      )

      assert {:ok, %{"context" => "new-ctx"}} = Task.await(task)
    end
  end

  describe "close/3" do
    test "sends browsingContext.close command", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.close(conn, "ctx-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.close"
      assert decoded["params"]["context"] == "ctx-1"

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      assert {:ok, _} = Task.await(task)
    end
  end

  describe "capture_screenshot/3" do
    test "sends browsingContext.captureScreenshot command", %{conn: conn} do
      task =
        Task.async(fn ->
          BrowsingContext.capture_screenshot(conn, "ctx-1", origin: "viewport")
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.captureScreenshot"
      assert decoded["params"]["context"] == "ctx-1"
      assert decoded["params"]["origin"] == "viewport"

      send(
        conn,
        {:mock_transport_receive,
         [{:text, JSON.encode!(%{id: decoded["id"], result: %{data: "base64..."}})}]}
      )

      assert {:ok, %{"data" => "base64..."}} = Task.await(task)
    end
  end

  describe "activate/2" do
    test "sends browsingContext.activate command", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.activate(conn, "ctx-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.activate"
      assert decoded["params"]["context"] == "ctx-1"

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      assert {:ok, _} = Task.await(task)
    end
  end

  describe "reload/3" do
    test "sends browsingContext.reload command", %{conn: conn} do
      task =
        Task.async(fn ->
          BrowsingContext.reload(conn, "ctx-1", wait: "complete", ignore_cache: true)
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.reload"
      assert decoded["params"]["context"] == "ctx-1"
      assert decoded["params"]["wait"] == "complete"
      assert decoded["params"]["ignoreCache"] == true

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      assert {:ok, _} = Task.await(task)
    end
  end
end
