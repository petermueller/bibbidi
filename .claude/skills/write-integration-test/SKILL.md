---
name: write-integration-test
description: This skill should be used when the user asks to "write an integration test", "add an integration test", or test a BiDi command or module against a real Firefox browser using Bibbidi.IntegrationCase in the bibbidi library.
---

# Write an Integration Test

Use when writing integration tests for a BiDi command or module. Run commands from `packages/bibbidi/`.

## Steps

1. **Create or edit the test file** at `test/integration/<module>_test.exs`.

2. **Use `Bibbidi.IntegrationCase`** — it handles browser launch, connection setup, and cleanup:

   ```elixir
   defmodule Bibbidi.Integration.ModuleNameTest do
     use Bibbidi.IntegrationCase

     # BrowsingContext, Connection, and Session are already aliased.
     # conn is available in test context.

     test "command works", %{conn: conn} do
       {:ok, result} = Bibbidi.Commands.ModuleName.some_command(conn, args)
       assert ...
     end
   end
   ```

3. **Get a browsing context** if the command needs one:
   ```elixir
   setup %{conn: conn} do
     {:ok, tree} = BrowsingContext.get_tree(conn)
     context = hd(tree["contexts"])["context"]
     %{context: context}
   end
   ```

4. **Navigate first** if the command needs page content:
   ```elixir
   BrowsingContext.navigate(conn, context, "data:text/html,<h1>Test</h1>", wait: "complete")
   ```

## Running

```bash
# All integration tests (requires Firefox)
mix test --include integration

# A specific integration test
mix test test/integration/browsing_context_test.exs --include integration

# Headed (visible browser)
BBD_DEBUG=1 mix test --include integration

# Connect to an existing browser
BBD_BROWSER_URL=ws://localhost:9222/session mix test --include integration
```

## Checklist

- [ ] Uses `use Bibbidi.IntegrationCase`
- [ ] Tests actual browser behavior, not just encoding
- [ ] Assertions check response structure and values
- [ ] No hardcoded context IDs (get them from `get_tree`)
- [ ] `mix test --include integration` passes
