defmodule Bibbidi.CommandCase do
  @moduledoc """
  Shared test case for command facade tests.

  Injects a Mox mock as `connection_mod` so facade functions never
  touch a GenServer. Tests set expectations on `execute/3` to verify
  the command struct is built correctly.

  ## Usage

      defmodule Bibbidi.Commands.FooTest do
        use Bibbidi.CommandCase, async: true

        alias Bibbidi.Commands.Foo

        test "sends the right command" do
          expect_execute(fn _conn, cmd ->
            assert %Foo.Bar{arg: "value"} = cmd
          end)

          assert {:ok, %{}} = Foo.bar(:conn, "value", connection_mod: MockConnection)
        end
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Mox

      alias Bibbidi.MockConnection

      setup :verify_on_exit!

      @doc false
      defp expect_execute(assertion, result \\ {:ok, %{}}) do
        expect(MockConnection, :execute, fn conn, cmd, _opts ->
          assertion.(conn, cmd)
          result
        end)
      end
    end
  end
end
