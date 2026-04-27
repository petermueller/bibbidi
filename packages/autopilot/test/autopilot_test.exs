defmodule AutopilotTest do
  use ExUnit.Case
  doctest Autopilot

  test "greets the world" do
    assert Autopilot.hello() == :world
  end
end
