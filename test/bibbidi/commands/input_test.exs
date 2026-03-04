defmodule Bibbidi.Commands.InputTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Commands.Input
  alias Bibbidi.Connection

  setup do
    {:ok, conn} =
      Connection.start_link(
        url: "ws://localhost:1234",
        transport: Bibbidi.MockTransport,
        transport_opts: [owner: self()]
      )

    %{conn: conn}
  end

  defp reply(conn, id, result \\ %{}) do
    send(conn, {:mock_transport_receive, [{:text, JSON.encode!(%{id: id, result: result})}]})
  end

  describe "perform_actions/3" do
    test "sends input.performActions command", %{conn: conn} do
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

      task = Task.async(fn -> Input.perform_actions(conn, "ctx-1", actions) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "input.performActions"
      assert decoded["params"]["context"] == "ctx-1"
      assert length(decoded["params"]["actions"]) == 1
      assert hd(decoded["params"]["actions"])["type"] == "key"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end

    test "sends pointer actions", %{conn: conn} do
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

      task = Task.async(fn -> Input.perform_actions(conn, "ctx-1", actions) end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      pointer = hd(decoded["params"]["actions"])
      assert pointer["type"] == "pointer"
      assert length(pointer["actions"]) == 3

      reply(conn, decoded["id"])
      Task.await(task)
    end
  end

  describe "release_actions/2" do
    test "sends input.releaseActions command", %{conn: conn} do
      task = Task.async(fn -> Input.release_actions(conn, "ctx-1") end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "input.releaseActions"
      assert decoded["params"]["context"] == "ctx-1"

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end

  describe "set_files/4" do
    test "sends input.setFiles command", %{conn: conn} do
      element = %{sharedId: "elem-1"}

      task =
        Task.async(fn ->
          Input.set_files(conn, "ctx-1", element, ["/path/to/file.txt"])
        end)

      assert_receive {:mock_transport_send, json}
      decoded = JSON.decode!(json)
      assert decoded["method"] == "input.setFiles"
      assert decoded["params"]["context"] == "ctx-1"
      assert decoded["params"]["element"] == %{"sharedId" => "elem-1"}
      assert decoded["params"]["files"] == ["/path/to/file.txt"]

      reply(conn, decoded["id"])
      assert {:ok, _} = Task.await(task)
    end
  end
end
