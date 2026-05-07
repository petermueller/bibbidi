defmodule Bibbidi.CDDL.Generator.ExamplesTest do
  use ExUnit.Case, async: false

  alias Bibbidi.CDDL.Generator.Examples

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

  describe "for_name/1" do
    test "returns empty string when no example file exists" do
      assert Examples.for_name("Bibbidi.Commands.Session.Subscribe") == ""
    end

    test "wraps file contents in a 2-space-indented `## Examples` section", %{tmp: tmp} do
      File.write!(
        Path.join(tmp, "Bibbidi.Commands.Session.Subscribe.md"),
        "Use it like so:\n\n    {:ok, _} = Bibbidi.Commands.Session.subscribe(conn, [\"log.entryAdded\"])\n"
      )

      assert Examples.for_name("Bibbidi.Commands.Session.Subscribe") ==
               """


                 ## Examples

                 Use it like so:

                     {:ok, _} = Bibbidi.Commands.Session.subscribe(conn, ["log.entryAdded"])
               """
    end

    test "preserves blank lines without trailing whitespace", %{tmp: tmp} do
      File.write!(Path.join(tmp, "X.md"), "line one\n\nline two\n")
      out = Examples.for_name("X")

      assert out == "\n\n  ## Examples\n\n  line one\n\n  line two\n"
      refute String.contains?(out, "  \n"), "blank lines must not carry the indent prefix"
    end

    test "trims trailing whitespace before wrapping", %{tmp: tmp} do
      File.write!(Path.join(tmp, "X.md"), "only line\n\n\n")
      assert Examples.for_name("X") == "\n\n  ## Examples\n\n  only line\n"
    end

    test "is keyed per emission point — different files for struct vs facade", %{tmp: tmp} do
      File.write!(Path.join(tmp, "Bibbidi.Commands.Session.Subscribe.md"), "struct example")
      File.write!(Path.join(tmp, "Bibbidi.Commands.Session.subscribe.md"), "facade example")

      assert Examples.for_name("Bibbidi.Commands.Session.Subscribe") =~ "struct example"
      assert Examples.for_name("Bibbidi.Commands.Session.subscribe") =~ "facade example"
    end
  end

  describe "dir/0" do
    test "honors the :examples_dir application env override", %{tmp: tmp} do
      assert Examples.dir() == tmp
    end

    test "defaults to priv/examples when no override is set" do
      Application.delete_env(:bibbidi, :examples_dir)
      assert Examples.dir() == "priv/examples"
    end
  end
end
