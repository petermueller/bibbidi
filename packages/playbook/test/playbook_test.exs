defmodule PlaybookTest do
  use ExUnit.Case
  doctest Playbook

  test "greets the world" do
    assert Playbook.hello() == :world
  end
end
