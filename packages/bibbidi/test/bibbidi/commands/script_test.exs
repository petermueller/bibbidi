defmodule Bibbidi.Commands.ScriptTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.Script
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

  describe "evaluate/5" do
    test "sends script.evaluate command", %{conn: conn} do
      task = Task.async(fn -> Script.evaluate(conn, "1 + 1", %{context: "ctx-1"}, true) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "script.evaluate"
      assert decoded["params"]["expression"] == "1 + 1"
      assert decoded["params"]["target"] == %{"context" => "ctx-1"}
      assert decoded["params"]["awaitPromise"] == true

      reply(conn, decoded["id"], %{type: "number", value: 2})
      assert {:ok, %{"type" => "number", "value" => 2}} = Task.await(task)
    end

    test "respects await_promise argument", %{conn: conn} do
      task =
        Task.async(fn ->
          Script.evaluate(conn, "fetch('/api')", %{context: "ctx-1"}, false)
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["params"]["awaitPromise"] == false

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "call_function/5" do
    test "sends script.callFunction command", %{conn: conn} do
      task =
        Task.async(fn ->
          Script.call_function(conn, "function(a, b) { return a + b; }", true, %{context: "ctx-1"},
            arguments: [%{type: "number", value: 1}, %{type: "number", value: 2}]
          )
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "script.callFunction"
      assert decoded["params"]["functionDeclaration"] == "function(a, b) { return a + b; }"
      assert length(decoded["params"]["arguments"]) == 2

      reply(conn, decoded["id"], %{type: "number", value: 3})
      assert {:ok, %{"type" => "number", "value" => 3}} = Task.await(task)
    end
  end

  describe "get_realms/2" do
    test "sends script.getRealms command", %{conn: conn} do
      task = Task.async(fn -> Script.get_realms(conn) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "script.getRealms"

      reply(conn, decoded["id"], %{realms: []})
      assert {:ok, %{"realms" => []}} = Task.await(task)
    end
  end

  describe "add_preload_script/3" do
    test "sends script.addPreloadScript command", %{conn: conn} do
      task =
        Task.async(fn -> Script.add_preload_script(conn, "() => { window.test = true; }") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "script.addPreloadScript"
      assert decoded["params"]["functionDeclaration"] == "() => { window.test = true; }"

      reply(conn, decoded["id"], %{script: "script-1"})
      assert {:ok, %{"script" => "script-1"}} = Task.await(task)
    end
  end

  describe "remove_preload_script/2" do
    test "sends script.removePreloadScript command", %{conn: conn} do
      task = Task.async(fn -> Script.remove_preload_script(conn, "script-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "script.removePreloadScript"
      assert decoded["params"]["script"] == "script-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "disown/3" do
    test "sends script.disown command", %{conn: conn} do
      task = Task.async(fn -> Script.disown(conn, ["handle-1"], %{context: "ctx-1"}) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "script.disown"
      assert decoded["params"]["handles"] == ["handle-1"]

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end
end
