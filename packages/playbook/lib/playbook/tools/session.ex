defmodule Playbook.Tools.Session do
  @moduledoc "Recording session tools: start, stop, annotate, peek."

  alias LangChain.Function
  alias LangChain.FunctionParam

  def start_recording do
    Function.new!(%{
      name: "start_recording",
      description: "Start recording a browser session. Events (clicks, inputs, navigation) are captured automatically.",
      parameters: [
        FunctionParam.new!(%{name: "name", type: :string, required: true,
          description: "Session name, e.g. 'UHC Portal Login'"})
      ],
      function: fn %{"name" => name}, _context ->
        case Playbook.Recorder.begin_session(name) do
          :ok -> {:ok, "Recording started: \"#{name}\". Browser events are being captured. The user can provide context notes anytime."}
          {:error, reason} -> {:error, "start failed: #{inspect(reason)}"}
        end
      end
    })
  end

  def stop_recording do
    Function.new!(%{
      name: "stop_recording",
      description: """
      Stop the current recording session without generating a playbook.
      Use this if the user explicitly wants to pause/stop. If they want to
      generate a playbook, call generate_playbook directly — it stops recording
      on its own.
      """,
      parameters: [],
      function: fn _args, _context ->
        case Playbook.Recorder.end_session() do
          {:ok, name, log} ->
            {:ok, "Stopped recording \"#{name}\" — #{length(log)} events captured."}
          {:error, :not_recording} ->
            {:ok, "Not currently recording."}
        end
      end
    })
  end

  def annotate do
    Function.new!(%{
      name: "annotate",
      description: """
      Add a context note to the recording. Use this whenever the user explains
      what they're doing, why a step matters, or provides context about the page.
      Examples: "this popup is conditional", "the password is in uhc.txt",
      "this is the 2FA step", "I clicked the wrong button, ignore that".
      """,
      parameters: [
        FunctionParam.new!(%{name: "text", type: :string, required: true,
          description: "The annotation text"})
      ],
      function: fn %{"text" => text}, _context ->
        case Playbook.Recorder.annotate(text) do
          :ok -> {:ok, "Note added: \"#{text}\""}
          {:error, :not_recording} -> {:error, "Not currently recording."}
        end
      end
    })
  end

  def peek do
    Function.new!(%{
      name: "peek",
      description: "Show the current recording log without stopping.",
      parameters: [],
      function: fn _args, _context ->
        log = Playbook.Recorder.get_log()

        if log == [] do
          {:ok, "Log is empty. No events captured yet."}
        else
          lines = log
            |> Enum.with_index(1)
            |> Enum.map(fn {entry, i} ->
              "#{i}. #{Playbook.LogEntry.to_log_line(entry)}"
            end)
            |> Enum.join("\n")

          {:ok, "Session log (#{length(log)} events):\n#{lines}"}
        end
      end
    })
  end
end
