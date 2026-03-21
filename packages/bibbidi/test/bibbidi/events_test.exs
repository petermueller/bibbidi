defmodule Bibbidi.EventsTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Events

  describe "parse/2" do
    test "parses browsingContext.load into Load struct" do
      params = %{
        "context" => "ctx-1",
        "navigation" => "nav-1",
        "timestamp" => 1234,
        "url" => "https://example.com",
        "userContext" => "default"
      }

      result = Events.parse("browsingContext.load", params)

      assert %Events.BrowsingContext.Load{} = result
      assert result.context == "ctx-1"
      assert result.navigation == "nav-1"
      assert result.timestamp == 1234
      assert result.url == "https://example.com"
      assert result.user_context == "default"
    end

    test "parses browsingContext.navigationStarted into NavigationStarted struct" do
      params = %{
        "context" => "ctx-1",
        "navigation" => "nav-1",
        "timestamp" => 5678,
        "url" => "https://example.com"
      }

      result = Events.parse("browsingContext.navigationStarted", params)

      assert %Events.BrowsingContext.NavigationStarted{} = result
      assert result.context == "ctx-1"
      assert result.navigation == "nav-1"
    end

    test "parses network.beforeRequestSent into BeforeRequestSent struct" do
      params = %{
        "context" => "ctx-1",
        "isBlocked" => false,
        "navigation" => "nav-1",
        "redirectCount" => 0,
        "request" => %{"url" => "https://example.com"},
        "timestamp" => 1234,
        "initiator" => %{}
      }

      result = Events.parse("network.beforeRequestSent", params)

      assert %Events.Network.BeforeRequestSent{} = result
      assert result.context == "ctx-1"
      assert result.is_blocked == false
      assert result.request == %{"url" => "https://example.com"}
    end

    test "parses log.entryAdded into EntryAdded struct" do
      params = %{
        "level" => "info",
        "source" => %{},
        "text" => "hello",
        "timestamp" => 1234,
        "type" => "console",
        "method" => "log",
        "args" => []
      }

      result = Events.parse("log.entryAdded", params)

      assert %Events.Log.EntryAdded{} = result
      assert result.level == "info"
      assert result.text == "hello"
      assert result.method == "log"
    end

    test "returns raw map for unknown events" do
      params = %{"foo" => "bar"}
      assert Events.parse("vendor.customEvent", params) == params
    end

    test "returns raw map for unknown events within known module" do
      params = %{"foo" => "bar"}
      assert Events.parse("browsingContext.unknownEvent", params) == params
    end
  end
end
