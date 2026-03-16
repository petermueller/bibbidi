# Bibbidi Architecture Plan v3 — Protocols, Telemetry, and Ecosystem

## Summary

The core architectural insight: **bibbidi should not be a workflow engine**. It should be a building block library that is trivially wrappable by any orchestration tool.

bibbidi provides: `Encodable` protocol, command structs, `Connection.execute/2`, and telemetry events. That's the integration surface.

Workflow composition (`Op`, `Runner`) becomes example code and an Igniter generator — owned by the consumer, not maintained as library code.

Integration with ecosystem workflow libraries (`Runic`, `Reactor`, etc.) lives in separate packages within a monorepo.

### Current State of Bibbidi

bibbidi v0.1.0 (https://hex.pm/packages/bibbidi, https://github.com/petermueller/bibbidi) currently has:

**Original (pre-plan) modules:**
- `Bibbidi.Connection` — GenServer owning the WebSocket. Correlates command IDs to callers, dispatches events to subscribers.
- `Bibbidi.Protocol` — Pure JSON encode/decode module (NOT an Elixir Protocol). No process state.
- `Bibbidi.Transport` — Behaviour for swappable WebSocket transports.
- `Bibbidi.Transport.MintWS` — Default transport using mint_web_socket.
- `Bibbidi.Commands.BrowsingContext` — navigate, getTree, create, close, captureScreenshot, print, reload, setViewport, handleUserPrompt, activate, traverseHistory, locateNodes
- `Bibbidi.Commands.Script` — evaluate, callFunction, getRealms, disown, addPreloadScript, removePreloadScript
- `Bibbidi.Session` — Higher-level session lifecycle (new, end_session, status, subscribe, unsubscribe)

**Added by Plan v1 (Phases 1-3, already implemented):**
- `Bibbidi.Encodable` protocol — `method/1` and `params/1`
- Command structs for all BiDi commands, each implementing `Encodable`
- `Bibbidi.Expandable` protocol — returns bare structs, lists, or `{expandable, handler}` tuples
- `Bibbidi.Operation` struct — execution record with steps
- `Bibbidi.Operation.Runner` — recursive interpreter over Expandable
- `Bibbidi.Operation.Reducer` protocol — result interpretation
- `Connection.execute/2` — accepts Encodable structs (without telemetry)

**NOT implemented from Plan v1:**
- Phase 4 (Playwright trace writer) — intentionally skipped

**NOT implemented from Plan v2:**
- No `Op` builder, no tagged tuple algebra, no named steps, no `branch`

## Repo Structure

```
bibbidi/                              # monorepo root
├── packages/
│   ├── bibbidi/                      # the core hex package (existing, relocated)
│   │   ├── lib/
│   │   │   └── bibbidi/
│   │   │       ├── encodable.ex
│   │   │       ├── connection.ex
│   │   │       ├── protocol.ex       # existing, backwards compat
│   │   │       ├── session.ex
│   │   │       ├── transport.ex
│   │   │       ├── transport/
│   │   │       │   └── mint_ws.ex
│   │   │       └── commands/
│   │   │           ├── browsing_context.ex
│   │   │           ├── browsing_context/
│   │   │           │   ├── navigate.ex
│   │   │           │   ├── get_tree.ex
│   │   │           │   └── ... (all command structs)
│   │   │           ├── script.ex
│   │   │           ├── script/
│   │   │           │   ├── evaluate.ex
│   │   │           │   └── ...
│   │   │           ├── input/
│   │   │           │   └── perform_actions.ex
│   │   │           └── session/
│   │   │               └── ...
│   │   ├── examples/
│   │   │   ├── simple_workflow.exs        # standalone runnable example
│   │   │   ├── google_search.exs          # the full google example
│   │   │   └── op_workflow/               # the Op pattern as a self-contained example project
│   │   │       ├── lib/
│   │   │       │   ├── op.ex
│   │   │       │   ├── operation.ex
│   │   │       │   ├── runner.ex
│   │   │       │   └── example_workflows/
│   │   │       │       ├── click_element.ex
│   │   │       │       ├── wait_for_selector.ex
│   │   │       │       └── search_google.ex
│   │   │       ├── test/
│   │   │       │   ├── op_test.exs
│   │   │       │   ├── runner_test.exs
│   │   │       │   └── example_workflows_test.exs
│   │   │       └── mix.exs               # depends on :bibbidi
│   │   ├── test/
│   │   ├── mix.exs
│   │   └── README.md
│   │
│   └── bibbidi_runic/                # Runic integration package
│       ├── lib/
│       │   └── bibbidi_runic/
│       │       ├── step.ex           # Runic.Component impl for BiDi commands
│       │       ├── invokable.ex      # Invokable protocol impl
│       │       └── workflow.ex       # helpers for building Runic workflows from BiDi commands
│       ├── test/
│       │   ├── step_test.exs
│       │   └── workflow_test.exs
│       ├── mix.exs                   # depends on :bibbidi, :runic
│       └── README.md
│
├── mix.exs                           # umbrella or workspace root (if needed)
└── README.md                         # monorepo overview
```

### Note on Monorepo Structure

There are two options for the monorepo:

**Option A — Umbrella project**: Use `mix new bibbidi --umbrella` with apps in `packages/`. Standard Elixir umbrella with shared config and dependency resolution.

**Option B — Flat monorepo with independent packages**: Each package in `packages/` has its own `mix.exs` and is independently publishable. No umbrella `mix.exs`. CI runs tests per-package. This is how some Ash ecosystem packages work.

Option B is recommended — it avoids umbrella coupling and each package's `mix.exs` declares its own deps. A root `Makefile` or `Justfile` can orchestrate cross-package tasks.

---

## What Ships in `bibbidi` (the hex package)

### 1. `Bibbidi.Encodable` Protocol

Unchanged from v1/v2. Struct → BiDi wire format.

```elixir
defprotocol Bibbidi.Encodable do
  @moduledoc """
  Encode a command struct into the WebDriver BiDi wire format.

  Every BiDi command struct implements this protocol. Consumers and
  integration libraries use it to introspect commands before sending.
  """

  @doc "The BiDi method string (e.g., \"browsingContext.navigate\")"
  @spec method(t()) :: String.t()
  def method(command)

  @doc "Encode into the BiDi params map"
  @spec params(t()) :: map()
  def params(command)
end
```

### 2. Command Structs

One struct per BiDi command, implementing `Encodable`. Unchanged from v1.

```elixir
defmodule Bibbidi.Commands.BrowsingContext.Navigate do
  @moduledoc "BiDi browsingContext.navigate command"
  @enforce_keys [:context, :url]
  defstruct [:context, :url, :wait]

  defimpl Bibbidi.Encodable do
    def method(_), do: "browsingContext.navigate"

    def params(%{context: ctx, url: url} = cmd) do
      base = %{"context" => ctx, "url" => url}
      if cmd.wait, do: Map.put(base, "wait", cmd.wait), else: base
    end
  end
end
```

The existing function API continues to work as a convenience wrapper:

```elixir
defmodule Bibbidi.Commands.BrowsingContext do
  def navigate(conn, context, url, opts \\ []) do
    command = %Bibbidi.Commands.BrowsingContext.Navigate{
      context: context,
      url: url,
      wait: Keyword.get(opts, :wait)
    }
    Bibbidi.Connection.execute(conn, command, opts)
  end
end
```

### 3. `Bibbidi.Connection.execute/2,3`

New function on `Connection` that accepts `Encodable` structs and wraps the send/receive cycle with telemetry.

```elixir
defmodule Bibbidi.Connection do
  # ... existing code ...

  @doc """
  Execute an Encodable command struct against this connection.

  Encodes the command via the Encodable protocol, sends it over the
  WebSocket, waits for the correlated response, and returns it.

  Emits telemetry events:
  - `[:bibbidi, :command, :start]`
  - `[:bibbidi, :command, :stop]`
  - `[:bibbidi, :command, :exception]`

  ## Options

  - `:timeout` — response timeout in milliseconds (default: 5_000)

  ## Examples

      {:ok, result} = Bibbidi.Connection.execute(conn, %BrowsingContext.Navigate{
        context: ctx, url: "https://example.com", wait: "complete"
      })

  """
  @spec execute(GenServer.server(), Bibbidi.Encodable.t(), keyword()) ::
    {:ok, term()} | {:error, term()}
  def execute(conn, %{__struct__: _} = command, opts \\ []) do
    method = Bibbidi.Encodable.method(command)
    params = Bibbidi.Encodable.params(command)
    timeout = Keyword.get(opts, :timeout, 5_000)

    telemetry_metadata = %{
      command: command,
      method: method,
      params: params,
      connection: conn
    }

    start_time = System.monotonic_time()

    :telemetry.execute(
      [:bibbidi, :command, :start],
      %{system_time: System.system_time()},
      telemetry_metadata
    )

    try do
      case send_command(conn, method, params, timeout) do
        {:ok, response} ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:bibbidi, :command, :stop],
            %{duration: duration},
            Map.merge(telemetry_metadata, %{result: {:ok, response}})
          )

          {:ok, response}

        {:error, reason} ->
          duration = System.monotonic_time() - start_time

          :telemetry.execute(
            [:bibbidi, :command, :stop],
            %{duration: duration},
            Map.merge(telemetry_metadata, %{result: {:error, reason}})
          )

          {:error, reason}
      end
    rescue
      e ->
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          [:bibbidi, :command, :exception],
          %{duration: duration},
          Map.merge(telemetry_metadata, %{kind: :exception, reason: e, stacktrace: __STACKTRACE__})
        )

        reraise e, __STACKTRACE__
    end
  end
end
```

Alternatively, use `:telemetry.span/3` which handles the start/stop/exception pattern:

```elixir
def execute(conn, %{__struct__: _} = command, opts \\ []) do
  method = Bibbidi.Encodable.method(command)
  params = Bibbidi.Encodable.params(command)
  timeout = Keyword.get(opts, :timeout, 5_000)

  metadata = %{command: command, method: method, params: params, connection: conn}

  :telemetry.span([:bibbidi, :command], metadata, fn ->
    result = send_command(conn, method, params, timeout)
    {result, Map.put(metadata, :result, result)}
  end)
end
```

`:telemetry.span/3` is the cleaner form. It emits `:start`, `:stop`, and `:exception` events automatically. Use whichever form is clearer in the actual codebase — the telemetry event names and metadata shapes are the public contract, not the internal implementation.

### 4. Telemetry Events

These are the public contract for observability. Document them in the moduledoc and in a dedicated `Bibbidi.Telemetry` module (documentation-only, no code).

```elixir
defmodule Bibbidi.Telemetry do
  @moduledoc """
  Telemetry events emitted by Bibbidi.

  ## Command Lifecycle

  Emitted by `Bibbidi.Connection.execute/3`:

  ### `[:bibbidi, :command, :start]`

  Emitted when a command is about to be sent.

  **Measurements:** `%{system_time: integer()}`
  **Metadata:**
  - `:command` — the `Encodable` struct being sent
  - `:method` — the BiDi method string (e.g., `"browsingContext.navigate"`)
  - `:params` — the encoded params map
  - `:connection` — the connection pid or name

  ### `[:bibbidi, :command, :stop]`

  Emitted when a response is received (success or error).

  **Measurements:** `%{duration: integer()}` (native time units)
  **Metadata:** same as `:start`, plus:
  - `:result` — `{:ok, response}` or `{:error, reason}`

  ### `[:bibbidi, :command, :exception]`

  Emitted when the send/receive raises an exception.

  **Measurements:** `%{duration: integer()}`
  **Metadata:** same as `:start`, plus:
  - `:kind` — `:exception`
  - `:reason` — the exception
  - `:stacktrace` — the stacktrace

  ## BiDi Events

  Emitted by `Bibbidi.Connection` when a BiDi event is received
  from the browser (navigation events, console messages, network
  activity, etc.):

  ### `[:bibbidi, :event, :received]`

  **Measurements:** `%{system_time: integer()}`
  **Metadata:**
  - `:event` — the BiDi event name (e.g., `"browsingContext.load"`)
  - `:params` — the event params map from the browser
  - `:connection` — the connection pid or name
  """
end
```

### 5. Event Emission for BiDi Events

Update `Connection` to emit telemetry when BiDi events arrive (in addition to the existing process-message dispatch):

```elixir
# In Connection's event handling code, after dispatching to subscribers:
:telemetry.execute(
  [:bibbidi, :event, :received],
  %{system_time: System.system_time()},
  %{event: event_name, params: event_params, connection: self()}
)
```

This means a telemetry handler can observe all BiDi events without needing to subscribe to the connection process directly — useful for trace writers and loggers that are decoupled from the connection lifecycle.

---

## What Ships as Examples

### `examples/op_workflow/` — The Op Pattern

This is a self-contained Mix project in `examples/` that demonstrates the Op builder pattern from Plan v2. It depends on `:bibbidi` and serves as both documentation and a testable example.

It contains:

- **`Op`** — the Multi-style pipeline builder with `Op.new/0`, `Op.send/3`, `Op.run/3`, `Op.branch/3`
- **`Operation`** — the execution record struct with `steps`, `results`, `events`
- **`Runner`** — the sequential interpreter that walks an `Op` and calls `Connection.execute/2`
- **Example workflows** — `ClickElement`, `WaitForSelector`, `SearchGoogleAndClickFirstOrganicLink`
- **Tests** — unit tests for Op builder, runner, and example workflows against a mock

The Runner in the example uses `Connection.execute/2` directly:

```elixir
defmodule Examples.OpWorkflow.Runner do
  @moduledoc """
  Sequential runner for Op pipelines. Calls Bibbidi.Connection.execute/2
  for each leaf command and accumulates named results.

  This is example code — not a maintained library. Copy it into your
  project and modify as needed. If you're using Runic, Reactor, or
  another workflow engine, use their orchestration instead and call
  Connection.execute/2 from their step implementations.
  """

  alias Examples.OpWorkflow.{Op, Operation}

  def execute(conn, %Op{} = op, opts \\ []) do
    operation = %Operation{
      id: generate_id(),
      started_at: System.monotonic_time(:millisecond)
    }

    run_pipeline(conn, op.steps, %{}, operation, opts)
  end

  defp run_pipeline(_conn, [], results, operation, _opts) do
    {:ok, results, finalize(operation, results)}
  end

  defp run_pipeline(conn, [{name, {:send, cmd}} | rest], results, operation, opts) do
    case Bibbidi.Connection.execute(conn, cmd, opts) do
      {:ok, response} ->
        step = %{command: cmd, result: {:ok, response}, at: System.monotonic_time(:millisecond)}
        operation = %{operation | steps: operation.steps ++ [step]}
        run_pipeline(conn, rest, Map.put(results, name, {:ok, response}), operation, opts)

      {:error, reason} ->
        step = %{command: cmd, result: {:error, reason}, at: System.monotonic_time(:millisecond)}
        operation = %{operation | steps: operation.steps ++ [step]}
        {:error, {name, reason}, finalize(operation, results, {:failed, name, reason})}
    end
  end

  defp run_pipeline(conn, [{name, {:send_fn, fun}} | rest], results, operation, opts) do
    case fun.(results) do
      {:send, cmd} ->
        run_pipeline(conn, [{name, {:send, cmd}} | rest], results, operation, opts)

      {:ok, value} ->
        run_pipeline(conn, rest, Map.put(results, name, {:ok, value}), operation, opts)

      {:error, reason} ->
        {:error, {name, reason}, finalize(operation, results, {:failed, name, reason})}
    end
  end

  defp run_pipeline(conn, [{name, {:run, expandable_fn}} | rest], results, operation, opts) do
    case expandable_fn.(conn, results, opts) do
      {:ok, result} ->
        run_pipeline(conn, rest, Map.put(results, name, {:ok, result}), operation, opts)

      {:error, reason} ->
        {:error, {name, reason}, finalize(operation, results, {:failed, name, reason})}
    end
  end

  defp run_pipeline(conn, [{name, {:branch_fn, fun}} | rest], results, operation, opts) do
    case fun.(results) do
      {:send, cmd} ->
        case Bibbidi.Connection.execute(conn, cmd, opts) do
          {:ok, response} ->
            run_pipeline(conn, rest, Map.put(results, name, {:ok, response}), operation, opts)
          {:error, reason} ->
            {:error, {name, reason}, finalize(operation, results, {:failed, name, reason})}
        end

      {:ok, value} ->
        run_pipeline(conn, rest, Map.put(results, name, {:ok, value}), operation, opts)

      {:error, reason} ->
        {:error, {name, reason}, finalize(operation, results, {:failed, name, reason})}
    end
  end

  # ... helpers ...
end
```

### Igniter Generator

```bash
mix bibbidi.gen.workflow
```

Generates into the consumer's project:

- `lib/my_app/bibbidi/op.ex` — the Op builder
- `lib/my_app/bibbidi/operation.ex` — the Operation struct
- `lib/my_app/bibbidi/runner.ex` — the sequential runner
- `test/my_app/bibbidi/runner_test.exs` — basic test scaffold

The generated code is clearly marked as consumer-owned:

```elixir
defmodule MyApp.Bibbidi.Op do
  @moduledoc """
  Multi-style pipeline builder for composing BiDi commands.

  Generated by `mix bibbidi.gen.workflow`. This code is yours to modify.
  See the bibbidi examples/ directory for the reference implementation.
  """

  # ... same Op builder code as in examples/ ...
end
```

The generator is a separate concern from the core library. It lives in `lib/mix/tasks/bibbidi.gen.workflow.ex` within the bibbidi package and depends on `:igniter`.

---

## `bibbidi_runic` Package

### Purpose

Wraps bibbidi command structs as Runic workflow components so that BiDi commands can be composed using Runic's DAG-based workflow engine.

### Dependencies

```elixir
# packages/bibbidi_runic/mix.exs
defp deps do
  [
    {:bibbidi, "~> 0.2.0"},   # or path: "../bibbidi" for monorepo dev
    {:runic, "~> 0.1.0-alpha"}
  ]
end
```

### Core Module: `BibbidiRunic.Step`

A Runic `Component` and `Invokable` implementation for BiDi commands.

```elixir
defmodule BibbidiRunic.Step do
  @moduledoc """
  A Runic component that executes a BiDi command via Bibbidi.

  ## Usage

      require Runic

      # Create a step from a BiDi command struct
      step = BibbidiRunic.Step.new(
        %Bibbidi.Commands.BrowsingContext.Navigate{
          context: ctx, url: "https://example.com", wait: "complete"
        },
        conn: conn
      )

      # Use in a Runic workflow
      workflow = Runic.workflow(
        name: "navigate and screenshot",
        steps: [
          BibbidiRunic.Step.new(
            %Bibbidi.Commands.BrowsingContext.Navigate{context: ctx, url: url, wait: "complete"},
            conn: conn, name: :navigate
          ),
          BibbidiRunic.Step.new(
            %Bibbidi.Commands.BrowsingContext.CaptureScreenshot{context: ctx},
            conn: conn, name: :screenshot
          )
        ]
      )

      workflow
      |> Runic.Workflow.react_until_satisfied(nil)
      |> Runic.Workflow.raw_productions()
  """

  defstruct [:command, :conn, :name, :opts]

  def new(command, options) do
    %__MODULE__{
      command: command,
      conn: Keyword.fetch!(options, :conn),
      name: Keyword.get(options, :name, default_name(command)),
      opts: Keyword.take(options, [:timeout])
    }
  end

  defp default_name(command) do
    command
    |> Bibbidi.Encodable.method()
    |> String.replace(".", "_")
    |> String.to_atom()
  end
end
```

### Runic Protocol Implementations

```elixir
defimpl Runic.Component, for: BibbidiRunic.Step do
  def name(%{name: name}), do: name

  # Component protocol methods for adding to workflows
  # (exact API depends on Runic version — refer to Runic.Component docs)
end

defimpl Runic.Workflow.Invokable, for: BibbidiRunic.Step do
  def prepare(%{command: cmd, conn: conn, opts: opts}) do
    %Runic.Runnable{
      work: fn _input ->
        Bibbidi.Connection.execute(conn, cmd, opts)
      end
    }
  end

  def execute(_node, %Runic.Runnable{work: work} = runnable) do
    result = work.(nil)
    %{runnable | result: result}
  end

  def apply(workflow, _node, %{result: result}) do
    case result do
      {:ok, response} ->
        Runic.Workflow.assert(workflow, response)

      {:error, reason} ->
        # How to handle errors depends on the workflow design
        # Could assert an error fact, halt, or trigger a different branch
        Runic.Workflow.assert(workflow, {:error, reason})
    end
  end
end
```

### Dynamic Step Builder

For cases where the BiDi command depends on a previous step's result (like clicking an element after locating it):

```elixir
defmodule BibbidiRunic.DynamicStep do
  @moduledoc """
  A Runic step that builds its BiDi command at runtime from
  the input fact flowing through the workflow.

  ## Usage

      BibbidiRunic.DynamicStep.new(
        fn %{"nodes" => [node | _]} ->
          %Script.CallFunction{
            function_declaration: "el => el.click()",
            target: %{context: ctx},
            arguments: [node]
          }
        end,
        conn: conn, name: :click
      )
  """

  defstruct [:builder_fn, :conn, :name, :opts]

  def new(builder_fn, options) when is_function(builder_fn, 1) do
    %__MODULE__{
      builder_fn: builder_fn,
      conn: Keyword.fetch!(options, :conn),
      name: Keyword.fetch!(options, :name),
      opts: Keyword.take(options, [:timeout])
    }
  end
end

defimpl Runic.Workflow.Invokable, for: BibbidiRunic.DynamicStep do
  def prepare(%{builder_fn: builder_fn, conn: conn, opts: opts}) do
    %Runic.Runnable{
      work: fn input ->
        command = builder_fn.(input)
        Bibbidi.Connection.execute(conn, command, opts)
      end
    }
  end

  def execute(_node, %Runic.Runnable{work: work} = runnable) do
    # Input comes from the parent fact in the workflow
    result = work.(runnable.input)
    %{runnable | result: result}
  end

  def apply(workflow, _node, %{result: result}) do
    case result do
      {:ok, response} -> Runic.Workflow.assert(workflow, response)
      {:error, reason} -> Runic.Workflow.assert(workflow, {:error, reason})
    end
  end
end
```

### Tests

Tests should verify:

1. A `BibbidiRunic.Step` can be added to a Runic workflow
2. The workflow executes commands via `Connection.execute/2` (using a mock connection)
3. Results flow through the workflow as Runic facts
4. Multi-step workflows with data dependencies work (locate → click)
5. Error handling propagates correctly

---

## Igniter Generator Details

### `mix bibbidi.gen.workflow`

```elixir
defmodule Mix.Tasks.Bibbidi.Gen.Workflow do
  @shortdoc "Generate a workflow runner for BiDi command orchestration"

  @moduledoc """
  Generates a Multi-style workflow builder and sequential runner
  into your project.

      mix bibbidi.gen.workflow

  This generates:

  - `lib/<app>/bibbidi/op.ex` — pipeline builder
  - `lib/<app>/bibbidi/operation.ex` — execution record struct
  - `lib/<app>/bibbidi/runner.ex` — sequential runner
  - `test/<app>/bibbidi/runner_test.exs` — test scaffold

  The generated code calls `Bibbidi.Connection.execute/2` for
  leaf commands and accumulates results in a named map.

  This code is yours to own and modify. If you're using a workflow
  engine like Runic or Reactor, consider using `bibbidi_runic` or
  writing a thin adapter instead.
  """

  use Igniter.Mix.Task

  def igniter(igniter) do
    app_name = Igniter.Project.Application.app_name(igniter)
    module_prefix = Igniter.Project.Module.module_name(igniter)

    igniter
    |> generate_op(module_prefix)
    |> generate_operation(module_prefix)
    |> generate_runner(module_prefix)
    |> generate_runner_test(app_name, module_prefix)
  end

  # Each function creates a file from a template with the consumer's module prefix
  # ...
end
```

---

## Implementation Phases

### What Already Exists

v1 Phases 1-3 are implemented. bibbidi currently has:

- **`Bibbidi.Encodable` protocol** — `method/1` and `params/1`, defined and implemented
- **Command structs** — one per BiDi command, each implementing `Encodable`
- **`Connection.execute/2`** — sends an `Encodable` struct over the wire (may not have telemetry yet)
- **`Bibbidi.Expandable` protocol** — returns bare structs, lists, or `{expandable, handler}` tuples
- **`Bibbidi.Operation` struct** — execution record
- **`Bibbidi.Operation.Runner`** — recursive interpreter over `Expandable` return types
- **`Bibbidi.Operation.Reducer` protocol** — result interpretation
- **`Expandable` impls on command structs** — identity impls returning self

The function-based API (`BrowsingContext.navigate/4` etc.) continues to work.

### Phase 1: Extract Workflow Code from Core

`Expandable`, `Runner`, `Reducer`, and `Operation` are workflow engine concerns and should be removed from the core library. They will be refactored into example code.

#### 1.1 Identify files to extract

Remove from `lib/bibbidi/`:
- `Bibbidi.Expandable` protocol definition
- `Bibbidi.Operation` struct
- `Bibbidi.Operation.Runner`
- `Bibbidi.Operation.Reducer` protocol definition
- All `Expandable` impls on command structs (remove the `defimpl Bibbidi.Expandable` blocks from each command struct file)

Also remove associated test files from `test/`.

#### 1.2 Remove `Expandable` impls from command structs

Each command struct currently has an `Expandable` impl. Remove these. The command structs should only implement `Encodable`.

If `Expandable` uses `@fallback_to_any` or `@derive`, remove that machinery from command struct modules.

#### 1.3 Delete workflow modules from `lib/`

Delete:
- `lib/bibbidi/expandable.ex`
- `lib/bibbidi/operation.ex`
- `lib/bibbidi/operation/runner.ex`
- `lib/bibbidi/operation/reducer.ex`
- Any corresponding test files

#### 1.4 Verify core still compiles and tests pass

After extraction:
- All command structs still implement `Encodable` only
- `Connection.execute/2` still works
- The function-based API still works
- No remaining references to `Expandable`, `Runner`, `Reducer`, or `Operation` in `lib/bibbidi/`

#### 1.5 Preserve extracted code for Phase 3

Save the removed modules somewhere (a git stash, a temp branch, or copy them to a scratch directory). They'll be the starting point for the example code in Phase 3, refactored to use the `Op` builder pattern.

### Phase 2: Telemetry

Add telemetry instrumentation to `Connection.execute/2` and BiDi event dispatch.

1. Add `:telemetry` as a dependency in `mix.exs` (if not already present)
2. Wrap `Connection.execute/2` with `:telemetry.span/3`:
   ```elixir
   def execute(conn, %{__struct__: _} = command, opts \\ []) do
     method = Bibbidi.Encodable.method(command)
     params = Bibbidi.Encodable.params(command)
     timeout = Keyword.get(opts, :timeout, 5_000)

     metadata = %{command: command, method: method, params: params, connection: conn}

     :telemetry.span([:bibbidi, :command], metadata, fn ->
       result = send_command(conn, method, params, timeout)
       {result, Map.put(metadata, :result, result)}
     end)
   end
   ```
3. Add telemetry emission to the existing BiDi event dispatch path in `Connection`:
   ```elixir
   :telemetry.execute(
     [:bibbidi, :event, :received],
     %{system_time: System.system_time()},
     %{event: event_name, params: event_params, connection: self()}
   )
   ```
4. Create `lib/bibbidi/telemetry.ex` as a documentation-only module with `@moduledoc` describing all emitted events, their measurements, and metadata shapes (as specified in the "Telemetry Events" section above)
5. Ensure all existing convenience functions (`BrowsingContext.navigate/4` etc.) route through `execute/2`
6. Write tests:
   - Attach a telemetry handler in test setup, send a command, verify `[:bibbidi, :command, :start]` fires with correct metadata
   - Verify `[:bibbidi, :command, :stop]` fires with `%{duration: _, result: {:ok, _}}` on success
   - Verify `[:bibbidi, :command, :stop]` fires with `%{result: {:error, _}}` on command failure
   - Verify `[:bibbidi, :event, :received]` fires when a BiDi event arrives

### Phase 3: Examples

Create `examples/op_workflow/` as a standalone Mix project demonstrating the Op builder pattern. This uses the v3 design: tagged tuples (`{:send, cmd}`, `{:ok, val}`, `{:error, reason}`), named steps with accumulated results, and `branch` for decision points.

Start from the extracted v1 Runner/Operation code, but refactor significantly:
- Replace `Expandable` protocol dispatch with the `Op` struct and tagged tuples
- Replace positional "previous result" with named results map
- Replace nested `{expandable, handler}` tuples with `Op.branch/3`

#### 3.1 Create the example project

```bash
mix new examples/op_workflow
```

Add `{:bibbidi, path: "../../"}` (or `{:bibbidi, "~> 0.2.0"}`) as a dep.

#### 3.2 Implement core modules in `examples/op_workflow/lib/`

**`Op`** — Multi-style pipeline builder:
- `Op.new/0`
- `Op.send/3` — `(op, name, command)` or `(op, name, fn results -> {:send, cmd} | {:ok, val} | {:error, reason} end)`
- `Op.run/3` — `(op, name, fun)` where fun is `fn conn, results, opts -> {:ok, _} | {:error, _} end`
- `Op.branch/3` — `(op, name, fn results -> {:send, cmd} | {:ok, val} | {:error, reason} end)`
- Step name uniqueness validation
- Internal step tags: `{:send, cmd}`, `{:send_fn, fun}`, `{:run, fun}`, `{:branch_fn, fun}`

**`Operation`** — execution record:
- `id`, `started_at`, `ended_at`, `status`, `error`
- `steps` — ordered list of `%{command: _, result: _, at: _}` for every wire command
- `results` — `%{atom => {:ok, _} | {:error, _}}` named pipeline results

**`Runner`** — sequential interpreter:
- `Runner.execute(conn, %Op{}, opts)` → `{:ok, results_map, %Operation{}} | {:error, {step_name, reason}, %Operation{}}`
- Calls `Bibbidi.Connection.execute/2` for each `{:send, cmd}`
- Accumulates named results map, passes to step functions
- Step failure halts pipeline, returns partial results

#### 3.3 Implement example workflows in `examples/op_workflow/lib/example_workflows/`

**`ClickElement`** — 3-step Op: locate nodes → get bounding rect → pointer click

**`WaitForSelector`** — a plain function (not a struct/protocol) that polls `Connection.execute/2` with `LocateNodes` in a retry loop. Called via `Op.run/3`.

**`SearchGoogleAndClickFirstOrganicLink`** — full example using `Op.send`, `Op.run`, and `Op.branch`. As specified in the "Full Example" section of this plan.

#### 3.4 Write tests

- Op builder: step ordering, name uniqueness, duplicate name rejection
- Runner: static sends, dynamic sends, run steps, branch steps, error halting, partial results in operation
- Example workflows: against a mock connection returning canned BiDi responses
- Verify `operation.steps` records every wire command in order
- Verify `operation.results` contains all named step outcomes

#### 3.5 Documentation

Add a guide page to bibbidi's hexdocs: "Building Workflows with Bibbidi" showing:
- Plain `with` chain approach (simplest, no dependencies)
- The Op pattern (pointing to `examples/op_workflow/` and the Igniter generator)
- Pointers to `bibbidi_runic` for Runic users
- A note about Reactor for Ash ecosystem users

### Phase 4: Igniter Generator

1. Add `:igniter` as an optional dependency in bibbidi's `mix.exs`
2. Create `lib/mix/tasks/bibbidi.gen.workflow.ex`
3. The generator copies Op/Operation/Runner from templates (derived from `examples/op_workflow/`) into the consumer's project:
   - `lib/<app>/bibbidi/op.ex`
   - `lib/<app>/bibbidi/operation.ex`
   - `lib/<app>/bibbidi/runner.ex`
   - `test/<app>/bibbidi/runner_test.exs`
4. Each generated file includes a moduledoc: "Generated by `mix bibbidi.gen.workflow`. This code is yours to own and modify."
5. Test the generator produces compilable code

### Phase 5: Monorepo Migration

Move to `packages/` structure before creating `bibbidi_runic`.

1. Create `packages/` directory at the repo root
2. Move existing bibbidi code into `packages/bibbidi/` (use `git mv` to preserve history)
3. Move `examples/` into `packages/bibbidi/examples/`
4. Update CI to run from `packages/bibbidi/`
5. Verify all tests pass from the new location
6. Add a root `Justfile`:
   ```just
   test-all:
     cd packages/bibbidi && mix test
     cd packages/bibbidi/examples/op_workflow && mix test

   test-bibbidi:
     cd packages/bibbidi && mix test

   format-all:
     cd packages/bibbidi && mix format
   ```
7. Update root `README.md` to describe the monorepo layout

### Phase 6: `bibbidi_runic` Package

1. Create `packages/bibbidi_runic/` with its own `mix.exs`:
   ```elixir
   defp deps do
     [
       {:bibbidi, path: "../bibbidi"},  # dev
       # {:bibbidi, "~> 0.2.0"},       # publish
       {:runic, "~> 0.1.0-alpha"}
     ]
   end
   ```
2. Implement `BibbidiRunic.Step` — wraps an `Encodable` command struct as a Runic component
3. Implement `BibbidiRunic.DynamicStep` — builder function receives workflow input, constructs command at runtime
4. Implement Runic protocol impls (`Component`, `Invokable`) for both
5. Write tests against a mock connection + real Runic workflow execution
6. Write a README with usage examples
7. Update root `Justfile`:
   ```just
   test-all:
     cd packages/bibbidi && mix test
     cd packages/bibbidi/examples/op_workflow && mix test
     cd packages/bibbidi_runic && mix test

   test-bibbidi-runic:
     cd packages/bibbidi_runic && mix test
   ```
8. Update CI to test `bibbidi_runic` after `bibbidi` passes

## Example: Google Search With Each Approach

### Approach 1: Plain `with` (No Workflow Library)

```elixir
defmodule MyApp.GoogleSearch do
  alias Bibbidi.Connection
  alias Bibbidi.Commands.{BrowsingContext, Script}

  def search_and_click_first_organic(conn, context, query) do
    with {:ok, _} <- Connection.execute(conn, %BrowsingContext.Navigate{
           context: context, url: "https://www.google.com", wait: "complete"
         }),
         {:ok, _} <- Connection.execute(conn, %Script.Evaluate{
           expression: dismiss_cookies_js(),
           target: %{context: context}
         }),
         {:ok, _} <- Connection.execute(conn, %Script.Evaluate{
           expression: type_and_submit_js(query),
           target: %{context: context}
         }),
         {:ok, _} <- wait_for_selector(conn, context, "#search a h3"),
         {:ok, organic} <- Connection.execute(conn, %Script.Evaluate{
           expression: find_organic_link_js(),
           target: %{context: context}
         }),
         href <- get_in(organic, ["result", "value", "href"]),
         true <- is_binary(href) || {:error, :no_organic_results},
         {:ok, nav} <- Connection.execute(conn, %BrowsingContext.Navigate{
           context: context, url: href, wait: "complete"
         }) do
      {:ok, %{url: nav["url"], link_text: get_in(organic, ["result", "value", "text"])}}
    end
  end

  defp wait_for_selector(conn, context, selector, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10_000)
    interval = Keyword.get(opts, :interval, 250)
    max_attempts = div(timeout, interval)
    do_wait(conn, context, selector, 0, max_attempts, interval)
  end

  defp do_wait(_conn, _context, selector, attempts, max, _interval) when attempts >= max do
    {:error, {:timeout_waiting_for_selector, selector}}
  end

  defp do_wait(conn, context, selector, attempts, max, interval) do
    if attempts > 0, do: Process.sleep(interval)

    case Connection.execute(conn, %BrowsingContext.LocateNodes{
      context: context, locator: %{type: "css", value: selector}
    }) do
      {:ok, %{"nodes" => [_ | _]} = result} -> {:ok, result}
      {:ok, %{"nodes" => []}} -> do_wait(conn, context, selector, attempts + 1, max, interval)
      {:error, reason} -> {:error, reason}
    end
  end

  # JS helpers
  defp dismiss_cookies_js, do: "(() => { const b = document.querySelector('[id=\"L2AGLb\"]'); if (b) b.click(); return true; })()"
  defp type_and_submit_js(query), do: ~s[(() => { const i = document.querySelector('textarea[name="q"], input[name="q"]'); i.value = #{Jason.encode!(query)}; i.dispatchEvent(new Event('input', {bubbles:true})); i.form.submit(); return true; })()]
  defp find_organic_link_js, do: ~S[(() => { for (const a of document.querySelectorAll('#search a')) { if (a.closest('[data-text-ad]')) continue; if (!a.querySelector('h3')) continue; const h = a.href; if (!h || h.includes('google.com/search')) continue; return {href: h, text: a.querySelector('h3')?.textContent}; } return null; })()]
end
```

### Approach 2: Generated Op Workflow

```elixir
defmodule MyApp.GoogleSearch do
  alias MyApp.Bibbidi.{Op, Runner}
  alias Bibbidi.Commands.{BrowsingContext, Script}

  def search_and_click_first_organic(conn, context, query) do
    op =
      Op.new()
      |> Op.send(:navigate, %BrowsingContext.Navigate{
           context: context, url: "https://www.google.com", wait: "complete"
         })
      |> Op.send(:cookies, %Script.Evaluate{
           expression: dismiss_cookies_js(), target: %{context: context}
         })
      |> Op.send(:submit, %Script.Evaluate{
           expression: type_and_submit_js(query), target: %{context: context}
         })
      |> Op.run(:wait, fn conn, _results, opts ->
           wait_for_selector(conn, context, "#search a h3", opts)
         end)
      |> Op.send(:find_organic, %Script.Evaluate{
           expression: find_organic_link_js(), target: %{context: context}
         })
      |> Op.branch(:result, fn
           %{find_organic: {:ok, %{"result" => %{"value" => %{"href" => href}}}}} ->
             {:send, %BrowsingContext.Navigate{context: context, url: href, wait: "complete"}}
           %{find_organic: {:ok, %{"result" => %{"value" => nil}}}} ->
             {:error, :no_organic_results}
         end)

    Runner.execute(conn, op)
  end

  # ... same helper functions ...
end
```

### Approach 3: Runic Workflow (via `bibbidi_runic`)

```elixir
defmodule MyApp.GoogleSearch do
  alias BibbidiRunic.{Step, DynamicStep}
  alias Bibbidi.Commands.{BrowsingContext, Script}
  alias Runic.Workflow

  def build_workflow(conn, context, query) do
    Runic.workflow(
      name: "google_search_and_click",
      steps: [
        {Step.new(%BrowsingContext.Navigate{context: context, url: "https://www.google.com", wait: "complete"},
           conn: conn, name: :navigate),
         [
           {Step.new(%Script.Evaluate{expression: dismiss_cookies_js(), target: %{context: context}},
              conn: conn, name: :cookies),
            [
              {Step.new(%Script.Evaluate{expression: type_and_submit_js(query), target: %{context: context}},
                 conn: conn, name: :submit),
               [
                 {Step.new(%Script.Evaluate{expression: find_organic_link_js(), target: %{context: context}},
                    conn: conn, name: :find_organic),
                  [
                    DynamicStep.new(
                      fn %{"result" => %{"value" => %{"href" => href}}} ->
                        %BrowsingContext.Navigate{context: context, url: href, wait: "complete"}
                      end,
                      conn: conn, name: :click_result
                    )
                  ]}
               ]}
            ]}
         ]}
      ]
    )
  end

  def run(conn, context, query) do
    build_workflow(conn, context, query)
    |> Workflow.react_until_satisfied(nil)
    |> Workflow.raw_productions()
  end
end
```

Note: The Runic example is verbose because Runic's tree-shaped step composition is designed for DAGs with fan-out, not linear pipelines. A consumer using Runic would likely build helper functions to linearize this. That's fine — the integration layer (`bibbidi_runic`) provides the primitives, the consumer builds the ergonomics they want.

---

## Design Notes

### Why Not Ship Op/Runner in bibbidi?

1. **It's a workflow engine.** bibbidi's README says "building-block library." Shipping a workflow runner contradicts that identity.
2. **Consumers already have workflow tools.** Anyone building serious RPA or testing has chosen their orchestration layer. Forcing them to adapt to bibbidi's runner creates friction.
3. **Maintenance burden.** A workflow runner attracts feature requests (parallel execution, retry policies, timeouts, saga compensation) that are someone else's problem to solve.
4. **The `with` chain works.** For 80% of use cases, a plain `with` chain calling `Connection.execute/2` is all you need. The Op pattern is nice but not essential.

### Why Ship Op/Runner as Examples + Generator?

1. **Discoverable.** New users need a "how do I compose multiple commands?" answer. The example provides it.
2. **Testable.** Having tests for the example code ensures it actually works with the current bibbidi API.
3. **Copyable.** The Igniter generator puts working code in the consumer's project. They own it.
4. **Not a contract.** Since it's not published as a library, breaking changes to the Op pattern don't require a major version bump on bibbidi.

### Future: `bobbidi`

If the Op pattern stabilizes and browser-first orchestration warrants a maintained library, it could become `bobbidi` ("BEAM Orchestration of Browser ..."). This would be a separate hex package in the monorepo that depends on `bibbidi` and provides:

- `Bobbidi.Op` — the pipeline builder
- `Bobbidi.Runner` — the sequential interpreter
- `Bobbidi.Actions.*` — pre-built compound actions (click, fill, wait, etc.)
- `Bobbidi.Trace` — Playwright trace zip generation

This keeps bibbidi as the protocol/transport layer and bobbidi as the orchestration/action layer. The naming continues the Cinderella Fairy Godmother spell: bibbidi-bobbidi-boo.

### Telemetry Is The Integration Surface

The most important thing bibbidi provides for ecosystem integration is telemetry. Every workflow tool, logging system, and observability platform in Elixir speaks telemetry. By emitting well-documented events with rich metadata (including the command struct), bibbidi enables:

- **Trace writers** — attach a handler that accumulates command/response pairs and writes a Playwright trace zip
- **Metrics** — attach a handler that reports command duration to StatsD/Prometheus
- **Logging** — attach a handler that logs every command at debug level
- **Retry logic** — attach a handler that counts consecutive failures and triggers circuit-breaking
- **Correlation** — the consumer adds their own correlation ID to `Logger.metadata` before calling `execute/2`, and the telemetry handler picks it up

None of these require bibbidi to know they exist.
