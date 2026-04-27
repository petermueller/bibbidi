defmodule Autopilot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Sagents registry — must start first
      {Registry, keys: :unique, name: Sagents.Registry},

      # PubSub — required by sagents
      {Phoenix.PubSub, name: :autopilot_pubsub},

      # Sagents dynamic supervisor
      Sagents.AgentsDynamicSupervisor,

      # Browser GenServer
      #Autopilot.Browser
    ]

    opts = [strategy: :one_for_one, name: Autopilot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
