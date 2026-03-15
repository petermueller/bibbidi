defprotocol Bibbidi.Encodable do
  @moduledoc """
  Protocol for encoding command structs into BiDi wire format.

  Every command struct implements this protocol to provide its BiDi method
  string and parameter map.
  """

  @doc "The BiDi method string (e.g., \"browsingContext.navigate\")"
  @spec method(t()) :: String.t()
  def method(command)

  @doc "Encode into the BiDi params map to send over the wire"
  @spec params(t()) :: map()
  def params(command)
end
