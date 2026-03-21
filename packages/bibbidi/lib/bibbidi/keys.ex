defmodule Bibbidi.Keys do
  @moduledoc """
  Maps human-friendly key names to BiDi `value` strings for `input.performActions`.

  BiDi `keyDown`/`keyUp` actions require a `value` field containing either a single
  Unicode character (for regular keys like `"a"`) or a WebDriver Unicode
  private-use-area codepoint (for special keys like Enter → `\\uE007`).

  ## Usage

      iex> Bibbidi.Keys.key(:enter)
      "\\uE007"

      iex> Bibbidi.Keys.key("ArrowUp")
      "\\uE013"

      iex> Bibbidi.Keys.key("a")
      "a"

  ## Accepted formats

  - **Atoms** — snake_case: `:enter`, `:arrow_up`, `:shift`, `:f1`
  - **Strings** — PascalCase (DOM `KeyboardEvent.key`): `"Enter"`, `"ArrowUp"`, `"Shift"`, `"F1"`
  - **Single characters** — pass through unchanged: `"a"`, `" "`, `"1"`
  """

  @keys %{
    # Navigation / editing
    cancel: "\uE001",
    help: "\uE002",
    backspace: "\uE003",
    tab: "\uE004",
    clear: "\uE005",
    enter: "\uE007",
    pause: "\uE00B",
    escape: "\uE00C",
    page_up: "\uE00E",
    page_down: "\uE00F",
    end: "\uE010",
    home: "\uE011",
    arrow_left: "\uE012",
    arrow_up: "\uE013",
    arrow_right: "\uE014",
    arrow_down: "\uE015",
    insert: "\uE016",
    delete: "\uE017",

    # Modifiers
    shift: "\uE008",
    control: "\uE009",
    alt: "\uE00A",
    meta: "\uE03D",

    # Function keys
    f1: "\uE031",
    f2: "\uE032",
    f3: "\uE033",
    f4: "\uE034",
    f5: "\uE035",
    f6: "\uE036",
    f7: "\uE037",
    f8: "\uE038",
    f9: "\uE039",
    f10: "\uE03A",
    f11: "\uE03B",
    f12: "\uE03C",

    # Space (maps to literal space character)
    space: " ",

    # Location-specific modifier variants
    shift_left: "\uE008",
    shift_right: "\uE059",
    control_left: "\uE009",
    control_right: "\uE051",
    alt_left: "\uE00A",
    alt_right: "\uE052",
    meta_left: "\uE03D",
    meta_right: "\uE053",

    # Numpad keys
    numpad_0: "\uE01A",
    numpad_1: "\uE01B",
    numpad_2: "\uE01C",
    numpad_3: "\uE01D",
    numpad_4: "\uE01E",
    numpad_5: "\uE01F",
    numpad_6: "\uE020",
    numpad_7: "\uE021",
    numpad_8: "\uE022",
    numpad_9: "\uE023",
    numpad_multiply: "\uE024",
    numpad_add: "\uE025",
    numpad_separator: "\uE026",
    numpad_subtract: "\uE027",
    numpad_decimal: "\uE028",
    numpad_divide: "\uE029"
  }

  # String aliases (PascalCase DOM KeyboardEvent.key names)
  @string_keys %{
    "Cancel" => "\uE001",
    "Help" => "\uE002",
    "Backspace" => "\uE003",
    "Tab" => "\uE004",
    "Clear" => "\uE005",
    "Enter" => "\uE007",
    "Pause" => "\uE00B",
    "Escape" => "\uE00C",
    "PageUp" => "\uE00E",
    "PageDown" => "\uE00F",
    "End" => "\uE010",
    "Home" => "\uE011",
    "ArrowLeft" => "\uE012",
    "ArrowUp" => "\uE013",
    "ArrowRight" => "\uE014",
    "ArrowDown" => "\uE015",
    "Insert" => "\uE016",
    "Delete" => "\uE017",
    "Shift" => "\uE008",
    "Control" => "\uE009",
    "Alt" => "\uE00A",
    "Meta" => "\uE03D",
    "F1" => "\uE031",
    "F2" => "\uE032",
    "F3" => "\uE033",
    "F4" => "\uE034",
    "F5" => "\uE035",
    "F6" => "\uE036",
    "F7" => "\uE037",
    "F8" => "\uE038",
    "F9" => "\uE039",
    "F10" => "\uE03A",
    "F11" => "\uE03B",
    "F12" => "\uE03C",
    "Space" => " ",
    "ShiftLeft" => "\uE008",
    "ShiftRight" => "\uE059",
    "ControlLeft" => "\uE009",
    "ControlRight" => "\uE051",
    "AltLeft" => "\uE00A",
    "AltRight" => "\uE052",
    "MetaLeft" => "\uE03D",
    "MetaRight" => "\uE053",
    "Numpad0" => "\uE01A",
    "Numpad1" => "\uE01B",
    "Numpad2" => "\uE01C",
    "Numpad3" => "\uE01D",
    "Numpad4" => "\uE01E",
    "Numpad5" => "\uE01F",
    "Numpad6" => "\uE020",
    "Numpad7" => "\uE021",
    "Numpad8" => "\uE022",
    "Numpad9" => "\uE023",
    "NumpadMultiply" => "\uE024",
    "NumpadAdd" => "\uE025",
    "NumpadSeparator" => "\uE026",
    "NumpadSubtract" => "\uE027",
    "NumpadDecimal" => "\uE028",
    "NumpadDivide" => "\uE029"
  }

  # Build a lowercase lookup map for case-insensitive string matching
  @lowercase_keys Map.new(@string_keys, fn {k, v} -> {String.downcase(k), v} end)

  # KeyCode aliases: key_a..key_z → "a".."z", digit_0..digit_9 → "0".."9"
  @keycode_atoms for(c <- ?a..?z, do: {String.to_atom("key_#{<<c>>}"), <<c>>}) ++
                   for(d <- ?0..?9, do: {String.to_atom("digit_#{<<d>>}"), <<d>>})

  @all_atom_keys Map.merge(@keys, Map.new(@keycode_atoms))

  @doc """
  Returns the full key mapping as a map of `%{atom => String.t()}`.
  """
  @spec keys() :: %{atom() => String.t()}
  def keys, do: @all_atom_keys

  @doc """
  Converts a key name to its BiDi value string.

  Accepts atoms (`:enter`, `:arrow_up`), PascalCase strings (`"Enter"`, `"ArrowUp"`),
  or single characters which pass through unchanged.

  Raises `ArgumentError` for unknown key names.

  ## Examples

      iex> Bibbidi.Keys.key(:enter)
      "\\uE007"

      iex> Bibbidi.Keys.key("ArrowUp")
      "\\uE013"

      iex> Bibbidi.Keys.key("a")
      "a"

      iex> Bibbidi.Keys.key(:space)
      " "

  """
  @spec key(atom() | String.t()) :: String.t()
  def key(name) when is_atom(name) do
    case Map.fetch(@all_atom_keys, name) do
      {:ok, value} -> value
      :error -> raise ArgumentError, "unknown key: #{inspect(name)}"
    end
  end

  def key(<<_::utf8>> = char), do: char

  def key(name) when is_binary(name) do
    case Map.fetch(@string_keys, name) do
      {:ok, value} ->
        value

      :error ->
        case Map.fetch(@lowercase_keys, String.downcase(name)) do
          {:ok, value} -> value
          :error -> raise ArgumentError, "unknown key: #{inspect(name)}"
        end
    end
  end
end
