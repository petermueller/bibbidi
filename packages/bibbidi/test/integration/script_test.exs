defmodule Bibbidi.Integration.ScriptTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.Script.{Evaluate, CallFunction, GetRealms}

  describe "function API" do
    test "evaluate a simple expression", %{conn: conn, context: context} do
      {:ok, result} = Script.evaluate(conn, "1 + 1", %{context: context}, true)
      assert result["result"]["type"] == "number"
      assert result["result"]["value"] == 2
    end

    test "call a function", %{conn: conn, context: context} do
      {:ok, result} =
        Script.call_function(conn, "function(a, b) { return a + b; }", true, %{context: context},
          arguments: [%{type: "number", value: 3}, %{type: "number", value: 4}]
        )

      assert result["result"]["type"] == "number"
      assert result["result"]["value"] == 7
    end

    test "get realms", %{conn: conn} do
      {:ok, result} = Script.get_realms(conn)
      assert is_list(result["realms"])
    end
  end

  describe "struct API via Connection.execute/2" do
    test "evaluate a simple expression", %{conn: conn, context: context} do
      {:ok, result} =
        Connection.execute(conn, %Evaluate{
          expression: "1 + 1",
          target: %{context: context},
          await_promise: false
        })

      assert result["result"]["type"] == "number"
      assert result["result"]["value"] == 2
    end

    test "evaluate with await_promise", %{conn: conn, context: context} do
      {:ok, result} =
        Connection.execute(conn, %Evaluate{
          expression: "Promise.resolve(42)",
          target: %{context: context},
          await_promise: true
        })

      assert result["result"]["type"] == "number"
      assert result["result"]["value"] == 42
    end

    test "call a function", %{conn: conn, context: context} do
      {:ok, result} =
        Connection.execute(conn, %CallFunction{
          function_declaration: "function(a, b) { return a + b; }",
          target: %{context: context},
          await_promise: false,
          arguments: [%{type: "number", value: 3}, %{type: "number", value: 4}]
        })

      assert result["result"]["type"] == "number"
      assert result["result"]["value"] == 7
    end

    test "call a function without arguments", %{conn: conn, context: context} do
      {:ok, result} =
        Connection.execute(conn, %CallFunction{
          function_declaration: "function() { return 99; }",
          target: %{context: context},
          await_promise: false
        })

      assert result["result"]["type"] == "number"
      assert result["result"]["value"] == 99
    end

    test "get realms", %{conn: conn} do
      {:ok, result} = Connection.execute(conn, %GetRealms{})
      assert is_list(result["realms"])
    end
  end
end
