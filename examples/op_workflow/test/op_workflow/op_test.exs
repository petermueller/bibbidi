defmodule OpWorkflow.OpTest do
  use ExUnit.Case, async: true

  alias OpWorkflow.Op
  alias Bibbidi.Commands.BrowsingContext

  describe "new/0" do
    test "creates an empty pipeline" do
      op = Op.new()
      assert op.steps == []
    end
  end

  describe "send/3" do
    test "adds a static send step" do
      cmd = %BrowsingContext.Activate{context: "ctx-1"}
      op = Op.new() |> Op.send(:activate, cmd)
      assert [{:activate, {:send, ^cmd}}] = op.steps
    end

    test "adds a dynamic send step with function" do
      op = Op.new() |> Op.send(:dynamic, fn _results -> {:ok, :done} end)
      assert [{:dynamic, {:send_fn, fun}}] = op.steps
      assert is_function(fun, 1)
    end
  end

  describe "run/3" do
    test "adds a run step" do
      op = Op.new() |> Op.run(:custom, fn _conn, _results, _opts -> {:ok, :done} end)
      assert [{:custom, {:run, fun}}] = op.steps
      assert is_function(fun, 3)
    end
  end

  describe "branch/3" do
    test "adds a branch step" do
      op = Op.new() |> Op.branch(:decide, fn _results -> {:ok, :yes} end)
      assert [{:decide, {:branch_fn, fun}}] = op.steps
      assert is_function(fun, 1)
    end
  end

  describe "step ordering" do
    test "preserves insertion order" do
      op =
        Op.new()
        |> Op.send(:a, %BrowsingContext.Activate{context: "c"})
        |> Op.send(:b, %BrowsingContext.Activate{context: "c"})
        |> Op.send(:c, %BrowsingContext.Activate{context: "c"})

      names = Enum.map(op.steps, &elem(&1, 0))
      assert names == [:a, :b, :c]
    end
  end

  describe "name uniqueness" do
    test "rejects duplicate step names" do
      op = Op.new() |> Op.send(:nav, %BrowsingContext.Activate{context: "c"})

      assert_raise ArgumentError, ~r/already used/, fn ->
        Op.send(op, :nav, %BrowsingContext.Activate{context: "c"})
      end
    end

    test "rejects duplicates across different step types" do
      op = Op.new() |> Op.send(:x, %BrowsingContext.Activate{context: "c"})

      assert_raise ArgumentError, ~r/already used/, fn ->
        Op.branch(op, :x, fn _ -> {:ok, :y} end)
      end
    end
  end
end