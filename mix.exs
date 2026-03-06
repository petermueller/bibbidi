defmodule Bibbidi.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/petermueller/bibbidi"

  def project do
    [
      app: :bibbidi,
      name: "Bibbidi",
      version: @version,
      elixir: "~> 1.19",
      description: "Low-level Elixir implementation of the W3C WebDriver BiDi Protocol.",
      source_url: @source_url,
      homepage_url: @source_url,
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      usage_rules: usage_rules()
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/icon.png",
      assets: %{"assets" => "assets"},
      source_ref: "v#{@version}",
      extras: ["README.md"],
      groups_for_modules: [
        Core: [
          Bibbidi,
          Bibbidi.Browser,
          Bibbidi.Connection,
          Bibbidi.Protocol,
          Bibbidi.Session
        ],
        Transport: ~r/Bibbidi\.Transport/,
        Commands: ~r/Bibbidi\.Commands\./,
        Events: ~r/Bibbidi\.Events\./,
        Types: ~r/Bibbidi\.Types\./,
        Internals: ~r/Bibbidi\.CDDL\./
      ],
      nest_modules_by_prefix: [
        Bibbidi.Commands,
        Bibbidi.Events,
        Bibbidi.Types,
        Bibbidi.Transport
      ]
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
      {:ex_doc, "~> 0.34", only: :dev, runtime: false, warn_if_outdated: true},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:bandit, "~> 1.0", only: :test},
      {:plug, "~> 1.14", only: :test}
    ]
  end
end
