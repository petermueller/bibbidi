---
name: run-tests
description: This skill should be used when the user asks to "run tests", "run the tests", "run integration tests", "run a specific test", "verify the build", "run mix test", "mix test.all", run headed / with a visible browser, or do a full compile + format + test verification of the bibbidi Elixir library.
---

# Run Tests

Run bibbidi's test suite. Run all commands from `packages/bibbidi/`.

## Unit tests only (default)

```bash
mix test
```

## Include integration tests (requires Firefox)

```bash
mix test.all
# equivalent to:
mix test --include integration
```

## Run headed (visible browser)

```bash
BBD_DEBUG=1 mix test --include integration
```

## Specific file

```bash
mix test test/bibbidi/commands/browsing_context_test.exs
```

## Specific test by line number

```bash
mix test test/bibbidi/commands/browsing_context_test.exs:15
```

## With an existing browser (skip auto-launch)

```bash
BBD_BROWSER_URL="ws://localhost:9222/session" mix test --include integration
```

## Full verification (run before finishing work)

```bash
mix compile --warnings-as-errors && mix format --check-formatted && mix test.all
```
