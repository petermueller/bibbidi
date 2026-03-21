defmodule Bibbidi.MixProject do
  use Mix.Project

  @version "0.3.0"
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
      aliases: aliases(),
      deps: deps(),
      docs: docs(),
      package: package(),
      usage_rules: usage_rules()
    ]
  end

  defp docs do
    [
      main: "readme",
      logo: "assets/icon.png",
      assets: %{"assets" => "assets"},
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "examples/interactive_browser.livemd",
        {"examples/op_workflow/op_workflow.md", title: "Op Workflow Example"}
      ],
      groups_for_extras: [
        Examples: [
          "examples/interactive_browser.livemd",
          "examples/op_workflow/op_workflow.md"
        ]
      ],
      groups_for_modules: [
        Core: [
          Bibbidi,
          Bibbidi.Browser,
          Bibbidi.Connection,
          Bibbidi.Protocol,
          Bibbidi.Session,
          Bibbidi.Encodable,
          Bibbidi.Keys,
          Bibbidi.Telemetry,
          Bibbidi.Telemetry.Metadata
        ],
        Transport: ~r/Bibbidi\.Transport/,
        "Commands: Browser": ~r/Bibbidi\.Commands\.Browser/,
        "Commands: BrowsingContext": ~r/Bibbidi\.Commands\.BrowsingContext/,
        "Commands: Emulation": ~r/Bibbidi\.Commands\.Emulation/,
        "Commands: Input": ~r/Bibbidi\.Commands\.Input/,
        "Commands: Log": ~r/Bibbidi\.Commands\.Log/,
        "Commands: Network": ~r/Bibbidi\.Commands\.Network/,
        "Commands: Script": ~r/Bibbidi\.Commands\.Script/,
        "Commands: Session": ~r/Bibbidi\.Commands\.Session/,
        "Commands: Storage": ~r/Bibbidi\.Commands\.Storage/,
        "Commands: WebExtension": ~r/Bibbidi\.Commands\.WebExtension/,
        "Events: BrowsingContext": ~r/Bibbidi\.Events\.BrowsingContext/,
        "Events: Input": ~r/Bibbidi\.Events\.Input/,
        "Events: Log": ~r/Bibbidi\.Events\.Log/,
        "Events: Network": ~r/Bibbidi\.Events\.Network/,
        "Events: Script": ~r/Bibbidi\.Events\.Script/,
        Events: ~r/\ABibbidi\.Events\z/,
        "Mix Tasks": ~r/Mix\.Tasks\./,
        Internals: ~r/Bibbidi\.CDDL/
      ],
      nest_modules_by_prefix: [
        Bibbidi.Commands,
        Bibbidi.Commands.Browser,
        Bibbidi.Commands.BrowsingContext,
        Bibbidi.Commands.Emulation,
        Bibbidi.Commands.Input,
        Bibbidi.Commands.Network,
        Bibbidi.Commands.Script,
        Bibbidi.Commands.Session,
        Bibbidi.Commands.Storage,
        Bibbidi.Commands.WebExtension,
        Bibbidi.Events,
        Bibbidi.Events.BrowsingContext,
        Bibbidi.Events.Input,
        Bibbidi.Events.Log,
        Bibbidi.Events.Network,
        Bibbidi.Events.Script,
        Bibbidi.Transport,
        Bibbidi.Telemetry
      ]
    ]
  end

  defp package do
    [
      files: ~w(lib priv .formatter.exs mix.exs README* LICENSE* CHANGELOG* usage-rules.md),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "WebDriver BiDi Spec" => "https://w3c.github.io/webdriver-bidi/"
      }
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

  def cli do
    [preferred_envs: ["test.all": :test]]
  end

  defp aliases do
    [
      "test.all": ["test --include integration"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "dev", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "dev"]
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
      {:telemetry, "~> 1.0"},
      {:zoi, "~> 0.17"},
      {:igniter, "~> 0.7", only: [:dev, :test]},
      {:nimble_parsec, "~> 1.0", only: [:dev, :test]},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false, warn_if_outdated: true},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:bandit, "~> 1.0", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:plug, "~> 1.14", only: :test},
      {:benchee, "~> 1.0", only: :dev, runtime: false}
    ]
  end
end
