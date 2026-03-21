defmodule OpWorkflow.ExampleWorkflows.ClickElement do
  @moduledoc """
  Example workflow: locate an element by CSS selector and click it.

  Demonstrates `Op.send/3` with a static command, `Op.branch/3` for
  conditional logic based on previous results, and dynamic command
  construction.
  """

  alias OpWorkflow.Op
  alias Bibbidi.Commands.{BrowsingContext, Script}

  @doc """
  Build an Op pipeline that locates `selector` in `context` and clicks it.
  """
  def build(context, selector) do
    Op.new()
    |> Op.send(:locate, %BrowsingContext.LocateNodes{
      context: context,
      locator: %{type: "css", value: selector}
    })
    |> Op.branch(:click, fn
      %{locate: {:ok, %{"nodes" => [node | _]}}} ->
        {:send,
         %Script.CallFunction{
           function_declaration: "node => node.click()",
           target: %{context: context},
           arguments: [node],
           await_promise: false
         }}

      %{locate: {:ok, %{"nodes" => []}}} ->
        {:error, {:not_found, selector}}
    end)
  end
end
