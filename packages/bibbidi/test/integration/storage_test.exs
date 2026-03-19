defmodule Bibbidi.Integration.StorageTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.BrowsingContext.Navigate
  alias Bibbidi.Commands.Storage.{SetCookie, GetCookies, DeleteCookies}

  describe "function API" do
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

  describe "struct API via Connection.execute/2" do
    test "cookie CRUD", %{conn: conn, context: context, base_url: base_url} do
      {:ok, _} =
        Connection.execute(conn, %Navigate{
          context: context,
          url: "#{base_url}/hello",
          wait: "complete"
        })

      {:ok, _} =
        Connection.execute(conn, %SetCookie{
          cookie: %{
            name: "struct_cookie",
            value: %{type: "string", value: "struct_value"},
            domain: "localhost"
          }
        })

      {:ok, result} =
        Connection.execute(conn, %GetCookies{filter: %{name: "struct_cookie"}})

      cookies = result["cookies"]
      assert length(cookies) > 0
      cookie = hd(cookies)
      assert cookie["name"] == "struct_cookie"
      assert cookie["value"]["value"] == "struct_value"

      {:ok, _} =
        Connection.execute(conn, %DeleteCookies{filter: %{name: "struct_cookie"}})

      {:ok, result} =
        Connection.execute(conn, %GetCookies{filter: %{name: "struct_cookie"}})

      assert result["cookies"] == []
    end
  end
end
