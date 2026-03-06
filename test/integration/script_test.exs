defmodule Bibbidi.Integration.ScriptTest do
  use Bibbidi.IntegrationCase

  test "evaluate a simple expression", %{conn: conn, context: context} do
    {:ok, result} = Script.evaluate(conn, "1 + 1", %{context: context})
    assert result["result"]["type"] == "number"
    assert result["result"]["value"] == 2
  end

  test "call a function", %{conn: conn, context: context} do
    {:ok, result} =
      Script.call_function(conn, "function(a, b) { return a + b; }", %{context: context},
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
