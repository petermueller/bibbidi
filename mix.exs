defmodule Bibbidi.MixWorkspace do
  use Mix.Project

  def project do
    [
      app: :bibbidi_workspace,
      version: "0.0.0",
      elixir: "~> 1.19",
      elixirc_paths: [],
      deps: deps(),
      aliases: aliases(),
      workspace: [
        type: :workspace
      ],
      lockfile: "workspace.lock"
    ]
  end

  defp aliases do
    [
      "test.all": ["workspace.run -t test"],
      "format.all": ["workspace.run -t format"],
      "deps.get.all": ["workspace.run -t deps.get"],
      "compile.all": ["workspace.run -t compile"]
    ]
  end

  defp deps do
    [
      {:workspace, "~> 0.3.1"}
    ]
  end
end
