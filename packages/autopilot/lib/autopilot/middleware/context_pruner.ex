defmodule Autopilot.Middleware.ContextPruner do
  @moduledoc """
  Prunes consumed tool results from message history before each LLM call.

  Keeps the last N turns in full detail. For older turns, replaces verbose
  tool results with one-line summaries. Never touches assistant messages
  (API requires valid tool_use blocks with original arguments).
  """

  @behaviour Sagents.Middleware

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def system_prompt(_config), do: ""

  @impl true
  def tools(_config), do: []

  @impl true
  def before_model(state, _config) do
    if enabled?() do
      {:ok, %{state | messages: prune(state.messages)}}
    else
      {:ok, state}
    end
  end

  @impl true
  def after_model(state, _config), do: {:ok, state}

  @impl true
  def handle_message(_msg, state, _config), do: {:ok, state}

  @impl true
  def on_server_start(state, _config), do: {:ok, state}

  # --- Pruning logic ---

  defp prune(messages) do
    keep_turns = keep_turns()

    {preamble, conversation} = split_preamble(messages)
    turns = group_turns(conversation)

    if length(turns) <= keep_turns do
      messages
    else
      {old_turns, recent_turns} = Enum.split(turns, length(turns) - keep_turns)

      summarized = Enum.flat_map(old_turns, &summarize_turn/1)
      recent = Enum.flat_map(recent_turns, & &1)

      preamble ++ summarized ++ recent
    end
  end

  defp split_preamble(messages) do
    idx = Enum.find_index(messages, &(&1.role == :assistant))

    case idx do
      nil -> {messages, []}
      0   -> {[], messages}
      i   -> Enum.split(messages, i)
    end
  end

  defp group_turns(messages) do
    messages
    |> Enum.chunk_while(
      [],
      fn msg, acc ->
        case {msg.role, acc} do
          {:assistant, []} ->
            {:cont, [msg]}
          {:assistant, acc} ->
            {:cont, Enum.reverse(acc), [msg]}
          {_role, acc} ->
            {:cont, [msg | acc]}
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
    |> Enum.reject(&(&1 == []))
  end

  defp summarize_turn(turn_messages) do
    Enum.map(turn_messages, fn msg ->
      case msg.role do
        :tool -> summarize_tool_result(msg)
        _     -> msg
      end
    end)
  end

  defp summarize_tool_result(msg) do
    content = case msg.content do
      text when is_binary(text) -> text
      _ -> ""
    end

    summary = cond do
      String.contains?(content, "Indexed") ->
        content

      String.contains?(content, "TASK_DONE") ->
        content

      String.contains?(content, "score=") ->
        match_count = content |> String.split("\n") |> Enum.reject(&(String.trim(&1) == "")) |> length()
        "[find_element returned #{match_count} matches]"

      String.contains?(content, "CAPTCHA") ->
        "[page contains CAPTCHA]"

      String.contains?(content, "href=") ->
        link_count = content |> String.split("\n") |> Enum.count(&String.contains?(&1, "href="))
        "[get_links returned #{link_count} links]"

      String.contains?(content, "DOM inputs") ->
        content |> String.split("\n") |> List.first() |> String.trim()

      String.length(content) > 150 ->
        "[#{String.slice(content, 0, 100)}...]"

      true ->
        content
    end

    %{msg | content: summary}
  end

  # --- Config ---

  defp enabled? do
    config = Application.get_env(:autopilot, :context_pruner, [])
    Keyword.get(config, :enabled, true)
  end

  defp keep_turns do
    config = Application.get_env(:autopilot, :context_pruner, [])
    Keyword.get(config, :keep_turns, 3)
  end
end
