defmodule Bibbidi.CDDL.Generator.Examples do
  @moduledoc false

  # Per-artifact example registry consulted by `mix bibbidi.gen`.
  #
  # The generator looks up each emission point (command struct module,
  # facade builder function, event struct module, event helper function)
  # by its fully-qualified Elixir name. If a matching markdown file exists
  # under `priv/examples/`, its contents are spliced into the generated
  # `@moduledoc` / `@doc` under a `## Examples` heading. Missing files are
  # not an error — the generator just emits today's docstring unchanged.
  #
  # Example file paths:
  #   priv/examples/Bibbidi.Commands.Session.Subscribe.md   (struct @moduledoc)
  #   priv/examples/Bibbidi.Commands.Session.subscribe.md   (facade @doc)
  #   priv/examples/Bibbidi.Events.BrowsingContext.ContextCreated.md
  #   priv/examples/Bibbidi.Events.BrowsingContext.context_created.md

  @default_dir "priv/examples"

  @doc """
  Returns a docstring fragment to splice for the given generated Elixir name,
  or `""` if no example file exists for it.

  When an example exists, the returned fragment is already shaped to drop
  into a heredoc whose closing `\"\"\"` sits at two-space indentation —
  every line is prefixed with `"  "` so it survives the generated module's
  heredoc dedent and renders as expected in ExDoc / IEx.
  """
  @spec for_name(String.t()) :: String.t()
  def for_name(elixir_name) when is_binary(elixir_name) do
    path = Path.join(dir(), elixir_name <> ".md")

    case File.read(path) do
      {:ok, body} ->
        body
        |> String.trim_trailing()
        |> indent_lines("  ")
        |> wrap()

      {:error, _} ->
        ""
    end
  end

  @doc """
  Directory the registry is loaded from. Defaults to `priv/examples` and is
  resolved relative to the current working directory (the generator runs
  from `packages/bibbidi/`). Tests override this via
  `Application.put_env(:bibbidi, :examples_dir, ...)`.
  """
  @spec dir() :: Path.t()
  def dir do
    Application.get_env(:bibbidi, :examples_dir, @default_dir)
  end

  defp indent_lines(body, prefix) do
    body
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> prefix <> line
    end)
  end

  defp wrap(indented_body) do
    "\n\n  ## Examples\n\n" <> indented_body <> "\n"
  end
end
