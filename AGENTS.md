# Bibbidi — WebDriver BiDi Protocol for Elixir

## Project Overview

Low-level Elixir implementation of the W3C WebDriver BiDi Protocol.
Building-block library — no opinionated supervision tree.

## Architecture

- **`Bibbidi.Transport`** — Behaviour for swappable WebSocket transports
- **`Bibbidi.Transport.MintWS`** — Default transport using `mint_web_socket`
- **`Bibbidi.Browser`** — GenServer: owns browser OS process via `Port.open`, kills process tree in `terminate/2`. Users supervise this themselves.
- **`Bibbidi.Connection`** — GenServer: WebSocket + command ID correlation + event dispatch. Users supervise this themselves.
- **`Bibbidi.Protocol`** — Pure JSON encode/decode (no process state)
- **`Bibbidi.Session`** — Functional module for session lifecycle (takes conn pid)
- **`Bibbidi.Commands.*`** — Command builder modules (one per BiDi module)
- **`Bibbidi.Events.*`** — Event types (generated from CDDL codegen)

## Monorepo Structure

```
packages/
├── bibbidi/                    — the core hex package
│   ├── lib/bibbidi/            — source code
│   ├── dev/                    — code generators (CDDL parser, Igniter tasks)
│   ├── test/                   — tests
│   ├── priv/cddl/              — downloaded CDDL spec files
│   ├── examples/op_workflow/   — standalone example project (Op builder pattern)
│   └── mix.exs
├── bibbidi_runic/              — Runic workflow integration
└── bibbidi_playwright_trace/   — Playwright trace file generation
```

## File Layout (packages/bibbidi/)

```
lib/bibbidi/browser.ex         — Browser lifecycle GenServer
lib/bibbidi/connection.ex      — Core GenServer (execute/2 + telemetry)
lib/bibbidi/encodable.ex       — Encodable protocol (method/1, params/1)
lib/bibbidi/telemetry.ex       — Telemetry event documentation
lib/bibbidi/protocol.ex        — Pure JSON encode/decode
lib/bibbidi/transport.ex       — Behaviour
lib/bibbidi/transport/mint_ws.ex — Mint.WebSocket impl
lib/bibbidi/session.ex         — Session lifecycle
lib/bibbidi/commands/*.ex      — Command builder modules
lib/bibbidi/commands/<mod>/*.ex — Command structs (generated, implement Encodable)
lib/bibbidi/events/*.ex        — Event helpers (generated)
dev/mix/tasks/*.ex             — Mix tasks (gen, download_spec, gen.workflow)
priv/cddl/                    — Downloaded CDDL spec files
test/support/                  — Test helpers (IntegrationCase, MockTransport)
test/bibbidi/                  — Unit tests
test/integration/              — Integration tests (tagged :integration)
```

## Coding Conventions

- Command builder functions live in `Bibbidi.Commands.<Module>` and take `(conn, required_args..., opts \\ [])`.
- Optional BiDi params use Elixir keyword opts with `snake_case` keys, mapped to `camelCase` JSON keys.
- All command functions return `{:ok, map()} | {:error, term()}`.
- Event subscribers receive `{:bibbidi_event, method, params}` messages.
- No auto-supervision — users add `Bibbidi.Connection` to their own sup trees.

## Environment Variables

All project env vars use the `BBD_` prefix:

- `BBD_DEV` — When set, satellite packages (`bibbidi_runic`, `bibbidi_playwright_trace`) depend on bibbidi via `path: "../bibbidi"` instead of a Hex version (`~> 0.2.0`). Use this for local development across packages.
- `BBD_BROWSER_URL` — Skip browser launch and connect to an existing instance
- `BBD_DEBUG=1` — Run headed (visible browser window)

## Testing

Run from `packages/bibbidi/`:

- `mix test` — Unit tests only (integration excluded by default)
- `mix test --include integration` — Runs integration tests (needs Firefox)
- Set `BBD_BROWSER_URL` to skip browser launch and connect to an existing instance
- Set `BBD_DEBUG=1` to run headed (visible browser window)
- Integration tests are tagged `@moduletag :integration`

Run example project tests from `packages/bibbidi/examples/op_workflow/`:

- `mix test` — Op builder and Runner tests

## Adding a New Protocol Module

1. Create `lib/bibbidi/commands/<module>.ex` with command builder functions
2. Each function calls `Bibbidi.Connection.send_command/3` with the BiDi method name
3. Add unit tests in `test/bibbidi/commands/<module>_test.exs` using `Bibbidi.MockTransport`
4. Add integration tests in `test/integration/<module>_test.exs` tagged `:integration`
5. Reference the CDDL spec in `priv/cddl/remote.cddl` (what client sends) and `priv/cddl/local.cddl` (what client receives)

## CDDL Spec

Run `mix bibbidi.download_spec` to download/update the CDDL files from the W3C spec.
The `remote.cddl` defines message formats the client sends; `local.cddl` defines what the client receives.

### Debugging the CDDL parser and code generator

Use `mix bibbidi.cddl.inspect` to introspect parsed CDDL rules **instead of** writing ad-hoc `mix run -e` scripts:

```
# List all parsed rule names
mix bibbidi.cddl.inspect

# Show the parsed AST for a specific rule
mix bibbidi.cddl.inspect session.UnsubscribeParameters

# Search rules by substring
mix bibbidi.cddl.inspect --search unsubscribe

# Show what fields the generator resolves for a params type
mix bibbidi.cddl.inspect --fields session.UnsubscribeParameters

# Show all commands the generator extracts for a BiDi module
mix bibbidi.cddl.inspect --commands session

# Limit to a specific spec file
mix bibbidi.cddl.inspect --file remote
```

---

<!-- usage-rules-start -->
<!-- usage_rules-start -->
## usage_rules usage
_A config-driven dev tool for Elixir projects to manage AGENTS.md files and agent skills from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- usage-rules-end -->
