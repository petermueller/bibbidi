defmodule Bibbidi.Events.GuardsTest do
  @moduledoc """
  Codegen-drift catcher for the generated event plumbing.

  Discovers event struct modules from the compiled `:bibbidi` app rather
  than from `Bibbidi.Events.event_modules/0`, so a freshly generated event
  (or a whole new namespace) that the `Events` / `Guards` generators missed
  is caught here instead of silently falling through
  `when is_bibbidi_event(msg)` clauses in user code.
  """

  use ExUnit.Case, async: true

  alias Bibbidi.Events
  alias Bibbidi.Events.Guards

  require Guards

  # Event struct modules are the `Bibbidi.Events.*` modules that define both
  # a struct and `method/0`. That excludes the namespace helper modules
  # (`Bibbidi.Events.Log`), `Guards`, and `Unknown` (struct, but no `method/0`).
  defp discovered_event_modules do
    {:ok, mods} = :application.get_key(:bibbidi, :modules)

    mods
    |> Enum.filter(&event_struct_module?/1)
    |> Enum.sort()
  end

  defp event_struct_module?(mod) do
    String.starts_with?(Atom.to_string(mod), "Elixir.Bibbidi.Events.") and
      Code.ensure_loaded?(mod) and
      function_exported?(mod, :__struct__, 0) and
      function_exported?(mod, :method, 0)
  end

  # Every exported 1-arity `is_bibbidi_*` macro except the umbrella guard.
  defp namespace_guards do
    for {name, 1} <- Guards.__info__(:macros),
        name != :is_bibbidi_event,
        String.starts_with?(Atom.to_string(name), "is_bibbidi_"),
        do: name
  end

  # `Bibbidi.Events.BrowsingContext.Load` -> :is_bibbidi_browsing_context_event
  defp expected_guard_for(mod) do
    ["Bibbidi", "Events", namespace | _] = Module.split(mod)
    :"is_bibbidi_#{Macro.underscore(namespace)}_event"
  end

  # Guard names are only known at runtime, so evaluate the macro call.
  defp guard_matches?(guard, term) do
    {result, _binding} =
      Code.eval_string(
        "require Bibbidi.Events.Guards; Bibbidi.Events.Guards.#{guard}(term)",
        term: term
      )

    result
  end

  test "discovers at least the namespaces the codegen is known to emit" do
    mods = discovered_event_modules()

    assert Events.Log.EntryAdded in mods
    assert Events.BrowsingContext.Load in mods
    assert Events.Script.Message in mods
    refute Events.Unknown in mods
  end

  test "Events.event_modules/0 lists exactly the discovered event structs" do
    assert Enum.sort(Events.event_modules()) == discovered_event_modules()
  end

  test "Events.parse/2 dispatches every discovered method to its struct" do
    for mod <- discovered_event_modules() do
      assert %^mod{} = Events.parse(mod.method(), %{}),
             "#{inspect(mod)}.method/0 (#{mod.method()}) is not dispatched by Events.parse/2"
    end
  end

  test "is_bibbidi_event/1 matches every discovered event struct" do
    for mod <- discovered_event_modules() do
      assert Guards.is_bibbidi_event(struct(mod)),
             "#{inspect(mod)} is not matched by is_bibbidi_event/1"
    end
  end

  test "every discovered event struct is matched by exactly its namespace guard" do
    guards = namespace_guards()

    for mod <- discovered_event_modules() do
      expected = expected_guard_for(mod)

      assert expected in guards,
             "no #{expected}/1 guard generated for #{inspect(mod)}"

      matching = Enum.filter(guards, &guard_matches?(&1, struct(mod)))

      assert matching == [expected],
             "#{inspect(mod)} matched #{inspect(matching)}, expected only #{expected}"
    end
  end

  test "every namespace guard matches at least one discovered event struct" do
    structs = Enum.map(discovered_event_modules(), &struct/1)

    for guard <- namespace_guards() do
      assert Enum.any?(structs, &guard_matches?(guard, &1)),
             "#{guard}/1 matches no generated event struct (stale namespace?)"
    end
  end

  test "namespace guards never match %Unknown{}" do
    unknown = %Events.Unknown{method: "log.entryAdded", params: %{}}

    for guard <- namespace_guards() do
      refute guard_matches?(guard, unknown), "#{guard}/1 unexpectedly matched %Unknown{}"
    end
  end
end
