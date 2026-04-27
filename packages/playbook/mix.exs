defmodule Playbook.MixProject do
  use Mix.Project

  def project do
    [
      app: :playbook,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Playbook.Application, []}
    ]
  end

  defp deps do
    [
      {:bibbidi, path: "../bibbidi"},
      {:autopilot, path: "../autopilot"},
      {:sagents, "~> 0.1"},
      {:langchain, "~> 0.3"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:dotenvy, "~> 0.8"}
    ]
  end
end
