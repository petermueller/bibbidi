defmodule Bibbidi.Integration.BrowsingContextTest do
  use Bibbidi.IntegrationCase

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

  test "navigate to a page", %{conn: conn} do
    {:ok, tree} = BrowsingContext.get_tree(conn)
    context = hd(tree["contexts"])["context"]

    {:ok, result} =
      BrowsingContext.navigate(conn, context, "data:text/html,<h1>Hello</h1>", wait: "complete")

    assert is_binary(result["navigation"])
  end

  test "capture screenshot", %{conn: conn} do
    {:ok, tree} = BrowsingContext.get_tree(conn)
    context = hd(tree["contexts"])["context"]

    {:ok, _} =
      BrowsingContext.navigate(conn, context, "data:text/html,<h1>Screenshot</h1>",
        wait: "complete"
      )

    {:ok, result} = BrowsingContext.capture_screenshot(conn, context)
    assert is_binary(result["data"])
  end
end
