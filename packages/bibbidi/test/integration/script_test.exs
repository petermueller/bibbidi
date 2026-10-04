defmodule Bibbidi.Integration.ScriptTest do
  use Bibbidi.IntegrationCase

  alias Bibbidi.Commands.Script.{Evaluate, CallFunction, GetRealms}
  alias Bibbidi.RemoteValue

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

    # Scoped to the test's own context: Firefox 157's unfiltered script.getRealms
    # throws "TypeError: realm is null" when any open context has no realm yet.
    test "get realms", %{conn: conn, context: context} do
      {:ok, result} = Script.get_realms(conn, context: context)
      assert is_list(result["realms"])
      assert result["realms"] != []
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

    test "get realms", %{conn: conn, context: context} do
      {:ok, result} = Connection.execute(conn, %GetRealms{context: context})
      assert is_list(result["realms"])
      assert result["realms"] != []
    end
  end

  describe "RemoteValue" do
    test "to_term/1 decodes a nested evaluate result", %{conn: conn, context: context} do
      {:ok, result} =
        Script.evaluate(
          conn,
          "({name: 'Widget', price: 9.99, tags: ['a', 'b'], missing: undefined, nothing: null})",
          %{context: context},
          false
        )

      assert RemoteValue.to_term(result["result"]) == %{
               "name" => "Widget",
               "price" => 9.99,
               "tags" => ["a", "b"],
               "missing" => :undefined,
               "nothing" => nil
             }
    end

    test "ref/1 of a node round-trips as a call_function argument",
         %{conn: conn, context: context} do
      {:ok, _} =
        BrowsingContext.navigate(conn, context, "data:text/html,<p id='x'>hello</p>",
          wait: "complete"
        )

      {:ok, %{"result" => node}} =
        Script.evaluate(conn, "document.getElementById('x')", %{context: context}, false)

      assert node["type"] == "node"
      assert is_binary(RemoteValue.shared_id(node))
      assert RemoteValue.ref!(node) == %{"sharedId" => RemoteValue.shared_id(node)}
      # to_term/1 does not flatten nodes
      assert RemoteValue.to_term(node) == node

      {:ok, %{"result" => text}} =
        Script.call_function(
          conn,
          "function(el) { return el.textContent }",
          false,
          %{context: context},
          arguments: [RemoteValue.ref!(node)]
        )

      assert RemoteValue.to_term(text) == "hello"
    end

    test "ref/1 and handle/1 of a root-owned object round-trip and disown",
         %{conn: conn, context: context} do
      {:ok, %{"result" => counter}} =
        Script.evaluate(conn, "({n: 0, bump() { return ++this.n }})", %{context: context}, false,
          result_ownership: "root"
        )

      assert is_binary(RemoteValue.handle(counter))
      assert RemoteValue.ref!(counter) == %{"handle" => RemoteValue.handle(counter)}

      for expected <- [1, 2] do
        {:ok, %{"result" => n}} =
          Script.call_function(
            conn,
            "function() { return this.bump() }",
            false,
            %{context: context},
            this: RemoteValue.ref!(counter)
          )

        assert RemoteValue.to_term(n) == expected
      end

      {:ok, _} = Script.disown(conn, [RemoteValue.handle(counter)], %{context: context})
    end
  end
end
