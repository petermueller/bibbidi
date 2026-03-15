defprotocol Bibbidi.Operation.Reducer do
  @moduledoc """
  Protocol for interpreting a completed operation into a consumer-meaningful result.

  Given the original command and the completed operation record,
  produce a consumer-facing result. This is optional — consumers can always
  destructure `%Bibbidi.Operation{}` directly.

  Different consumers (trace writers, RPA loggers, test reporters) can
  implement this protocol to interpret the same operation data differently.
  """

  @doc """
  Reduce an operation into a consumer-facing result.

  The operation contains all commands sent, all responses received,
  all events captured, and timing information.
  """
  @spec reduce(t(), Bibbidi.Operation.t()) :: term()
  def reduce(command, operation)
end
