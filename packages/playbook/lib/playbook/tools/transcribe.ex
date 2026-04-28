defmodule Playbook.Tools.Transcribe do
  @moduledoc """
  Transcribe recorded session logs into structured playbook JSON.

  Reads events from `.jsonl` raw log files produced by `Playbook.Recorder`,
  passes them through the LLM transcriber, and saves the resulting playbook.

  Tools exposed:
    - list_sessions:     list raw .jsonl logs available on disk
    - generate_playbook: transcribe the active session OR a specific past session
  """

  require Logger
  alias LangChain.{Function, FunctionParam}

  # ── Tools ──────────────────────────────────────────────────────

  def list_sessions do
    Function.new!(%{
      name: "list_sessions",
      description: """
      List recorded sessions available on disk (raw .jsonl files).
      Returns each session's filename, capture date/time, and event count.
      Call this when the user wants to generate or re-process a session
      that isn't currently active in memory.
      """,
      parameters: [],
      function: fn _args, _context ->
        sessions = scan_sessions()

        if sessions == [] do
          {:ok, "No recorded sessions found in ./playbooks/."}
        else
          formatted =
            sessions
            |> Enum.map(fn s ->
              "- #{s.filename} (#{s.event_count} events, recorded #{s.recorded_at}) → path: #{s.path}"
            end)
            |> Enum.join("\n")

          {:ok, "Available sessions:\n#{formatted}"}
        end
      end
    })
  end

  def generate_playbook do
    Function.new!(%{
      name: "generate_playbook",
      description: """
      Generate and save a playbook from a recorded session.

      If `raw_log_path` is provided, transcribes that file. Otherwise,
      transcribes the active or most recently active session in memory
      (stops the recording if still running).

      When the user names a past session, call `list_sessions` first
      to see available files, then pick the matching `raw_log_path`.
      """,
      parameters: [
        FunctionParam.new!(%{
          name: "raw_log_path",
          type: :string,
          required: false,
          description:
            "Optional. Path to a .jsonl raw log file (e.g. " <>
              "'./playbooks/dollar_pesos_20260427_205209_raw.jsonl'). " <>
              "Obtain valid paths from list_sessions."
        })
      ],
      function: fn args, _context ->
        # Stop active recording if any (no-op if not recording)
        case Playbook.Recorder.end_session() do
          {:ok, _name, _log} -> :ok
          {:error, :not_recording} -> :ok
        end

        raw_path =
          args["raw_log_path"] ||
            Playbook.Recorder.raw_log_path()

        cond do
          raw_path == nil ->
            {:error,
             "No session specified. Call list_sessions to see available recordings, " <>
               "or start a new recording first."}

          not File.exists?(raw_path) ->
            {:error,
             "Raw log file not found: #{raw_path}. Call list_sessions to see available files."}

          true ->
            name = derive_name(args, raw_path)
            transcribe_from_file(name, raw_path)
        end
      end
    })
  end

  # ── Public helper for re-transcribing arbitrary files ──────────

  @doc """
  Transcribe an arbitrary `.jsonl` raw log file into a playbook.
  Useful from iex for re-processing sessions without going through the LLM router.
  """
  def transcribe_file(raw_path, name \\ nil) do
    if File.exists?(raw_path) do
      session_name = name || infer_name_from_path(raw_path)
      transcribe_from_file(session_name, raw_path)
    else
      {:error, "File not found: #{raw_path}"}
    end
  end

  # ── Private — transcription pipeline ───────────────────────────

  defp transcribe_from_file(name, raw_path) do
    entries =
      raw_path
      |> read_jsonl()
      |> Enum.map(&Playbook.LogEntry.from_raw_map/1)
      |> Enum.reject(&is_nil/1)

    if entries == [] do
      {:error, "No events found in #{raw_path}"}
    else
      Logger.info(
        "[Transcribe] Loaded #{length(entries)} events from #{raw_path}, generating playbook for \"#{name}\""
      )

      llm_fn = Playbook.Llm.for_fn(:transcriber)

      try do
        case Playbook.Transcriber.generate(name, entries, llm_fn) do
          {:ok, playbook} ->
            path = save_playbook(playbook)
            Playbook.State.set_playbook(playbook)
            steps = playbook["steps"] || []

            {:ok,
             "Playbook saved to #{path} (#{length(steps)} steps). Raw log: #{raw_path}"}

          {:error, reason} ->
            Logger.error(
              "[Transcribe] Generation failed: #{inspect(reason, pretty: true, limit: :infinity)}"
            )

            {:error, "Generation failed: #{inspect(reason)}. Raw log: #{raw_path}"}
        end
      rescue
        e ->
          Logger.error("""
          [Transcribe] Exception during generation:
          #{Exception.format(:error, e, __STACKTRACE__)}
          """)

          {:error, "Exception: #{Exception.message(e)}. Raw log: #{raw_path}"}
      end
    end
  end

  defp read_jsonl(path) do
    path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.map(fn line ->
      case Jason.decode(line) do
        {:ok, event} -> event
        {:error, _} -> nil
      end
    end)
    |> Stream.reject(&is_nil/1)
    # Drop session_header lines, keep only real events
    |> Stream.reject(fn e -> e["type"] == "session_header" end)
    |> Enum.to_list()
  end

  defp save_playbook(playbook) do
    dir = Application.get_env(:playbook, :playbook_output_dir, "./playbooks")
    File.mkdir_p!(dir)
    name = playbook["name"] || "untitled"
    path = Path.join(dir, "#{sanitize(name)}.json")
    File.write!(path, Jason.encode!(playbook, pretty: true))
    path
  end

  # ── Private — session discovery ────────────────────────────────

  defp scan_sessions do
    dir = Application.get_env(:playbook, :playbook_output_dir, "./playbooks")

    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, "_raw.jsonl"))
        |> Enum.map(fn filename ->
          path = Path.join(dir, filename)

          %{
            filename: filename,
            path: path,
            event_count: count_events(path),
            recorded_at: format_mtime(path)
          }
        end)
        |> Enum.sort_by(& &1.recorded_at, :desc)

      _ ->
        []
    end
  end

  defp count_events(path) do
    total =
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.count()

    # Subtract one for the session_header line if present
    max(total - 1, 0)
  end

  defp format_mtime(path) do
    case File.stat(path) do
      {:ok, %{mtime: {{y, mo, d}, {h, mi, _s}}}} ->
        "#{y}-#{pad(mo)}-#{pad(d)} #{pad(h)}:#{pad(mi)}"

      _ ->
        "unknown"
    end
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  # ── Private — name inference ───────────────────────────────────

  defp derive_name(args, raw_path) do
    cond do
      # If the user-provided path matches the active session, prefer that name
      args["raw_log_path"] == nil and Playbook.Recorder.session_name() != nil ->
        Playbook.Recorder.session_name()

      true ->
        infer_name_from_path(raw_path)
    end
  end

  defp infer_name_from_path(path) do
    path
    |> Path.basename(".jsonl")
    |> String.replace(~r/_\d{8}_\d{6}_raw$/, "")
    |> String.replace("_", " ")
  end

  defp sanitize(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end
end
