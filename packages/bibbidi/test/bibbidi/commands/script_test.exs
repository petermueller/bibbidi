defmodule Bibbidi.Commands.ScriptTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.Script

  describe "evaluate/5" do
    test "sends script.evaluate command" do
      expect_execute(fn _conn, cmd ->
        assert %Script.Evaluate{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "script.evaluate"
        assert cmd.expression == "1 + 1"
        assert cmd.target == %{context: "ctx-1"}
        assert cmd.await_promise == true
      end)

      assert {:ok, %{}} =
               Script.evaluate(:conn, "1 + 1", %{context: "ctx-1"}, true,
                 connection_mod: MockConnection
               )
    end

    test "respects await_promise argument" do
      expect_execute(fn _conn, cmd ->
        assert cmd.await_promise == false
      end)

      Script.evaluate(:conn, "fetch('/api')", %{context: "ctx-1"}, false,
        connection_mod: MockConnection
      )
    end
  end

  describe "call_function/5" do
    test "sends script.callFunction command" do
      expect_execute(fn _conn, cmd ->
        assert %Script.CallFunction{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "script.callFunction"
        assert cmd.function_declaration == "function(a, b) { return a + b; }"
        assert length(cmd.arguments) == 2
      end)

      assert {:ok, %{}} =
               Script.call_function(
                 :conn,
                 "function(a, b) { return a + b; }",
                 true,
                 %{context: "ctx-1"},
                 arguments: [%{type: "number", value: 1}, %{type: "number", value: 2}],
                 connection_mod: MockConnection
               )
    end
  end

  describe "get_realms/2" do
    test "sends script.getRealms command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "script.getRealms"
      end)

      assert {:ok, %{}} = Script.get_realms(:conn, connection_mod: MockConnection)
    end
  end

  describe "add_preload_script/3" do
    test "sends script.addPreloadScript command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "script.addPreloadScript"
        assert cmd.function_declaration == "() => { window.test = true; }"
      end)

      assert {:ok, %{}} =
               Script.add_preload_script(:conn, "() => { window.test = true; }",
                 connection_mod: MockConnection
               )
    end
  end

  describe "remove_preload_script/2" do
    test "sends script.removePreloadScript command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "script.removePreloadScript"
        assert cmd.script == "script-1"
      end)

      assert {:ok, %{}} =
               Script.remove_preload_script(:conn, "script-1", connection_mod: MockConnection)
    end
  end

  describe "disown/3" do
    test "sends script.disown command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "script.disown"
        assert cmd.handles == ["handle-1"]
        assert cmd.target == %{context: "ctx-1"}
      end)

      assert {:ok, %{}} =
               Script.disown(:conn, ["handle-1"], %{context: "ctx-1"},
                 connection_mod: MockConnection
               )
    end
  end
end
