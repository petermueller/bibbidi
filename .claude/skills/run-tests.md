# Run Tests

## Unit tests only (default)
```bash
mix test
```

## Include integration tests (requires Firefox)
```bash
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

## Full verification
```bash
mix compile --warnings-as-errors && mix format --check-formatted && mix test
```
