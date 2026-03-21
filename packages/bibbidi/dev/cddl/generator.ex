defmodule Bibbidi.CDDL.Generator do
  @moduledoc false

  alias Bibbidi.CDDL.Parser
  alias Bibbidi.CDDL.Utils

  @modules ~w(browsingContext script session browser network log storage input emulation webExtension)

  @doc """
  Builds an `%Igniter{}` with all generated events and command modules.

  Returns the igniter struct — the caller decides whether to apply or dry-run.
  """
  @spec run(Igniter.t()) :: Igniter.t()
  def run(igniter) do
    {:ok, remote_rules} = Parser.parse_file("priv/cddl/remote.cddl")
    {:ok, local_rules} = Parser.parse_file("priv/cddl/local.cddl")

    all_rules = remote_rules ++ local_rules
    grouped = group_by_module(all_rules)

    # Collect all type refs used in command/event fields, transitively
    type_refs = collect_all_type_refs(remote_rules, local_rules, all_rules)

    # Generate type modules first (commands/events reference them)
    igniter = generate_type_modules(igniter, type_refs, all_rules)

    Enum.reduce(@modules, igniter, fn mod, igniter ->
      rules = Map.get(grouped, mod, [])

      igniter
      |> maybe_generate_events_module(mod, rules, local_rules, all_rules, type_refs)
      |> maybe_generate_command_modules(mod, remote_rules, all_rules, type_refs)
      |> maybe_generate_facade_module(mod, remote_rules, all_rules, type_refs)
    end)
  end

  defp group_by_module(rules) do
    rules
    |> Enum.filter(fn {name, _} -> String.contains?(name, ".") end)
    |> Enum.group_by(fn {name, _} -> name |> String.split(".") |> hd() end)
  end

  # ── Type ref collection ──────────────────────────────────────────

  @doc """
  Collects all CDDL ref names that should have generated type modules.

  Walks all command/event fields, extracts {:ref, name} types, and
  transitively follows those refs to find more refs.
  """
  def collect_all_type_refs(remote_rules, local_rules, all_rules) do
    # Collect refs from command fields
    command_refs =
      Enum.flat_map(@modules, fn mod ->
        commands = extract_commands(mod, remote_rules)

        Enum.flat_map(commands, fn {_, _, params_ref} ->
          fields = resolve_command_fields(params_ref, all_rules)
          Enum.flat_map(fields, fn {_, _, _, cddl_type} -> collect_refs_from_type(cddl_type) end)
        end)
      end)

    # Collect refs from event fields
    event_refs =
      Enum.flat_map(@modules, fn mod ->
        events = extract_events(mod, local_rules)

        Enum.flat_map(events, fn {_, params_ref} ->
          fields = resolve_command_fields(params_ref, all_rules)
          Enum.flat_map(fields, fn {_, _, _, cddl_type} -> collect_refs_from_type(cddl_type) end)
        end)
      end)

    # Transitively follow all refs
    seed_refs = MapSet.new(command_refs ++ event_refs)
    all_refs = expand_refs_transitively(seed_refs, all_rules, MapSet.new())

    # Filter to only refs that have an actual rule definition
    rule_names = MapSet.new(all_rules, fn {name, _} -> name end)
    MapSet.intersection(all_refs, rule_names)
  end

  defp expand_refs_transitively(to_visit, all_rules, visited) do
    new_refs = MapSet.difference(to_visit, visited)

    if MapSet.size(new_refs) == 0 do
      visited
    else
      visited = MapSet.union(visited, new_refs)

      # For each new ref, look up its definition and collect more refs
      more_refs =
        new_refs
        |> Enum.flat_map(fn ref_name ->
          case List.keyfind(all_rules, ref_name, 0) do
            {_, definition} -> collect_refs_from_definition(definition)
            nil -> []
          end
        end)
        |> MapSet.new()

      expand_refs_transitively(more_refs, all_rules, visited)
    end
  end

  defp collect_refs_from_definition({:map, content}) do
    Enum.flat_map(content, fn
      {:fields, fields} ->
        Enum.flat_map(fields, fn
          {:required, _, type} -> collect_refs_from_type(type)
          {:optional, _, type} -> collect_refs_from_type(type)
          {:embed, ref} -> [ref]
          {:extensible, _, _} -> []
          {:group_choice, groups} -> collect_refs_from_group_choice(groups)
          _ -> []
        end)

      {:group_choice, groups} ->
        collect_refs_from_group_choice(groups)

      _ ->
        []
    end)
  end

  defp collect_refs_from_definition({:choice, items}) do
    Enum.flat_map(items, &collect_refs_from_type/1)
  end

  defp collect_refs_from_definition({:choice, items, _constraint}) do
    Enum.flat_map(items, &collect_refs_from_type/1)
  end

  defp collect_refs_from_definition({:group, members}) do
    Enum.flat_map(members, fn
      {:required, _, type} -> collect_refs_from_type(type)
      {:optional, _, type} -> collect_refs_from_type(type)
      {:embed, ref} -> [ref]
      _ -> []
    end)
  end

  defp collect_refs_from_definition({:ref, name}), do: [name]
  defp collect_refs_from_definition({:array, inner, _}), do: collect_refs_from_type(inner)
  defp collect_refs_from_definition(_), do: []

  defp collect_refs_from_group_choice(groups) do
    Enum.flat_map(groups, fn
      {:fields, fields} ->
        Enum.flat_map(fields, fn
          {:required, _, type} -> collect_refs_from_type(type)
          {:optional, _, type} -> collect_refs_from_type(type)
          {:embed, ref} -> [ref]
          _ -> []
        end)

      {:group, members} ->
        Enum.flat_map(members, fn
          {:required, _, type} -> collect_refs_from_type(type)
          {:optional, _, type} -> collect_refs_from_type(type)
          {:embed, ref} -> [ref]
          _ -> []
        end)

      _ ->
        []
    end)
  end

  @doc false
  def collect_refs_from_type({:ref, name}), do: [name]
  def collect_refs_from_type({:array, inner, _}), do: collect_refs_from_type(inner)
  def collect_refs_from_type({:choice, items}), do: Enum.flat_map(items, &collect_refs_from_type/1)

  def collect_refs_from_type({:choice, items, _constraint}),
    do: Enum.flat_map(items, &collect_refs_from_type/1)

  def collect_refs_from_type({:map, [{:fields, fields}]}) do
    Enum.flat_map(fields, fn
      {:required, _, type} -> collect_refs_from_type(type)
      {:optional, _, type} -> collect_refs_from_type(type)
      {:embed, ref} -> [ref]
      _ -> []
    end)
  end

  def collect_refs_from_type(_), do: []

  # ── Ref-to-module name mapping ───────────────────────────────────

  @doc """
  Converts a CDDL ref name to an Elixir module name under `Bibbidi.Types`.

  ## Namespace convention

  - `browsingContext.BrowsingContext` → `Bibbidi.Types.BrowsingContext` (collapsed)
  - `script.Target` → `Bibbidi.Types.Script.Target` (nested)
  - `js-uint` → `Bibbidi.Types.JsUint` (no dot, top-level)
  """
  def cddl_ref_to_module(ref_name) do
    if String.contains?(ref_name, ".") do
      [mod_part, type_part] = String.split(ref_name, ".", parts: 2)
      mod_name = to_module_name(mod_part)
      type_name = to_module_name(type_part)

      if mod_name == type_name do
        # Collapsed: browsingContext.BrowsingContext → Bibbidi.Types.BrowsingContext
        "Bibbidi.Types.#{type_name}"
      else
        # Nested: script.Target → Bibbidi.Types.Script.Target
        "Bibbidi.Types.#{mod_name}.#{type_name}"
      end
    else
      # Top-level: js-uint → Bibbidi.Types.JsUint
      "Bibbidi.Types.#{to_module_name(ref_name)}"
    end
  end

  @doc """
  Converts a CDDL ref name to the file path for its type module.
  """
  def cddl_ref_to_path(ref_name) do
    if String.contains?(ref_name, ".") do
      [mod_part, type_part] = String.split(ref_name, ".", parts: 2)
      mod_snake = to_snake(mod_part)
      type_snake = to_snake(type_part)

      if to_module_name(mod_part) == to_module_name(type_part) do
        "lib/bibbidi/types/#{type_snake}.ex"
      else
        "lib/bibbidi/types/#{mod_snake}/#{type_snake}.ex"
      end
    else
      "lib/bibbidi/types/#{to_snake(ref_name)}.ex"
    end
  end

  @doc """
  Generates a spec anchor URL for a BiDi method name.
  """
  def spec_anchor(method) do
    # input.performActions → command-input-performActions
    [mod, cmd] = String.split(method, ".")
    "https://w3c.github.io/webdriver-bidi/#command-#{mod}-#{cmd}"
  end

  # ── Type module generation ───────────────────────────────────────

  defp generate_type_modules(igniter, type_refs, all_rules) do
    Enum.reduce(type_refs, igniter, fn ref_name, igniter ->
      case List.keyfind(all_rules, ref_name, 0) do
        {_, definition} ->
          generate_type_module(igniter, ref_name, definition, type_refs, all_rules)

        nil ->
          igniter
      end
    end)
  end

  defp generate_type_module(igniter, ref_name, definition, type_refs, all_rules) do
    module_name = cddl_ref_to_module(ref_name)
    path = cddl_ref_to_path(ref_name)

    content = build_type_module_content(module_name, ref_name, definition, type_refs, all_rules)
    Igniter.create_new_file(igniter, path, content, on_exists: :overwrite)
  end

  defp build_type_module_content(module_name, ref_name, definition, type_refs, all_rules) do
    case classify_type(definition, all_rules) do
      {:primitive_alias, _prim} ->
        build_primitive_alias_module(module_name, ref_name, definition, type_refs)

      {:string_enum, values} ->
        build_string_enum_module(module_name, ref_name, values)

      {:struct_like, fields} ->
        build_struct_like_module(module_name, ref_name, fields, type_refs)

      {:choice_union, alternatives} ->
        build_choice_union_module(module_name, ref_name, alternatives, type_refs)

      :opaque ->
        build_opaque_module(module_name, ref_name, definition, type_refs)
    end
  end

  defp classify_type({:primitive, _} = _def, _all_rules), do: {:primitive_alias, :primitive}
  defp classify_type({:primitive, _, _} = _def, _all_rules), do: {:primitive_alias, :primitive}
  defp classify_type({:range, _, _}, _all_rules), do: {:primitive_alias, :range}
  defp classify_type({:range_exclusive, _, _}, _all_rules), do: {:primitive_alias, :range}

  defp classify_type({:ref, inner_ref}, all_rules) do
    # Follow the ref to classify the underlying type
    case List.keyfind(all_rules, inner_ref, 0) do
      {_, inner_def} -> classify_type(inner_def, all_rules)
      nil -> :opaque
    end
  end

  defp classify_type({:choice, items}, _all_rules) do
    cond do
      Enum.all?(items, &match?({:string, _}, &1)) ->
        values = Enum.map(items, fn {:string, v} -> v end)
        {:string_enum, values}

      Enum.all?(items, &match?({:ref, _}, &1)) ->
        {:choice_union, items}

      true ->
        :opaque
    end
  end

  defp classify_type({:choice, items, _constraint}, all_rules) do
    classify_type({:choice, items}, all_rules)
  end

  defp classify_type({:map, [{:fields, fields}]}, _all_rules) do
    field_defs =
      fields
      |> Enum.flat_map(fn
        {:required, name, type} -> [{name, :required, type}]
        {:optional, name, type} -> [{name, :optional, type}]
        _ -> []
      end)

    {:struct_like, field_defs}
  end

  defp classify_type(_, _all_rules), do: :opaque

  defp build_primitive_alias_module(module_name, ref_name, definition, type_refs) do
    schema_str = type_to_schema(definition, type_refs)
    spec_str = type_to_spec(definition, type_refs)

    """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule #{module_name} do
      @moduledoc \"\"\"
      `#{ref_name}`
      \"\"\"

      @schema #{schema_str}
      @type t :: #{spec_str}

      @doc "Returns the Zoi schema for this type."
      def schema, do: @schema
    end
    """
  end

  defp build_string_enum_module(module_name, ref_name, values) do
    enum_values = Enum.map_join(values, ", ", fn v -> ~s["#{v}"] end)
    doc_values = Enum.map_join(values, "`, `", &~s(#{&1}))

    """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule #{module_name} do
      @moduledoc \"\"\"
      `#{ref_name}`

      Values: `#{doc_values}`
      \"\"\"

      @schema Zoi.enum([#{enum_values}])
      @type t :: String.t()
      @values ~w(#{Enum.join(values, " ")})

      @doc "Returns the Zoi schema for this type."
      def schema, do: @schema

      @doc "Returns the list of valid values."
      def values, do: @values
    end
    """
  end

  defp build_struct_like_module(module_name, ref_name, fields, type_refs) do
    schema_entries =
      fields
      |> Enum.map(fn {name, req, cddl_type} ->
        elixir_key = to_snake(name)
        base = type_to_schema_lazy(cddl_type, type_refs)

        if req == :optional do
          "#{elixir_key}: #{base} |> Zoi.optional()"
        else
          "#{elixir_key}: #{base}"
        end
      end)
      |> Enum.join(", ")

    spec_entries =
      fields
      |> Enum.map(fn {name, req, cddl_type} ->
        elixir_key = to_snake(name)
        spec = type_to_spec(cddl_type, type_refs)

        if req == :optional do
          "#{elixir_key}: #{spec} | nil"
        else
          "#{elixir_key}: #{spec}"
        end
      end)
      |> Enum.join(", ")

    doc_fields =
      fields
      |> Enum.map(fn {name, req, cddl_type} ->
        elixir_key = to_snake(name)
        type_doc = cddl_type_to_doc(cddl_type, type_refs)
        req_str = if req == :required, do: "required", else: "optional"
        "  - `#{elixir_key}` - #{type_doc} (#{req_str})"
      end)
      |> Enum.join("\n")

    """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule #{module_name} do
      @moduledoc \"\"\"
      `#{ref_name}`

      ## Fields

    #{doc_fields}
      \"\"\"

      @schema Zoi.map(%{#{schema_entries}})
      @type t :: %{#{spec_entries}}

      @doc "Returns the Zoi schema for this type."
      def schema, do: @schema
    end
    """
  end

  defp build_choice_union_module(module_name, ref_name, alternatives, type_refs) do
    schema_entries =
      alternatives
      |> Enum.map(fn {:ref, r} -> type_to_schema_lazy({:ref, r}, type_refs) end)
      |> Enum.join(", ")

    spec_entries =
      alternatives
      |> Enum.map(fn {:ref, r} -> type_to_spec({:ref, r}, type_refs) end)
      |> Enum.join(" | ")

    doc_items =
      alternatives
      |> Enum.map(fn {:ref, r} ->
        mod = cddl_ref_to_module(r)
        "  - `t:#{mod}.t/0`"
      end)
      |> Enum.join("\n")

    """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule #{module_name} do
      @moduledoc \"\"\"
      `#{ref_name}`

      One of:
    #{doc_items}
      \"\"\"

      @schema Zoi.union([#{schema_entries}])
      @type t :: #{spec_entries}

      @doc "Returns the Zoi schema for this type."
      def schema, do: @schema
    end
    """
  end

  defp build_opaque_module(module_name, ref_name, definition, type_refs) do
    schema_str = type_to_schema_lazy(definition, type_refs)
    spec_str = type_to_spec(definition, type_refs)

    """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule #{module_name} do
      @moduledoc \"\"\"
      `#{ref_name}`
      \"\"\"

      @schema #{schema_str}
      @type t :: #{spec_str}

      @doc "Returns the Zoi schema for this type."
      def schema, do: @schema
    end
    """
  end

  # ── ExDoc type documentation helper ──────────────────────────────

  @doc """
  Renders a CDDL type as an ExDoc-linked string for use in moduledocs.
  """
  def cddl_type_to_doc({:ref, name}, type_refs) do
    if MapSet.member?(type_refs, name) do
      mod = cddl_ref_to_module(name)
      "`t:#{mod}.t/0`"
    else
      "`#{name}`"
    end
  end

  def cddl_type_to_doc({:array, inner, _}, type_refs) do
    "list of #{cddl_type_to_doc(inner, type_refs)}"
  end

  def cddl_type_to_doc({:choice, items}, type_refs) do
    items
    |> Enum.map(&cddl_type_to_doc(&1, type_refs))
    |> Enum.join(" or ")
  end

  def cddl_type_to_doc({:choice, items, _}, type_refs), do: cddl_type_to_doc({:choice, items}, type_refs)
  def cddl_type_to_doc({:primitive, :text}, _), do: "`String.t()`"
  def cddl_type_to_doc({:primitive, :text, _}, _), do: "`String.t()`"
  def cddl_type_to_doc({:primitive, :uint}, _), do: "`non_neg_integer()`"
  def cddl_type_to_doc({:primitive, :uint, _}, _), do: "`non_neg_integer()`"
  def cddl_type_to_doc({:primitive, :int}, _), do: "`integer()`"
  def cddl_type_to_doc({:primitive, :int, _}, _), do: "`integer()`"
  def cddl_type_to_doc({:primitive, :float}, _), do: "`float()`"
  def cddl_type_to_doc({:primitive, :float, _}, _), do: "`float()`"
  def cddl_type_to_doc({:primitive, :bool}, _), do: "`boolean()`"
  def cddl_type_to_doc({:primitive, :bool, _}, _), do: "`boolean()`"
  def cddl_type_to_doc({:primitive, :any}, _), do: "`term()`"
  def cddl_type_to_doc({:primitive, :null}, _), do: "`nil`"
  def cddl_type_to_doc({:string, v}, _), do: "`\"#{v}\"`"
  def cddl_type_to_doc({:map, _}, _), do: "`map()`"
  def cddl_type_to_doc(_, _), do: "`term()`"

  # ── Event generation ─────────────────────────────────────────────

  @correlation_keys ~w(context navigation request)a

  defp maybe_generate_events_module(igniter, mod, _rules, local_rules, all_rules, type_refs) do
    events = extract_events(mod, local_rules)
    if events == [], do: igniter, else: generate_events_module(igniter, mod, events, all_rules, type_refs)
  end

  defp generate_events_module(igniter, mod, events, all_rules, type_refs) do
    snake = to_snake(mod)
    camel = to_module_name(mod)

    event_list =
      events
      |> Enum.map(fn {method, _params_ref} -> ~s("#{method}") end)
      |> Enum.join(",\n      ")

    event_functions =
      events
      |> Enum.map(fn {method, params_ref} ->
        fun_name = method |> String.split(".") |> List.last() |> to_snake()

        """
          @doc \"\"\"
          Event: `#{method}`

          Params type: `#{params_ref || "none"}`
          \"\"\"
          def #{fun_name}, do: "#{method}"
        """
      end)
      |> Enum.join("\n")

    # Build parse/2 clauses
    parse_clauses = generate_parse_clauses(events, all_rules)

    # Build struct aliases for parse/2
    struct_aliases = generate_struct_aliases(events, all_rules)

    content = """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule Bibbidi.Events.#{camel} do
      @moduledoc \"\"\"
      Events for the `#{mod}` module of the WebDriver BiDi protocol.
      \"\"\"

    #{struct_aliases}
      @doc "Returns all event method names for this module."
      @spec events() :: [String.t()]
      def events do
        [
          #{event_list}
        ]
      end

    #{event_functions}
      @doc "Parses a raw event params map into a typed struct."
      @spec parse(String.t(), map()) :: struct() | map()
    #{parse_clauses}
      def parse(_method, params), do: params
    end
    """

    path = "lib/bibbidi/events/#{snake}.ex"

    igniter = Igniter.create_new_file(igniter, path, content, on_exists: :overwrite)

    # Generate event struct modules
    generate_event_struct_modules(igniter, mod, events, all_rules, type_refs)
  end

  defp generate_parse_clauses(events, all_rules) do
    events
    |> Enum.map(fn {method, params_ref} ->
      struct_name = event_struct_name(method)
      fields = resolve_event_fields(params_ref, all_rules)

      if fields != [] do
        field_assignments =
          fields
          |> Enum.uniq_by(fn {json_key, _, _, _} -> json_key end)
          |> Enum.map(fn {json_key, elixir_key, _, _} ->
            "#{elixir_key}: params[\"#{json_key}\"]"
          end)
          |> Enum.join(", ")

        """
          def parse("#{method}", params) do
            %#{struct_name}{#{field_assignments}}
          end
        """
      else
        """
          def parse("#{method}", params), do: params
        """
      end
    end)
    |> Enum.join("\n")
  end

  defp generate_struct_aliases(events, all_rules) do
    events
    |> Enum.filter(fn {_, params_ref} -> resolve_event_fields(params_ref, all_rules) != [] end)
    |> Enum.map(fn {method, _} -> event_struct_name(method) end)
    |> Enum.map(fn name -> "  alias __MODULE__.#{name}" end)
    |> Enum.join("\n")
  end

  defp generate_event_struct_modules(igniter, mod, events, all_rules, type_refs) do
    snake_mod = to_snake(mod)

    events
    |> Enum.reduce(igniter, fn {method, params_ref}, igniter ->
      fields = resolve_event_fields(params_ref, all_rules)

      if fields != [] do
        generate_event_struct_module(igniter, snake_mod, mod, method, params_ref, fields, type_refs)
      else
        igniter
      end
    end)
  end

  defp generate_event_struct_module(igniter, snake_mod, mod, method, params_ref, fields, type_refs) do
    camel_mod = to_module_name(mod)
    struct_name = event_struct_name(method)
    snake_struct = to_snake(struct_name)

    unique_fields =
      fields
      |> Enum.uniq_by(fn {json_key, _, _, _} -> json_key end)

    field_atoms = Enum.map(unique_fields, fn {_, elixir_key, _, _} -> ":#{elixir_key}" end)
    fields_str = Enum.join(field_atoms, ", ")

    # Determine correlation keys for this struct
    field_atom_list = Enum.map(unique_fields, fn {_, elixir_key, _, _} -> String.to_atom(elixir_key) end)
    correlation = Enum.filter(@correlation_keys, &(&1 in field_atom_list))

    derive_line =
      if correlation == [] do
        ""
      else
        keys_str = Enum.map_join(correlation, ", ", &":#{&1}")
        "  @derive {Bibbidi.Telemetry.Metadata, keys: [#{keys_str}]}\n"
      end

    doc_fields =
      unique_fields
      |> Enum.map(fn {_json, elixir_key, req, cddl_type} ->
        type_doc = cddl_type_to_doc(cddl_type, type_refs)
        req_str = if req == :required, do: "required", else: "optional"
        "  - `#{elixir_key}` - #{type_doc} (#{req_str})"
      end)
      |> Enum.join("\n")

    content = """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule Bibbidi.Events.#{camel_mod}.#{struct_name} do
      @moduledoc \"\"\"
      Event struct for `#{method}`.

      Params type: `#{params_ref}`

      ## Fields

    #{doc_fields}
      \"\"\"

    #{derive_line}  defstruct [#{fields_str}]
    end
    """

    path = "lib/bibbidi/events/#{snake_mod}/#{snake_struct}.ex"
    Igniter.create_new_file(igniter, path, content, on_exists: :overwrite)
  end

  defp resolve_event_fields(nil, _all_rules), do: []

  defp resolve_event_fields(params_ref, all_rules) do
    resolve_command_fields(params_ref, all_rules)
  end

  # "browsingContext.contextCreated" -> "ContextCreated"
  defp event_struct_name(method) do
    method |> String.split(".") |> List.last() |> to_module_name()
  end

  defp extract_events(mod, local_rules) do
    local_rules
    |> Enum.filter(fn {name, def} ->
      String.starts_with?(name, mod <> ".") and is_event_def?(def)
    end)
    |> Enum.map(fn {_name, {:group, members}} ->
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

      {method, params_ref}
    end)
    |> Enum.reject(fn {method, _} -> is_nil(method) end)
  end

  # ── Command struct generation ─────────────────────────────────────

  defp maybe_generate_command_modules(igniter, mod, remote_rules, all_rules, type_refs) do
    commands = extract_commands(mod, remote_rules)
    if commands == [], do: igniter, else: generate_command_modules(igniter, mod, commands, all_rules, type_refs)
  end

  defp extract_commands(mod, remote_rules) do
    remote_rules
    |> Enum.filter(fn {name, def} ->
      String.starts_with?(name, mod <> ".") and Utils.command_def?(def)
    end)
    |> Enum.map(fn {name, {:group, members}} ->
      command_name = name |> String.split(".") |> List.last()

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

      {command_name, method, params_ref}
    end)
    |> Enum.reject(fn {_, method, _} -> is_nil(method) end)
  end

  defp generate_command_modules(igniter, mod, commands, all_rules, type_refs) do
    Enum.reduce(commands, igniter, fn {command_name, method, params_ref}, igniter ->
      generate_command_module(igniter, mod, command_name, method, params_ref, all_rules, type_refs)
    end)
  end

  defp generate_command_module(igniter, mod, command_name, method, params_ref, all_rules, type_refs) do
    snake_mod = to_snake(mod)
    camel_mod = to_module_name(mod)
    command_snake = to_snake(command_name)

    fields = resolve_command_fields(params_ref, all_rules)

    required = Enum.filter(fields, fn {_, _, req, _} -> req == :required end)
    optional = Enum.filter(fields, fn {_, _, req, _} -> req == :optional end)
    all_fields = required ++ optional

    # Build @schema (Zoi.struct)
    schema_fields =
      all_fields
      |> Enum.map(fn {_json, elixir, req, cddl_type} ->
        base = type_to_schema(cddl_type, type_refs)

        if req == :optional do
          "#{elixir}: #{base} |> Zoi.optional()"
        else
          "#{elixir}: #{base}"
        end
      end)
      |> Enum.join(", ")

    # Build @opts_schema (Zoi.keyword for optional fields)
    # Use Zoi.any() for ref types since users pass raw wire-format (camelCase) maps
    opts_schema_fields =
      optional
      |> Enum.map(fn {_json, elixir, _, cddl_type} ->
        "#{elixir}: #{type_to_opts_schema(cddl_type)} |> Zoi.optional()"
      end)
      |> Enum.join(", ")

    # Build @result_schema
    result_schema = resolve_result_schema(mod, command_name, all_rules, type_refs)

    params_body = generate_params_body(required, optional)

    # Add meta field to schema (optional, not sent on wire)
    meta_schema_field = "meta: Zoi.any() |> Zoi.optional()"

    full_schema_fields =
      if schema_fields == "" do
        meta_schema_field
      else
        "#{schema_fields}, #{meta_schema_field}"
      end

    # Build moduledoc with spec link and field descriptions
    moduledoc = build_command_moduledoc(method, all_fields, type_refs)

    content = """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule Bibbidi.Commands.#{camel_mod}.#{command_name} do
      @moduledoc \"\"\"
    #{moduledoc}
      \"\"\"

      @derive Bibbidi.Telemetry.Metadata
      @schema Zoi.struct(__MODULE__, %{#{full_schema_fields}})
      @opts_schema Zoi.keyword([#{opts_schema_fields}])
      @result_schema #{result_schema}

      @type t :: unquote(Zoi.type_spec(@schema))
      @type opts :: unquote(Zoi.type_spec(@opts_schema))
      @type result :: unquote(Zoi.type_spec(@result_schema))

      @enforce_keys Zoi.Struct.enforce_keys(@schema)
      defstruct Zoi.Struct.struct_fields(@schema)

      @doc "Returns the Zoi schema for this command struct."
      def schema, do: @schema

      @doc "Returns the Zoi schema for the keyword options."
      def opts_schema, do: @opts_schema

      @doc "Returns the Zoi schema for the result type."
      def result_schema, do: @result_schema

      defimpl Bibbidi.Encodable do
        def method(_), do: "#{method}"

    #{params_body}
      end
    end
    """

    path = "lib/bibbidi/commands/#{snake_mod}/#{command_snake}.ex"
    Igniter.create_new_file(igniter, path, content, on_exists: :overwrite)
  end

  defp build_command_moduledoc(method, fields, type_refs) do
    anchor = spec_anchor(method)

    field_docs =
      if fields == [] do
        ""
      else
        lines =
          fields
          |> Enum.map(fn {_json, elixir, req, cddl_type} ->
            type_doc = cddl_type_to_doc(cddl_type, type_refs)
            req_str = if req == :required, do: "required", else: "optional"
            "  - `#{elixir}` - #{type_doc} (#{req_str})"
          end)
          |> Enum.join("\n")

        "\n  ## Fields\n\n#{lines}\n"
      end

    "  Command struct for `#{method}`.\n\n  [WebDriver BiDi Spec](#{anchor})#{field_docs}"
  end

  @doc """
  Resolves a CDDL params reference into a list of
  `{json_key, elixir_key, :required | :optional, cddl_type}` tuples.

  Used by the code generator and by `mix bibbidi.cddl.inspect --fields`.
  """
  def resolve_command_fields(nil, _all_rules), do: []
  def resolve_command_fields("EmptyParams", _all_rules), do: []

  def resolve_command_fields(ref, all_rules) do
    case List.keyfind(all_rules, ref, 0) do
      {^ref, {:map, content}} ->
        extract_field_defs_from_map(content, all_rules)

      {^ref, {:group, members}} ->
        extract_field_defs(members, all_rules)

      {^ref, {:choice, alternatives}} ->
        # For choice types, merge fields from all alternatives (all optional)
        resolve_choice_fields(alternatives, all_rules)

      _ ->
        []
    end
  end

  defp extract_field_defs_from_map(content, all_rules) do
    Enum.flat_map(content, fn
      {:fields, fields} -> extract_field_defs(fields, all_rules)
      {:group_choice, groups} -> extract_field_defs_from_group_choice(groups, all_rules)
      _ -> []
    end)
  end

  defp extract_field_defs_from_group_choice(groups, all_rules) do
    # For group choices inside maps (e.g. coordinates // error),
    # include all fields as optional since only one branch is used at a time
    groups
    |> Enum.flat_map(fn
      {:fields, fields} ->
        Enum.flat_map(fields, fn
          {:required, name, type} -> [{name, to_snake(name), :optional, type}]
          {:optional, name, type} -> [{name, to_snake(name), :optional, type}]
          {:embed, ref} ->
            resolve_command_fields(ref, all_rules)
            |> Enum.map(fn {json, elixir, _, type} -> {json, elixir, :optional, type} end)
          _ -> []
        end)

      {:group, members} ->
        Enum.flat_map(members, fn
          {:required, name, type} -> [{name, to_snake(name), :optional, type}]
          {:optional, name, type} -> [{name, to_snake(name), :optional, type}]
          {:embed, ref} ->
            resolve_command_fields(ref, all_rules)
            |> Enum.map(fn {json, elixir, _, type} -> {json, elixir, :optional, type} end)
          _ -> []
        end)

      _ ->
        []
    end)
    |> Enum.uniq_by(fn {json, _, _, _} -> json end)
  end

  defp resolve_choice_fields(alternatives, all_rules) do
    # Resolve each alternative ref and merge all fields as optional
    Enum.flat_map(alternatives, fn
      {:ref, ref} ->
        resolve_command_fields(ref, all_rules)
        |> Enum.map(fn {json, elixir, _, type} -> {json, elixir, :optional, type} end)

      _ ->
        []
    end)
    |> Enum.uniq_by(fn {json, _, _, _} -> json end)
  end

  defp extract_field_defs(fields, all_rules) do
    Enum.flat_map(fields, fn
      {:required, name, type} ->
        [{name, to_snake(name), :required, type}]

      {:optional, name, type} ->
        [{name, to_snake(name), :optional, type}]

      {:group_choice, groups} ->
        extract_field_defs_from_group_choice(groups, all_rules)

      {:embed, ref} ->
        resolve_command_fields(ref, all_rules)

      _ ->
        []
    end)
  end

  defp generate_params_body([], []) do
    "    def params(_cmd), do: %{}"
  end

  defp generate_params_body(required, []) do
    fields =
      Enum.map_join(required, ", ", fn {json_key, elixir_key, _, _} ->
        "#{json_key}: cmd.#{elixir_key}"
      end)

    "    def params(cmd), do: %{#{fields}}"
  end

  defp generate_params_body(required, optional) do
    required_map =
      if required == [] do
        "%{}"
      else
        fields =
          Enum.map_join(required, ", ", fn {json_key, elixir_key, _, _} ->
            "#{json_key}: cmd.#{elixir_key}"
          end)

        "%{#{fields}}"
      end

    optional_entries =
      Enum.map_join(optional, ",\n        ", fn {json_key, elixir_key, _, _} ->
        "{:#{json_key}, cmd.#{elixir_key}}"
      end)

    """
        def params(cmd) do
          optional = [
            #{optional_entries}
          ]

          Enum.reduce(optional, #{required_map}, fn
            {_key, nil}, acc -> acc
            {key, value}, acc -> Map.put(acc, key, value)
          end)
        end
    """
  end

  # ── Result type resolution ──────────────────────────────────────

  @doc """
  Resolves the result Zoi schema string for a command.

  Looks up `<mod>.<CommandName>Result` in all_rules.
  """
  def resolve_result_schema(mod, command_name, all_rules, type_refs) do
    result_ref = "#{mod}.#{command_name}Result"
    resolve_result_ref(result_ref, all_rules, type_refs, 0)
  end

  defp resolve_result_ref(_ref, _all_rules, _type_refs, depth) when depth > 5 do
    "Zoi.map(Zoi.string(), Zoi.any())"
  end

  defp resolve_result_ref(ref, all_rules, type_refs, depth) do
    case List.keyfind(all_rules, ref, 0) do
      nil ->
        # No result type found
        "Zoi.map(Zoi.string(), Zoi.any())"

      {^ref, {:ref, "EmptyResult"}} ->
        "Zoi.map(Zoi.string(), Zoi.any())"

      {^ref, {:ref, inner_ref}} ->
        # Follow reference chain (e.g., ReloadResult → NavigateResult)
        resolve_result_ref(inner_ref, all_rules, type_refs, depth + 1)

      {^ref, {:map, [{:fields, []}]}} ->
        "Zoi.map(Zoi.string(), Zoi.any())"

      {^ref, {:map, [{:fields, fields}]}} ->
        field_schemas =
          fields
          |> Enum.map(fn
            {:required, key, type} -> "#{to_snake(key)}: #{type_to_schema(type, type_refs)}"
            {:optional, key, type} -> "#{to_snake(key)}: #{type_to_schema(type, type_refs)} |> Zoi.optional()"
            {:extensible, _, _} -> nil
            {:embed, _} -> nil
            {:group_choice, _} -> nil
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        "Zoi.map(%{#{field_schemas}})"

      {^ref, {:choice, _}} ->
        "Zoi.any()"

      {^ref, {:group, members}} ->
        # Check if it's an EmptyResult-like group
        real_fields =
          Enum.filter(members, fn
            {:required, _, _} -> true
            {:optional, _, _} -> true
            _ -> false
          end)

        if real_fields == [] do
          "Zoi.map(Zoi.string(), Zoi.any())"
        else
          field_schemas =
            real_fields
            |> Enum.map(fn
              {:required, key, type} -> "#{to_snake(key)}: #{type_to_schema(type, type_refs)}"
              {:optional, key, type} -> "#{to_snake(key)}: #{type_to_schema(type, type_refs)} |> Zoi.optional()"
            end)
            |> Enum.join(", ")

          "Zoi.map(%{#{field_schemas}})"
        end

      _ ->
        "Zoi.map(Zoi.string(), Zoi.any())"
    end
  end

  # ── Predicate helpers ───────────────────────────────────────────────

  defp is_event_def?({:group, members}) do
    has_method =
      Enum.any?(members, fn
        {:required, "method", {:string, m}} -> not String.ends_with?(m, "Command")
        _ -> false
      end)

    has_method and Utils.command_def?({:group, members})
  end

  defp is_event_def?(_), do: false

  # ── Zoi schema generation ─────────────────────────────────────────

  @doc """
  Like `type_to_schema/2` but wraps ref calls in `Zoi.lazy` to avoid
  compile-time circular dependencies between type modules.
  """
  def type_to_schema_lazy(type, type_refs) do
    # For refs, wrap in Zoi.lazy; for everything else, delegate to type_to_schema
    case type do
      {:ref, name} ->
        if MapSet.member?(type_refs, name) do
          "Zoi.lazy({#{cddl_ref_to_module(name)}, :schema, []})"
        else
          "Zoi.any()"
        end

      {:array, inner, _q} ->
        "Zoi.list(#{type_to_schema_lazy(inner, type_refs)})"

      {:choice, items} ->
        schemas = Enum.map(items, &type_to_schema_lazy(&1, type_refs))
        "Zoi.union([#{Enum.join(schemas, ", ")}])"

      {:choice, items, _constraint} ->
        type_to_schema_lazy({:choice, items}, type_refs)

      {:map, [{:fields, fields}]} ->
        field_schemas =
          fields
          |> Enum.map(fn
            {:required, key, t} -> "#{to_snake(key)}: #{type_to_schema_lazy(t, type_refs)}"
            {:optional, key, t} -> "#{to_snake(key)}: #{type_to_schema_lazy(t, type_refs)} |> Zoi.optional()"
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.join(", ")

        "Zoi.map(%{#{field_schemas}})"

      _ ->
        type_to_schema(type, type_refs)
    end
  end

  @doc """
  Like `type_to_schema/2` but keeps ref types as `Zoi.any()`.

  Used for `@opts_schema` where users pass raw wire-format (camelCase) maps
  that shouldn't be validated/stripped by typed schemas.
  """
  def type_to_opts_schema({:ref, _name}), do: "Zoi.any()"
  def type_to_opts_schema({:array, inner, _q}), do: "Zoi.list(#{type_to_opts_schema(inner)})"

  def type_to_opts_schema({:choice, items}) do
    schemas = Enum.map(items, &type_to_opts_schema/1)
    "Zoi.union([#{Enum.join(schemas, ", ")}])"
  end

  def type_to_opts_schema({:choice, items, _}), do: type_to_opts_schema({:choice, items})
  def type_to_opts_schema({:map, _}), do: "Zoi.any()"
  def type_to_opts_schema(type), do: type_to_schema(type)

  @doc false
  def type_to_schema(type, type_refs \\ MapSet.new())

  def type_to_schema({:primitive, :text}, _type_refs), do: "Zoi.string()"
  def type_to_schema({:primitive, :text, _}, _type_refs), do: "Zoi.string()"
  def type_to_schema({:primitive, :uint}, _type_refs), do: "Zoi.integer() |> Zoi.min(0)"
  def type_to_schema({:primitive, :uint, _}, _type_refs), do: "Zoi.integer() |> Zoi.min(0)"
  def type_to_schema({:primitive, :int}, _type_refs), do: "Zoi.integer()"
  def type_to_schema({:primitive, :int, _}, _type_refs), do: "Zoi.integer()"
  def type_to_schema({:primitive, :float}, _type_refs), do: "Zoi.float()"
  def type_to_schema({:primitive, :float, _}, _type_refs), do: "Zoi.float()"
  def type_to_schema({:primitive, :bool}, _type_refs), do: "Zoi.boolean()"
  def type_to_schema({:primitive, :bool, _}, _type_refs), do: "Zoi.boolean()"
  def type_to_schema({:primitive, :any}, _type_refs), do: "Zoi.any()"
  def type_to_schema({:primitive, :null}, _type_refs), do: "Zoi.null()"
  def type_to_schema({:string, _}, _type_refs), do: "Zoi.string()"
  def type_to_schema({:number, n}, _type_refs) when is_integer(n), do: "Zoi.integer()"
  def type_to_schema({:number, n}, _type_refs) when is_float(n), do: "Zoi.float()"
  def type_to_schema({:range, low, high}, _type_refs), do: "Zoi.integer() |> Zoi.min(#{low}) |> Zoi.max(#{high})"
  def type_to_schema({:range_exclusive, _low, _high}, _type_refs), do: "Zoi.integer()"

  def type_to_schema({:ref, name}, type_refs) do
    if MapSet.member?(type_refs, name) do
      "#{cddl_ref_to_module(name)}.schema()"
    else
      "Zoi.any()"
    end
  end

  def type_to_schema({:array, inner, _q}, type_refs), do: "Zoi.list(#{type_to_schema(inner, type_refs)})"

  def type_to_schema({:choice, items}, type_refs) do
    schemas = Enum.map(items, &type_to_schema(&1, type_refs))
    "Zoi.union([#{Enum.join(schemas, ", ")}])"
  end

  def type_to_schema({:choice, items, _constraint}, type_refs) do
    # 3-element choice with constraint (e.g. {:choice, items, {:default, _}})
    type_to_schema({:choice, items}, type_refs)
  end

  def type_to_schema({:map, [{:fields, fields}]}, type_refs) do
    field_schemas =
      fields
      |> Enum.map(fn
        {:required, key, type} -> "#{to_snake(key)}: #{type_to_schema(type, type_refs)}"
        {:optional, key, type} -> "#{to_snake(key)}: #{type_to_schema(type, type_refs)} |> Zoi.optional()"
        {:extensible, _, _} -> nil
        {:embed, _} -> nil
        {:group_choice, _} -> nil
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    "Zoi.map(%{#{field_schemas}})"
  end

  def type_to_schema({:map, _}, _type_refs), do: "Zoi.map(Zoi.string(), Zoi.any())"
  def type_to_schema({:group, _}, _type_refs), do: "Zoi.map(Zoi.string(), Zoi.any())"
  def type_to_schema({:tuple, items}, type_refs), do: "Zoi.tuple({#{Enum.map_join(items, ", ", &type_to_schema(&1, type_refs))}})"
  def type_to_schema({:group_choice, _}, _type_refs), do: "Zoi.any()"
  def type_to_schema(_, _type_refs), do: "Zoi.any()"

  # ── Typespec generation (for facade specs from CDDL types) ──────

  @doc false
  def type_to_spec(type, type_refs \\ MapSet.new())

  def type_to_spec({:primitive, :text}, _type_refs), do: "String.t()"
  def type_to_spec({:primitive, :text, _constraint}, _type_refs), do: "String.t()"
  def type_to_spec({:primitive, :uint}, _type_refs), do: "non_neg_integer()"
  def type_to_spec({:primitive, :uint, _constraint}, _type_refs), do: "non_neg_integer()"
  def type_to_spec({:primitive, :int}, _type_refs), do: "integer()"
  def type_to_spec({:primitive, :int, _constraint}, _type_refs), do: "integer()"
  def type_to_spec({:primitive, :float}, _type_refs), do: "float()"
  def type_to_spec({:primitive, :float, _constraint}, _type_refs), do: "float()"
  def type_to_spec({:primitive, :bool}, _type_refs), do: "boolean()"
  def type_to_spec({:primitive, :bool, _constraint}, _type_refs), do: "boolean()"
  def type_to_spec({:primitive, :any}, _type_refs), do: "term()"
  def type_to_spec({:primitive, :null}, _type_refs), do: "nil"
  def type_to_spec({:string, _}, _type_refs), do: "String.t()"
  def type_to_spec({:number, n}, _type_refs) when is_integer(n), do: "integer()"
  def type_to_spec({:number, n}, _type_refs) when is_float(n), do: "float()"
  def type_to_spec({:range, _low, _high}, _type_refs), do: "integer()"
  def type_to_spec({:range_exclusive, _low, _high}, _type_refs), do: "integer()"

  def type_to_spec({:ref, name}, type_refs) do
    if MapSet.member?(type_refs, name) do
      "#{cddl_ref_to_module(name)}.t()"
    else
      "term()"
    end
  end

  def type_to_spec({:choice, items}, type_refs) do
    items
    |> Enum.map(&type_to_spec(&1, type_refs))
    |> Enum.uniq()
    |> Enum.join(" | ")
  end

  def type_to_spec({:choice, items, _constraint}, type_refs) do
    type_to_spec({:choice, items}, type_refs)
  end

  def type_to_spec({:array, inner, _quantifier}, type_refs), do: "[#{type_to_spec(inner, type_refs)}]"
  def type_to_spec({:tuple, items}, type_refs), do: "{#{Enum.map_join(items, ", ", &type_to_spec(&1, type_refs))}}"
  def type_to_spec({:map, _}, _type_refs), do: "map()"
  def type_to_spec({:group, _}, _type_refs), do: "map()"
  def type_to_spec({:group_choice, _}, _type_refs), do: "map()"
  def type_to_spec(_, _type_refs), do: "term()"

  # ── Facade module generation ──────────────────────────────────────

  defp maybe_generate_facade_module(igniter, mod, remote_rules, all_rules, type_refs) do
    commands = extract_commands(mod, remote_rules)
    if commands == [], do: igniter, else: generate_facade_module(igniter, mod, commands, all_rules, type_refs)
  end

  defp generate_facade_module(igniter, mod, commands, all_rules, type_refs) do
    snake = to_snake(mod)
    camel = to_module_name(mod)

    # Collect all command module aliases needed
    command_aliases =
      commands
      |> Enum.map(fn {command_name, _, _} -> command_name end)
      |> Enum.map(fn name -> "  alias __MODULE__.#{name}" end)
      |> Enum.join("\n")

    functions =
      commands
      |> Enum.map(fn {command_name, method, params_ref} ->
        generate_facade_function(camel, command_name, method, params_ref, all_rules, type_refs)
      end)
      |> Enum.join("\n")

    session_note =
      if mod == "session" do
        "\n\n  See also `Bibbidi.Session` for a higher-level convenience API."
      else
        ""
      end

    content = """
    # Generated by mix bibbidi.gen — do not edit manually
    defmodule Bibbidi.Commands.#{camel} do
      @moduledoc \"\"\"
      Command builders for the `#{mod}` module of the WebDriver BiDi protocol.#{session_note}
      \"\"\"

      alias Bibbidi.Connection
    #{command_aliases}

    #{functions}end
    """

    path = "lib/bibbidi/commands/#{snake}.ex"
    Igniter.create_new_file(igniter, path, content, on_exists: :overwrite)
  end

  # Elixir reserved words that can't be function names
  @reserved_words ~w(end do fn if else case cond for receive try raise rescue after catch with)

  defp generate_facade_function(_camel_mod, command_name, method, params_ref, all_rules, type_refs) do
    raw_name = to_snake(command_name)

    fun_name =
      if raw_name in @reserved_words do
        # Derive a safe name from the BiDi module prefix + command name
        mod_prefix = method |> String.split(".") |> hd()
        to_snake(mod_prefix) <> "_" <> raw_name
      else
        raw_name
      end

    fields = resolve_command_fields(params_ref, all_rules)

    required = Enum.filter(fields, fn {_, _, req, _} -> req == :required end)
    optional = Enum.filter(fields, fn {_, _, req, _} -> req == :optional end)

    # Build the function signature — every function takes opts for :connection_mod
    required_args = Enum.map_join(required, ", ", fn {_, elixir, _, _} -> elixir end)

    args_str =
      case required_args do
        "" -> "conn, opts \\\\ []"
        r -> "conn, #{r}, opts \\\\ []"
      end

    # Build the struct creation body
    struct_body =
      case {required, optional} do
        {[], []} ->
          "%#{command_name}{}"

        {req, []} ->
          fields_str =
            req
            |> Enum.map(fn {_, elixir, _, _} -> "{:#{elixir}, #{elixir}}" end)
            |> Enum.join(", ")

          "struct!(#{command_name}, [#{fields_str}])"

        {req, _} ->
          required_pairs =
            req
            |> Enum.map(fn {_, elixir, _, _} -> "{:#{elixir}, #{elixir}}" end)

          all_pairs = Enum.join(required_pairs, ", ")

          if all_pairs == "" do
            "struct!(#{command_name}, opts)"
          else
            "struct!(#{command_name}, [#{all_pairs} | opts])"
          end
      end

    # Build the @spec with real types
    spec_required_args =
      required
      |> Enum.map(fn {_, _, _, cddl_type} -> type_to_spec(cddl_type, type_refs) end)

    spec_args =
      case spec_required_args do
        [] ->
          "GenServer.server(), #{command_name}.opts()"

        r ->
          "GenServer.server(), #{Enum.join(r, ", ")}, #{command_name}.opts()"
      end

    result_type = "#{command_name}.result()"

    # Build @doc with opts description
    doc =
      if optional != [] do
        """
          @doc \"\"\"
          Executes the `#{method}` command.

          ## Options

          \#{Zoi.describe(#{command_name}.opts_schema())}
          \"\"\"
        """
      else
        "  @doc \"Executes the `#{method}` command.\"\n"
      end

    # Build parse line for opts
    parse_line =
      if optional != [] do
        "    opts = Zoi.parse!(#{command_name}.opts_schema(), opts)\n"
      else
        ""
      end

    pop_line =
      if optional != [] do
        "    {connection_mod, opts} = Keyword.pop(opts, :connection_mod, Connection)"
      else
        "    {connection_mod, _opts} = Keyword.pop(opts, :connection_mod, Connection)"
      end

    """
    #{doc}  @spec #{fun_name}(#{spec_args}) :: {:ok, #{result_type}} | {:error, term()}
      def #{fun_name}(#{args_str}) do
    #{pop_line}
    #{parse_line}    connection_mod.execute(conn, #{struct_body}, [])
      end
    """
  end

  defdelegate to_snake(str), to: Utils
  defdelegate to_module_name(str), to: Utils
end
