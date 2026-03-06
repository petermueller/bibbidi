defmodule Bibbidi.Integration.StorageTest do
  use Bibbidi.IntegrationCase

  test "cookie CRUD", %{conn: conn, context: context, base_url: base_url} do
    # Navigate to a real HTTP page so cookies work (not data: URLs)
    {:ok, _} = BrowsingContext.navigate(conn, context, "#{base_url}/hello", wait: "complete")

    # Set a cookie
    {:ok, _} =
      Storage.set_cookie(conn, %{
        name: "test_cookie",
        value: %{type: "string", value: "test_value"},
        domain: "localhost"
      })

    # Get cookies and verify it's present
    {:ok, result} = Storage.get_cookies(conn, filter: %{name: "test_cookie"})
    cookies = result["cookies"]
    assert length(cookies) > 0
    cookie = hd(cookies)
    assert cookie["name"] == "test_cookie"
    assert cookie["value"]["value"] == "test_value"

    # Delete the cookie
    {:ok, _} = Storage.delete_cookies(conn, filter: %{name: "test_cookie"})

    # Verify it's gone
    {:ok, result} = Storage.get_cookies(conn, filter: %{name: "test_cookie"})
    assert result["cookies"] == []
  end
end
