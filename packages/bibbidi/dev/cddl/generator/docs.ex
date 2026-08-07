defmodule Bibbidi.CDDL.Generator.Docs do
  @moduledoc """
  Per-artifact documentation registry consulted by `mix bibbidi.gen`.

  The generator hard-codes the *structural* parts of every `@moduledoc` /
  `@doc` it emits (spec link, field table, opts schema). Hand-written prose —
  usage examples and the like — lives here instead, so adding it never means
  editing the generator.

  Each emission point (command struct module, facade builder function, event
  struct module, event helper function) is looked up by its fully-qualified
  Elixir name. For every configured section, a matching markdown file is
  composed into the generated docstring under the section's heading. Missing
  files are not an error — the generator emits today's docstring unchanged.

  ## Sections

  A section is one `## Heading` block backed by a `priv/<dir>/` folder. Within
  it, `@moduledoc` and `@doc` examples are split into `module/` and `function/`
  subfolders, keyed by the emission point's fully-qualified Elixir name:

      priv/examples/module/Bibbidi.Commands.Session.Subscribe.md     # struct @moduledoc
      priv/examples/function/Bibbidi.Commands.Session.subscribe.md   # facade @doc
      priv/examples/module/Bibbidi.Events.BrowsingContext.ContextCreated.md
      priv/examples/function/Bibbidi.Events.BrowsingContext.context_created.md

  The subfolder is derived from the name's last segment (PascalCase → `module`,
  snake_case → `function`). The split keeps a struct moduledoc and its facade's
  `@doc` from colliding on case-insensitive filesystems, where e.g.
  `Subscribe.md` and `subscribe.md` would otherwise be the same file.

  Today there is one section, "Examples". Adding another (say a "Usage" block
  from `priv/usage/`) is a single entry in `sections/0` plus the folder — the
  generator call sites don't change.
  """

  @sections [
    %{key: :examples, heading: "Examples", dir: "priv/examples"}
  ]

  @doc """
  Returns the documentation block to splice for `elixir_name`, or `nil` when no
  configured section has content for it.

  The block is self-contained and two-space-indented on every non-blank line
  (heading included), with no surrounding blank lines — the caller decides how
  to join it onto the base docstring. Multiple sections are concatenated in
  `sections/0` order, each under its own `## <heading>`.
  """
  @spec for_name(String.t()) :: String.t() | nil
  def for_name(elixir_name) when is_binary(elixir_name) do
    sections()
    |> Enum.map(&render_section(&1, elixir_name))
    |> Enum.reject(&is_nil/1)
    |> join_sections()
  end

  @doc """
  The configured documentation sections, in emission order. Each is a map with
  `:key`, `:heading`, and `:dir`. The sole extension point — add a map here to
  introduce a new doc section.
  """
  @spec sections() :: [map()]
  def sections, do: @sections

  @doc """
  Resolves the directory a section is read from, honoring a per-section
  `:"\#{key}_dir"` application-env override (e.g. `:examples_dir`) before
  falling back to the section's `:dir`.
  """
  @spec dir(map()) :: Path.t()
  def dir(%{key: key, dir: default}) do
    Application.get_env(:bibbidi, :"#{key}_dir", default)
  end

  defp render_section(%{heading: heading} = section, elixir_name) do
    path = Path.join([dir(section), kind_dir(elixir_name), elixir_name <> ".md"])

    case File.read(path) do
      {:ok, body} ->
        indented = body |> String.trim_trailing() |> indent_lines("  ")
        "  ## #{heading}\n\n" <> indented

      {:error, _} ->
        nil
    end
  end

  # `@moduledoc` and `@doc` examples live in separate subfolders so a struct
  # moduledoc and its facade `@doc` don't collide on case-insensitive
  # filesystems. The kind is read off the last segment's case.
  defp kind_dir(elixir_name) do
    case elixir_name |> String.split(".") |> List.last() do
      <<c, _::binary>> when c in ?A..?Z -> "module"
      _ -> "function"
    end
  end

  defp join_sections([]), do: nil
  defp join_sections(blocks), do: Enum.join(blocks, "\n\n")

  defp indent_lines(body, prefix) do
    body
    |> String.split("\n")
    |> Enum.map_join("\n", fn
      "" -> ""
      line -> prefix <> line
    end)
  end
end
