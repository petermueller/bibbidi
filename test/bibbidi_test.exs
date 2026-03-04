defmodule BibbidiTest do
  use ExUnit.Case
  doctest Bibbidi

  test "greets the world" do
    assert Bibbidi.hello() == :world
  end
end
