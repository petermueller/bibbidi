defmodule Bibbidi.KeysTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Keys

  describe "key/1 with atoms" do
    test "navigation keys" do
      assert Keys.key(:cancel) == "\uE001"
      assert Keys.key(:help) == "\uE002"
      assert Keys.key(:backspace) == "\uE003"
      assert Keys.key(:tab) == "\uE004"
      assert Keys.key(:clear) == "\uE005"
      assert Keys.key(:enter) == "\uE007"
      assert Keys.key(:pause) == "\uE00B"
      assert Keys.key(:escape) == "\uE00C"
      assert Keys.key(:page_up) == "\uE00E"
      assert Keys.key(:page_down) == "\uE00F"
      assert Keys.key(:end) == "\uE010"
      assert Keys.key(:home) == "\uE011"
      assert Keys.key(:insert) == "\uE016"
      assert Keys.key(:delete) == "\uE017"
    end

    test "arrow keys" do
      assert Keys.key(:arrow_left) == "\uE012"
      assert Keys.key(:arrow_up) == "\uE013"
      assert Keys.key(:arrow_right) == "\uE014"
      assert Keys.key(:arrow_down) == "\uE015"
    end

    test "modifier keys" do
      assert Keys.key(:shift) == "\uE008"
      assert Keys.key(:control) == "\uE009"
      assert Keys.key(:alt) == "\uE00A"
      assert Keys.key(:meta) == "\uE03D"
    end

    test "function keys" do
      assert Keys.key(:f1) == "\uE031"
      assert Keys.key(:f2) == "\uE032"
      assert Keys.key(:f3) == "\uE033"
      assert Keys.key(:f4) == "\uE034"
      assert Keys.key(:f5) == "\uE035"
      assert Keys.key(:f6) == "\uE036"
      assert Keys.key(:f7) == "\uE037"
      assert Keys.key(:f8) == "\uE038"
      assert Keys.key(:f9) == "\uE039"
      assert Keys.key(:f10) == "\uE03A"
      assert Keys.key(:f11) == "\uE03B"
      assert Keys.key(:f12) == "\uE03C"
    end

    test "space" do
      assert Keys.key(:space) == " "
    end

    test "location-specific modifiers" do
      assert Keys.key(:shift_left) == "\uE008"
      assert Keys.key(:shift_right) == "\uE059"
      assert Keys.key(:control_left) == "\uE009"
      assert Keys.key(:control_right) == "\uE051"
      assert Keys.key(:alt_left) == "\uE00A"
      assert Keys.key(:alt_right) == "\uE052"
      assert Keys.key(:meta_left) == "\uE03D"
      assert Keys.key(:meta_right) == "\uE053"
    end

    test "numpad keys" do
      assert Keys.key(:numpad_0) == "\uE01A"
      assert Keys.key(:numpad_9) == "\uE023"
      assert Keys.key(:numpad_multiply) == "\uE024"
      assert Keys.key(:numpad_add) == "\uE025"
      assert Keys.key(:numpad_subtract) == "\uE027"
      assert Keys.key(:numpad_decimal) == "\uE028"
      assert Keys.key(:numpad_divide) == "\uE029"
    end

    test "keycode aliases" do
      assert Keys.key(:key_a) == "a"
      assert Keys.key(:key_z) == "z"
      assert Keys.key(:digit_0) == "0"
      assert Keys.key(:digit_9) == "9"
    end

    test "unknown atom raises ArgumentError" do
      assert_raise ArgumentError, ~r/unknown key: :nope/, fn ->
        Keys.key(:nope)
      end
    end
  end

  describe "key/1 with strings" do
    test "PascalCase special keys" do
      assert Keys.key("Enter") == "\uE007"
      assert Keys.key("ArrowUp") == "\uE013"
      assert Keys.key("ArrowDown") == "\uE015"
      assert Keys.key("Tab") == "\uE004"
      assert Keys.key("Escape") == "\uE00C"
      assert Keys.key("Backspace") == "\uE003"
      assert Keys.key("Delete") == "\uE017"
      assert Keys.key("Shift") == "\uE008"
      assert Keys.key("Control") == "\uE009"
      assert Keys.key("Alt") == "\uE00A"
      assert Keys.key("Meta") == "\uE03D"
      assert Keys.key("F1") == "\uE031"
      assert Keys.key("F12") == "\uE03C"
      assert Keys.key("PageUp") == "\uE00E"
      assert Keys.key("PageDown") == "\uE00F"
      assert Keys.key("Space") == " "
    end

    test "single characters pass through" do
      assert Keys.key("a") == "a"
      assert Keys.key("Z") == "Z"
      assert Keys.key("1") == "1"
      assert Keys.key(" ") == " "
      assert Keys.key("!") == "!"
    end

    test "case-insensitive matching" do
      assert Keys.key("enter") == "\uE007"
      assert Keys.key("ENTER") == "\uE007"
      assert Keys.key("arrowup") == "\uE013"
      assert Keys.key("ARROWUP") == "\uE013"
      assert Keys.key("pagedown") == "\uE00F"
    end

    test "unknown string raises ArgumentError" do
      assert_raise ArgumentError, ~r/unknown key: "NotAKey"/, fn ->
        Keys.key("NotAKey")
      end
    end
  end

  describe "keys/0" do
    test "returns a map of all atom keys" do
      keys = Keys.keys()
      assert is_map(keys)
      assert keys[:enter] == "\uE007"
      assert keys[:key_a] == "a"
      assert keys[:digit_0] == "0"
    end
  end
end
