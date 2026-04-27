defmodule Autopilot.MixProject do
  use Mix.Project

  def project do
    [
      app: :autopilot,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Autopilot.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:bibbidi, path: "../bibbidi"},
      {:sagents, "~> 0.3.1"},
      {:langchain, "~> 0.6.1"},
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:dotenvy, "~> 0.8"}
    ]
  end
end
