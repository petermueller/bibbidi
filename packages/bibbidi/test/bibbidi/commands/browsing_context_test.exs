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

  describe "print/3" do
    test "sends browsingContext.print command", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.print(conn, "ctx-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.print"
      assert decoded["params"]["context"] == "ctx-1"

      send(
        conn,
        {:mock_transport_receive,
         [{:text, JSON.encode!(%{id: decoded["id"], result: %{data: "base64pdf"}})}]}
      )

      assert {:ok, %{"data" => "base64pdf"}} = Task.await(task)
    end

    test "includes print options", %{conn: conn} do
      task =
        Task.async(fn ->
          BrowsingContext.print(conn, "ctx-1",
            orientation: "landscape",
            scale: 0.5,
            shrink_to_fit: true,
            page_ranges: [1, "2-3"]
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["orientation"] == "landscape"
      assert decoded["params"]["scale"] == 0.5
      assert decoded["params"]["shrinkToFit"] == true
      assert decoded["params"]["pageRanges"] == [1, "2-3"]

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      Task.await(task)
    end
  end

  describe "set_viewport/2" do
    test "sends browsingContext.setViewport with viewport", %{conn: conn} do
      task =
        Task.async(fn ->
          BrowsingContext.set_viewport(conn, context: "ctx-1", viewport: %{width: 1280, height: 720})
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.setViewport"
      assert decoded["params"]["context"] == "ctx-1"
      assert decoded["params"]["viewport"] == %{"width" => 1280, "height" => 720}

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      assert {:ok, _} = Task.await(task)
    end

    test "sends nil viewport to reset", %{conn: conn} do
      task =
        Task.async(fn ->
          BrowsingContext.set_viewport(conn, context: "ctx-1", viewport: nil)
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["viewport"] == nil

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      Task.await(task)
    end
  end

  describe "handle_user_prompt/3" do
    test "sends browsingContext.handleUserPrompt command", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.handle_user_prompt(conn, "ctx-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.handleUserPrompt"
      assert decoded["params"]["context"] == "ctx-1"

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      assert {:ok, _} = Task.await(task)
    end

    test "includes accept and user_text options", %{conn: conn} do
      task =
        Task.async(fn ->
          BrowsingContext.handle_user_prompt(conn, "ctx-1", accept: true, user_text: "hello")
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["accept"] == true
      assert decoded["params"]["userText"] == "hello"

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      Task.await(task)
    end
  end

  describe "traverse_history/3" do
    test "sends browsingContext.traverseHistory command", %{conn: conn} do
      task = Task.async(fn -> BrowsingContext.traverse_history(conn, "ctx-1", -1) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.traverseHistory"
      assert decoded["params"]["context"] == "ctx-1"
      assert decoded["params"]["delta"] == -1

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      assert {:ok, _} = Task.await(task)
    end
  end

  describe "locate_nodes/4" do
    test "sends browsingContext.locateNodes command", %{conn: conn} do
      locator = %{type: "css", value: "h1"}

      task =
        Task.async(fn -> BrowsingContext.locate_nodes(conn, "ctx-1", locator) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "browsingContext.locateNodes"
      assert decoded["params"]["context"] == "ctx-1"
      assert decoded["params"]["locator"] == %{"type" => "css", "value" => "h1"}

      send(
        conn,
        {:mock_transport_receive,
         [{:text, JSON.encode!(%{id: decoded["id"], result: %{nodes: []}})}]}
      )

      assert {:ok, %{"nodes" => []}} = Task.await(task)
    end

    test "includes max_node_count option", %{conn: conn} do
      locator = %{type: "css", value: "div"}

      task =
        Task.async(fn ->
          BrowsingContext.locate_nodes(conn, "ctx-1", locator, max_node_count: 5)
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["maxNodeCount"] == 5

      send(
        conn,
        {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: %{}})}]}
      )

      Task.await(task)
    end
  end
end
