# Bibbidi 0.4 — Events refactor

This plan covers breaking changes needed in **bibbidi** for **bobbidi** to land cleanly. Self-contained: another Claude session can work this without the full bobbidi context. The bobbidi events shape is decided in `plans/bobbidi.md` ("Bridge for recorder events" and elsewhere); this plan is bibbidi-side only.

## Goals

1. Drop the redundant method-string from the event-dispatch tuple. Subscribers receive raw event structs in their mailbox by default.
2. Add `%Bibbidi.Events.Unknown{method, params}` fallback for events from spec versions or vendor extensions bibbidi hasn't generated typed structs for.
3. Add a method-string introspection helper (`Bibbidi.Events.method_for/1`) for users who want to filter by method without struct-matching.
4. Add per-namespace defguards alongside the generated event modules (`is_bibbidi_event/1`, `is_bibbidi_log_event/1`, etc.).
5. Add a per-subscribe `wrap:` keyword opt for customizing the message shape sent to subscribers. Default = `Function.identity/1`. Global `Application` config layer below it. Per-subscribe wins.
6. Ensure `script.message` channel support (W3C BiDi mechanism for in-page-JS-to-Elixir communication) is fully present in the codegen output and in `Connection.subscribe`.

## Out of scope

- `defmacro __using__` for `Bibbidi.Connection`. Forward-looking convenience for adapter authors who want to override `wrap/1` in a module instead of per-subscribe; tracked as future minor, NOT 0.4.
- Any API changes outside the events plumbing.
- Renames or new top-level modules.
- Backwards-compatibility shim for the old 3-tuple. Clean break is simpler given the small consumer set.

## Status (2026-05-18)

Goals 1–6 are landed on `bibbidi-0.4-events` (off `main`):

| #   | Goal                                                           | Commit    |
| --- | -------------------------------------------------------------- | --------- |
| 1   | Drop method-string tuple → raw struct                          | `6cefc02` |
| 2   | `%Bibbidi.Events.Unknown{}` fallback                           | `b2f7e81` |
| 3   | `Bibbidi.Events.method_for/1`                                  | `b2f7e81` |
| 4   | per-namespace defguards                                        | `b2f7e81` |
| 5   | per-subscribe `wrap:` + app-env default (shipped as MFA-or-fn) | `6cefc02` |
| 6   | `script.message` channel support + integration test            | `33b4ab1` |

Adjacent work that also landed: `Macro.underscore/camelize` codegen naming with acronym preservation (`672066d`), `MIGRATING.md` (`71532ff`), the `regen-codegen` skill (`1457f93`), and a README/Livebook/op_workflow-example refresh.

### Remaining work for 0.4

1. **`mix bibbidi.events.verify_guards` task** — codegen-drift catcher (test plan #7). Not built. See "Remaining: verify_guards" below.
2. **`RemoteValue.unwrap/1` helper** — placement undecided. See "Remaining: RemoteValue.unwrap/1" below.
3. **Incorporate `claude/gen-examples-registry`** — a parallel branch off `main` adding a codegen example registry. See "Remaining: incorporate gen-examples-registry" below.
4. **Version bump** `mix.exs` `0.3.0` → `0.4.0` — trivial, lands at release time.

### Remaining: verify_guards

Ship `mix bibbidi.events.verify_guards` (under `dev/mix/tasks/`, maintainer-only like the rest of `dev/`). It loads `Bibbidi.Events.event_modules/0` and asserts every module is matched by `Bibbidi.Events.Guards.is_bibbidi_event/1` AND by exactly one per-namespace guard. Fails loudly (non-zero exit) if a generated event slips through — catches the case where someone adds an event namespace but the `Guards` generator wasn't re-run. Should be runnable in CI and called out in the `regen-codegen` skill as a post-regen check.

Open detail: pure runtime check (build a struct per module, test the guard) vs. static check (compare the `event_modules/0` list against parsed `Guards` clauses). Runtime is simpler and catches real breakage; prefer it unless struct construction has surprises.

### Remaining: RemoteValue.unwrap/1 — where/how

Decision deferred to discussion. The Slice E integration test currently reads the raw RemoteValue map directly (`data["type"]`, `data["value"]`, `data["handle"]`) — no helper exists yet. Options for where the unwrap logic lives:

- **A. `Bibbidi.RemoteValue` (new module).** A dedicated home: `unwrap/1` (RemoteValue map → Elixir term, dropping handles) plus future `serialize/1` and handle-aware introspection. Most discoverable; matches the plan's original wording. Cost: a new public module to maintain + version.
- **B. `Bibbidi.Events.Script` or `Bibbidi.Protocol`.** Fold `unwrap/1` into an existing module. Smaller surface, but RemoteValue isn't events-specific (command results carry it too), and `Protocol` is currently pure wire encode/decode — unwrap is a layer up.
- **C. Don't ship it in bibbidi; let bobbidi own decode.** RemoteValue → Elixir term is arguably a convenience-layer concern. bibbidi stays raw-wire-faithful; `Bobbidi.JS`/`Bobbidi.Bridge` own the unwrap (they need `evaluate_json`-style decode anyway, per `plans/bobbidi.md` F4). Cost: every non-bobbidi bibbidi consumer (Cerberus's raw `send_command` path, Wallabidi) re-implements the `extract_value` boilerplate that already shows up 6+ times in Wallabidi.

Recommendation to discuss: **A**, scoped tightly to `unwrap/1` for now. It's the natural home, it's reused by command results AND channel messages AND bobbidi's bridge, and keeping it in bibbidi avoids every consumer re-deriving the `%{"type" => ..., "value" => ...}` walk. Round-trip concern: `unwrap/1` must be lossy-by-design for handles (a primitive loses its handle), so pair it with a documented "use the raw map when you need the handle" note — exactly the `ownership: "root"` helpers-install case from Slice E.

If we ship A, update the Slice E test to assert through `RemoteValue.unwrap/1` for the primitive cases (test plan #5 explicitly wants this), while keeping the raw-map assertion for the `handle` case.

### Remaining: incorporate gen-examples-registry

`origin/claude/gen-examples-registry` (single commit `0abc9be`, branched off `main`) added a content-only example registry to the codegen: drop `priv/examples/<FullyQualifiedElixirName>.md` and `mix bibbidi.gen` splices it into the matching generated module/function under a `## Examples` heading. It added `Bibbidi.CDDL.Generator.Examples`, wired four emission points (command struct moduledoc, facade fn doc, event struct moduledoc, event helper fn doc), `priv/examples/README.md`, tests, and an AGENTS.md line.

Re-implemented rather than cherry-picked. The 0.4 generator changed too much since that commit (Macro naming, the `Events`/`Guards` generators, `method/0` on event structs, the facade `@doc` shape), so a cherry-pick conflicts in `dev/cddl/generator.ex`. Same idea: a content-only registry read at codegen time; no files means today's output, unchanged.

How it works:

- Module is `Bibbidi.CDDL.Generator.Docs`, not `Examples`. Examples is one section; the module handles sections in general.
- `@sections` is a compile-time list of `%{key, heading, dir}`. It currently has one entry: `%{key: :examples, heading: "Examples", dir: "priv/examples"}`. To add a section, add an entry. It is not runtime-configurable.
- `Docs.for_name(name)` reads the markdown for each section, returns the present ones joined (each under its `## <heading>`) as a two-space-indented block with no surrounding blank lines, or `nil` if there are none.
- `splice_docs(base, docs)` joins that block onto each emission point's base text: `nil` returns base unchanged, otherwise `String.trim_trailing(base) <> "\n\n" <> docs`. The registry function stays free of leading-newline rules; the caller adds separation.
- Per-section dir override at `:"#{key}_dir"` (`:examples_dir` for examples), on `Docs.dir/1`, used by tests.

Module-doc and function-doc examples go in `module/` and `function/` subfolders. Without the split, a struct moduledoc (`Bibbidi.Commands.Session.Subscribe`) and its facade `@doc` (`Bibbidi.Commands.Session.subscribe`) are the same file on a case-insensitive filesystem like macOS, and one silently overwrites the other. The original's flat layout had this bug. `Docs.for_name/1` picks the subfolder from the last segment's case (PascalCase → `module/`, snake_case → `function/`), so call sites pass the same name as before.

Four emission points, each composed with `splice_docs/2`:

1. Command struct `@moduledoc` — `build_command_moduledoc/4`, key `Bibbidi.Commands.<Mod>.<Command>`.
2. Facade builder fn `@doc` — `generate_facade_function/6`, key `Bibbidi.Commands.<Mod>.<fun>`. One-line `@doc` when there's only the summary, heredoc when there are opts and/or docs. Renamed the field lists `required`/`optional` to `requireds`/`optionals` while here.
3. Event struct `@moduledoc` — `generate_event_struct_module/7`, key `Bibbidi.Events.<Mod>.<Struct>`.
4. Event helper fn `@doc` — `generate_events_module/5`, key `Bibbidi.Events.<Mod>.<fun>`.

### Done (2026-06-17)

- [x] `dev/cddl/generator/docs.ex`: `Docs` module (`@sections`, `for_name/1`, `sections/0`, `dir/1`).
- [x] `Docs.for_name/1` + `splice_docs/2` wired into the four emission points; un-underscored `camel_mod` in `generate_facade_function`.
- [x] `priv/examples/README.md`: naming, the `module/`/`function/` split, how to add a section. Uses the 0.4 raw-struct event shape in its sample, not the old 3-tuple.
- [x] `test/bibbidi/cddl/generator/docs_test.exs`: wrapping, no surrounding blank lines, blank-line and trailing-whitespace handling, the module/function split, `sections/0`, and `dir/1` override + default. No runtime multi-section test — `@sections` is compile-time.
- [x] Optional step added to root `AGENTS.md`.
- [x] Regen with an empty registry leaves `lib/` unchanged.
- [x] Checked end to end with throwaway `module/` + `function/` examples (splice, order after `## Options`, code-block indent, subfolder routing), then deleted them. `priv/examples/` ships only the README; real example content can be added later.
- [x] `mix test` (192) and `mix test.all` (239) pass; `mix compile --warnings-as-errors` is clean.

## Breaking change: tuple → raw struct

### Before (current 0.3.x)

```elixir
def handle_info({:bibbidi_event, "log.entryAdded", %Bibbidi.Events.Log.EntryAdded{} = ev}, state) do
  ...
end
```

### After (0.4)

```elixir
def handle_info(%Bibbidi.Events.Log.EntryAdded{} = ev, state) do
  ...
end

# Or via guards:
def handle_info(msg, state) when is_bibbidi_log_event(msg) do
  ...
end

# Or method-based filtering:
def handle_info(msg, state) when is_bibbidi_event(msg) do
  case Bibbidi.Events.method_for(msg) do
    "log.entryAdded" -> ...
    _ -> ...
  end
end
```

The default subscriber receives the bare struct. Pattern-matching on `{:bibbidi_event, _, _}` will not match.

## New constructs

### `%Bibbidi.Events.Unknown{}`

```elixir
defmodule Bibbidi.Events.Unknown do
  @moduledoc """
  Fallback event struct for BiDi events not covered by the generated typed structs.
  Vendor extensions, future spec versions, or events the codegen hasn't run for.
  """
  defstruct [:method, :params]

  @type t :: %__MODULE__{method: String.t(), params: map()}
end
```

The protocol decoder dispatches to a typed struct when one exists; otherwise emits `%Unknown{method: "...", params: %{...}}`.

### `Bibbidi.Events.method_for/1`

```elixir
@spec method_for(struct) :: String.t()
def method_for(%Bibbidi.Events.Log.EntryAdded{}), do: "log.entryAdded"
def method_for(%Bibbidi.Events.BrowsingContext.Load{}), do: "browsingContext.load"
# ... generated alongside event modules
def method_for(%Bibbidi.Events.Unknown{method: m}), do: m
```

Generated by the CDDL codegen. Consumers can use this for method-based filtering without needing to know the full struct list.

### Per-namespace defguards

Generated alongside event modules in `Bibbidi.Events.Guards`:

```elixir
defmodule Bibbidi.Events.Guards do
  defguard is_bibbidi_log_event(msg)
    when is_struct(msg, Bibbidi.Events.Log.EntryAdded)

  defguard is_bibbidi_browsing_context_event(msg)
    when is_struct(msg, Bibbidi.Events.BrowsingContext.Load)
      or is_struct(msg, Bibbidi.Events.BrowsingContext.NavigationStarted)
      or is_struct(msg, Bibbidi.Events.BrowsingContext.FragmentNavigated)
      or is_struct(msg, Bibbidi.Events.BrowsingContext.UserPromptOpened)
      or is_struct(msg, Bibbidi.Events.BrowsingContext.UserPromptClosed)
      or is_struct(msg, Bibbidi.Events.BrowsingContext.DownloadWillBegin)
      # ... etc

  defguard is_bibbidi_input_event(msg)
    when is_struct(msg, Bibbidi.Events.Input.FileDialogOpened)

  defguard is_bibbidi_network_event(msg)
    when is_struct(msg, Bibbidi.Events.Network.BeforeRequestSent)
      or is_struct(msg, Bibbidi.Events.Network.ResponseStarted)
      or is_struct(msg, Bibbidi.Events.Network.ResponseCompleted)
      or is_struct(msg, Bibbidi.Events.Network.FetchError)
      or is_struct(msg, Bibbidi.Events.Network.AuthRequired)

  defguard is_bibbidi_script_event(msg)
    when is_struct(msg, Bibbidi.Events.Script.Message)
      or is_struct(msg, Bibbidi.Events.Script.RealmCreated)
      or is_struct(msg, Bibbidi.Events.Script.RealmDestroyed)

  defguard is_bibbidi_event(msg)
    when is_bibbidi_log_event(msg)
      or is_bibbidi_browsing_context_event(msg)
      or is_bibbidi_input_event(msg)
      or is_bibbidi_network_event(msg)
      or is_bibbidi_script_event(msg)
      or is_struct(msg, Bibbidi.Events.Unknown)
      # ... all namespaces
end
```

Users `import Bibbidi.Events.Guards` in their handler module and use them in `handle_info` clauses.

The codegen is responsible for keeping this module in sync as new events are added — a Mix-task verifier (e.g. `mix bibbidi.events.verify_guards`) is worth shipping to catch drift.

### Per-subscribe `wrap:` keyword opt

```elixir
@spec subscribe(conn, event_method :: String.t(), pid, opts :: keyword) :: :ok | {:error, term}
def subscribe(conn, event_method, pid, opts \\ []) do
  wrap = resolve_wrap(opts)   # per-subscribe → app config → Function.identity
  # store wrap fn alongside the subscription
end
```

Default `wrap/1` is `&Function.identity/1` — subscribers receive raw structs.

Per-subscribe overrides:

```elixir
# Receive {:my_app_event, struct}:
Bibbidi.Connection.subscribe(conn, "log.entryAdded", pid, wrap: fn s -> {:my_app_event, s} end)

# Explicit identity (the default form):
Bibbidi.Connection.subscribe(conn, "log.entryAdded", pid, wrap: &Function.identity/1)
```

Global default (Application config):

```elixir
config :bibbidi, event_wrapper: fn s -> {:bibbidi_event, s} end
```

The connection picks per-subscribe override > global config > `Function.identity`.

The wrap fn runs in `Bibbidi.Connection`'s process before `send`. **Document this constraint loudly.** Heavy decoding (regex, JSON parse, network calls) belongs in the consumer's pid, not in the wrap fn.

## `script.message` channel support

W3C BiDi: `script.addPreloadScript` accepts a `channels:` parameter — `[{channel: "id", serializationOptions: {...}, ownership: "root" | "none"}]`. The channel is passed to the preload script as a function argument; calling it emits a `script.message` event with the channel id and a `RemoteValue` payload.

This is the proper mechanism for in-page-JS-to-Elixir communication, replacing `console.log` + `[MARKER]` + `log.entryAdded` workarounds (the current `packages/playbook/lib/playbook/recorder.ex` pattern).

### What 0.4 must support

1. `Bibbidi.Commands.Script.AddPreloadScript` accepts a `channels:` parameter — verify the CDDL codegen covers it; add if not.
2. `Bibbidi.Commands.Script.CallFunction` and `Script.Evaluate` accept `channels:` arguments — verify same.
3. `%Bibbidi.Events.Script.Message{channel, data, source}` event struct is generated (alongside guards).
4. Decode of `data: RemoteValue` follows the same path as `Script.Evaluate` results.

### Decision: leave `Script.Message.data` as raw RemoteValue

Settled: `Script.Message.data` is the raw RemoteValue map (the generated `%Bibbidi.Events.Script.Message{}` carries it untouched), NOT a pre-decoded Elixir term. Verified by the Slice E integration test (`33b4ab1`), which reads `data["type"]` / `data["value"]` / `data["handle"]` directly.

Rationale: SharedReferences must remain accessible from channel data — bobbidi's helpers-handle install path delivers a SharedReference via channel + `ownership: "root"`, and a pre-decoded primitive value would lose that.

The `unwrap/1` convenience helper (RemoteValue map → Elixir term, lossy for handles) is still outstanding — its placement is under discussion in "Remaining: RemoteValue.unwrap/1" above.

## Migration guide for downstream consumers

### In this monorepo

| Package                             | Affected file(s)                               | Change                                                                                     |
| ----------------------------------- | ---------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `packages/bibbidi_runic`            | TBD — check usage of `{:bibbidi_event, _, _}`  | Pattern-match update                                                                       |
| `packages/bibbidi_playwright_trace` | TBD — same                                     | Pattern-match update                                                                       |
| `packages/autopilot`                | `lib/autopilot/browser.ex:244-254` (subscribe) | None for that file; consumers of subscribed events update their pattern-matches            |
| `packages/playbook`                 | `lib/playbook/recorder.ex:179-186`             | Switch to bobbidi anyway in the bobbidi port. Old shape can ride 0.3 until then if needed. |

### External consumers

- **Cerberus** (`/Users/peter/work/cerberus/lib/cerberus/driver/browser/bidi.ex:115-119`) — pattern-matches on the 3-tuple. Mechanical update. Coordinate with Cerberus maintainer; see `plans/adapter-cerberus.md`.
- **Wallabidi** — uses its own forked WebSocket client; unaffected.

Migration is mechanical:

```elixir
# Before
def handle_info({:bibbidi_event, "log.entryAdded", params}, state), do: ...

# After
def handle_info(%Bibbidi.Events.Log.EntryAdded{} = ev, state), do: ...
```

Provide a CHANGELOG entry showing both shapes side by side and a one-paragraph justification (redundancy + better pattern matching).

## Forward-looking note: `use Bibbidi.Connection`

Not in 0.4. Reserved for a future minor.

```elixir
defmodule MyApp.Connection do
  use Bibbidi.Connection

  # Override default wrap for all subscribers of this connection module:
  def wrap(event), do: {:my_app_event, event}

  # Future: custom event filtering, transformation, etc.
end
```

The intent is the Ecto.Repo / Phoenix.Endpoint pattern — declare a connection module, get configurable defaults that subscribers don't have to repeat. Per-subscribe `wrap:` still wins per-call.

## Test plan

1. Unit tests for `method_for/1` on all generated event types.
2. Unit tests for the defguards — ensure each fires only on its namespace.
3. Unit tests for per-subscribe `wrap:` — verify the fn runs in connection process; verify the message arrives in the expected shape.
4. Unit tests for `%Unknown{}` fallback when a synthetic event arrives with an unknown method name.
5. Integration test: subscribe to `script.message` with a registered channel; verify the Elixir term arrives and SharedReferences round-trip via `RemoteValue.unwrap/1`.
6. Integration test: re-run existing autopilot/playbook integration tests against the new shape after migrating their pattern-matches.
7. CDDL-codegen verifier: a `mix bibbidi.events.verify_guards` task that confirms `Bibbidi.Events.Guards` covers every generated event module (catches codegen drift).

## File changes (estimated)

```
packages/bibbidi/
├── lib/bibbidi/
│   ├── connection.ex                # subscribe/4 + per-subscribe wrap
│   ├── events.ex                    # method_for/1
│   ├── events/
│   │   ├── unknown.ex               # NEW
│   │   ├── guards.ex                # NEW (codegen output)
│   │   └── script/
│   │       └── message.ex           # NEW (if codegen hasn't covered)
│   ├── remote_value.ex              # confirm unwrap/1 exists
│   └── ...
├── dev/mix/tasks/
│   ├── gen.ex                       # codegen emits Guards module
│   └── events.verify_guards.ex      # NEW
├── test/bibbidi/events/
│   ├── guards_test.exs              # NEW
│   ├── unknown_test.exs             # NEW
│   └── method_for_test.exs          # NEW
└── CHANGELOG.md                     # 0.4.0 entry
```

## Open questions

1. **`wrap:` shorthand atoms?** `wrap: :none` = `Function.identity`; `wrap: :tagged` = `fn s -> {:bibbidi_event, s} end`. Friendlier than always passing a fn. Or keep raw fn-only for simplicity. Recommendation: ship raw fn only; we can add atoms later if there's demand.
2. **RemoteValue decode location for `Script.Message`** — see "Decision" above. Confirmed: leave raw, provide `unwrap/1`.
3. **Compat shim for one release cycle?** Probably not — clean break is simpler given the small consumer set, and the migration is mechanical.
4. **`is_bibbidi_event/1` performance**: the union-of-guards form may compile to a long `or` chain. Worth measuring; if it's a hot path, fall back to a runtime `is_struct(msg) and module_in_namespace?(msg)` check via `Bibbidi.Events.namespaces/0` + `__struct__` introspection. Likely a non-issue.

## References

- `plans/bobbidi.md` — what bobbidi consumes from this refactor
- W3C BiDi spec: https://w3c.github.io/webdriver-bidi/
- Recent commit `8e4ce5f` — generated `Bibbidi.Types.*` modules and typed event structs (the foundation this builds on)
