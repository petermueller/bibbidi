defmodule Bibbidi.Operation do
  @moduledoc """
  Tracks all commands, responses, and events produced during execution
  of an expandable command tree.

  An operation correlates everything back to the original intent,
  enabling trace generation, logging, and structured result interpretation.
  """

  @type step :: %{
          command: Bibbidi.Encodable.t(),
          response: term() | nil,
          sent_at: integer(),
          received_at: integer() | nil
        }

  @type event :: %{
          event: String.t(),
          params: map(),
          timestamp: integer()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          intent: term(),
          steps: [step()],
          events: [event()],
          started_at: integer(),
          ended_at: integer() | nil,
          status: :running | :completed | :failed,
          error: term() | nil
        }

  defstruct [
    :id,
    :intent,
    :started_at,
    :ended_at,
    :error,
    steps: [],
    events: [],
    status: :running
  ]
end
