defmodule Playbook.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # Ensure output directories exist
    playbook_dir = Application.get_env(:playbook, :playbook_output_dir, "./playbooks")
    File.mkdir_p!(playbook_dir)
    File.mkdir_p!("passwords")

    children = [
      # Sagents registry — must start first
      #{Registry, keys: :unique, name: Sagents.Registry},

      # PubSub — required by Sagents
      {Phoenix.PubSub, name: :playbook_pubsub},

      # Sagents dynamic supervisor
      #Sagents.AgentsDynamicSupervisor,

      # Shared state between agent runs
      Playbook.State
    ]

    opts = [strategy: :one_for_one, name: Playbook.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
