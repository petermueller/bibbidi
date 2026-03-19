defmodule Bibbidi.CDDL.Parser do
  @moduledoc """
  Parses a subset of CDDL (Concise Data Definition Language) used by the
  WebDriver BiDi specification.

  Produces a list of `{name, definition}` tuples representing each rule
  in the CDDL file.
  """

  import NimbleParsec

  # ── Whitespace & comments ──────────────────────────────────────────
  line_comment = string(";") |> utf8_string([not: ?\n], min: 0) |> optional(string("\n"))

  html_comment =
    string("<!--")
    |> repeat(
      lookahead_not(string("-->"))
      |> utf8_char([])
    )
    |> string("-->")

  ws =
    repeat(
      choice([
        utf8_char([?\s, ?\t, ?\n, ?\r]),
        line_comment,
        html_comment
      ])
    )

  # ── Primitives ─────────────────────────────────────────────────────
  # Identifiers: alphanumeric, dots, hyphens, underscores
  identifier =
    utf8_string([?a..?z, ?A..?Z], 1)
    |> utf8_string([?a..?z, ?A..?Z, ?0..?9, ?., ?-, ?_], min: 0)
    |> reduce({Enum, :join, [""]})

  # Quoted string value
  quoted_string =
    ignore(string("\""))
    |> utf8_string([not: ?"], min: 0)
    |> ignore(string("\""))
    |> unwrap_and_tag(:string)

  # Numbers (integer and float)
  digits = utf8_string([?0..?9], min: 1)

  number =
    optional(ascii_char([?-]))
    |> concat(digits)
    |> optional(string(".") |> concat(digits))
    |> reduce(:parse_number)

  # ── Type expressions ───────────────────────────────────────────────
  # Forward declarations for recursive grammar
  defcombinatorp(:type_expr, parsec(:type_choice))

  # type_choice: type1 / type1 / ...  (single slash = type choice)
  defcombinatorp(
    :type_choice,
    parsec(:type_single)
    |> repeat(
      ignore(ws)
      |> ignore(
        string("/")
        |> lookahead_not(string("/"))
      )
      |> ignore(ws)
      |> parsec(:type_single)
    )
    |> reduce(:maybe_choice)
  )

  # A single type (not a choice)
  defcombinatorp(
    :type_single,
    choice([
      # null
      string("null") |> replace({:primitive, :null}),
      # bool
      string("bool") |> replace({:primitive, :bool}),
      # float
      string("float")
      |> lookahead_not(utf8_char([?a..?z, ?A..?Z, ?0..?9, ?., ?-]))
      |> replace({:primitive, :float}),
      # text
      string("text")
      |> lookahead_not(utf8_char([?a..?z, ?A..?Z, ?0..?9, ?., ?-]))
      |> replace({:primitive, :text}),
      # any
      string("any")
      |> lookahead_not(utf8_char([?a..?z, ?A..?Z, ?0..?9, ?., ?-]))
      |> replace({:primitive, :any}),
      # int / uint
      string("int")
      |> lookahead_not(utf8_char([?a..?z, ?A..?Z, ?0..?9, ?., ?-]))
      |> replace({:primitive, :int}),
      string("uint")
      |> lookahead_not(utf8_char([?a..?z, ?A..?Z, ?0..?9, ?., ?-]))
      |> replace({:primitive, :uint}),
      # Quoted string literal
      quoted_string,
      # Array: [*Type] or [+Type] or [Type]
      parsec(:array_type),
      # Map: { ... }
      parsec(:map_type),
      # Parenthesized type: (type_expr) — tried before group to handle (uint .ge 1)
      parsec(:paren_type),
      # Group: ( ... )
      parsec(:group_type),
      # Range: num..num (must come before bare number)
      parsec(:range_or_number),
      # Reference to another rule
      identifier |> unwrap_and_tag(:ref)
    ])
    |> optional(ignore(ws) |> parsec(:constraint))
    |> reduce(:apply_constraint)
  )

  # Constraints: .default val, .ge val, .gt val
  defcombinatorp(
    :constraint,
    choice([
      ignore(string(".default"))
      |> ignore(ws)
      |> parsec(:type_expr)
      |> unwrap_and_tag(:default),
      ignore(string(".ge"))
      |> ignore(ws)
      |> parsec(:type_expr)
      |> unwrap_and_tag(:ge),
      ignore(string(".gt"))
      |> ignore(ws)
      |> parsec(:type_expr)
      |> unwrap_and_tag(:gt)
    ])
  )

  # Range or bare number
  defcombinatorp(
    :range_or_number,
    number
    |> optional(
      ignore(ws)
      |> choice([
        string("...") |> replace(:exclusive),
        string("..") |> replace(:inclusive)
      ])
      |> ignore(ws)
      |> concat(number)
    )
    |> reduce(:build_range_or_number)
  )

  # Array types: [*type], [+type], [type], or tuple: [type1, type2]
  defcombinatorp(
    :array_type,
    ignore(string("["))
    |> ignore(ws)
    |> choice([
      # Quantified array: [*type] or [+type]
      choice([
        string("*") |> replace(:zero_or_more),
        string("+") |> replace(:one_or_more)
      ])
      |> ignore(ws)
      |> parsec(:type_expr),
      # Unquantified: single type [type] or tuple [type1, type2, ...]
      parsec(:type_expr)
      |> repeat(
        ignore(ws)
        |> ignore(string(","))
        |> ignore(ws)
        |> parsec(:type_expr)
      )
    ])
    |> ignore(ws)
    |> ignore(string("]"))
    |> reduce(:build_array)
  )

  # Map types: { field1, field2, ... } or { group1 // group2 }
  defcombinatorp(
    :map_type,
    ignore(string("{"))
    |> ignore(ws)
    |> optional(parsec(:map_body))
    |> ignore(ws)
    |> ignore(string("}"))
    |> reduce(:build_map)
  )

  # Map body: supports // group choice at top level inside braces
  defcombinatorp(
    :map_body,
    parsec(:map_fields)
    |> repeat(
      ignore(ws)
      |> ignore(string("//"))
      |> ignore(ws)
      |> parsec(:map_fields)
    )
    |> reduce(:maybe_map_group_choice)
  )

  defcombinatorp(
    :map_fields,
    parsec(:group_member)
    |> repeat(
      ignore(ws)
      |> optional(ignore(string(",")))
      |> ignore(ws)
      |> lookahead_not(choice([string("}"), string("//")]))
      |> parsec(:group_member)
    )
    |> reduce(:build_field_group)
  )

  # Parenthesized type expression: (type_expr)
  # Handles e.g. (uint .ge 1) — a single type with optional constraint wrapped in parens.
  # Tried before group_type; backtracks on failure (e.g. for groups with fields).
  defcombinatorp(
    :paren_type,
    ignore(string("("))
    |> ignore(ws)
    |> parsec(:type_expr)
    |> ignore(ws)
    |> ignore(string(")"))
  )

  # Group types: ( ... )
  # Can be a group choice (with //), a field list, or a parenthesized type choice (with /)
  defcombinatorp(
    :group_type,
    ignore(string("("))
    |> ignore(ws)
    |> parsec(:group_body)
    |> ignore(ws)
    |> ignore(string(")"))
  )

  # Group body: try group choice (with //) first, then field list
  defcombinatorp(
    :group_body,
    parsec(:group_members)
    |> repeat(
      ignore(ws)
      |> ignore(string("//"))
      |> ignore(ws)
      |> parsec(:group_members)
    )
    |> reduce(:maybe_group_choice)
  )

  # Group members: comma-separated fields/types within a group
  # Also handles type-level / choices between bare references
  defcombinatorp(
    :group_members,
    parsec(:group_member)
    |> repeat(
      ignore(ws)
      |> choice([
        # Type choice separator (single /) between bare types
        ignore(string("/") |> lookahead_not(string("/")))
        |> ignore(ws)
        |> parsec(:group_member)
        |> tag(:type_alt),
        # Regular comma-separated field
        optional(ignore(string(",")))
        |> ignore(ws)
        |> lookahead_not(choice([string("//"), string(")")]))
        |> parsec(:group_member)
        |> tag(:field_next)
      ])
    )
    |> reduce(:build_group_members)
  )

  # A single member of a group (same as map_field essentially)
  defcombinatorp(
    :group_member,
    choice([
      # Extensible: *text => any
      string("*")
      |> ignore(ws)
      |> concat(identifier)
      |> ignore(ws)
      |> ignore(string("=>"))
      |> ignore(ws)
      |> parsec(:type_expr)
      |> reduce(:build_extensible),
      # Optional field: ? key: type
      ignore(string("?"))
      |> ignore(ws)
      |> choice([
        identifier
        |> ignore(ws)
        |> ignore(string(":"))
        |> ignore(ws)
        |> parsec(:type_expr)
        |> reduce(:build_optional_field),
        parsec(:type_expr) |> reduce(:build_optional_embed)
      ]),
      # Inline group choice: (group1 // group2)
      parsec(:group_type),
      # Inline map type: { ... } (e.g. in type choices inside groups)
      parsec(:map_type) |> reduce(:unwrap_map),
      # Inline array type: [ ... ] (e.g. tuples in type choices)
      parsec(:array_type) |> reduce(:unwrap_single),
      # Required field: key: type
      identifier
      |> ignore(ws)
      |> ignore(string(":"))
      |> ignore(ws)
      |> parsec(:type_expr)
      |> reduce(:build_required_field),
      # Bare string literal (for enums in groups)
      quoted_string,
      # Bare reference (embedded group)
      identifier |> reduce(:build_embed)
    ])
    |> ignore(ws)
    |> ignore(optional(string(",")))
  )

  # ── Top-level rule ─────────────────────────────────────────────────
  # name = type ;?
  rule =
    ignore(ws)
    |> concat(identifier)
    |> ignore(ws)
    |> ignore(string("="))
    |> ignore(ws)
    |> parsec(:type_expr)
    |> ignore(ws)
    |> ignore(optional(string(";")))
    |> reduce(:build_rule)

  defparsec(:parse_cddl, repeat(rule) |> ignore(ws) |> eos())

  # ── Reducer functions ──────────────────────────────────────────────

  @doc false
  def parse_number(parts) do
    str =
      parts
      |> Enum.map(fn
        c when is_integer(c) -> <<c>>
        s -> s
      end)
      |> Enum.join()

    if String.contains?(str, ".") do
      {:number, String.to_float(str)}
    else
      {:number, String.to_integer(str)}
    end
  end

  @doc false
  def build_range_or_number([{:number, n}]), do: {:number, n}

  def build_range_or_number([{:number, low}, :inclusive, {:number, high}]),
    do: {:range, low, high}

  def build_range_or_number([{:number, low}, :exclusive, {:number, high}]),
    do: {:range_exclusive, low, high}

  @doc false
  def apply_constraint([type]), do: type

  def apply_constraint([type, constraint]),
    do: Tuple.insert_at(type, tuple_size(type), constraint)

  @doc false
  def maybe_choice([single]), do: single
  def maybe_choice(items), do: {:choice, items}

  @doc false
  def build_array([:zero_or_more, type]), do: {:array, type, :zero_or_more}
  def build_array([:one_or_more, type]), do: {:array, type, :one_or_more}
  def build_array([type]), do: {:array, type, :zero_or_more}
  def build_array(types) when length(types) > 1, do: {:tuple, types}

  @doc false
  def unwrap_map([item]), do: item
  def unwrap_single([item]), do: item

  @doc false
  def build_map(fields), do: {:map, fields}

  @doc false
  def maybe_map_group_choice([single]), do: single
  def maybe_map_group_choice(groups), do: {:group_choice, groups}

  @doc false
  def build_field_group(fields), do: {:fields, fields}

  @doc false
  def build_required_field([name, type]) when is_binary(name), do: {:required, name, type}

  @doc false
  def build_optional_field([name, type]) when is_binary(name), do: {:optional, name, type}

  @doc false
  def build_optional_embed([type]), do: {:optional_embed, type}

  @doc false
  def build_embed([name]) when is_binary(name), do: {:embed, name}

  @doc false
  def build_extensible(["*", key_type | rest]) do
    value_type = List.last(rest)
    {:extensible, key_type, value_type}
  end

  @doc false
  def maybe_group_choice([single]), do: single
  def maybe_group_choice(groups), do: {:group_choice, groups}

  @doc false
  def build_group_members(members) do
    # Check if this is purely a type choice (only bare types with :type_alt tags)
    {fields, type_alts} = split_group_members(members, [], [])

    case {fields, type_alts} do
      {[single], alts} when alts != [] ->
        # All /  separated — this is a type choice
        {:choice, [single | alts]}

      _ ->
        # Regular field group
        {:group, fields}
    end
  end

  defp split_group_members([], fields, alts) do
    {Enum.reverse(fields), Enum.reverse(alts)}
  end

  defp split_group_members([{:type_alt, [item]} | rest], fields, alts) do
    split_group_members(rest, fields, [item | alts])
  end

  defp split_group_members([{:field_next, [item]} | rest], fields, alts) do
    split_group_members(rest, [item | fields], alts)
  end

  defp split_group_members([item | rest], fields, alts) do
    split_group_members(rest, [item | fields], alts)
  end

  @doc false
  def build_rule([name, definition]), do: {name, definition}

  # ── Public API ─────────────────────────────────────────────────────

  @doc """
  Parses a CDDL string into a list of `{name, definition}` tuples.
  """
  @spec parse(String.t()) :: {:ok, [{String.t(), term()}]} | {:error, term()}
  def parse(cddl_string) do
    case parse_cddl(cddl_string) do
      {:ok, rules, "", _, _, _} ->
        {:ok, rules}

      {:ok, _rules, rest, _, _, line_col} ->
        {:error, {:unparsed_input, String.slice(rest, 0, 100), line_col}}

      {:error, reason, rest, _, _, line_col} ->
        {:error, {reason, String.slice(rest, 0, 100), line_col}}
    end
  end

  @doc """
  Parses a CDDL file at the given path.
  """
  @spec parse_file(String.t()) :: {:ok, [{String.t(), term()}]} | {:error, term()}
  def parse_file(path) do
    path |> File.read!() |> parse()
  end
end
