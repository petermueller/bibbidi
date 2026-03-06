defmodule Mix.Tasks.Bibbidi.Gen do
  @moduledoc """
  Generates type and event modules from the CDDL spec files.

      mix bibbidi.gen

  Reads `priv/cddl/remote.cddl` and `priv/cddl/local.cddl`, parses them,
  and generates:

    * `lib/bibbidi/types/<module>.ex` — typespecs for all types
    * `lib/bibbidi/events/<module>.ex` — event method names and helpers
  """

  use Mix.Task

  @shortdoc "Generate types and events from CDDL spec"

  @impl Mix.Task
  def run(_args) do
    Bibbidi.CDDL.Generator.run()
    Mix.shell().info("Done.")
  end
end
