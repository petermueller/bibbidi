defmodule Bibbidi.Events do
  @moduledoc """
  Top-level dispatcher for parsing raw BiDi event params into typed structs.
  """

  @doc """
  Parses a raw BiDi event into a typed struct.

  Dispatches to the appropriate module's `parse/2` based on the method prefix.
  Returns the raw params map for unknown event types.

  ## Examples

      iex> Bibbidi.Events.parse("browsingContext.load", %{"context" => "ctx-1", "url" => "..."})
      %Bibbidi.Events.BrowsingContext.NavigationInfo{method: :load, context: "ctx-1", ...}

      iex> Bibbidi.Events.parse("unknown.event", %{"foo" => "bar"})
      %{"foo" => "bar"}
  """
  @spec parse(String.t(), map()) :: struct() | map()
  def parse(method, params) do
    case String.split(method, ".", parts: 2) do
      ["browsingContext", _] -> Bibbidi.Events.BrowsingContext.parse(method, params)
      ["network", _] -> Bibbidi.Events.Network.parse(method, params)
      ["script", _] -> Bibbidi.Events.Script.parse(method, params)
      ["log", _] -> Bibbidi.Events.Log.parse(method, params)
      ["input", _] -> Bibbidi.Events.Input.parse(method, params)
      _ -> params
    end
  end
end
