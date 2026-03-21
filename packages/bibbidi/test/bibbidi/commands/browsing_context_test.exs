defmodule Bibbidi.Commands.BrowsingContextTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.BrowsingContext

  describe "navigate/4" do
    test "sends browsingContext.navigate command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.navigate"
        assert cmd.context == "ctx-1"
        assert cmd.url == "https://example.com"
        assert cmd.wait == nil
      end)

      assert {:ok, %{}} =
               BrowsingContext.navigate(:conn, "ctx-1", "https://example.com",
                 connection_mod: MockConnection
               )
    end

    test "includes wait option" do
      expect_execute(fn _conn, cmd ->
        assert cmd.wait == "complete"
      end)

      BrowsingContext.navigate(:conn, "ctx-1", "https://example.com",
        wait: "complete",
        connection_mod: MockConnection
      )
    end
  end

  describe "get_tree/2" do
    test "sends browsingContext.getTree command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.getTree"
      end)

      assert {:ok, %{}} = BrowsingContext.get_tree(:conn, connection_mod: MockConnection)
    end

    test "includes max_depth and root options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.max_depth == 2
        assert cmd.root == "ctx-1"
      end)

      BrowsingContext.get_tree(:conn,
        max_depth: 2,
        root: "ctx-1",
        connection_mod: MockConnection
      )
    end
  end

  describe "create/3" do
    test "sends browsingContext.create command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.create"
        assert cmd.type == "tab"
      end)

      assert {:ok, %{}} =
               BrowsingContext.create(:conn, "tab", connection_mod: MockConnection)
    end
  end

  describe "close/3" do
    test "sends browsingContext.close command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.close"
        assert cmd.context == "ctx-1"
      end)

      assert {:ok, %{}} =
               BrowsingContext.close(:conn, "ctx-1", connection_mod: MockConnection)
    end
  end

  describe "capture_screenshot/3" do
    test "sends browsingContext.captureScreenshot command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.captureScreenshot"
        assert cmd.context == "ctx-1"
        assert cmd.origin == "viewport"
      end)

      assert {:ok, %{}} =
               BrowsingContext.capture_screenshot(:conn, "ctx-1",
                 origin: "viewport",
                 connection_mod: MockConnection
               )
    end
  end

  describe "activate/2" do
    test "sends browsingContext.activate command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.activate"
        assert cmd.context == "ctx-1"
      end)

      assert {:ok, %{}} =
               BrowsingContext.activate(:conn, "ctx-1", connection_mod: MockConnection)
    end
  end

  describe "reload/3" do
    test "sends browsingContext.reload command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.reload"
        assert cmd.context == "ctx-1"
        assert cmd.wait == "complete"
        assert cmd.ignore_cache == true
      end)

      assert {:ok, %{}} =
               BrowsingContext.reload(:conn, "ctx-1",
                 wait: "complete",
                 ignore_cache: true,
                 connection_mod: MockConnection
               )
    end
  end

  describe "print/3" do
    test "sends browsingContext.print command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.print"
        assert cmd.context == "ctx-1"
      end)

      assert {:ok, %{}} =
               BrowsingContext.print(:conn, "ctx-1", connection_mod: MockConnection)
    end

    test "includes print options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.orientation == "landscape"
        assert cmd.scale == 0.5
        assert cmd.shrink_to_fit == true
        assert cmd.page_ranges == [1, "2-3"]
      end)

      BrowsingContext.print(:conn, "ctx-1",
        orientation: "landscape",
        scale: 0.5,
        shrink_to_fit: true,
        page_ranges: [1, "2-3"],
        connection_mod: MockConnection
      )
    end
  end

  describe "set_viewport/2" do
    test "sends browsingContext.setViewport with viewport" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.setViewport"
        assert cmd.context == "ctx-1"
        assert cmd.viewport == %{width: 1280, height: 720}
      end)

      assert {:ok, %{}} =
               BrowsingContext.set_viewport(:conn,
                 context: "ctx-1",
                 viewport: %{width: 1280, height: 720},
                 connection_mod: MockConnection
               )
    end

    test "sends nil viewport to reset" do
      expect_execute(fn _conn, cmd ->
        assert cmd.viewport == nil
      end)

      BrowsingContext.set_viewport(:conn,
        context: "ctx-1",
        viewport: nil,
        connection_mod: MockConnection
      )
    end
  end

  describe "handle_user_prompt/3" do
    test "sends browsingContext.handleUserPrompt command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.handleUserPrompt"
        assert cmd.context == "ctx-1"
      end)

      assert {:ok, %{}} =
               BrowsingContext.handle_user_prompt(:conn, "ctx-1", connection_mod: MockConnection)
    end

    test "includes accept and user_text options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.accept == true
        assert cmd.user_text == "hello"
      end)

      BrowsingContext.handle_user_prompt(:conn, "ctx-1",
        accept: true,
        user_text: "hello",
        connection_mod: MockConnection
      )
    end
  end

  describe "traverse_history/3" do
    test "sends browsingContext.traverseHistory command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.traverseHistory"
        assert cmd.context == "ctx-1"
        assert cmd.delta == -1
      end)

      assert {:ok, %{}} =
               BrowsingContext.traverse_history(:conn, "ctx-1", -1,
                 connection_mod: MockConnection
               )
    end
  end

  describe "locate_nodes/4" do
    test "sends browsingContext.locateNodes command" do
      locator = %{type: "css", value: "h1"}

      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "browsingContext.locateNodes"
        assert cmd.context == "ctx-1"
        assert cmd.locator == locator
      end)

      assert {:ok, %{}} =
               BrowsingContext.locate_nodes(:conn, "ctx-1", locator,
                 connection_mod: MockConnection
               )
    end

    test "includes max_node_count option" do
      locator = %{type: "css", value: "div"}

      expect_execute(fn _conn, cmd ->
        assert cmd.max_node_count == 5
      end)

      BrowsingContext.locate_nodes(:conn, "ctx-1", locator,
        max_node_count: 5,
        connection_mod: MockConnection
      )
    end
  end
end
