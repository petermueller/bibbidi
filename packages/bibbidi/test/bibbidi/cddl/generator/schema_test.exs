defmodule Bibbidi.CDDL.Generator.SchemaTest do
  use ExUnit.Case, async: true

  alias Bibbidi.CDDL.Generator

  describe "type_to_schema/2 literals" do
    test "CDDL literal strings emit Zoi.literal/1, not Zoi.string/0" do
      assert Generator.type_to_schema({:string, "node"}) == ~s|Zoi.literal("node")|
      assert Generator.type_to_schema({:primitive, :text}) == "Zoi.string()"
    end
  end

  # Behavioural check on the generated output: with literal discriminators the
  # per-type schemas reject the wrong `type`, and the union can tell its
  # branches apart instead of accepting anything with a string `type`.
  describe "generated schemas discriminate on literal type fields" do
    alias Bibbidi.Types.Script.{NodeRemoteValue, RemoteValue}

    test "a type module rejects a different type literal" do
      assert {:ok, _} = Zoi.parse(NodeRemoteValue.schema(), %{type: "node", shared_id: "n1"})
      assert {:error, _} = Zoi.parse(NodeRemoteValue.schema(), %{type: "object", shared_id: "n1"})
    end

    test "the RemoteValue union rejects a node with a non-string sharedId" do
      assert {:ok, _} = Zoi.parse(RemoteValue.schema(), %{type: "node", shared_id: "n1"})
      assert {:error, _} = Zoi.parse(RemoteValue.schema(), %{type: "node", shared_id: 42})
      assert {:error, _} = Zoi.parse(RemoteValue.schema(), %{type: "no-such-type"})
    end
  end
end
