defmodule Autopilot.Middleware.Observer do
  @moduledoc """
  Observability middleware — writes the full agent decision cycle to a per-task log file.

  Each task produces one log file in `logs/tasks/` with:
    - The task description
    - Each turn: messages sent to LLM, LLM response, tool calls + args, tool results
    - Timing for each turn and total
  """

  @behaviour Sagents.Middleware

  alias Autopilot.TaskLog

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def system_prompt(_config), do: ""

  @impl true
  def tools(_config), do: []

  @impl true
  def on_server_start(state, _config) do
    if enabled?() do
      task = state.messages
        |> Enum.find(&(&1.role == :user))
        |> case do
          %{content: text} when is_binary(text) -> text
          _ -> "unknown_task"
        end

      path = TaskLog.start(task)

      # System prompts may not be in state.messages yet — Sagents may compose
      # them separately before the LLM call. Log what we have, if anything.
      system_msgs = Enum.filter(state.messages, &(&1.role == :system))
      if system_msgs != [] do
        prompt_text = system_msgs
          |> Enum.map(&extract_text/1)
          |> Enum.join("\n---\n")
        TaskLog.log("SYSTEM_PROMPT", prompt_text)
      end

      IO.puts("[Observer] Logging to: #{path}")
    end

    {:ok, state}
  end

  @impl true
  def before_model(state, _config) do
    if enabled?() and TaskLog.current_path() do
      turn = (Process.get(:task_log_turn) || 0) + 1
      TaskLog.log_turn(turn)

      messages = state.messages || []
      by_role = messages
        |> Enum.group_by(& &1.role)
        |> Enum.map(fn {role, msgs} -> "#{role}=#{length(msgs)}" end)
        |> Enum.join(" ")

      TaskLog.log("LLM_INPUT", "total_messages=#{length(messages)} (#{by_role})")

      # Log the last N messages that the LLM will see this turn
      recent = messages |> Enum.reverse() |> Enum.take(5) |> Enum.reverse()

      recent
      |> Enum.each(fn msg ->
        role = msg.role
        text = extract_text(msg)
        tool_calls = extract_tool_calls(msg)

        cond do
          tool_calls != [] ->
            calls_str = tool_calls
              |> Enum.map(fn {name, args} ->
                clean = args |> Map.drop(["screenshot"]) |> inspect(limit: :infinity, printable_limit: 2000)
                "  #{name}(#{clean})"
              end)
              |> Enum.join("\n")
            TaskLog.log("LLM_INPUT:#{role}", "tool_calls:\n#{calls_str}")

          text != "" ->
            TaskLog.log("LLM_INPUT:#{role}", truncate(text, 1000))

          true ->
            :ok
        end
      end)
    end

    {:ok, state}
  end

  @impl true
  def after_model(state, _config) do
    if enabled?() and TaskLog.current_path() do
      messages = state.messages || []

      # Find the last assistant message
      last_assistant = messages
        |> Enum.reverse()
        |> Enum.find(&(&1.role == :assistant))

      case last_assistant do
        nil ->
          TaskLog.log("LLM_OUTPUT", "(no assistant response)")

        msg ->
          # Log reasoning
          text = extract_text(msg)
          if text != "" do
            TaskLog.log("LLM_REASONING", truncate(text, 2000))
          end

          # Log tool calls with full args (except screenshots)
          tool_calls = extract_tool_calls(msg)
          if tool_calls != [] do
            calls_str = tool_calls
              |> Enum.map(fn {name, args} ->
                clean = args |> Map.drop(["screenshot"]) |> inspect(limit: :infinity, printable_limit: 4000)
                "  → #{name}(#{clean})"
              end)
              |> Enum.join("\n")
            TaskLog.log("LLM_TOOL_CALLS", calls_str)
          end

          # Detect task_complete — stop the log from within the AgentServer process
          # (TaskLog uses process dictionary, so stop() must run in the same process
          # that called start(), which is this AgentServer process via on_server_start)
          has_task_complete = Enum.any?(tool_calls, fn {name, _} -> name == "task_complete" end)
          if has_task_complete do
            TaskLog.stop()
          end
      end

      # Log the most recent tool results
      last_tool_results = messages
        |> Enum.reverse()
        |> Enum.take_while(&(&1.role != :assistant))
        |> Enum.filter(&(&1.role == :tool))
        |> Enum.reverse()

      if last_tool_results != [] do
        results_str = last_tool_results
          |> Enum.map(fn msg ->
            text = extract_text(msg)
            tool_id = Map.get(msg, :tool_call_id, "?")
            "  [#{tool_id}] #{truncate(text, 1500)}"
          end)
          |> Enum.join("\n")
        TaskLog.log("TOOL_RESULTS", results_str)
      end
    end

    {:ok, state}
  end

  @impl true
  def handle_message(_msg, state, _config), do: {:ok, state}

  # --- Helpers ---

  defp enabled? do
    config = Application.get_env(:autopilot, :observer, [])
    Keyword.get(config, :enabled, true)
  end

  defp truncate(text, max) do
    text = String.trim(to_string(text))
    if String.length(text) > max do
      String.slice(text, 0, max) <> "\n... (#{String.length(text)} chars total)"
    else
      text
    end
  end

  defp extract_text(msg) do
    case msg.content do
      text when is_binary(text) -> text
      parts when is_list(parts) ->
        parts
        |> Enum.filter(fn
          %{type: :text} -> true
          %{"type" => "text"} -> true
          p when is_binary(p) -> true
          _ -> false
        end)
        |> Enum.map(fn
          %{content: c} -> to_string(c)
          %{"content" => c} -> to_string(c)
          %{text: t} -> to_string(t)
          %{"text" => t} -> to_string(t)
          p when is_binary(p) -> p
          _ -> ""
        end)
        |> Enum.join("")
      _ -> ""
    end
  end

  defp extract_tool_calls(msg) do
    case msg.content do
      parts when is_list(parts) ->
        parts
        |> Enum.filter(fn
          %{type: :tool_call} -> true
          %{"type" => "tool_use"} -> true
          _ -> false
        end)
        |> Enum.map(fn
          %{name: n, arguments: a} -> {n, a || %{}}
          %{"name" => n, "input" => a} -> {n, a || %{}}
          _ -> {"unknown", %{}}
        end)
      _ -> []
    end
  end
end
