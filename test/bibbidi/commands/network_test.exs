defmodule Bibbidi.Commands.NetworkTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.Network
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

  defp reply(conn, id, result \\ %{}) do
    send(conn, {:mock_transport_receive, [{:text, JSON.encode!(%{id: id, result: result})}]})
  end

  describe "add_data_collector/4" do
    test "sends network.addDataCollector command", %{conn: conn} do
      task =
        Task.async(fn -> Network.add_data_collector(conn, ["request", "response"], 1_048_576) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.addDataCollector"
      assert decoded["params"]["dataTypes"] == ["request", "response"]
      assert decoded["params"]["maxEncodedDataSize"] == 1_048_576

      reply(conn, decoded["id"], %{collector: "collector-1"})
      assert {:ok, %{"collector" => "collector-1"}} = Task.await(task)
    end

    test "includes options", %{conn: conn} do
      task =
        Task.async(fn ->
          Network.add_data_collector(conn, ["request"], 1024,
            collector_type: "blob",
            contexts: ["ctx-1"]
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["collectorType"] == "blob"
      assert decoded["params"]["contexts"] == ["ctx-1"]

      reply(conn, decoded["id"], %{collector: "collector-1"})
      Task.await(task)
    end
  end

  describe "add_intercept/3" do
    test "sends network.addIntercept command", %{conn: conn} do
      task = Task.async(fn -> Network.add_intercept(conn, ["beforeRequestSent"]) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.addIntercept"
      assert decoded["params"]["phases"] == ["beforeRequestSent"]

      reply(conn, decoded["id"], %{intercept: "intercept-1"})
      assert {:ok, %{"intercept" => "intercept-1"}} = Task.await(task)
    end

    test "includes url_patterns option", %{conn: conn} do
      patterns = [%{type: "string", pattern: "https://example.com/*"}]

      task =
        Task.async(fn ->
          Network.add_intercept(conn, ["responseStarted"], url_patterns: patterns)
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)

      assert decoded["params"]["urlPatterns"] == [
               %{"type" => "string", "pattern" => "https://example.com/*"}
             ]

      reply(conn, decoded["id"], %{intercept: "intercept-1"})
      Task.await(task)
    end
  end

  describe "continue_request/3" do
    test "sends network.continueRequest command", %{conn: conn} do
      task = Task.async(fn -> Network.continue_request(conn, "req-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.continueRequest"
      assert decoded["params"]["request"] == "req-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "includes options", %{conn: conn} do
      task =
        Task.async(fn ->
          Network.continue_request(conn, "req-1",
            method: "POST",
            url: "https://example.com/api",
            headers: [%{name: "X-Custom", value: %{type: "string", value: "test"}}]
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["method"] == "POST"
      assert decoded["params"]["url"] == "https://example.com/api"
      assert length(decoded["params"]["headers"]) == 1

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "continue_response/3" do
    test "sends network.continueResponse command", %{conn: conn} do
      task = Task.async(fn -> Network.continue_response(conn, "req-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.continueResponse"
      assert decoded["params"]["request"] == "req-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "includes options", %{conn: conn} do
      task =
        Task.async(fn ->
          Network.continue_response(conn, "req-1",
            status_code: 200,
            reason_phrase: "OK"
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["statusCode"] == 200
      assert decoded["params"]["reasonPhrase"] == "OK"

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "continue_with_auth/2" do
    test "sends network.continueWithAuth command", %{conn: conn} do
      task =
        Task.async(fn ->
          Network.continue_with_auth(conn, "req-1")
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.continueWithAuth"
      assert decoded["params"]["request"] == "req-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "disown_data/4" do
    test "sends network.disownData command", %{conn: conn} do
      task =
        Task.async(fn -> Network.disown_data(conn, "request", "collector-1", "req-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.disownData"
      assert decoded["params"]["dataType"] == "request"
      assert decoded["params"]["collector"] == "collector-1"
      assert decoded["params"]["request"] == "req-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "fail_request/2" do
    test "sends network.failRequest command", %{conn: conn} do
      task = Task.async(fn -> Network.fail_request(conn, "req-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.failRequest"
      assert decoded["params"]["request"] == "req-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "get_data/4" do
    test "sends network.getData command", %{conn: conn} do
      task = Task.async(fn -> Network.get_data(conn, "response", "req-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.getData"
      assert decoded["params"]["dataType"] == "response"
      assert decoded["params"]["request"] == "req-1"

      reply(conn, decoded["id"], %{data: "base64..."})
      assert {:ok, %{"data" => "base64..."}} = Task.await(task)
    end

    test "includes options", %{conn: conn} do
      task =
        Task.async(fn ->
          Network.get_data(conn, "response", "req-1",
            collector: "collector-1",
            disown: true
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["collector"] == "collector-1"
      assert decoded["params"]["disown"] == true

      reply(conn, decoded["id"], %{data: "base64..."})
      Task.await(task)
    end
  end

  describe "provide_response/3" do
    test "sends network.provideResponse command", %{conn: conn} do
      task = Task.async(fn -> Network.provide_response(conn, "req-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.provideResponse"
      assert decoded["params"]["request"] == "req-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "includes options", %{conn: conn} do
      task =
        Task.async(fn ->
          Network.provide_response(conn, "req-1",
            status_code: 404,
            reason_phrase: "Not Found",
            body: %{type: "string", value: "Not found"},
            headers: [%{name: "Content-Type", value: %{type: "string", value: "text/plain"}}]
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["statusCode"] == 404
      assert decoded["params"]["reasonPhrase"] == "Not Found"
      assert decoded["params"]["body"]["type"] == "string"
      assert length(decoded["params"]["headers"]) == 1

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "remove_data_collector/2" do
    test "sends network.removeDataCollector command", %{conn: conn} do
      task = Task.async(fn -> Network.remove_data_collector(conn, "collector-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.removeDataCollector"
      assert decoded["params"]["collector"] == "collector-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "remove_intercept/2" do
    test "sends network.removeIntercept command", %{conn: conn} do
      task = Task.async(fn -> Network.remove_intercept(conn, "intercept-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.removeIntercept"
      assert decoded["params"]["intercept"] == "intercept-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_cache_behavior/3" do
    test "sends network.setCacheBehavior command", %{conn: conn} do
      task = Task.async(fn -> Network.set_cache_behavior(conn, "bypass") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.setCacheBehavior"
      assert decoded["params"]["cacheBehavior"] == "bypass"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "includes contexts option", %{conn: conn} do
      task =
        Task.async(fn ->
          Network.set_cache_behavior(conn, "default", contexts: ["ctx-1"])
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["contexts"] == ["ctx-1"]

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "set_extra_headers/3" do
    test "sends network.setExtraHeaders command", %{conn: conn} do
      headers = [%{name: "X-Custom", value: %{type: "string", value: "test"}}]
      task = Task.async(fn -> Network.set_extra_headers(conn, headers) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "network.setExtraHeaders"
      assert length(decoded["params"]["headers"]) == 1

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "includes contexts and user_contexts options", %{conn: conn} do
      task =
        Task.async(fn ->
          Network.set_extra_headers(conn, [],
            contexts: ["ctx-1"],
            user_contexts: ["user-ctx-1"]
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["contexts"] == ["ctx-1"]
      assert decoded["params"]["userContexts"] == ["user-ctx-1"]

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end
end
