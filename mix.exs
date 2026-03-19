defmodule Bibbidi.MixWorkspace do
  use Mix.Project

  def project do
    [
      app: :bibbidi_workspace,
      version: "0.0.0",
      elixir: "~> 1.19",
      elixirc_paths: [],
      deps: deps(),
      workspace: [
        type: :workspace
      ],
      lockfile: "workspace.lock"
    ]
  end

  defp deps do
    [
      {:workspace, "~> 0.3.1"}
    ]
  end
end
