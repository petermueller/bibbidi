defmodule Playbook.Middleware.ContextPruner do
  @moduledoc """
  Keeps conversation history manageable between agent runs.

  Keeps the last N messages in full. Older messages are summarized
  to a single line to preserve context without filling the prompt.
  """

  @behaviour Sagents.Middleware

  @keep_messages 10

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def system_prompt(_config), do: ""

  @impl true
  def tools(_config), do: []

  @impl true
  def before_model(state, _config) do
    {:ok, %{state | messages: prune(state.messages)}}
  end

  @impl true
  def after_model(state, _config), do: {:ok, state}

  @impl true
  def handle_message(_msg, state, _config), do: {:ok, state}

  @impl true
  def on_server_start(state, _config), do: {:ok, state}

  # ── Pruning ────────────────────────────────────────────────────

  defp prune(messages) when length(messages) <= @keep_messages, do: messages

  defp prune(messages) do
    {old, recent} = Enum.split(messages, length(messages) - @keep_messages)

    summary = old
      |> Enum.map(&summarize/1)
      |> Enum.reject(&is_nil/1)

    case summary do
      [] -> recent
      lines ->
        summary_msg = %LangChain.Message{
          role: :user,
          content: "Previous conversation summary:\n" <> Enum.join(lines, "\n")
        }
        [summary_msg | recent]
    end
  end

  defp summarize(%{role: :user, content: content}) do
    "- User: #{truncate(content, 80)}"
  end

  defp summarize(%{role: :assistant, content: content}) when is_binary(content) do
    "- Assistant: #{truncate(content, 80)}"
  end

  defp summarize(%{role: :tool, content: content}) do
    "- Tool result: #{truncate(to_string(content), 60)}"
  end

  defp summarize(_), do: nil

  defp truncate(text, max) do
    if String.length(text) > max do
      String.slice(text, 0, max) <> "..."
    else
      text
    end
  end
end
