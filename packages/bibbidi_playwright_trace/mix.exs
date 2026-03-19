defmodule BibbidiPlaywrightTrace.MixProject do
  use Mix.Project

  def project do
    [
      app: :bibbidi_playwright_trace,
      version: "0.1.0",
      elixir: "~> 1.19",
      description: "Generates Playwright-compatible trace files from Bibbidi telemetry events.",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:bibbidi, path: "../bibbidi"},
      {:jason, "~> 1.0"}
    ]
  end
end
