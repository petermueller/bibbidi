defmodule Mix.Tasks.Bibbidi.Cddl.Inspect do
  @moduledoc """
  Inspect parsed CDDL rules for debugging the parser and code generator.

      # Show all rule names
      mix bibbidi.cddl.inspect

      # Show a specific rule by exact name
      mix bibbidi.cddl.inspect session.UnsubscribeParameters

      # Search rule names by substring (case-insensitive)
      mix bibbidi.cddl.inspect --search unsubscribe

      # Show only rules from a specific spec file
      mix bibbidi.cddl.inspect --file remote
      mix bibbidi.cddl.inspect --file local

      # Show resolved command fields (what the generator would produce)
      mix bibbidi.cddl.inspect --fields session.UnsubscribeParameters

      # Show all commands the generator extracts for a module
      mix bibbidi.cddl.inspect --commands session
  """

  @shortdoc "Inspect parsed CDDL rules"

  use Mix.Task

  alias Bibbidi.CDDL.Parser

  @impl Mix.Task
  def run(argv) do
    {opts, args, _} =
      OptionParser.parse(argv,
        strict: [search: :string, file: :string, fields: :string, commands: :string],
        aliases: [s: :search, f: :file]
      )

    remote = parse_file("priv/cddl/remote.cddl")
    local = parse_file("priv/cddl/local.cddl")

    rules =
      case opts[:file] do
        "remote" -> remote
        "local" -> local
        _ -> remote ++ local
      end

    cond do
      opts[:commands] ->
        show_commands(opts[:commands], remote, remote ++ local)

      opts[:fields] ->
        show_fields(opts[:fields], remote ++ local)

      opts[:search] ->
        search_rules(rules, opts[:search])

      args != [] ->
        show_rule(rules, hd(args))

      true ->
        list_rules(rules)
    end
  end

  defp parse_file(path) do
    case Parser.parse_file(path) do
      {:ok, rules} -> rules
      {:error, reason} ->
        Mix.shell().error("Failed to parse #{path}: #{inspect(reason)}")
        []
    end
  end

  defp list_rules(rules) do
    names = rules |> Enum.map(&elem(&1, 0)) |> Enum.sort()
    Mix.shell().info("#{length(names)} rules:\n")

    for name <- names do
      {^name, def} = List.keyfind(rules, name, 0)
      Mix.shell().info("  #{name}  (#{rule_kind(def)})")
    end
  end

  defp show_rule(rules, name) do
    case List.keyfind(rules, name, 0) do
      nil ->
        Mix.shell().error("Rule #{inspect(name)} not found.")
        close = rules |> Enum.map(&elem(&1, 0)) |> Enum.filter(&String.contains?(&1, name))

        if close != [] do
          Mix.shell().info("\nDid you mean one of these?")
          for n <- close, do: Mix.shell().info("  #{n}")
        end

      {^name, definition} ->
        Mix.shell().info("#{name}:\n")
        definition |> inspect(pretty: true, limit: :infinity, width: 100) |> Mix.shell().info()
    end
  end

  defp search_rules(rules, query) do
    query_down = String.downcase(query)

    matches =
      rules
      |> Enum.filter(fn {name, _} -> name |> String.downcase() |> String.contains?(query_down) end)
      |> Enum.sort_by(&elem(&1, 0))

    Mix.shell().info("#{length(matches)} matches for #{inspect(query)}:\n")

    for {name, def} <- matches do
      Mix.shell().info("  #{name}  (#{rule_kind(def)})")
    end
  end

  defp show_fields(ref, all_rules) do
    fields = Bibbidi.CDDL.Generator.resolve_command_fields(ref, all_rules)

    if fields == [] do
      Mix.shell().info("No fields resolved for #{inspect(ref)}.\n")
      Mix.shell().info("Showing raw rule instead:")
      show_rule(all_rules, ref)
    else
      Mix.shell().info("Fields for #{ref}:\n")

      for {json_key, elixir_key, req} <- fields do
        marker = if req == :required, do: "*", else: " "
        Mix.shell().info("  #{marker} #{elixir_key} (wire: #{json_key})")
      end

      Mix.shell().info("\n  * = required")
    end
  end

  defp show_commands(mod, remote_rules, all_rules) do
    commands =
      remote_rules
      |> Enum.filter(fn {name, def} ->
        String.starts_with?(name, mod <> ".") and is_command_def?(def)
      end)
      |> Enum.sort_by(&elem(&1, 0))

    Mix.shell().info("#{length(commands)} commands for #{mod}:\n")

    for {name, {:group, members}} <- commands do
      method =
        Enum.find_value(members, fn
          {:required, "method", {:string, m}} -> m
          _ -> nil
        end)

      params_ref =
        Enum.find_value(members, fn
          {:required, "params", {:ref, r}} -> r
          _ -> nil
        end)

      fields = Bibbidi.CDDL.Generator.resolve_command_fields(params_ref, all_rules)

      required = Enum.filter(fields, fn {_, _, r} -> r == :required end)
      optional = Enum.filter(fields, fn {_, _, r} -> r == :optional end)

      Mix.shell().info("  #{name}")
      Mix.shell().info("    method: #{method}")
      Mix.shell().info("    params: #{params_ref || "EmptyParams"}")
      Mix.shell().info("    fields: #{length(required)} required, #{length(optional)} optional")

      for {json_key, elixir_key, req} <- fields do
        marker = if req == :required, do: "*", else: " "
        Mix.shell().info("      #{marker} #{elixir_key} (#{json_key})")
      end

      Mix.shell().info("")
    end
  end

  defp is_command_def?({:group, members}) do
    Enum.any?(members, fn
      {:required, "method", {:string, _}} -> true
      _ -> false
    end) and
      Enum.any?(members, fn
        {:required, "params", _} -> true
        _ -> false
      end)
  end

  defp is_command_def?(_), do: false

  defp rule_kind({:group, _}), do: "group"
  defp rule_kind({:map, _}), do: "map"
  defp rule_kind({:choice, _}), do: "choice"
  defp rule_kind({:array, _, _}), do: "array"
  defp rule_kind({:primitive, _, _}), do: "primitive"
  defp rule_kind({:primitive, _}), do: "primitive"
  defp rule_kind({:ref, _}), do: "ref"
  defp rule_kind({:string, _}), do: "string"
  defp rule_kind(_), do: "other"
end
