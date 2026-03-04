defmodule Bibbidi.Commands.LogTest do
  use ExUnit.Case, async: true

  test "module exists and has no commands" do
    assert {:module, Bibbidi.Commands.Log} = Code.ensure_loaded(Bibbidi.Commands.Log)

    # Log module defines no commands — it only produces events.
    # Verify no public functions are exported (besides module_info).
    exports =
      Bibbidi.Commands.Log.__info__(:functions)
      |> Keyword.keys()
      |> Enum.reject(&(&1 == :__info__))

    assert exports == []
  end
end
