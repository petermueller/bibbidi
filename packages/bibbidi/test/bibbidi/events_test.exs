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

    test "wraps unknown top-level namespace events in %Unknown{}" do
      params = %{"foo" => "bar"}

      assert %Events.Unknown{method: "vendor.customEvent", params: ^params} =
               Events.parse("vendor.customEvent", params)
    end

    test "wraps unknown events within a known namespace in %Unknown{}" do
      params = %{"foo" => "bar"}

      assert %Events.Unknown{method: "browsingContext.unknownEvent", params: ^params} =
               Events.parse("browsingContext.unknownEvent", params)
    end
  end

  describe "method_for/1" do
    test "returns the method string for a typed event struct" do
      ev = %Events.Log.EntryAdded{}
      assert Events.method_for(ev) == "log.entryAdded"
    end

    test "returns the carried method string for %Unknown{}" do
      ev = %Events.Unknown{method: "vendor.custom", params: %{}}
      assert Events.method_for(ev) == "vendor.custom"
    end

    test "works for every generated event struct" do
      for mod <- Events.event_modules() do
        assert is_binary(mod.method()), "expected #{inspect(mod)}.method/0 to return a string"
        assert Events.method_for(struct(mod)) == mod.method()
      end
    end
  end

  describe "event_modules/0" do
    test "returns a non-empty list of generated event struct modules" do
      mods = Events.event_modules()
      assert is_list(mods)
      assert length(mods) > 0
      assert Events.Log.EntryAdded in mods
      assert Events.BrowsingContext.Load in mods
      assert Events.Script.Message in mods
    end
  end

  describe "guards" do
    require Bibbidi.Events.Guards
    import Bibbidi.Events.Guards

    test "is_bibbidi_event/1 matches typed event structs" do
      assert is_bibbidi_event(%Events.Log.EntryAdded{})
      assert is_bibbidi_event(%Events.BrowsingContext.Load{})
      assert is_bibbidi_event(%Events.Script.Message{})
    end

    test "is_bibbidi_event/1 matches %Unknown{}" do
      assert is_bibbidi_event(%Events.Unknown{method: "vendor.x"})
    end

    test "is_bibbidi_event/1 rejects non-event terms" do
      refute is_bibbidi_event(:not_an_event)
      refute is_bibbidi_event(%{not: :a_struct})
      refute is_bibbidi_event(123)
      refute is_bibbidi_event(nil)
    end

    test "namespace-specific guards match only their namespace" do
      assert is_bibbidi_log_event(%Events.Log.EntryAdded{})
      refute is_bibbidi_log_event(%Events.BrowsingContext.Load{})
      refute is_bibbidi_log_event(%Events.Unknown{method: "log.foo"})

      assert is_bibbidi_browsing_context_event(%Events.BrowsingContext.Load{})
      refute is_bibbidi_browsing_context_event(%Events.Log.EntryAdded{})
    end

    test "namespace-specific guards reject %Unknown{} even when method matches namespace" do
      # Unknown is namespace-agnostic by design — the dispatch couldn't confirm
      # a typed struct, so we don't pretend to know which namespace it belongs to.
      refute is_bibbidi_log_event(%Events.Unknown{method: "log.entryAddedV2"})
    end
  end
end
