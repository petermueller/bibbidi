defmodule Playbook.State do
  @moduledoc "Shared state between agent runs: conversation history and last playbook."

  use Agent

  @max_history 10

  @doc "Starts the state process. Called automatically by the application supervisor."
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{last_playbook: nil, history: []} end, name: __MODULE__)
  end

  # ── Playbook ───────────────────────────────────────────────────

  def set_playbook(playbook) do
    Agent.update(__MODULE__, &Map.put(&1, :last_playbook, playbook))
  end

  def get_playbook do
    Agent.get(__MODULE__, &Map.get(&1, :last_playbook))
  end

  # ── Conversation history ───────────────────────────────────────

  def add_user_message(content) do
    Agent.update(__MODULE__, fn state ->
      history = state.history ++ [%{role: :user, content: content}]
      %{state | history: Enum.take(history, -@max_history)}
    end)
  end

  def add_assistant_message(content) do
    Agent.update(__MODULE__, fn state ->
      history = state.history ++ [%{role: :assistant, content: content}]
      %{state | history: Enum.take(history, -@max_history)}
    end)
  end

  def get_history do
    Agent.get(__MODULE__, &Map.get(&1, :history, []))
  end

  def clear_history do
    Agent.update(__MODULE__, &Map.put(&1, :history, []))
  end
end
