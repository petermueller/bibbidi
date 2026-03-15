defprotocol Bibbidi.Expandable do
  @fallback_to_any true

  @moduledoc """
  Protocol for expanding high-level commands into trees of wire commands.

  Return values from `expand/1`:
  - A struct implementing `Encodable` (leaf — send this single command)
  - A list of `Expandable` values (sequence — run all in order)
  - A `{expandable, handler}` tuple where handler receives the result
    and returns `{:cont, next_expandable}` or `{:halt, final_result}`
  """

  @type expansion ::
          Bibbidi.Encodable.t()
          | [expansion()]
          | {expansion(), (term() -> {:cont, expansion()} | {:halt, term()})}

  @doc """
  Expand a command into an execution plan.

  Leaf commands (Encodable structs) should return themselves.
  """
  @spec expand(t()) :: expansion()
  def expand(command)
end

defimpl Bibbidi.Expandable, for: Any do
  @doc """
  Default implementation returns the struct unchanged (identity expansion).

  This makes every `Encodable` struct a valid leaf in an expansion tree
  without requiring explicit `Expandable` implementations.
  """
  def expand(command), do: command
end
