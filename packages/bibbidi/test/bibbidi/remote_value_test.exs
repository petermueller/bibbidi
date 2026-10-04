defmodule Bibbidi.RemoteValueTest do
  use ExUnit.Case, async: true

  doctest Bibbidi.RemoteValue

  alias Bibbidi.RemoteValue

  defp num(n), do: %{"type" => "number", "value" => n}
  defp str(s), do: %{"type" => "string", "value" => s}

  describe "to_term/1 primitives" do
    test "undefined and null are distinct" do
      assert RemoteValue.to_term(%{"type" => "undefined"}) == :undefined
      assert RemoteValue.to_term(%{"type" => "null"}) == nil
    end

    test "string, boolean, number pass through" do
      assert RemoteValue.to_term(str("hi")) == "hi"
      assert RemoteValue.to_term(%{"type" => "boolean", "value" => false}) == false
      assert RemoteValue.to_term(num(42)) == 42
      assert RemoteValue.to_term(num(1.5)) == 1.5
    end

    test "special numbers become atoms, -0 becomes -0.0" do
      assert RemoteValue.to_term(num("NaN")) == :nan
      assert RemoteValue.to_term(num("Infinity")) == :infinity
      assert RemoteValue.to_term(num("-Infinity")) == :neg_infinity
      assert RemoteValue.to_term(num("-0")) === -0.0
    end

    test "bigint becomes an integer" do
      assert RemoteValue.to_term(%{"type" => "bigint", "value" => "12345678901234567890"}) ==
               12_345_678_901_234_567_890
    end
  end

  describe "to_term/1 collections" do
    test "array, nodelist, htmlcollection become lists" do
      for type <- ["array", "nodelist", "htmlcollection"] do
        assert RemoteValue.to_term(%{"type" => type, "value" => [num(1), str("a")]}) == [1, "a"]
      end
    end

    test "set becomes a MapSet" do
      assert RemoteValue.to_term(%{"type" => "set", "value" => [num(1), num(2), num(1)]}) ==
               MapSet.new([1, 2])
    end

    test "object becomes a string-keyed map, recursively" do
      value = %{
        "type" => "object",
        "value" => [
          ["name", str("Widget")],
          ["tags", %{"type" => "array", "value" => [str("a"), str("b")]}],
          [
            "meta",
            %{"type" => "object", "value" => [["ok", %{"type" => "boolean", "value" => true}]]}
          ]
        ]
      }

      assert RemoteValue.to_term(value) == %{
               "name" => "Widget",
               "tags" => ["a", "b"],
               "meta" => %{"ok" => true}
             }
    end

    test "map keys may be RemoteValues" do
      value = %{"type" => "map", "value" => [[num(1), str("one")], ["two", num(2)]]}
      assert RemoteValue.to_term(value) == %{1 => "one", "two" => 2}
    end

    test "date becomes a DateTime, falling back to the string" do
      assert RemoteValue.to_term(%{"type" => "date", "value" => "2026-10-04T01:02:03.000Z"}) ==
               ~U[2026-10-04 01:02:03.000Z]

      assert RemoteValue.to_term(%{"type" => "date", "value" => "Invalid Date"}) == "Invalid Date"
    end

    test "regexp returns the pattern/flags map" do
      assert RemoteValue.to_term(%{
               "type" => "regexp",
               "value" => %{"pattern" => "a+", "flags" => "gi"}
             }) ==
               %{"pattern" => "a+", "flags" => "gi"}
    end
  end

  describe "to_term/1 leaves reference and opaque values untouched" do
    test "node keeps its sharedId" do
      node = %{
        "type" => "node",
        "sharedId" => "n1",
        "value" => %{"nodeType" => 1, "localName" => "div"}
      }

      assert RemoteValue.to_term(node) == node
    end

    test "window, function, promise, error, symbol pass through" do
      for raw <- [
            %{"type" => "window", "value" => %{"context" => "ctx"}},
            %{"type" => "function", "handle" => "h"},
            %{"type" => "promise"},
            %{"type" => "error", "handle" => "h"},
            %{"type" => "symbol"}
          ] do
        assert RemoteValue.to_term(raw) == raw
      end
    end

    test "depth-truncated object (no value) is returned raw so the handle survives" do
      raw = %{"type" => "object", "handle" => "h1"}
      assert RemoteValue.to_term(raw) == raw
    end

    test "cyclic back-reference is returned raw inside its parent" do
      value = %{
        "type" => "object",
        "internalId" => "1",
        "value" => [["self", %{"type" => "object", "internalId" => "1"}]]
      }

      assert RemoteValue.to_term(value) == %{"self" => %{"type" => "object", "internalId" => "1"}}
    end

    test "identity is dropped from values that are converted" do
      value = %{"type" => "object", "handle" => "h1", "value" => [["a", num(1)]]}
      assert RemoteValue.to_term(value) == %{"a" => 1}
    end
  end

  describe "ref/1, handle/1, shared_id/1" do
    test "node prefers sharedId" do
      node = %{"type" => "node", "sharedId" => "n1", "handle" => "h1"}
      assert RemoteValue.ref(node) == %{"sharedId" => "n1"}
      assert RemoteValue.shared_id(node) == "n1"
      assert RemoteValue.handle(node) == "h1"
    end

    test "object with a handle" do
      obj = %{"type" => "object", "handle" => "h1", "value" => []}
      assert RemoteValue.ref(obj) == %{"handle" => "h1"}
      assert RemoteValue.handle(obj) == "h1"
      assert RemoteValue.shared_id(obj) == nil
    end

    test "no identity yields nil everywhere" do
      obj = %{"type" => "object", "value" => []}
      assert RemoteValue.ref(obj) == nil
      assert RemoteValue.handle(obj) == nil
      assert RemoteValue.shared_id(obj) == nil
    end
  end
end
