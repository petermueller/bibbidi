defmodule BibbidiRunic do
  @moduledoc """
  Runic workflow integration for Bibbidi WebDriver BiDi commands.

  Wraps Bibbidi `Encodable` command structs as Runic workflow steps
  so that BiDi commands can be composed using Runic's graph-based
  workflow engine.

  ## Usage

      require Runic
      alias Bibbidi.Commands.{BrowsingContext, Script}

      workflow = Runic.workflow(
        name: "navigate and screenshot",
        steps: [
          {BibbidiRunic.step(
             %BrowsingContext.Navigate{context: ctx, url: url, wait: "complete"},
             conn: conn, name: :navigate
           ),
           [BibbidiRunic.step(
              %BrowsingContext.CaptureScreenshot{context: ctx},
              conn: conn, name: :screenshot
            )]}
        ]
      )

      results = workflow
        |> Runic.Workflow.react_until_satisfied(nil)
        |> Runic.Workflow.raw_productions()
  """

  alias Runic.Workflow.Step

  # Runic uses :erlang.phash2 with this range for content-addressable hashing
  @hash_range Integer.pow(2, 32)

  @doc """
  Create a Runic step from a Bibbidi `Encodable` command struct.

  The step sends the command via `Bibbidi.Connection.execute/2` and
  produces the result as a fact in the workflow.

  ## Options

    - `:conn` (required) — the Bibbidi connection pid or name
    - `:name` — step name (defaults to the BiDi method name)
    - `:timeout` — command timeout in milliseconds
  """
  @spec step(Bibbidi.Encodable.t(), keyword()) :: Step.t()
  def step(command, opts) do
    conn = Keyword.fetch!(opts, :conn)
    name = Keyword.get(opts, :name, default_name(command))
    cmd_opts = Keyword.take(opts, [:timeout])

    work = fn _input -> Bibbidi.Connection.execute(conn, command, cmd_opts) end

    method = Bibbidi.Encodable.method(command)
    hash = :erlang.phash2({:bibbidi_step, method, Bibbidi.Encodable.params(command)}, @hash_range)

    %Step{
      name: name,
      work: work,
      hash: hash
    }
  end

  @doc """
  Create a Runic step that builds its BiDi command at runtime from
  the input fact flowing through the workflow.

  The builder function receives the input value and must return a
  Bibbidi `Encodable` command struct.

  ## Options

    - `:conn` (required) — the Bibbidi connection pid or name
    - `:name` (required) — step name
    - `:timeout` — command timeout in milliseconds
  """
  @spec dynamic_step((term() -> Bibbidi.Encodable.t()), keyword()) :: Step.t()
  def dynamic_step(builder_fn, opts) when is_function(builder_fn, 1) do
    conn = Keyword.fetch!(opts, :conn)
    name = Keyword.fetch!(opts, :name)
    cmd_opts = Keyword.take(opts, [:timeout])

    work = fn input ->
      command = builder_fn.(input)
      Bibbidi.Connection.execute(conn, command, cmd_opts)
    end

    hash = :erlang.phash2({:bibbidi_dynamic_step, name}, @hash_range)

    %Step{
      name: name,
      work: work,
      hash: hash
    }
  end

  defp default_name(command) do
    command
    |> Bibbidi.Encodable.method()
    |> String.replace(".", "_")
    |> String.to_atom()
  end
end
