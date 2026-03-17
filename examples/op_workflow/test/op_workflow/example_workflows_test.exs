defmodule OpWorkflow.ExampleWorkflowsTest do
  use ExUnit.Case, async: true

  alias Bibbidi.Connection
  alias OpWorkflow.Runner
  alias OpWorkflow.ExampleWorkflows.ClickElement

  setup do
    {:ok, conn} =
      Connection.start_link(
        url: "ws://localhost:1234",
        transport: OpWorkflow.MockTransport,
        transport_opts: [owner: self()]
      )

    %{conn: conn}
  end

  defp mock_reply(conn, result) do
    assert_receive {:mock_transport_send, json}
    decoded = JSON.decode!(json)

    send(
      conn,
      {:mock_transport_receive,
       [{:text, JSON.encode!(%{id: decoded["id"], result: result})}]}
    )

    decoded
  end

  describe "ClickElement" do
    test "locates and clicks an element", %{conn: conn} do
      op = ClickElement.build("ctx-1", "button.submit")

      task = Task.async(fn -> Runner.execute(conn, op) end)

      # Step 1: locateNodes
      d1 = mock_reply(conn, %{nodes: [%{type: "node", value: %{nodeType: 1}}]})
      assert d1["method"] == "browsingContext.locateNodes"
      assert d1["params"]["locator"] == %{"type" => "css", "value" => "button.submit"}

      # Step 2: callFunction (click)
      d2 = mock_reply(conn, %{result: %{type: "undefined"}})
      assert d2["method"] == "script.callFunction"
      assert d2["params"]["functionDeclaration"] == "node => node.click()"

      assert {:ok, results, _} = Task.await(task)
      assert {:ok, _} = results[:locate]
      assert {:ok, _} = results[:click]
    end

    test "returns error when element not found", %{conn: conn} do
      op = ClickElement.build("ctx-1", "button.missing")

      task = Task.async(fn -> Runner.execute(conn, op) end)

      # locateNodes returns empty
      mock_reply(conn, %{nodes: []})

      assert {:error, {:click, {:not_found, "button.missing"}}, _} = Task.await(task)
    end
  end
end
