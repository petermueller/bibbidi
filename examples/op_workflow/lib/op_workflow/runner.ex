defmodule OpWorkflow.Runner do
  @moduledoc """
  Sequential runner for Op pipelines.

  Calls `Bibbidi.Connection.execute/2` for each leaf command and
  accumulates named results.

  This is example code — not a maintained library. Copy it into your
  project and modify as needed. If you're using Runic, Reactor, or
  another workflow engine, use their orchestration instead and call
  Connection.execute/2 from their step implementations.
  """

  alias OpWorkflow.{Op, Operation}

  @doc """
  Execute a pipeline, returning `{:ok, results, operation}` or
  `{:error, {step_name, reason}, operation}`.
  """
  @spec execute(GenServer.server(), Op.t(), keyword()) ::
          {:ok, Op.results(), Operation.t()} | {:error, {atom(), term()}, Operation.t()}
  def execute(conn, %Op{} = op, opts \\ []) do
    operation = %Operation{
      id: generate_id(),
      started_at: System.monotonic_time(:millisecond)
    }

    run_pipeline(conn, op.steps, %{}, operation, opts)
  end

  defp run_pipeline(_conn, [], results, operation, _opts) do
    {:ok, results, finalize(operation, results)}
  end

  defp run_pipeline(conn, [{name, {:send, cmd}} | rest], results, operation, opts) do
    case Bibbidi.Connection.execute(conn, cmd, opts) do
      {:ok, response} ->
        step = %{name: name, command: cmd, result: {:ok, response}, at: now()}
        operation = record_step(operation, step)
        run_pipeline(conn, rest, Map.put(results, name, {:ok, response}), operation, opts)

      {:error, reason} ->
        step = %{name: name, command: cmd, result: {:error, reason}, at: now()}
        operation = record_step(operation, step)
        {:error, {name, reason}, finalize_failed(operation, results, name, reason)}
    end
  end

  defp run_pipeline(conn, [{name, {:send_fn, fun}} | rest], results, operation, opts) do
    case fun.(results) do
      {:send, cmd} ->
        run_pipeline(conn, [{name, {:send, cmd}} | rest], results, operation, opts)

      {:ok, value} ->
        step = %{name: name, command: nil, result: {:ok, value}, at: now()}
        operation = record_step(operation, step)
        run_pipeline(conn, rest, Map.put(results, name, {:ok, value}), operation, opts)

      {:error, reason} ->
        step = %{name: name, command: nil, result: {:error, reason}, at: now()}
        operation = record_step(operation, step)
        {:error, {name, reason}, finalize_failed(operation, results, name, reason)}
    end
  end

  defp run_pipeline(conn, [{name, {:run, fun}} | rest], results, operation, opts) do
    case fun.(conn, results, opts) do
      {:ok, value} ->
        step = %{name: name, command: nil, result: {:ok, value}, at: now()}
        operation = record_step(operation, step)
        run_pipeline(conn, rest, Map.put(results, name, {:ok, value}), operation, opts)

      {:error, reason} ->
        step = %{name: name, command: nil, result: {:error, reason}, at: now()}
        operation = record_step(operation, step)
        {:error, {name, reason}, finalize_failed(operation, results, name, reason)}
    end
  end

  defp run_pipeline(conn, [{name, {:branch_fn, fun}} | rest], results, operation, opts) do
    case fun.(results) do
      {:send, cmd} ->
        case Bibbidi.Connection.execute(conn, cmd, opts) do
          {:ok, response} ->
            step = %{name: name, command: cmd, result: {:ok, response}, at: now()}
            operation = record_step(operation, step)
            run_pipeline(conn, rest, Map.put(results, name, {:ok, response}), operation, opts)

          {:error, reason} ->
            step = %{name: name, command: cmd, result: {:error, reason}, at: now()}
            operation = record_step(operation, step)
            {:error, {name, reason}, finalize_failed(operation, results, name, reason)}
        end

      {:ok, value} ->
        step = %{name: name, command: nil, result: {:ok, value}, at: now()}
        operation = record_step(operation, step)
        run_pipeline(conn, rest, Map.put(results, name, {:ok, value}), operation, opts)

      {:error, reason} ->
        step = %{name: name, command: nil, result: {:error, reason}, at: now()}
        operation = record_step(operation, step)
        {:error, {name, reason}, finalize_failed(operation, results, name, reason)}
    end
  end

  defp record_step(operation, step) do
    %{operation | steps: operation.steps ++ [step]}
  end

  defp finalize(operation, results) do
    %{operation | status: :completed, results: results, ended_at: now()}
  end

  defp finalize_failed(operation, results, name, reason) do
    %{operation | status: :failed, results: results, error: {name, reason}, ended_at: now()}
  end

  defp now, do: System.monotonic_time(:millisecond)

  defp generate_id do
    "op_" <> Base.url_encode64(:crypto.strong_rand_bytes(9), padding: false)
  end
end