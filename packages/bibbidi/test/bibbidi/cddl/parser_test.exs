defmodule Bibbidi.CDDL.ParserTest do
  use ExUnit.Case, async: true

  alias Bibbidi.CDDL.Parser

  describe "parse/1 basics" do
    test "parses simple type alias" do
      assert {:ok, [{"Foo", {:primitive, :text}}]} = Parser.parse("Foo = text")
    end

    test "parses type alias with semicolon" do
      assert {:ok, [{"Foo", {:primitive, :text}}]} = Parser.parse("Foo = text;")
    end

    test "parses numeric range" do
      assert {:ok, [{"js-uint", {:range, 0, 9_007_199_254_740_991}}]} =
               Parser.parse("js-uint = 0..9007199254740991")
    end

    test "parses string enum with /" do
      assert {:ok, [{"Foo", {:choice, [{:string, "a"}, {:string, "b"}]}}]} =
               Parser.parse(~s|Foo = "a" / "b"|)
    end

    test "parses simple map" do
      assert {:ok, [{"Foo", {:map, _}}]} = Parser.parse("Foo = { bar: text }")
    end

    test "parses map with optional field" do
      {:ok, [{"Foo", {:map, [{:fields, fields}]}}]} =
        Parser.parse("Foo = { name: text, ? age: uint }")

      assert {:required, "name", {:primitive, :text}} = Enum.at(fields, 0)
      assert {:optional, "age", {:primitive, :uint}} = Enum.at(fields, 1)
    end

    test "parses group with method and params" do
      {:ok, [{"Foo", {:group, members}}]} =
        Parser.parse(~s|Foo = ( method: "session.status", params: EmptyParams )|)

      assert {:required, "method", {:string, "session.status"}} = Enum.at(members, 0)
      assert {:required, "params", {:ref, "EmptyParams"}} = Enum.at(members, 1)
    end

    test "parses group choice with //" do
      {:ok, [{"Foo", {:group_choice, _groups}}]} =
        Parser.parse("Foo = ( A // B // C )")
    end

    test "parses type choice in group with /" do
      {:ok, [{"Foo", {:choice, items}}]} =
        Parser.parse("Foo = ( A / B / C )")

      assert length(items) == 3
    end

    test "parses array types" do
      {:ok, [{"Foo", {:array, {:primitive, :text}, :zero_or_more}}]} =
        Parser.parse("Foo = [*text]")

      {:ok, [{"Bar", {:array, {:primitive, :text}, :one_or_more}}]} =
        Parser.parse("Bar = [+text]")
    end

    test "parses array with spaces around quantifier" do
      {:ok, [{"Foo", {:array, {:ref, "Bar"}, :one_or_more}}]} =
        Parser.parse("Foo = [ + Bar ]")
    end

    test "parses constraint .default" do
      {:ok, [{"Foo", {:primitive, :bool, {:default, {:string, "false"}}}}]} =
        Parser.parse(~s|Foo = bool .default "false"|)
    end

    test "parses constraint .ge" do
      {:ok, [{"Foo", {:primitive, :float, {:ge, {:number, +0.0}}}}]} =
        Parser.parse("Foo = float .ge 0.0")
    end

    test "parses extensible map" do
      {:ok, [{"Foo", {:map, [{:fields, fields}]}}]} =
        Parser.parse("Foo = { name: text, *text => any }")

      assert {:extensible, _, _} = List.last(fields)
    end

    test "parses map with group choice //" do
      {:ok, [{"Foo", {:map, [{:group_choice, _}]}}]} =
        Parser.parse("Foo = { A // B }")
    end

    test "parses null type" do
      assert {:ok, [{"Foo", {:choice, [{:ref, "Bar"}, {:primitive, :null}]}}]} =
               Parser.parse("Foo = Bar / null")
    end

    test "handles line comments" do
      {:ok, rules} = Parser.parse("; this is a comment\nFoo = text")
      assert [{"Foo", {:primitive, :text}}] = rules
    end

    test "handles html comments" do
      {:ok, rules} = Parser.parse("<!-- comment -->\nFoo = text")
      assert [{"Foo", {:primitive, :text}}] = rules
    end

    test "parses parenthesized constrained type" do
      cddl = "Foo = { ? bar: (uint .ge 1) }"
      {:ok, [{"Foo", _}]} = Parser.parse(cddl)
    end

    test "parses type choice with maps inside group" do
      cddl = """
      Foo = (
        A /
        { B } /
        C
      )
      """

      {:ok, [{"Foo", result}]} = Parser.parse(cddl)
      assert {:choice, _} = result
    end

    test "parses nested array with tuple" do
      cddl = ~s|Foo = [*[(A / text), B]]|
      {:ok, [{"Foo", _}]} = Parser.parse(cddl)
    end
  end

  describe "parse_file/1" do
    test "parses remote.cddl" do
      {:ok, rules} = Parser.parse_file("priv/cddl/remote.cddl")
      assert length(rules) > 100

      # Check known rules exist
      names = Enum.map(rules, &elem(&1, 0))
      assert "Command" in names
      assert "SessionCommand" in names
      assert "BrowsingContextCommand" in names
      assert "NetworkCommand" in names
      assert "ScriptCommand" in names
    end

    test "parses local.cddl" do
      {:ok, rules} = Parser.parse_file("priv/cddl/local.cddl")
      assert length(rules) > 50

      names = Enum.map(rules, &elem(&1, 0))
      assert "Message" in names
      assert "CommandResponse" in names
      assert "ErrorResponse" in names
      assert "Event" in names
    end
  end
end
