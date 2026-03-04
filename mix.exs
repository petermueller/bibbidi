defmodule Bibbidi.MixProject do
  use Mix.Project

  def project do
    [
      app: :bibbidi,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      usage_rules: usage_rules()
    ]
  end

  defp usage_rules do
    # Example for those using claude.
    [
      file: "AGENTS.md",
      # rules to include directly in AGENTS.md
      usage_rules: ["usage_rules:all"],
      skills: [
        location: ".claude/skills",
        # build skills that combine multiple usage rules
        build: []
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mint_web_socket, "~> 1.0"},
      {:nimble_parsec, "~> 1.0", only: [:dev, :test]},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:bypass, "~> 2.1", only: :test}
    ]
  end
end
