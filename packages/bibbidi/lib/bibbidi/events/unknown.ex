defmodule Bibbidi.Events.Unknown do
  @moduledoc """
  Fallback event struct for BiDi events not covered by the generated typed structs.

  Used when an event method either:

    * does not belong to any known module namespace (vendor extensions,
      future spec versions), or
    * belongs to a known namespace but doesn't match any generated event
      struct in that namespace (codegen hasn't run for it yet).

  Carries the raw method string and params map so consumers can still inspect them.
  """

  @enforce_keys [:method]
  defstruct [:method, params: %{}]

  @type t :: %__MODULE__{
          method: String.t(),
          params: map()
        }
end
