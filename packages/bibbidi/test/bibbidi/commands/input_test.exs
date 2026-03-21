defmodule Bibbidi.Commands.InputTest do
  use Bibbidi.CommandCase, async: true

  alias Bibbidi.Commands.Input

  describe "perform_actions/3" do
    test "sends input.performActions command" do
      actions = [
        %{
          type: "key",
          id: "keyboard-1",
          actions: [
            %{type: "keyDown", value: "a"},
            %{type: "keyUp", value: "a"}
          ]
        }
      ]

      expect_execute(fn _conn, cmd ->
        assert %Input.PerformActions{} = cmd
        assert Bibbidi.Encodable.method(cmd) == "input.performActions"
        assert cmd.context == "ctx-1"
        assert length(cmd.actions) == 1
        assert hd(cmd.actions).type == "key"
      end)

      assert {:ok, %{}} =
               Input.perform_actions(:conn, "ctx-1", actions, connection_mod: MockConnection)
    end

    test "sends pointer actions" do
      actions = [
        %{
          type: "pointer",
          id: "mouse-1",
          parameters: %{pointerType: "mouse"},
          actions: [
            %{type: "pointerMove", x: 100, y: 200},
            %{type: "pointerDown", button: 0},
            %{type: "pointerUp", button: 0}
          ]
        }
      ]

      expect_execute(fn _conn, cmd ->
        pointer = hd(cmd.actions)
        assert pointer.type == "pointer"
        assert length(pointer.actions) == 3
      end)

      Input.perform_actions(:conn, "ctx-1", actions, connection_mod: MockConnection)
    end
  end

  describe "release_actions/2" do
    test "sends input.releaseActions command" do
      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "input.releaseActions"
        assert cmd.context == "ctx-1"
      end)

      assert {:ok, %{}} =
               Input.release_actions(:conn, "ctx-1", connection_mod: MockConnection)
    end
  end

  describe "set_files/4" do
    test "sends input.setFiles command" do
      element = %{sharedId: "elem-1"}

      expect_execute(fn _conn, cmd ->
        assert Bibbidi.Encodable.method(cmd) == "input.setFiles"
        assert cmd.context == "ctx-1"
        assert cmd.element == %{sharedId: "elem-1"}
        assert cmd.files == ["/path/to/file.txt"]
      end)

      assert {:ok, %{}} =
               Input.set_files(:conn, "ctx-1", element, ["/path/to/file.txt"],
                 connection_mod: MockConnection
               )
    end
  end
end
