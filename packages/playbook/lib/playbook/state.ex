defmodule Playbook.State do
  @moduledoc "Simple state holder for sharing data between tool calls across agent runs."

  use Agent

  @doc "Starts the state process. Called automatically by the application supervisor."
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{last_playbook: nil} end, name: __MODULE__)
  end

  def set_playbook(playbook) do
    Agent.update(__MODULE__, &Map.put(&1, :last_playbook, playbook))
  end

  def get_playbook do
    Agent.get(__MODULE__, &Map.get(&1, :last_playbook))
  end
end
