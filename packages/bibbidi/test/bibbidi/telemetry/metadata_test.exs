defmodule Bibbidi.Telemetry.MetadataTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Telemetry.Metadata

  describe "fallback (Any)" do
    test "returns empty map for non-derived structs" do
      assert Metadata.telemetry_metadata(%URI{}) == %{}
    end

    test "returns empty map for non-structs" do
      assert Metadata.telemetry_metadata("hello") == %{}
      assert Metadata.telemetry_metadata(42) == %{}
    end
  end

  describe "default derive (command structs)" do
    test "extracts :meta from command struct" do
      cmd = %Bibbidi.Commands.BrowsingContext.Navigate{
        context: "ctx-1",
        url: "https://example.com",
        meta: %{trace_id: "abc"}
      }

      assert Metadata.telemetry_metadata(cmd) == %{meta: %{trace_id: "abc"}}
    end

    test "extracts :meta as nil when not set" do
      cmd = %Bibbidi.Commands.BrowsingContext.Activate{context: "ctx-1"}

      assert Metadata.telemetry_metadata(cmd) == %{meta: nil}
    end
  end

  describe "custom keys derive (event structs)" do
    test "extracts correlation keys from event struct" do
      event = %Bibbidi.Events.BrowsingContext.Load{
        context: "ctx-1",
        navigation: "nav-1",
        timestamp: 123,
        url: "https://example.com"
      }

      assert Metadata.telemetry_metadata(event) == %{context: "ctx-1", navigation: "nav-1"}
    end

    test "extracts network correlation keys" do
      event = %Bibbidi.Events.Network.BeforeRequestSent{
        context: "ctx-1",
        navigation: "nav-1",
        request: %{"url" => "https://example.com"},
        is_blocked: false,
        redirect_count: 0,
        timestamp: 123
      }

      assert Metadata.telemetry_metadata(event) == %{
               context: "ctx-1",
               navigation: "nav-1",
               request: %{"url" => "https://example.com"}
             }
    end

    test "returns empty map for event struct with no correlation keys" do
      event = %Bibbidi.Events.Script.RealmDestroyed{realm: "realm-1"}

      assert Metadata.telemetry_metadata(event) == %{}
    end
  end
end
