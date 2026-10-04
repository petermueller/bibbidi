defmodule Bibbidi.CDDL.Generator.DocsTest do
  use ExUnit.Case, async: false

  alias Bibbidi.CDDL.Generator.Docs

  setup do
    tmp = Path.join(System.tmp_dir!(), "bibbidi-examples-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    prev = Application.get_env(:bibbidi, :examples_dir)
    Application.put_env(:bibbidi, :examples_dir, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)

      case prev do
        nil -> Application.delete_env(:bibbidi, :examples_dir)
        v -> Application.put_env(:bibbidi, :examples_dir, v)
      end
    end)

    {:ok, tmp: tmp}
  end

  # Writes a fixture into the kind subfolder the generator will look in:
  # PascalCase last segment → module/, snake_case → function/.
  defp write_example(tmp, name, body) do
    sub =
      if String.match?(List.last(String.split(name, ".")), ~r/^[A-Z]/),
        do: "module",
        else: "function"

    dir = Path.join(tmp, sub)
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, name <> ".md"), body)
  end

  describe "for_name/1" do
    test "returns nil when no example file exists" do
      assert Docs.for_name("Bibbidi.Commands.Session.Subscribe") == nil
    end

    test "wraps file contents in a 2-space-indented `## Examples` block", %{tmp: tmp} do
      write_example(
        tmp,
        "Bibbidi.Commands.Session.Subscribe",
        "Use it like so:\n\n    {:ok, _} = Bibbidi.Commands.Session.subscribe(conn, [\"log.entryAdded\"])\n"
      )

      assert Docs.for_name("Bibbidi.Commands.Session.Subscribe") ==
               "  ## Examples\n\n  Use it like so:\n\n      {:ok, _} = Bibbidi.Commands.Session.subscribe(conn, [\"log.entryAdded\"])"
    end

    test "carries no leading or trailing blank line", %{tmp: tmp} do
      write_example(tmp, "X", "an example")
      out = Docs.for_name("X")

      refute String.starts_with?(out, "\n")
      refute String.ends_with?(out, "\n")
    end

    test "preserves blank lines without indenting them", %{tmp: tmp} do
      write_example(tmp, "X", "line one\n\nline two\n")
      out = Docs.for_name("X")

      assert out == "  ## Examples\n\n  line one\n\n  line two"
      refute String.contains?(out, "  \n"), "blank lines must not carry the indent prefix"
    end

    test "trims trailing whitespace before wrapping", %{tmp: tmp} do
      write_example(tmp, "X", "only line\n\n\n")
      assert Docs.for_name("X") == "  ## Examples\n\n  only line"
    end

    test "splits module vs function examples so case-only names don't collide", %{tmp: tmp} do
      write_example(tmp, "Bibbidi.Commands.Session.Subscribe", "struct example")
      write_example(tmp, "Bibbidi.Commands.Session.subscribe", "facade example")

      assert Docs.for_name("Bibbidi.Commands.Session.Subscribe") =~ "struct example"
      assert Docs.for_name("Bibbidi.Commands.Session.subscribe") =~ "facade example"
    end
  end

  describe "sections/0" do
    test "exposes the Examples section as the extension point" do
      assert %{key: :examples, heading: "Examples", dir: "priv/examples"} in Docs.sections()
    end
  end

  describe "dir/1" do
    test "honors the per-section `<key>_dir` application env override", %{tmp: tmp} do
      assert Docs.dir(%{key: :examples, dir: "priv/examples"}) == tmp
    end

    test "falls back to the section's :dir when no override is set" do
      Application.delete_env(:bibbidi, :examples_dir)
      assert Docs.dir(%{key: :examples, dir: "priv/examples"}) == "priv/examples"
    end
  end
end
