defmodule Bibbidi.CDDL.Utils do
  @moduledoc false

  @doc """
  Returns true if the CDDL definition is a command (has method + params).
  """
  def command_def?({:group, members}) do
    Enum.any?(members, fn
      {:required, "method", {:string, _}} -> true
      _ -> false
    end) and
      Enum.any?(members, fn
        {:required, "params", _} -> true
        _ -> false
      end)
  end

  def command_def?(_), do: false

  @doc """
  Converts a camelCase BiDi module name to an Elixir module name,
  preserving internal casing boundaries.

  Known multi-letter acronyms (`XPath`, `HTML`) are preserved verbatim
  rather than collapsed to title case (`Xpath`, `Html`). This keeps the
  generated module names symmetric with `Macro.underscore/1` and
  matches Elixir convention for aliases (cf. `ExUnit.CaptureIO`,
  `Mix.SCM` — capitals retained for acronyms).

  ## Examples

      iex> Bibbidi.CDDL.Utils.to_module_name("browsingContext")
      "BrowsingContext"

      iex> Bibbidi.CDDL.Utils.to_module_name("webExtension")
      "WebExtension"

      iex> Bibbidi.CDDL.Utils.to_module_name("session")
      "Session"

      iex> Bibbidi.CDDL.Utils.to_module_name("XPathLocator")
      "XPathLocator"

      iex> Bibbidi.CDDL.Utils.to_module_name("HTMLCollectionRemoteValue")
      "HTMLCollectionRemoteValue"
  """
  def to_module_name("XPath" <> rest), do: "XPath" <> to_module_name(rest)
  def to_module_name("HTML" <> rest), do: "HTML" <> to_module_name(rest)

  def to_module_name(str) do
    # Macro.underscore |> Macro.camelize is the Elixir-idiomatic round-trip
    # for camelCase/PascalCase identifiers; it loses multi-letter acronyms
    # (handled by the explicit clauses above) and doesn't recognise hyphens
    # as word separators (`js-uint` would survive intact), so normalise
    # hyphens to underscores first — `Macro.camelize` splits on those.
    str
    |> String.replace("-", "_")
    |> Macro.underscore()
    |> Macro.camelize()
  end

  @doc """
  Converts a camelCase / PascalCase / kebab-case string to snake_case,
  matching Elixir's module-to-file-path convention.

  Uses `Macro.underscore/1`, so the result is the inverse of
  `Macro.camelize/1` (modulo multi-letter acronyms — see `to_module_name/1`
  for that nuance). Hyphens are pre-normalised because `Macro.underscore`
  treats them as identifier-illegal and leaves them intact.

  ## Examples

      iex> Bibbidi.CDDL.Utils.to_snake("browsingContext")
      "browsing_context"

      iex> Bibbidi.CDDL.Utils.to_snake("XPathLocator")
      "x_path_locator"

      iex> Bibbidi.CDDL.Utils.to_snake("Base64Value")
      "base64_value"

      iex> Bibbidi.CDDL.Utils.to_snake("js-uint")
      "js_uint"
  """
  def to_snake(str) do
    str
    |> String.replace("-", "_")
    |> Macro.underscore()
  end
end
