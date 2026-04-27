defmodule Autopilot.TaskLog do
  @moduledoc """
  Per-task file logging.

  Each task gets its own log file in `logs/tasks/`.
  Uses process dictionary so any code running in the agent process
  (middleware, tool functions, call_vision) can log to the same file.
  """

  @log_dir "logs/tasks"

  def start(task_description) do
    File.mkdir_p!(@log_dir)

    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
    slug = task_description
      |> String.slice(0, 50)
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    filename = "#{timestamp}_#{slug}.log"
    path = Path.join(@log_dir, filename)

    Process.put(:task_log_path, path)
    Process.put(:task_log_turn, 0)
    Process.put(:task_log_start, System.monotonic_time(:millisecond))

    write(path, """
    ================================================================================
    TASK: #{task_description}
    STARTED: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    LOG: #{path}
    ================================================================================
    """)

    path
  end

  def log(tag, content) do
    case Process.get(:task_log_path) do
      nil -> :ok
      path ->
        elapsed = System.monotonic_time(:millisecond) - Process.get(:task_log_start, 0)
        ts = format_elapsed(elapsed)
        write(path, "\n[#{ts}] [#{tag}]\n#{content}\n")
    end
  end

  def log_turn(turn) do
    Process.put(:task_log_turn, turn)
    log("TURN", "═══════════════════════════════ Turn #{turn} ═══════════════════════════════")
  end

  def stop do
    case Process.get(:task_log_path) do
      nil -> :ok
      path ->
        elapsed = System.monotonic_time(:millisecond) - Process.get(:task_log_start, 0)
        write(path, "\n\n================================================================================\nFINISHED: #{DateTime.utc_now() |> DateTime.to_iso8601()} (#{format_elapsed(elapsed)} total)\n================================================================================\n")
        Process.delete(:task_log_path)
        Process.delete(:task_log_turn)
        Process.delete(:task_log_start)
        path
    end
  end

  def current_path, do: Process.get(:task_log_path)

  # --- Private ---

  defp write(path, content) do
    File.write!(path, content, [:append])
  end

  defp format_elapsed(ms) do
    cond do
      ms < 1000   -> "#{ms}ms"
      ms < 60_000 -> "#{Float.round(ms / 1000, 1)}s"
      true        -> "#{div(ms, 60_000)}m#{rem(div(ms, 1000), 60)}s"
    end
  end
end
