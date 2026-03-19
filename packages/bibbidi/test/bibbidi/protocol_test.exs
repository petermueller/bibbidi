defmodule Bibbidi.ProtocolTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Protocol

  describe "encode_command/3" do
    test "encodes a command as JSON" do
      json = Protocol.encode_command(1, "session.status", %{})
      decoded = JSON.decode!(json)

      assert decoded == %{"id" => 1, "method" => "session.status", "params" => %{}}
    end

    test "encodes command with params" do
      json =
        Protocol.encode_command(42, "browsingContext.navigate", %{
          context: "ctx-1",
          url: "https://example.com",
          wait: "complete"
        })

      decoded = JSON.decode!(json)
      assert decoded["id"] == 42
      assert decoded["method"] == "browsingContext.navigate"
      assert decoded["params"]["context"] == "ctx-1"
      assert decoded["params"]["url"] == "https://example.com"
    end
  end

  describe "decode_message/1" do
    test "decodes a command response" do
      json = JSON.encode!(%{id: 1, result: %{ready: true, message: "ok"}})

      assert {:command_response, 1, %{"ready" => true, "message" => "ok"}} =
               Protocol.decode_message(json)
    end

    test "decodes an error response" do
      json =
        JSON.encode!(%{
          id: 2,
          error: "unknown command",
          message: "no such method",
          stacktrace: nil
        })

      assert {:error_response, 2, error} = Protocol.decode_message(json)
      assert error.error == "unknown command"
      assert error.message == "no such method"
    end

    test "decodes an event" do
      json =
        JSON.encode!(%{
          method: "browsingContext.load",
          params: %{
            context: "ctx-1",
            navigation: "nav-1",
            timestamp: 12345,
            url: "https://example.com"
          }
        })

      assert {:event, "browsingContext.load", params} = Protocol.decode_message(json)
      assert params["context"] == "ctx-1"
    end

    test "returns error for invalid JSON" do
      assert {:error, {:json_decode, _}} = Protocol.decode_message("not json")
    end

    test "returns error for unknown message shape" do
      json = JSON.encode!(%{foo: "bar"})
      assert {:error, {:unknown_message, _}} = Protocol.decode_message(json)
    end
  end
end
