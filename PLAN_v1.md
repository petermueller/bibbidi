# Bibbidi Operation Protocol Plan

## Context

Bibbidi (https://hex.pm/packages/bibbidi, https://github.com/petermueller/bibbidi) is a low-level Elixir WebDriver BiDi library. It currently has:

- `Bibbidi.Connection` — GenServer owning the WebSocket. Correlates command IDs to callers, dispatches events to subscribers.
- `Bibbidi.Protocol` — Pure JSON encode/decode module (not an Elixir Protocol), no process state.
- `Bibbidi.Transport` — Behaviour for swappable WebSocket transports.
- `Bibbidi.Transport.MintWS` — Default transport using mint_web_socket.
- `Bibbidi.Commands.BrowsingContext` — navigate, getTree, create, close, captureScreenshot, print, reload, setViewport, handleUserPrompt, activate, traverseHistory, locateNodes
- `Bibbidi.Commands.Script` — evaluate, callFunction, getRealms, disown, addPreloadScript, removePreloadScript
- `Bibbidi.Session` — Higher-level session lifecycle (new, end_session, status, subscribe, unsubscribe)

The library currently uses plain maps for commands and responses. Commands are module functions that take a connection pid and arguments, then return `{:ok, result}` tuples.

## Goal

Refactor bibbidi to support **command composition with automatic correlation**. A single high-level consumer intent (like "click this element" or "search Google and click a result") should be expressible as a data structure that expands into multiple BiDi wire commands. All commands, responses, and events produced during execution must be automatically correlated back to the original intent.

This enables three key consumer use cases without bibbidi needing to understand any of them:

1. **Playwright-compatible trace generation** — a trace writer walks the correlated operation and produces `trace.zip` files viewable at `trace.playwright.dev`
2. **RPA frameworks** — logging, retry, and error reporting at the intent level
3. **Test frameworks** — assertion context, failure diagnostics, step-level reporting

## Architecture: Three Protocols

### Protocol 1: `Bibbidi.Encodable`

Responsible for: struct → BiDi wire JSON. Pure, stateless, 1:1 mapping.

```elixir
defprotocol Bibbidi.Encodable do
  @doc "The BiDi method string (e.g., \"browsingContext.navigate\")"
  @spec method(t()) :: String.t()
  def method(command)

  @doc "Encode into the BiDi params map to send over the wire"
  @spec params(t()) :: map()
  def params(command)
end
```

Every existing command module function becomes a struct with an `Encodable` implementation. For example, `Bibbidi.Commands.BrowsingContext.navigate(conn, context, url, opts)` becomes:

```elixir
defmodule Bibbidi.Commands.BrowsingContext.Navigate do
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

The existing function-based API (`BrowsingContext.navigate(conn, ctx, url)`) should continue to work as a convenience wrapper that constructs the struct and sends it through `Connection`. This is a backwards-compatible change.

### Protocol 2: `Bibbidi.Expandable`

Responsible for: struct → tree of wire commands, possibly with branching based on intermediate results.

```elixir
defprotocol Bibbidi.Expandable do
  @doc """
  Expand a high-level command into an execution plan.

  Return values:
  - A struct implementing `Encodable` (leaf — send this single command)
  - A list of `Expandable` values (sequence — run all in order, no branching)
  - A `{expandable, handler}` tuple where handler is a function that receives
    the result and returns `{:cont, next_expandable}` or `{:halt, final_result}`
  """
  @type expansion ::
    Encodable.t()
    | [expansion()]
    | {expansion(), (term() -> {:cont, expansion()} | {:halt, term()})}

  @spec expand(t()) :: expansion()
  def expand(command)
end
```

**Default command structs expand to themselves** (identity — they're already leaves):

```elixir
# Every Encodable struct gets a default Expandable impl
defimpl Bibbidi.Expandable, for: Bibbidi.Commands.BrowsingContext.Navigate do
  def expand(cmd), do: cmd
end
```

Consider using `@fallback_to_any true` plus a fallback that checks for `Encodable` implementation, or use `@derive` to reduce boilerplate. The exact mechanism is an implementation detail — the important thing is that plain command structs are valid `Expandable` values with zero additional code.

**Static sequences** need no function — just return a list:

```elixir
defmodule MyApp.NavigateAndScreenshot do
  defstruct [:context, :url]

  defimpl Bibbidi.Expandable do
    def expand(%{context: ctx, url: url}) do
      [
        %Bibbidi.Commands.BrowsingContext.Navigate{context: ctx, url: url, wait: "complete"},
        %Bibbidi.Commands.BrowsingContext.CaptureScreenshot{context: ctx}
      ]
    end
  end
end
```

**Dynamic sequences** use the continuation tuple:

```elixir
defimpl Bibbidi.Expandable, for: MyApp.ClickElement do
  def expand(%{context: ctx, selector: sel}) do
    locate = %Bibbidi.Commands.BrowsingContext.LocateNodes{
      context: ctx,
      locator: %{type: "css", value: sel}
    }

    {locate, fn
      {:ok, %{"nodes" => [node | _]}} ->
        {:cont, build_click_actions(ctx, node)}

      {:ok, %{"nodes" => []}} ->
        {:halt, {:error, :element_not_found}}
    end}
  end
end
```

**Expandables can return other Expandables** — not just Encodables. This enables composition: a `SearchAndClick` expandable can expand into a `Navigate` (leaf) followed by a `ClickElement` (which itself is an expandable that uses continuations). The runner recurses until it reaches leaves.

### Protocol 3: `Bibbidi.Operation.Reducer`

Responsible for: (original intent struct, completed operation with all correlated data) → consumer-meaningful result.

```elixir
defprotocol Bibbidi.Operation.Reducer do
  @doc """
  Given the original command and the completed operation record,
  produce a consumer-facing result.

  The operation contains all commands sent, all responses received,
  all events captured, and timing information.
  """
  @spec reduce(t(), Bibbidi.Operation.t()) :: term()
  def reduce(command, operation)
end
```

This protocol is optional — consumers can always destructure `%Bibbidi.Operation{}` directly. It exists so that different consumers (trace writers, RPA loggers, test reporters) can interpret the same operation data differently.

## The Operation Struct

```elixir
defmodule Bibbidi.Operation do
  @type t :: %__MODULE__{
    id: String.t(),
    intent: term(),
    steps: [step()],
    events: [event()],
    started_at: integer(),
    ended_at: integer() | nil,
    status: :running | :completed | :failed,
    error: term() | nil
  }

  @type step :: %{
    command: Encodable.t(),
    response: term() | nil,
    sent_at: integer(),
    received_at: integer() | nil
  }

  defstruct [
    :id, :intent, :started_at, :ended_at, :error,
    steps: [],
    events: [],
    status: :running
  ]
end
```

## The Runner

The runner is a recursive interpreter that walks the `Expandable` tree, sends leaf commands through `Connection`, and accumulates everything into an `%Operation{}`.

```elixir
defmodule Bibbidi.Operation.Runner do
  alias Bibbidi.{Connection, Encodable, Expandable, Operation}

  @doc """
  Execute an expandable command, returning {result, operation}.

  Options:
    - :capture_events - list of BiDi event names to capture during execution
    - :timeout - per-command timeout (default: 5_000)
  """
  @spec execute(GenServer.server(), Expandable.t(), keyword()) ::
    {:ok, term(), Operation.t()} | {:error, term(), Operation.t()}
  def execute(conn, command, opts \\ []) do
    op = %Operation{
      id: generate_id(),
      intent: command,
      started_at: System.monotonic_time(:millisecond)
    }

    event_names = Keyword.get(opts, :capture_events, [])
    setup_event_capture(conn, event_names)

    try do
      case run(conn, Expandable.expand(command), op, opts) do
        {:ok, result, op} ->
          op = finalize(op, :completed)
          {:ok, result, op}

        {:error, reason, op} ->
          op = finalize(op, :failed, reason)
          {:error, reason, op}
      end
    after
      teardown_event_capture(conn, event_names)
    end
  end

  # Leaf — an Encodable struct, send it on the wire
  defp run(conn, %{__struct__: _} = cmd, op, opts) when is_encodable(cmd) do
    sent_at = System.monotonic_time(:millisecond)
    timeout = Keyword.get(opts, :timeout, 5_000)

    case Connection.send_command(conn, Encodable.method(cmd), Encodable.params(cmd), timeout) do
      {:ok, result} ->
        step = %{command: cmd, response: result, sent_at: sent_at, received_at: now()}
        op = %{op | steps: op.steps ++ [step]}
        {:ok, result, op}

      {:error, reason} ->
        step = %{command: cmd, response: {:error, reason}, sent_at: sent_at, received_at: now()}
        op = %{op | steps: op.steps ++ [step]}
        {:error, reason, op}
    end
  end

  # Sequence — run all items in order
  defp run(conn, list, op, opts) when is_list(list) do
    Enum.reduce_while(list, {:ok, nil, op}, fn item, {:ok, _prev, op} ->
      case run(conn, Expandable.expand(item), op, opts) do
        {:ok, result, op} -> {:cont, {:ok, result, op}}
        {:error, _, _} = err -> {:halt, err}
      end
    end)
  end

  # Continuation — run inner, then call handler with result to get next step
  defp run(conn, {inner, handler}, op, opts) when is_function(handler, 1) do
    case run(conn, Expandable.expand(inner), op, opts) do
      {:ok, result, op} ->
        case handler.(result) do
          {:cont, next} -> run(conn, Expandable.expand(next), op, opts)
          {:halt, final} -> {:ok, final, op}
        end

      {:error, _, _} = err ->
        err
    end
  end
end
```

### Note on `is_encodable` guard

The runner needs to distinguish leaf nodes (send on the wire) from expandable nodes (recurse). Options:

1. Check if the struct implements `Encodable` at runtime via protocol dispatch
2. Use a marker field or behaviour
3. Pattern match on known structs

Recommended: attempt `Expandable.expand(thing)` first — if it returns itself, it's a leaf. This avoids needing a separate guard mechanism. The runner calls `Expandable.expand/1` on everything and only calls `Connection.send_command/4` when the expansion result is the same struct it started with (identity expansion = leaf).

## Implementation Steps

### Phase 1: Command Structs + Encodable Protocol

**Goal**: Replace the current map-based command encoding with structs implementing `Encodable`, while keeping the existing function API working.

1. Define the `Bibbidi.Encodable` protocol with `method/1` and `params/1`
2. Create a struct for every command in every command module:
   - `Bibbidi.Commands.BrowsingContext.Navigate`
   - `Bibbidi.Commands.BrowsingContext.GetTree`
   - `Bibbidi.Commands.BrowsingContext.Create`
   - `Bibbidi.Commands.BrowsingContext.Close`
   - `Bibbidi.Commands.BrowsingContext.CaptureScreenshot`
   - `Bibbidi.Commands.BrowsingContext.Print`
   - `Bibbidi.Commands.BrowsingContext.Reload`
   - `Bibbidi.Commands.BrowsingContext.SetViewport`
   - `Bibbidi.Commands.BrowsingContext.HandleUserPrompt`
   - `Bibbidi.Commands.BrowsingContext.Activate`
   - `Bibbidi.Commands.BrowsingContext.TraverseHistory`
   - `Bibbidi.Commands.BrowsingContext.LocateNodes`
   - `Bibbidi.Commands.Script.Evaluate`
   - `Bibbidi.Commands.Script.CallFunction`
   - `Bibbidi.Commands.Script.GetRealms`
   - `Bibbidi.Commands.Script.Disown`
   - `Bibbidi.Commands.Script.AddPreloadScript`
   - `Bibbidi.Commands.Script.RemovePreloadScript`
   - Session commands if not already covered
3. Each existing module function (e.g., `BrowsingContext.navigate/4`) becomes a wrapper: construct the struct, then call a new `Connection.execute/3` function that accepts an `Encodable`
4. Update `Bibbidi.Connection` to accept `Encodable` structs via a new `execute/3` alongside the existing `send_command/4`
5. All existing tests must continue to pass — function API is unchanged

### Phase 2: Expandable Protocol + Runner

**Goal**: Allow compound commands that expand into multiple wire commands with automatic correlation.

1. Define `Bibbidi.Expandable` protocol
2. Implement default `Expandable` for all command structs (identity — returns self). Evaluate whether `@fallback_to_any` or `@derive` is cleaner here.
3. Define `Bibbidi.Operation` struct
4. Implement `Bibbidi.Operation.Runner.execute/3` with the recursive interpreter
5. Add event capture support — during an operation's execution window, BiDi events matching a filter are collected into `op.events`
6. Write tests using mock/test transports (bibbidi already has `Bibbidi.Transport` as a behaviour — use that)

### Phase 3: Reducer Protocol + Telemetry

**Goal**: Provide structured result interpretation and observability hooks.

1. Define `Bibbidi.Operation.Reducer` protocol
2. Emit `:telemetry` events at operation boundaries:
   - `[:bibbidi, :operation, :start]` — when an operation begins
   - `[:bibbidi, :operation, :step]` — when each individual command is sent/received
   - `[:bibbidi, :operation, :stop]` — when an operation completes
   - `[:bibbidi, :operation, :exception]` — on failure
3. The telemetry metadata should include the `%Operation{}` struct, allowing consumers to attach handlers for logging, tracing, metrics, etc., without coupling to bibbidi

### Phase 4: Trace Writer (Separate Library or Example)

**Goal**: Demonstrate the architecture by implementing Playwright trace zip generation.

This is likely a separate hex package (e.g., `bibbidi_trace`) or an `examples/` module. It subscribes to telemetry events, collects operations, and writes Playwright-compatible trace zips.

A Playwright `trace.zip` contains:
- `trace.trace` — newline-delimited JSON of trace events (one JSON object per line)
- `trace.network` — newline-delimited JSON of network events
- `resources/` — directory of binary blobs keyed by SHA1 hash (screenshots, DOM snapshots)

Each action event in `trace.trace` has fields like:
```json
{"type":"context-options","browserName":"firefox","options":{}}
{"type":"action","callId":"call@1","apiName":"page.goto","startTime":1234,"endTime":1235,"params":{"url":"..."},"pageId":"page@1","beforeSnapshot":"sha1-abc","afterSnapshot":"sha1-def","log":["navigating to ...","waiting for load"]}
{"type":"screencast-frame","pageId":"page@1","sha1":"sha1-ghi","timestamp":1234,"width":1280,"height":720}
```

The trace writer's `Reducer` implementation walks `operation.steps` and maps each step to one or more Playwright trace events. It maps BiDi method names to Playwright API names (e.g., `browsingContext.navigate` → `page.goto`).

## Realistic Example: Search Google and Click First Organic Link

This example shows how a consumer (an RPA library or test framework built on bibbidi) would define a compound operation that:
1. Navigates to Google
2. Types a search query
3. Waits for results
4. Finds the first non-sponsored/non-promoted link
5. Clicks it
6. Waits for the destination page to load

### The Consumer-Defined Structs

```elixir
defmodule MyRPA.Actions.TypeIntoElement do
  @moduledoc """
  Locate an element by CSS selector and type text into it by
  calling a JS function that sets the value and dispatches input events.
  """
  defstruct [:context, :selector, :text]

  defimpl Bibbidi.Expandable do
    alias Bibbidi.Commands.{BrowsingContext, Script}

    def expand(%{context: ctx, selector: sel, text: text}) do
      locate = %BrowsingContext.LocateNodes{
        context: ctx,
        locator: %{type: "css", value: sel}
      }

      {locate, fn
        {:ok, %{"nodes" => [node | _]}} ->
          # Use callFunction to set value and dispatch events
          set_value = %Script.CallFunction{
            function_declaration: """
            function(el, text) {
              el.value = text;
              el.dispatchEvent(new Event('input', { bubbles: true }));
            }
            """,
            target: %{context: ctx},
            arguments: [node, %{type: "string", value: text}],
            await_promise: false
          }
          {:halt, set_value}

        {:ok, %{"nodes" => []}} ->
          {:halt, {:error, {:element_not_found, sel}}}
      end}
    end
  end
end

defmodule MyRPA.Actions.ClickElement do
  @moduledoc """
  Locate an element, compute its center coordinates, and perform
  a pointer click action at those coordinates.
  """
  defstruct [:context, :selector]

  defimpl Bibbidi.Expandable do
    alias Bibbidi.Commands.{BrowsingContext, Script, Input}

    def expand(%{context: ctx, selector: sel}) do
      locate = %BrowsingContext.LocateNodes{
        context: ctx,
        locator: %{type: "css", value: sel}
      }

      {locate, fn
        {:ok, %{"nodes" => [node | _]}} ->
          # Get bounding rect to compute click coordinates
          get_rect = %Script.CallFunction{
            function_declaration: """
            function(el) {
              const rect = el.getBoundingClientRect();
              return { x: rect.x + rect.width / 2, y: rect.y + rect.height / 2 };
            }
            """,
            target: %{context: ctx},
            arguments: [node],
            await_promise: false
          }

          {get_rect, fn
            {:ok, %{"result" => %{"value" => %{"x" => x, "y" => y}}}} ->
              click = %Input.PerformActions{
                context: ctx,
                actions: [%{
                  type: "pointer",
                  id: "mouse",
                  parameters: %{pointerType: "mouse"},
                  actions: [
                    %{type: "pointerMove", x: round(x), y: round(y)},
                    %{type: "pointerDown", button: 0},
                    %{type: "pointerUp", button: 0}
                  ]
                }]
              }
              {:halt, click}

            {:error, reason} ->
              {:halt, {:error, reason}}
          end}

        {:ok, %{"nodes" => []}} ->
          {:halt, {:error, {:element_not_found, sel}}}
      end}
    end
  end
end

defmodule MyRPA.Actions.WaitForSelector do
  @moduledoc """
  Poll for an element matching a CSS selector until it appears or timeout.
  This is a dynamic expandable that re-issues locateNodes in a loop.
  """
  defstruct [:context, :selector, :timeout_ms, attempts: 0, interval_ms: 200]

  defimpl Bibbidi.Expandable do
    alias Bibbidi.Commands.BrowsingContext

    def expand(%{context: ctx, selector: sel, timeout_ms: timeout, attempts: attempts, interval_ms: interval} = cmd) do
      max_attempts = div(timeout, interval)

      locate = %BrowsingContext.LocateNodes{
        context: ctx,
        locator: %{type: "css", value: sel}
      }

      {locate, fn
        {:ok, %{"nodes" => [_ | _]} = result} ->
          {:halt, {:ok, result}}

        {:ok, %{"nodes" => []}} when attempts < max_attempts ->
          # Return another expandable — the runner will recurse
          # The sleep would need to happen here or be modeled as a special command
          {:cont, %{cmd | attempts: attempts + 1}}

        {:ok, %{"nodes" => []}} ->
          {:halt, {:error, {:timeout, sel}}}
      end}
    end
  end
end

defmodule MyRPA.Actions.SearchGoogleAndClickFirstOrganicLink do
  @moduledoc """
  The top-level intent. Navigates to Google, searches, finds the first
  non-sponsored result, and clicks it.

  This expands into a sequence mixing static steps (navigate) with
  dynamic steps (type, wait, find organic link, click).
  """
  defstruct [:context, :query]

  defimpl Bibbidi.Expandable do
    alias Bibbidi.Commands.{BrowsingContext, Script}

    def expand(%{context: ctx, query: query}) do
      # Step 1: Navigate to Google (static leaf)
      navigate = %BrowsingContext.Navigate{
        context: ctx,
        url: "https://www.google.com",
        wait: "complete"
      }

      # Step 2: Accept cookies dialog if present, then type query and submit
      # This is a continuation from navigate
      {navigate, fn
        {:ok, _nav_result} ->
          # Dismiss cookie consent if present (best-effort)
          dismiss_cookies = %Script.Evaluate{
            expression: """
            (() => {
              const btn = document.querySelector('[id="L2AGLb"]');
              if (btn) btn.click();
            })()
            """,
            target: %{context: ctx},
            await_promise: false
          }

          {dismiss_cookies, fn
            _ ->
              # Type into the search box and submit
              type_and_submit = %Script.Evaluate{
                expression: """
                (() => {
                  const input = document.querySelector('textarea[name="q"], input[name="q"]');
                  if (!input) throw new Error('Search input not found');
                  input.value = #{Jason.encode!(query)};
                  input.dispatchEvent(new Event('input', { bubbles: true }));
                  input.form.submit();
                })()
                """,
                target: %{context: ctx},
                await_promise: false
              }

              # After submitting, wait for results to load, then find and click
              {type_and_submit, fn
                {:ok, _} ->
                  # Wait for organic results to appear
                  wait_for_results = %MyRPA.Actions.WaitForSelector{
                    context: ctx,
                    selector: "#search a h3",
                    timeout_ms: 10_000
                  }

                  {wait_for_results, fn
                    {:ok, _} ->
                      # Find first non-sponsored link
                      find_organic = %Script.Evaluate{
                        expression: """
                        (() => {
                          const results = document.querySelectorAll('#search a');
                          for (const a of results) {
                            // Skip sponsored results
                            const parent = a.closest('[data-text-ad]') || a.closest('.commercial-unit-desktop-top');
                            if (parent) continue;
                            // Skip results without h3 (not real search results)
                            if (!a.querySelector('h3')) continue;
                            // Skip Google's own links
                            const href = a.href;
                            if (!href || href.includes('google.com/search') || href.startsWith('javascript:')) continue;
                            return { href: href, text: a.querySelector('h3')?.textContent || '' };
                          }
                          return null;
                        })()
                        """,
                        target: %{context: ctx},
                        await_promise: false
                      }

                      {find_organic, fn
                        {:ok, %{"result" => %{"value" => %{"href" => href, "text" => text}}}} ->
                          # Click the link by navigating directly
                          # (more reliable than pointer click for search results)
                          click_result = %BrowsingContext.Navigate{
                            context: ctx,
                            url: href,
                            wait: "complete"
                          }

                          {:halt, click_result}

                        {:ok, %{"result" => %{"value" => nil}}} ->
                          {:halt, {:error, :no_organic_results_found}}

                        {:error, reason} ->
                          {:halt, {:error, reason}}
                      end}

                    {:error, reason} ->
                      {:halt, {:error, {:results_did_not_load, reason}}}
                  end}

                {:error, reason} ->
                  {:halt, {:error, {:search_submit_failed, reason}}}
              end}
          end}
      end}
    end
  end

  # Optional: structured result from the operation
  defimpl Bibbidi.Operation.Reducer do
    def reduce(_cmd, %Bibbidi.Operation{steps: steps, status: :completed}) do
      # The last step's response is the final navigation result
      last_step = List.last(steps)
      nav_result = last_step.response

      # Walk backward to find the organic link evaluation
      organic_step = Enum.find(steps, fn step ->
        match?(%Script.Evaluate{}, step.command) and
        is_map(step.response) and
        get_in(step.response, ["result", "value", "href"])
      end)

      %{
        destination_url: get_in(nav_result, ["url"]),
        organic_link: get_in(organic_step.response, ["result", "value"]),
        total_steps: length(steps),
        duration_ms: List.last(steps).received_at - hd(steps).sent_at
      }
    end

    def reduce(_cmd, %Bibbidi.Operation{status: :failed, error: error}) do
      {:error, error}
    end
  end
end
```

### Calling It

```elixir
{:ok, conn} = Bibbidi.Connection.start_link(url: "ws://localhost:9222/session")
{:ok, _caps} = Bibbidi.Session.new(conn)

{:ok, tree} = Bibbidi.Commands.BrowsingContext.get_tree(conn)
context = hd(tree["contexts"])["context"]

# Execute the compound operation
search = %MyRPA.Actions.SearchGoogleAndClickFirstOrganicLink{
  context: context,
  query: "elixir programming language"
}

{:ok, result, operation} = Bibbidi.Operation.Runner.execute(conn, search,
  capture_events: ["browsingContext.load", "network.responseCompleted"]
)

# result is whatever the last {:halt, ...} returned — the final Navigate response

# operation contains ALL correlated data:
IO.inspect(length(operation.steps))
# => 7 (navigate + cookie dismiss + type/submit + locate*N + find_organic + final navigate)

# Use the Reducer for a structured result:
summary = Bibbidi.Operation.Reducer.reduce(search, operation)
# => %{destination_url: "https://elixir-lang.org/", organic_link: %{...}, ...}

# A trace writer could also consume this same operation:
BibbidiTrace.Writer.write_trace(operation, "trace.zip")
```

### What the Operation Record Looks Like

After execution, `operation` contains:

```elixir
%Bibbidi.Operation{
  id: "op_a1b2c3",
  intent: %MyRPA.Actions.SearchGoogleAndClickFirstOrganicLink{
    context: "ctx-1", query: "elixir programming language"
  },
  status: :completed,
  started_at: 1710400000000,
  ended_at: 1710400003500,
  steps: [
    %{command: %BrowsingContext.Navigate{url: "https://www.google.com", ...},
      response: %{"navigation" => "nav-1", "url" => "https://www.google.com/"},
      sent_at: 1710400000000, received_at: 1710400000800},
    %{command: %Script.Evaluate{expression: "(() => { const btn = ...", ...},
      response: %{"result" => %{"type" => "undefined"}},
      sent_at: 1710400000810, received_at: 1710400000850},
    %{command: %Script.Evaluate{expression: "(() => { const input = ...", ...},
      response: %{"result" => %{"type" => "undefined"}},
      sent_at: 1710400000860, received_at: 1710400000900},
    %{command: %BrowsingContext.LocateNodes{selector: "#search a h3", ...},
      response: %{"nodes" => []},
      sent_at: 1710400000910, received_at: 1710400001100},
    %{command: %BrowsingContext.LocateNodes{selector: "#search a h3", ...},
      response: %{"nodes" => [%{"type" => "node", ...}]},
      sent_at: 1710400001300, received_at: 1710400001500},
    %{command: %Script.Evaluate{expression: "(() => { const results = ...", ...},
      response: %{"result" => %{"value" => %{"href" => "https://elixir-lang.org/", "text" => "Elixir"}}},
      sent_at: 1710400001510, received_at: 1710400001600},
    %{command: %BrowsingContext.Navigate{url: "https://elixir-lang.org/", ...},
      response: %{"navigation" => "nav-2", "url" => "https://elixir-lang.org/"},
      sent_at: 1710400001610, received_at: 1710400003500}
  ],
  events: [
    # BiDi events captured during execution
    %{event: "browsingContext.load", params: %{"context" => "ctx-1", "url" => "https://www.google.com/"}, timestamp: ...},
    %{event: "network.responseCompleted", params: %{...}, timestamp: ...},
    # ... more events
  ]
}
```

### How the Trace Writer Uses This

A Playwright trace writer (Phase 4) would iterate `operation.steps` and produce:

```
# trace.trace (NDJSON)
{"type":"context-options","browserName":"firefox","options":{}}
{"type":"action","callId":"call@1","apiName":"page.goto","startTime":...,"endTime":...,"params":{"url":"https://www.google.com"}}
{"type":"action","callId":"call@2","apiName":"page.evaluate","startTime":...,"endTime":...,"params":{"expression":"dismiss cookies"}}
{"type":"action","callId":"call@3","apiName":"page.evaluate","startTime":...,"endTime":...,"params":{"expression":"type and submit"}}
{"type":"action","callId":"call@4","apiName":"page.waitForSelector","startTime":...,"endTime":...,"params":{"selector":"#search a h3"}}
{"type":"action","callId":"call@5","apiName":"page.evaluate","startTime":...,"endTime":...,"params":{"expression":"find organic link"}}
{"type":"action","callId":"call@6","apiName":"page.goto","startTime":...,"endTime":...,"params":{"url":"https://elixir-lang.org/"}}
```

Note how the trace writer collapses the two `LocateNodes` retries into a single logical "waitForSelector" action. This is where `Reducer` shines — the same raw operation data supports different interpretations.

## Open Design Questions

1. **Sleep/delay between retries**: The `WaitForSelector` example needs to pause between `LocateNodes` attempts. Options: (a) a special `%Bibbidi.Commands.Sleep{}` struct the runner interprets, (b) the continuation function itself calls `Process.sleep/1` before returning `{:cont, ...}`, (c) the runner accepts a `:retry_interval` option. Option (b) is simplest but makes expansions impure.

2. **Parallel branches**: The current algebra supports sequences and continuations but not parallel execution (e.g., "navigate page A and page B simultaneously, then join"). This could be added later as a `{:parallel, [expansion()]}` variant without breaking the existing types.

3. **Error recovery / retry at the operation level**: Should the runner support retrying the entire expansion on failure? Or is that the consumer's responsibility? Recommendation: consumer's responsibility — keep the runner simple.

4. **Event filtering during operations**: The current design captures all events matching a name filter. Should events also be filterable by page/context ID? Probably yes, since multiple operations might run concurrently on different contexts.

5. **`@fallback_to_any` vs explicit impls**: For `Expandable`, using `@fallback_to_any true` with a fallback that returns the struct unchanged means any `Encodable` struct is automatically expandable. The downside is that passing a non-Encodable, non-Expandable struct won't raise — it'll return itself and then fail at the runner level. Explicit impls are safer but more boilerplate. Consider using `@derive [Bibbidi.Expandable]` on command structs as a middle ground.

6. **Naming**: `Encodable` / `Expandable` / `Reducer` are working names. Other options: `Command` / `Action` / `Collector`. Pick what reads best in the actual codebase.

## File Structure (Expected)

```
lib/
  bibbidi/
    encodable.ex              # defprotocol Bibbidi.Encodable
    expandable.ex             # defprotocol Bibbidi.Expandable
    operation.ex              # %Bibbidi.Operation{} struct
    operation/
      runner.ex               # Bibbidi.Operation.Runner
      reducer.ex              # defprotocol Bibbidi.Operation.Reducer
    commands/
      browsing_context.ex     # existing module, updated
      browsing_context/
        navigate.ex           # struct + Encodable + Expandable impls
        get_tree.ex           # struct + Encodable + Expandable impls
        create.ex             # ...
        close.ex
        capture_screenshot.ex
        print.ex
        reload.ex
        set_viewport.ex
        handle_user_prompt.ex
        activate.ex
        traverse_history.ex
        locate_nodes.ex
      script.ex               # existing module, updated
      script/
        evaluate.ex
        call_function.ex
        get_realms.ex
        disown.ex
        add_preload_script.ex
        remove_preload_script.ex
      input/
        perform_actions.ex    # new — needed for click actions
      session/                # if session commands get structs
        new.ex
        end_session.ex
        subscribe.ex
        unsubscribe.ex
    connection.ex             # updated to accept Encodable structs
    protocol.ex               # existing — kept for backwards compat, delegates to Encodable
    session.ex                # existing — updated to use structs internally
    transport.ex              # unchanged
    transport/
      mint_ws.ex              # unchanged
```

## Testing Strategy

- **Unit tests for each command struct**: Verify `Encodable.method/1` and `Encodable.params/1` produce correct BiDi JSON
- **Unit tests for Expandable**: Verify each compound action expands into the expected tree structure (without executing)
- **Integration tests with mock transport**: Use a mock WebSocket transport to verify the runner sends commands in the correct order and handles continuation branching
- **Property-based tests**: Verify that any `Encodable` struct round-trips through `expand → run → operation.steps` and appears in the operation record
- **Backwards compatibility tests**: The existing function-based API (`BrowsingContext.navigate(conn, ctx, url)`) must produce identical wire output as the new struct-based path
