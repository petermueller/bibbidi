defmodule Bibbidi.Operation.Runner do
  @moduledoc """
  Recursive interpreter that walks an `Expandable` tree, sends leaf commands
  through `Connection`, and accumulates everything into an `%Operation{}`.

  ## Telemetry Events

  The runner emits the following `:telemetry` events:

    * `[:bibbidi, :operation, :start]` — when an operation begins
      - Measurements: `%{system_time: integer()}`
      - Metadata: `%{operation: Operation.t(), conn: pid()}`

    * `[:bibbidi, :operation, :step]` — when each individual command completes
      - Measurements: `%{duration: integer()}` (in milliseconds)
      - Metadata: `%{operation: Operation.t(), step: step(), conn: pid()}`

    * `[:bibbidi, :operation, :stop]` — when an operation completes successfully
      - Measurements: `%{duration: integer()}` (in milliseconds)
      - Metadata: `%{operation: Operation.t(), result: term(), conn: pid()}`

    * `[:bibbidi, :operation, :exception]` — on failure
      - Measurements: `%{duration: integer()}` (in milliseconds)
      - Metadata: `%{operation: Operation.t(), reason: term(), conn: pid()}`
  """

  alias Bibbidi.{Connection, Encodable, Expandable, Operation}

  @doc """
  Execute an expandable command, returning `{:ok, result, operation}` or
  `{:error, reason, operation}`.

  ## Options

    - `:capture_events` - list of BiDi event names to capture during execution
    - `:timeout` - per-command timeout (default: 30_000)
  """
  @spec execute(GenServer.server(), Expandable.t(), keyword()) ::
          {:ok, term(), Operation.t()} | {:error, term(), Operation.t()}
  def execute(conn, command, opts \\ []) do
    op = %Operation{
      id: generate_id(),
      intent: command,
      started_at: System.monotonic_time(:millisecond)
    }

    :telemetry.execute(
      [:bibbidi, :operation, :start],
      %{system_time: System.system_time(:millisecond)},
      %{operation: op, conn: conn}
    )

    event_names = Keyword.get(opts, :capture_events, [])
    if event_names != [], do: setup_event_capture(conn, event_names)

    try do
      case run(conn, Expandable.expand(command), op, opts) do
        {:ok, result, op} ->
          op = finalize(op, :completed)

          :telemetry.execute(
            [:bibbidi, :operation, :stop],
            %{duration: op.ended_at - op.started_at},
            %{operation: op, result: result, conn: conn}
          )

          {:ok, result, op}

        {:error, reason, op} ->
          op = finalize(op, :failed, reason)

          :telemetry.execute(
            [:bibbidi, :operation, :exception],
            %{duration: op.ended_at - op.started_at},
            %{operation: op, reason: reason, conn: conn}
          )

          {:error, reason, op}
      end
    after
      if event_names != [], do: teardown_event_capture(conn, event_names)
    end
  end

  # Leaf — a struct, check if it's the same as what we started with (identity expansion = leaf)
  # Since Expandable.expand returns self for leaves, we detect leaves by checking
  # if expand returns the same struct. We call expand first and if it returns itself, send it.
  defp run(conn, %{__struct__: _} = cmd, op, opts) do
    expanded = Expandable.expand(cmd)

    if expanded == cmd do
      # Leaf — send on the wire
      send_leaf(conn, cmd, op, opts)
    else
      # Not a leaf — recurse into the expansion
      run(conn, expanded, op, opts)
    end
  end

  # Sequence — run all items in order
  defp run(conn, list, op, opts) when is_list(list) do
    Enum.reduce_while(list, {:ok, nil, op}, fn item, {:ok, _prev, op} ->
      case run(conn, Expandable.expand(item), op, opts) do
        {:ok, result, op} -> {:cont, {:ok, result, op}}
        {:error, _, _} = err -> {:halt, err}
      end
    end)
  end

  # Continuation — run inner, then call handler with result to get next step
  defp run(conn, {inner, handler}, op, opts) when is_function(handler, 1) do
    case run(conn, Expandable.expand(inner), op, opts) do
      {:ok, result, op} ->
        case handler.({:ok, result}) do
          {:cont, next} -> run(conn, Expandable.expand(next), op, opts)
          {:halt, final} -> {:ok, final, op}
        end

      {:error, reason, op} ->
        case handler.({:error, reason}) do
          {:cont, next} -> run(conn, Expandable.expand(next), op, opts)
          {:halt, final} -> {:ok, final, op}
        end
    end
  end

  defp send_leaf(conn, cmd, op, opts) do
    sent_at = System.monotonic_time(:millisecond)
    timeout = Keyword.get(opts, :timeout, 30_000)

    case Connection.send_command(
           conn,
           Encodable.method(cmd),
           Encodable.params(cmd),
           timeout: timeout
         ) do
      {:ok, result} ->
        step = %{command: cmd, response: result, sent_at: sent_at, received_at: now()}
        op = %{op | steps: op.steps ++ [step]}

        :telemetry.execute(
          [:bibbidi, :operation, :step],
          %{duration: step.received_at - step.sent_at},
          %{operation: op, step: step, conn: conn}
        )

        {:ok, result, op}

      {:error, reason} ->
        step = %{command: cmd, response: {:error, reason}, sent_at: sent_at, received_at: now()}
        op = %{op | steps: op.steps ++ [step]}

        :telemetry.execute(
          [:bibbidi, :operation, :step],
          %{duration: step.received_at - step.sent_at},
          %{operation: op, step: step, conn: conn}
        )

        {:error, reason, op}
    end
  end

  defp finalize(op, :completed) do
    %{op | status: :completed, ended_at: now()}
  end

  defp finalize(op, :failed, reason) do
    %{op | status: :failed, error: reason, ended_at: now()}
  end

  defp setup_event_capture(conn, event_names) do
    Enum.each(event_names, &Connection.subscribe(conn, &1))
  end

  defp teardown_event_capture(conn, event_names) do
    Enum.each(event_names, &Connection.unsubscribe(conn, &1))
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp generate_id do
    "op_" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
  end
end
