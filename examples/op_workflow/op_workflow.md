# Op Workflow Example

A standalone Mix project demonstrating the workflow builder pattern generated
by `mix bibbidi.gen.workflow`.

## What's Inside

- `lib/op_workflow/bibbidi/op.ex` — Multi-style pipeline builder for composing BiDi commands
- `lib/op_workflow/bibbidi/operation.ex` — Execution record struct tracking steps, results, and timing
- `lib/op_workflow/bibbidi/runner.ex` — Sequential runner that executes pipelines via `Bibbidi.Connection.execute/2`
- `test/op_workflow/bibbidi/runner_test.exs` — Tests covering static sends, branching, error handling, and metadata

## Usage

```elixir
alias OpWorkflow.Bibbidi.{Op, Runner}
alias Bibbidi.Commands.BrowsingContext

op =
  Op.new()
  |> Op.send(:nav, %BrowsingContext.Navigate{
    context: ctx, url: "https://example.com", wait: "complete"
  })
  |> Op.send(:tree, %BrowsingContext.GetTree{})
  |> Op.branch(:maybe_screenshot, fn
    %{nav: {:ok, _}} ->
      {:send, %BrowsingContext.CaptureScreenshot{context: ctx}}
    _ ->
      {:ok, :skipped}
  end)

{:ok, results, operation} = Runner.execute(conn, op)
```

## Running Tests

```bash
cd examples/op_workflow
mix deps.get
mix test
```

## Generating Your Own

Run `mix bibbidi.gen.workflow` in your project to scaffold the same files.
The generated code is yours to own and modify.
