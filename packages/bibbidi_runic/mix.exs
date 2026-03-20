defmodule BibbidiRunic.MixProject do
  use Mix.Project

  def project do
    [
      app: :bibbidi_runic,
      version: "0.1.0",
      elixir: "~> 1.19",
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
      bibbidi_dep(),
      {:runic, "~> 0.1.0-alpha"}
    ]
  end

  defp bibbidi_dep do
    if System.get_env("BBD_DEV") do
      {:bibbidi, path: "../bibbidi"}
    else
      {:bibbidi, "~> 0.2.0"}
    end
  end
end
