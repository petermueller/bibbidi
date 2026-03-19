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

  ## Examples

      iex> Bibbidi.CDDL.Utils.to_module_name("browsingContext")
      "BrowsingContext"

      iex> Bibbidi.CDDL.Utils.to_module_name("webExtension")
      "WebExtension"

      iex> Bibbidi.CDDL.Utils.to_module_name("session")
      "Session"
  """
  def to_module_name(str) do
    str
    |> String.replace(~r/([a-z])([A-Z])/, "\\1_\\2")
    |> String.split(~r/[_-]/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end

  @doc """
  Converts a camelCase string to snake_case.
  """
  def to_snake(str) do
    str
    |> String.replace(~r/([a-z])([A-Z])/, "\\1_\\2")
    |> String.replace(~r/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
    |> String.replace("-", "_")
    |> String.downcase()
  end
end
