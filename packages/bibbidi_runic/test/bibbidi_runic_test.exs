defmodule BibbidiRunicTest do
  use ExUnit.Case, async: true

  require Runic
  alias Bibbidi.Connection
  alias Bibbidi.Commands.BrowsingContext
  alias Runic.Workflow

  setup do
    {:ok, conn} =
      Connection.start_link(
        url: "ws://localhost:1234",
        transport: BibbidiRunic.MockTransport,
        transport_opts: [owner: self()]
      )

    %{conn: conn}
  end

  defp mock_reply(conn, result) do
    assert_receive {:mock_transport_send, json}
    decoded = JSON.decode!(json)

    send(
      conn,
      {:mock_transport_receive, [{:text, JSON.encode!(%{id: decoded["id"], result: result})}]}
    )

    decoded
  end

  defp production_values(results) do
    Enum.map(results, fn {_label, value} -> value end)
  end

  describe "BibbidiRunic.step/2" do
    test "creates a Runic step from a command struct", %{conn: conn} do
      step =
        BibbidiRunic.step(
          %BrowsingContext.Activate{context: "ctx-1"},
          conn: conn
        )

      assert %Runic.Workflow.Step{} = step
      assert step.name == :browsingContext_activate
    end

    test "accepts custom name", %{conn: conn} do
      step =
        BibbidiRunic.step(
          %BrowsingContext.Activate{context: "ctx-1"},
          conn: conn,
          name: :my_activate
        )

      assert step.name == :my_activate
    end

    test "step executes via workflow", %{conn: conn} do
      step =
        BibbidiRunic.step(
          %BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"},
          conn: conn,
          name: :navigate
        )

      workflow = Runic.workflow(name: "test", steps: [step])

      task =
        Task.async(fn ->
          workflow
          |> Workflow.react_until_satisfied(:go)
          |> Workflow.raw_productions()
          |> production_values()
        end)

      decoded = mock_reply(conn, %{navigation: "nav-1", url: "https://example.com"})
      assert decoded["method"] == "browsingContext.navigate"

      values = Task.await(task)

      assert Enum.any?(values, &match?({:ok, %{"navigation" => "nav-1"}}, &1)) or
               Enum.any?(values, &match?(%{"navigation" => "nav-1"}, &1))
    end
  end

  describe "BibbidiRunic.dynamic_step/2" do
    test "builds command from input fact", %{conn: conn} do
      navigate_step =
        BibbidiRunic.step(
          %BrowsingContext.Navigate{context: "ctx-1", url: "https://example.com"},
          conn: conn,
          name: :navigate
        )

      tree_step =
        BibbidiRunic.dynamic_step(
          fn _input -> %BrowsingContext.GetTree{} end,
          conn: conn,
          name: :tree
        )

      workflow =
        Runic.workflow(
          name: "nav_then_tree",
          steps: [{navigate_step, [tree_step]}]
        )

      task =
        Task.async(fn ->
          workflow
          |> Workflow.react_until_satisfied(:go)
          |> Workflow.raw_productions()
          |> production_values()
        end)

      d1 = mock_reply(conn, %{navigation: "nav-1", url: "https://example.com"})
      assert d1["method"] == "browsingContext.navigate"

      d2 = mock_reply(conn, %{contexts: [%{context: "ctx-1"}]})
      assert d2["method"] == "browsingContext.getTree"

      values = Task.await(task)

      assert Enum.any?(values, fn
               {:ok, %{"contexts" => _}} -> true
               %{"contexts" => _} -> true
               _ -> false
             end)
    end
  end

  describe "multi-step workflow" do
    test "executes steps in dependency order", %{conn: conn} do
      step1 =
        BibbidiRunic.step(
          %BrowsingContext.Navigate{
            context: "ctx-1",
            url: "https://example.com",
            wait: "complete"
          },
          conn: conn,
          name: :navigate
        )

      step2 =
        BibbidiRunic.step(
          %BrowsingContext.CaptureScreenshot{context: "ctx-1"},
          conn: conn,
          name: :screenshot
        )

      workflow =
        Runic.workflow(
          name: "navigate_and_screenshot",
          steps: [{step1, [step2]}]
        )

      task =
        Task.async(fn ->
          workflow
          |> Workflow.react_until_satisfied(:go)
          |> Workflow.raw_productions()
          |> production_values()
        end)

      d1 = mock_reply(conn, %{navigation: "nav-1", url: "https://example.com"})
      assert d1["method"] == "browsingContext.navigate"

      d2 = mock_reply(conn, %{data: "base64screenshot"})
      assert d2["method"] == "browsingContext.captureScreenshot"

      values = Task.await(task)

      assert Enum.any?(values, fn
               {:ok, %{"data" => "base64screenshot"}} -> true
               %{"data" => "base64screenshot"} -> true
               _ -> false
             end)
    end
  end
end
