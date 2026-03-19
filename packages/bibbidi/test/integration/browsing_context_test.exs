defmodule Bibbidi.Integration.BrowsingContextTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.BrowsingContext.{Navigate, GetTree, Create, Close, CaptureScreenshot}

  describe "function API" do
    test "get_tree returns browsing contexts", %{conn: conn} do
      {:ok, result} = BrowsingContext.get_tree(conn)
      assert is_list(result["contexts"])
      assert length(result["contexts"]) > 0
    end

    test "create and close a tab", %{conn: conn} do
      {:ok, result} = BrowsingContext.create(conn, "tab")
      context = result["context"]
      assert is_binary(context)

      {:ok, _} = BrowsingContext.close(conn, context)
    end

    test "navigate to a page", %{conn: conn, context: context} do
      {:ok, result} =
        BrowsingContext.navigate(conn, context, "data:text/html,<h1>Hello</h1>", wait: "complete")

      assert is_binary(result["navigation"])
    end

    test "capture screenshot", %{conn: conn, context: context} do
      {:ok, _} =
        BrowsingContext.navigate(conn, context, "data:text/html,<h1>Screenshot</h1>",
          wait: "complete"
        )

      {:ok, result} = BrowsingContext.capture_screenshot(conn, context)
      assert is_binary(result["data"])
    end
  end

  describe "struct API via Connection.execute/2" do
    test "get_tree returns browsing contexts", %{conn: conn} do
      {:ok, result} = Connection.execute(conn, %GetTree{})
      assert is_list(result["contexts"])
      assert length(result["contexts"]) > 0
    end

    test "create and close a tab", %{conn: conn} do
      {:ok, result} = Connection.execute(conn, %Create{type: "tab"})
      context = result["context"]
      assert is_binary(context)

      {:ok, _} = Connection.execute(conn, %Close{context: context})
    end

    test "navigate to a page", %{conn: conn, context: context} do
      {:ok, result} =
        Connection.execute(conn, %Navigate{
          context: context,
          url: "data:text/html,<h1>Hello Struct</h1>",
          wait: "complete"
        })

      assert is_binary(result["navigation"])
    end

    test "navigate without wait option", %{conn: conn, context: context} do
      {:ok, result} =
        Connection.execute(conn, %Navigate{
          context: context,
          url: "data:text/html,<h1>No Wait</h1>"
        })

      assert is_binary(result["navigation"])
    end

    test "capture screenshot", %{conn: conn, context: context} do
      {:ok, _} =
        Connection.execute(conn, %Navigate{
          context: context,
          url: "data:text/html,<h1>Screenshot Struct</h1>",
          wait: "complete"
        })

      {:ok, result} = Connection.execute(conn, %CaptureScreenshot{context: context})
      assert is_binary(result["data"])
    end

    test "get_tree with root filter", %{conn: conn, context: context} do
      {:ok, result} = Connection.execute(conn, %GetTree{root: context})
      assert is_list(result["contexts"])
      assert length(result["contexts"]) == 1
      assert hd(result["contexts"])["context"] == context
    end
  end
end
