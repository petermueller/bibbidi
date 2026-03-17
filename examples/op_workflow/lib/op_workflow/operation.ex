defmodule OpWorkflow.Operation do
  @moduledoc """
  Execution record for a workflow pipeline.

  Tracks every wire command sent, its result, and the accumulated
  named step outcomes.
  """

  @type step :: %{
          name: atom(),
          command: Bibbidi.Encodable.t() | nil,
          result: {:ok, term()} | {:error, term()},
          at: integer()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          steps: [step()],
          results: %{atom() => {:ok, term()} | {:error, term()}},
          started_at: integer(),
          ended_at: integer() | nil,
          status: :running | :completed | :failed,
          error: term() | nil
        }

  defstruct [
    :id,
    :started_at,
    :ended_at,
    :error,
    steps: [],
    results: %{},
    status: :running
  ]
end