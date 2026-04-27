defmodule Playbook.Tools.Persistence do
  @moduledoc "Persistence tools: save, load, and run playbooks."

  alias LangChain.Function
  alias LangChain.FunctionParam

  def save_playbook do
    Function.new!(%{
      name: "save_playbook",
      description: """
      Save the last generated playbook to a JSON file.
      If no path is given, saves to the default playbooks directory
      using the playbook name as filename.
      """,
      parameters: [
        FunctionParam.new!(%{name: "path", type: :string, required: false,
          description: "File path to save to. Optional — defaults to playbooks/<name>.json"})
      ],
      function: fn args, _context ->
        case Playbook.State.get_playbook() do
          nil ->
            {:error, "No playbook to save. Generate one first."}

          playbook ->
            path = args["path"] || default_path(playbook)
            dir = Path.dirname(path)
            File.mkdir_p!(dir)

            json = Jason.encode!(playbook, pretty: true)
            File.write!(path, json)

            {:ok, "Playbook saved to #{path}"}
        end
      end
    })
  end

  def load_playbook do
    Function.new!(%{
      name: "load_playbook",
      description: "Load a playbook from a JSON file and display its contents.",
      parameters: [
        FunctionParam.new!(%{name: "name", type: :string, required: true,
          description: "Playbook name or file path, e.g. 'uhc_login' or 'playbooks/uhc_login.json'"})
      ],
      function: fn %{"name" => name}, _context ->
        path = resolve_path(name)

        case File.read(path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, playbook} ->
                Playbook.State.set_playbook(playbook)
                steps = playbook["steps"] || []

                summary = steps
                  |> Enum.with_index(1)
                  |> Enum.map(fn {step, i} ->
                    "#{i}. [#{step["action"]}] #{step["label"] || "?"}"
                  end)
                  |> Enum.join("\n")

                {:ok, "Loaded \"#{playbook["name"]}\" (#{length(steps)} steps):\n#{summary}"}

              {:error, _} ->
                {:error, "Invalid JSON in #{path}"}
            end

          {:error, :enoent} ->
            available = list_playbooks()
            {:error, "File not found: #{path}\n#{available}"}
        end
      end
    })
  end

  def run_playbook do
    Function.new!(%{
      name: "run_playbook",
      description: "Execute a saved playbook. Loads and runs it step by step.",
      parameters: [
        FunctionParam.new!(%{name: "name", type: :string, required: true,
          description: "Playbook name or file path, e.g. 'uhc_login' or 'playbooks/uhc_login.json'"})
      ],
      function: fn %{"name" => name}, _context ->
        path = resolve_path(name)

        case File.read(path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, playbook} ->
                steps = playbook["steps"] || []

                case Playbook.Runner.execute(playbook) do
                  :ok ->
                    {:ok, "Playbook \"#{playbook["name"]}\" completed successfully (#{length(steps)} steps)."}

                  {:error, step_num, reason} ->
                    {:error, "Playbook failed at step #{step_num}: #{inspect(reason)}"}
                end

              {:error, _} ->
                {:error, "Invalid JSON in #{path}"}
            end

          {:error, :enoent} ->
            available = list_playbooks()
            {:error, "File not found: #{path}\n#{available}"}
        end
      end
    })
  end

  # ── Helpers ────────────────────────────────────────────────────

  defp playbook_dir do
    Application.get_env(:playbook, :playbook_output_dir, "./playbooks")
  end

  defp resolve_path(name) do
    cond do
      String.ends_with?(name, ".json") ->
        name

      File.exists?(Path.join(playbook_dir(), "#{name}.json")) ->
        Path.join(playbook_dir(), "#{name}.json")

      File.exists?(Path.join(playbook_dir(), "#{sanitize(name)}.json")) ->
        Path.join(playbook_dir(), "#{sanitize(name)}.json")

      true ->
        Path.join(playbook_dir(), "#{sanitize(name)}.json")
    end
  end

  defp default_path(playbook) do
    name = playbook["name"] || "untitled"
    Path.join(playbook_dir(), "#{sanitize(name)}.json")
  end

  defp sanitize(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end

  defp list_playbooks do
    case File.ls(playbook_dir()) do
      {:ok, files} ->
        jsons = Enum.filter(files, &String.ends_with?(&1, ".json"))
        if jsons != [] do
          "Available playbooks:\n" <> Enum.map_join(jsons, "\n", &"  • #{&1}")
        else
          "No playbooks found in #{playbook_dir()}"
        end

      _ ->
        "Playbooks directory not found."
    end
  end
end
