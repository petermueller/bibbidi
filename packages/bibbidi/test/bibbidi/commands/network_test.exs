defmodule Bibbidi.Commands.NetworkTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.Network

  describe "add_data_collector/4" do
    test "sends network.addDataCollector command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.addDataCollector"
        assert cmd.data_types == ["request", "response"]
        assert cmd.max_encoded_data_size == 1_048_576
      end)

      assert {:ok, %{}} =
               Network.add_data_collector(:conn, ["request", "response"], 1_048_576,
                 connection_mod: MockConnection
               )
    end

    test "includes options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.collector_type == "blob"
        assert cmd.contexts == ["ctx-1"]
      end)

      Network.add_data_collector(:conn, ["request"], 1024,
        collector_type: "blob",
        contexts: ["ctx-1"],
        connection_mod: MockConnection
      )
    end
  end

  describe "add_intercept/3" do
    test "sends network.addIntercept command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.addIntercept"
        assert cmd.phases == ["beforeRequestSent"]
      end)

      assert {:ok, %{}} =
               Network.add_intercept(:conn, ["beforeRequestSent"], connection_mod: MockConnection)
    end

    test "includes url_patterns option" do
      patterns = [%{type: "string", pattern: "https://example.com/*"}]

      expect_execute(fn _conn, cmd ->
        assert cmd.url_patterns == patterns
      end)

      Network.add_intercept(:conn, ["responseStarted"],
        url_patterns: patterns,
        connection_mod: MockConnection
      )
    end
  end

  describe "continue_request/3" do
    test "sends network.continueRequest command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.continueRequest"
        assert cmd.request == "req-1"
      end)

      assert {:ok, %{}} =
               Network.continue_request(:conn, "req-1", connection_mod: MockConnection)
    end

    test "includes options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.method == "POST"
        assert cmd.url == "https://example.com/api"
        assert length(cmd.headers) == 1
      end)

      Network.continue_request(:conn, "req-1",
        method: "POST",
        url: "https://example.com/api",
        headers: [%{name: "X-Custom", value: %{type: "string", value: "test"}}],
        connection_mod: MockConnection
      )
    end
  end

  describe "continue_response/3" do
    test "sends network.continueResponse command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.continueResponse"
        assert cmd.request == "req-1"
      end)

      assert {:ok, %{}} =
               Network.continue_response(:conn, "req-1", connection_mod: MockConnection)
    end

    test "includes options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.status_code == 200
        assert cmd.reason_phrase == "OK"
      end)

      Network.continue_response(:conn, "req-1",
        status_code: 200,
        reason_phrase: "OK",
        connection_mod: MockConnection
      )
    end
  end

  describe "continue_with_auth/2" do
    test "sends network.continueWithAuth command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.continueWithAuth"
        assert cmd.request == "req-1"
      end)

      assert {:ok, %{}} =
               Network.continue_with_auth(:conn, "req-1", connection_mod: MockConnection)
    end
  end

  describe "disown_data/4" do
    test "sends network.disownData command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.disownData"
        assert cmd.data_type == "request"
        assert cmd.collector == "collector-1"
        assert cmd.request == "req-1"
      end)

      assert {:ok, %{}} =
               Network.disown_data(:conn, "request", "collector-1", "req-1",
                 connection_mod: MockConnection
               )
    end
  end

  describe "fail_request/2" do
    test "sends network.failRequest command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.failRequest"
        assert cmd.request == "req-1"
      end)

      assert {:ok, %{}} =
               Network.fail_request(:conn, "req-1", connection_mod: MockConnection)
    end
  end

  describe "get_data/4" do
    test "sends network.getData command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.getData"
        assert cmd.data_type == "response"
        assert cmd.request == "req-1"
      end)

      assert {:ok, %{}} =
               Network.get_data(:conn, "response", "req-1", connection_mod: MockConnection)
    end

    test "includes options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.collector == "collector-1"
        assert cmd.disown == true
      end)

      Network.get_data(:conn, "response", "req-1",
        collector: "collector-1",
        disown: true,
        connection_mod: MockConnection
      )
    end
  end

  describe "provide_response/3" do
    test "sends network.provideResponse command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.provideResponse"
        assert cmd.request == "req-1"
      end)

      assert {:ok, %{}} =
               Network.provide_response(:conn, "req-1", connection_mod: MockConnection)
    end

    test "includes options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.status_code == 404
        assert cmd.reason_phrase == "Not Found"
        assert cmd.body == %{type: "string", value: "Not found"}
        assert length(cmd.headers) == 1
      end)

      Network.provide_response(:conn, "req-1",
        status_code: 404,
        reason_phrase: "Not Found",
        body: %{type: "string", value: "Not found"},
        headers: [%{name: "Content-Type", value: %{type: "string", value: "text/plain"}}],
        connection_mod: MockConnection
      )
    end
  end

  describe "remove_data_collector/2" do
    test "sends network.removeDataCollector command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.removeDataCollector"
        assert cmd.collector == "collector-1"
      end)

      assert {:ok, %{}} =
               Network.remove_data_collector(:conn, "collector-1", connection_mod: MockConnection)
    end
  end

  describe "remove_intercept/2" do
    test "sends network.removeIntercept command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.removeIntercept"
        assert cmd.intercept == "intercept-1"
      end)

      assert {:ok, %{}} =
               Network.remove_intercept(:conn, "intercept-1", connection_mod: MockConnection)
    end
  end

  describe "set_cache_behavior/3" do
    test "sends network.setCacheBehavior command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.setCacheBehavior"
        assert cmd.cache_behavior == "bypass"
      end)

      assert {:ok, %{}} =
               Network.set_cache_behavior(:conn, "bypass", connection_mod: MockConnection)
    end

    test "includes contexts option" do
      expect_execute(fn _conn, cmd ->
        assert cmd.contexts == ["ctx-1"]
      end)

      Network.set_cache_behavior(:conn, "default",
        contexts: ["ctx-1"],
        connection_mod: MockConnection
      )
    end
  end

  describe "set_extra_headers/3" do
    test "sends network.setExtraHeaders command" do
      headers = [%{name: "X-Custom", value: %{type: "string", value: "test"}}]

      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "network.setExtraHeaders"
        assert length(cmd.headers) == 1
      end)

      assert {:ok, %{}} =
               Network.set_extra_headers(:conn, headers, connection_mod: MockConnection)
    end

    test "includes contexts and user_contexts options" do
      expect_execute(fn _conn, cmd ->
        assert cmd.contexts == ["ctx-1"]
        assert cmd.user_contexts == ["user-ctx-1"]
      end)

      Network.set_extra_headers(:conn, [],
        contexts: ["ctx-1"],
        user_contexts: ["user-ctx-1"],
        connection_mod: MockConnection
      )
    end
  end
end
