# Bobbidi — High-level browser actions on top of bibbidi

## What bobbidi is

Bobbidi is a higher-level browser-actions library built on top of [bibbidi](https://hex.pm/packages/bibbidi), the low-level W3C WebDriver BiDi protocol client for Elixir. It provides composable, reusable operations for common browser automation tasks — element finding via locators, actions with auto-wait, snapshot capture, recorder bridges, wait strategies — without imposing opinions about supervision or test-framework integration.

Bobbidi is a separate package from bibbidi so we can iterate on the convenience API without affecting the semver stability of the protocol library. Consumers like Cerberus, Wallaby driver shims, Jido.Browser adapters, autopilot/playbook successors, and workflow-orchestration frameworks depend on `bibbidi` for the connection + protocol and `bobbidi` for the orchestration layer.

## Naming

- **BIBBIDI** — **B**EAM **I**nterface to **B**rowsers with **Bi**Di (low-level protocol)
- **BOBBIDI** — **B**EAM **O**rchestration of **B**rowsers with **BiDi** (this library — actions / orchestration)
- **BOO** — reserved for a future package. Likely candidates: stealth plugins (`navigator.webdriver` patches, anti-fingerprint helpers), observability layers, or similar things this library should not absorb. Comes after BIBBIDI and BOBBIDI in the spell, like the rest of bobbidi's design — built carefully, in order.

## What bobbidi explicitly is NOT

- **Not a connection owner.** Bobbidi never starts `Bibbidi.Connection`. The connection is always passed in by the caller.
- **Not a process / GenServer / supervision tree.** All bobbidi types are pure data; all bobbidi functions are pure data-transforms or single bibbidi command dispatches. Consumers wrap bobbidi in their own processes if they want.
- **Not a test framework.** The Wallaby driver shim, Cerberus driver, PhoenixTest-style API, etc. are separate adapter packages that depend on bobbidi.
- **Not an LLM agent loop.** Tool definitions for LangChain/Sagents/Jido are the consumer's job. Bobbidi's `Snapshot` and `Locator` give them the substrate.
- **Not a stealth library.** A separate package (working name: BOO) handles `navigator.webdriver` patches, mutation-observer evasion, etc. Bobbidi avoids creating fingerprints by default but doesn't actively patch them.
- **Not a workflow definition / replay / repair framework.** A separate orchestration package (see `plans/workflow-orchestration.md`) builds on bobbidi.
- **Not an Op/Runner pipeline.** That lives in the orchestration framework. Bobbidi exports primitives that serialize cleanly so an Op layer above can be built.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  Consumer: Cerberus driver, Wallaby driver shim,         │
│  Jido.Browser adapter, workflow orchestration, RPA app   │
├──────────────────────────────────────────────────────────┤
│  BOBBIDI                                                 │
│  - Bobbidi.Session (pure data)                           │
│  - Bobbidi.Locator + Selector/Filter/Picker protocols    │
│  - Bobbidi.{Navigation, Input, Capture, Cookies, Tabs}   │
│  - Bobbidi.{Snapshot, Bridge, JS, Wait, Expect}          │
│  - Bobbidi.Recorded.* event structs                      │
│  - Helpers install (closure-only via channel)            │
├──────────────────────────────────────────────────────────┤
│  BIBBIDI ~> 0.4                                          │
│  - Bibbidi.Connection (WebSocket GenServer)              │
│  - Bibbidi.Commands.* / Bibbidi.Events.*                 │
│  - Bibbidi.Encodable protocol                            │
│  - script.message channel support                        │
│  - Raw event structs in subscriber mailbox; defguards    │
├──────────────────────────────────────────────────────────┤
│  Browser (Firefox, Chrome via BiDi)                      │
└──────────────────────────────────────────────────────────┘
```

Bobbidi requires bibbidi 0.4+ — see `plans/bibbidi-0.4.md` for the events refactor it depends on.

## Core abstractions

### `Bobbidi.Session` — pure data

```elixir
%Bobbidi.Session{
  conn: pid_or_name,                   # required: Bibbidi.Connection
  context: ctx_id,                     # required: BrowsingContext id
  user_context: ucx_id,                # optional: BiDi user context
  default_timeout: 30_000,             # ms — actions
  default_assertion_timeout: 5_000,    # ms — Bobbidi.Expect matchers
  default_match: :strict,              # :strict | :first | :all
  test_id_attr: "data-testid",         # used by the TestId selector
  helpers: :preload | :inline | :none,
  helpers_handle: shared_ref | nil,    # set after preload install
  helpers_channel: channel_id | nil,   # set after preload install
  scope: nil_or_locator,               # current locator scope (within/frame)
  meta: %{}                            # adapter-private extension space
}
```

The session is created by the consumer. Bobbidi never starts a connection.

```elixir
{:ok, conn} = Bibbidi.Connection.start_link(url: ws_url)
{:ok, _caps} = Bibbidi.Session.new(conn)            # bibbidi-level session
{:ok, %{contexts: [%{context: ctx} | _]}} =
  Bibbidi.Commands.BrowsingContext.get_tree(conn)

session = Bobbidi.Session.new(conn, ctx)
{:ok, session} = Bobbidi.Session.ready(session)     # installs helpers if mode allows
```

`Bobbidi.Session.ready/1` is idempotent. It installs the closure-only helpers (see below) and captures the resulting handle on the session struct. Realm changes (cross-document navigation) make the captured handle stale; bobbidi listens for `script.realmCreated` and re-runs install for the new realm, updating the session's `helpers_handle`. Consumers that don't subscribe to realm-creation events are responsible for calling `ready/1` again after navigations.

Many actions return `{:ok, session, result}` so the (possibly mutated) session can be threaded forward. State that mutates: `helpers_handle` (after re-install), `scope` (under `Locator.within`), `meta` (adapter use).

### `Bobbidi.Locator` — struct + protocols

The user-facing identity for "an element to act on." Lazy: it describes how to find, not what was found. Re-resolves on every action — staleness is invisible to the user.

```elixir
%Bobbidi.Locator{
  session: %Bobbidi.Session{},
  steps: [
    %Bobbidi.Step.Match{kind: %Bobbidi.Selector.Role{role: "button", name: "Submit"}},
    %Bobbidi.Step.Filter{kind: %Bobbidi.Filter.HasText{text: "Pay now"}},
    %Bobbidi.Step.Filter{kind: %Bobbidi.Filter.Visible{}},
    %Bobbidi.Step.Pick{kind: %Bobbidi.Picker.First{}}
  ],
  match: :strict     # overrides session default if set
}
```

Each step is dispatched via three protocols:

```elixir
defprotocol Bobbidi.Selector do
  @spec resolve(t, scope :: [shared_ref], session) :: {:ok, [shared_ref]} | {:error, term}
  def resolve(struct, scope, session)
end

defprotocol Bobbidi.Filter do
  @spec apply(t, [shared_ref], session) :: {:ok, [shared_ref]} | {:error, term}
  def apply(struct, refs, session)
end

defprotocol Bobbidi.Picker do
  @spec pick(t, [shared_ref]) :: {:ok, [shared_ref]} | {:error, term}
  def pick(struct, refs)
end
```

Custom selectors / filters / pickers = define your own struct + protocol implementation. No registry, no `Application.put_env`, no global state. Capybara's `add_selector` model — but via Elixir-idiomatic protocol dispatch, not runtime registration.

**Built-in selectors (Phase 1):**
- `Css{value}` → BiDi `locateNodes` with CSS
- `Xpath{value}` → BiDi `locateNodes` with XPath
- `InnerText{text, exact}` → BiDi `locateNodes` with innerText
- `AccessibilityRole{role, name}` → BiDi `locateNodes` with accessibility kind
- `TestId{value}` → uses session `test_id_attr` to compose CSS
- `Coords{x, y}` → virtual locator; resolves to a viewport position, not a SharedReference (actions handle this case specially)
- `SnapshotIndex{snapshot, index}` → look up snapshot element by index, return its SharedReference if any (or error if stale)
- `SharedRef{ref}` → escape hatch; returns the ref directly

**Built-in filters (Phase 1):**
- `HasText{text, exact}` — runs in helpers
- `Has{child_locator}` — child locator must resolve to ≥1 descendant
- `Visible{}` — actionability-Visible only
- `Enabled{}` — actionability-Enabled only
- `Editable{}` — actionability-Editable only
- `Attribute{name, value}` — DOM attribute match

**Built-in pickers (Phase 1):**
- `First{}`, `Last{}`, `Nth{n}`, `All{}`

**Composition API** (pipe-friendly builders):

```elixir
session
|> Locator.role("button", name: "Submit")
|> Locator.has_text("Pay now")
|> Locator.visible()
|> Locator.first()

# Within scoping:
session
|> Locator.test_id("checkout")
|> Locator.within(fn checkout ->
  checkout |> Locator.role("button")
end)

# Frame scoping (rebinds context):
session
|> Locator.frame(Locator.css("iframe.payment"))
|> Locator.role("button", name: "Pay")
```

`Locator.within/2` pushes a scope step; subsequent selectors resolve within it. `Locator.frame/2` is `within` plus rebinding the BrowsingContext for nested-frame navigation.

**Strict mode is the default.** Resolving a locator that matches >1 element returns `{:error, %Bobbidi.Error{reason: :strict_violation, count: n}}`. Override per-call: `Bobbidi.click(locator, match: :first)`. Override per-session: `Bobbidi.Session.new(..., default_match: :first)`.

### Helpers mode — closure-only handle install

Bobbidi never sets a `window.__bobbidi` global. Helpers are installed via a preload script that captures them in an IIFE closure and emits the helpers object's SharedReference (with `ownership: "root"`) on a `script.message` channel:

```js
// Preload script body — runs on every new document
((channel) => {
  // Helpers live ONLY in this IIFE closure.
  // Not on window. Not on document. Page JS can't reach them.
  const helpers = {
    checkActionable: (el, opts) => { /* visible + stable + enabled + hit-test */ },
    captureSnapshot: (opts) => { /* DOM walk → list of interactive elements */ },
    filter: { hasText: ..., visible: ..., has: ... },
    extractMarkdown: (el) => { ... }
  };

  channel({type: "helpers_ready", helpers});

  // Recorder listeners on the same channel:
  document.addEventListener('click', (e) => {
    channel({type: "recorded.click", x: e.clientX, y: e.clientY, target: e.target});
  }, true);
  // ...input, navigation, focus, blur, etc.
})(arguments[0]);
```

Subsequent helper calls go through `Script.callFunction` with `target: helpers_handle`, e.g.:

```elixir
Bibbidi.Commands.Script.call_function(
  conn,
  "function(el, opts) { return this.checkActionable(el, opts) }",
  this: helpers_handle,
  arguments: [target_el, click_opts],
  await_promise: false,
  context: ctx
)
```

The page realm has nothing to find. `Object.keys(window)` shows nothing bobbidi-shaped.

**Helpers modes:**

- `:preload` (default) — closure-only handle install on `Session.ready/1`. Re-installed on realm change.
- `:inline` — every action ships its full JS + arguments. No setup, no persistent handle. Higher per-call cost (~1KB JS per call) but stateless. Useful for stealth scenarios that distrust preload scripts entirely.
- `:none` — bobbidi makes no helper-requiring calls. Runtime-rejects `Bobbidi.click(locator)` (auto-wait), `Bobbidi.Snapshot.capture/2`, locator filters, etc., with `{:error, %Bobbidi.Error{reason: :requires_helpers, alternatives: [...]}}`. Used by stealth setups that have installed their own undetected helpers.

Channel ID is randomized per session by default. The only persistent fingerprint surface is the preload script body during execution; everything that survives the IIFE is closure-captured.

**Use cases motivating the modes:**

| Scenario | Mode |
|---|---|
| Cerberus testing the team's own app | `:preload` |
| Wallaby testing the team's own app | `:preload` |
| Internal tool automation | `:preload` |
| LLM agent against customer-portal automation (CloudFlare/Akamai-protected) | `:inline` |
| Workflow replay against vendor SaaS with bot detection | `:inline` |
| Stealth setup with custom undetected helper realm | `:none` |

## Module organization

Module names broadcast which side of the BiDi-native vs. JS-injected line each function falls on:

| Module | BiDi-native? | Helpers required? |
|---|---|---|
| `Bobbidi.Navigation` | Yes (`BrowsingContext.{Navigate, Reload, TraverseHistory}`) | No |
| `Bobbidi.Input` | Yes (`Input.PerformActions`) | No |
| `Bobbidi.Cookies` | Yes (`Storage.{GetCookies, SetCookie, DeleteCookies}`) | No |
| `Bobbidi.Tabs` | Yes (`BrowsingContext.{Create, Close, GetTree, Activate}`) | No |
| `Bobbidi.Capture` | Mixed — screenshot/print native; markdown helpers | Sometimes |
| `Bobbidi.Locator` | Selectors mostly native; filters helpers-only | Mixed |
| `Bobbidi.Wait` | `for_url`/`for_load_state` native; `for_actionable` helpers | Mixed |
| `Bobbidi.Snapshot` | No — DOM walking | Always |
| `Bobbidi.Bridge` | No — preload + channel | Always |
| `Bobbidi.JS` | No — escape hatch | Always |
| `Bobbidi.Expect` | Mixed — URL/load native; element-state helpers | Mixed |

Each function's `@doc` declares which BiDi commands and which helper methods it invokes. A `@bobbidi_uses` attribute drives docs auto-generation and a `Bobbidi.requires_helpers?(fn)` introspection helper.

`helpers: :none` mode rejects helper-requiring calls at the call site with errors that name BiDi-native alternatives.

## Phase 1 — minimum coherent cut

### 1.1 Session & Locator core

- `Bobbidi.Session` struct + `new/3`, `ready/1`, `with_scope/2`
- `Bobbidi.Locator` struct + builder functions
- All Phase-1 selectors / filters / pickers + protocol impls
- Strict-mode default with per-call/per-session override
- `Locator.resolve(loc) :: {:ok, [shared_ref] | %Bobbidi.Element{}} | {:error, _}`
- `Bobbidi.Element` enriched: `{shared_ref, context, selector, bbox, role, text}` — populated when known, `nil` otherwise. Enables coord-fallback when refs go stale; role+text enable selector-strategy generation at record time.

### 1.2 Helpers install (closure-only via channel)

- `Bobbidi.Session.ready/1` installs preload script with closure-captured helpers + channel-emitted handle
- Listens for `helpers_ready` channel message and stashes `helpers_handle` + `helpers_channel` on the session
- Re-install on realm change (subscribe to `script.realmCreated`; helper consumes; re-runs install for new realm)
- `helpers: :inline` and `:none` modes implemented end-to-end

### 1.3 Direct API: navigation, input, capture, cookies, tabs

`Bobbidi.Navigation`:
- `navigate(session, url, opts)` — `wait: :complete | :interactive | :none`
- `reload(session, opts)`
- `go_back(session)`, `go_forward(session)`, `traverse_history(session, delta)`
- `current_url(session)`, `current_title(session)`

`Bobbidi.Input` (BiDi-native, no helpers required):
- `click_at(session, x, y, opts)` — pointer click at viewport coords; `button:`, `modifiers:`
- `type_keys(session, text, opts)` — page-level keyboard input via `Input.PerformActions`
- `press_key(session, key, opts)` — uses `Bibbidi.Keys` named atoms (`:enter`, `:tab`, `:escape`, etc.)
- `scroll_at(session, x, y, dx, dy)` — wheel input
- `hover_at(session, x, y)` — pointer move
- `drag(session, from_xy, to_xy, opts)` — pointer down/move/up

`Bobbidi.Capture`:
- `screenshot(session, opts)` — returns `%{bytes, mime}` (raw bytes, not base64)
- `print(session, opts)` — PDF
- `outer_html(session, opts)` — `:scope` opt for sub-tree

`Bobbidi.Cookies`:
- `get(session, opts)`, `set(session, cookie, opts)`, `delete(session, opts)`

`Bobbidi.Tabs`:
- `list(session)`, `new(session, opts)`, `switch(session, tab_id)`, `close(session, tab_id)`
- `current(session)` returns the active tab id

### 1.4 High-level actions on Locator (auto-wait by default)

All Phase-1 actions auto-wait on actionability checks (Visible + Stable + Enabled + ReceivesEvents) before firing. Per-call `force: true` skips checks; `trial: true` runs checks without firing the action.

- `Bobbidi.click(locator, opts)` — runs all four actionability checks
- `Bobbidi.fill(locator, value, opts)` — single setValue + dispatched `input`/`change` events; auto-wait skips Stable
- `Bobbidi.press_sequentially(locator, text, opts)` — char-by-char with `delay:`, for autocompleters/contenteditable
- `Bobbidi.hover(locator, opts)`, `Bobbidi.scroll_into_view(locator, opts)`
- `Bobbidi.select_option(locator, value_or_label_or_index, opts)`
- `Bobbidi.upload(locator, file_paths, opts)` — DataTransfer JS shim; documented as best-effort. Real upload requires CDP fallback or chromium-bidi's file-upload extension.
- `Bobbidi.check(locator, opts)`, `Bobbidi.uncheck(locator, opts)`
- `Bobbidi.text(locator, opts)`, `Bobbidi.attribute(locator, name, opts)`, `Bobbidi.value(locator, opts)`, `Bobbidi.bounding_box(locator)`

All actions take per-call `timeout:` and `match:` opts.

### 1.5 Wait primitives

`Bobbidi.Wait`:
- `for_url(session, predicate, opts)` — native: filters `browsingContext.load`/`fragmentNavigated`
- `for_load_state(session, state, opts)` — `:load | :domcontentloaded | :network_idle`. `:network_idle` reduces over `network.beforeRequestSent` + `network.responseCompleted`
- `for_navigation(session, opts)` — convenience wrapping `for_load_state` + URL change
- `for_actionable(locator, opts)` — helpers required; default mode is `:browser` (Promise loop with `await_promise: true`, one round-trip); `mode: :elixir` polls Elixir-side (one round-trip per tick) for cancellation/per-tick telemetry

### 1.6 Expect matchers (web-first assertions)

`Bobbidi.Expect` — auto-retrying matchers, default timeout 5_000 ms (lower than action timeouts; assertions should be tighter):

- `visible(locator, opts)` — locator resolves to a visible element
- `hidden(locator, opts)`, `attached(locator, opts)`, `detached(locator, opts)`
- `text(locator, expected, opts)` — exact / `:regex` / `:contains`
- `value(locator, expected, opts)`
- `count(locator, n, opts)` — locator must resolve to exactly n elements
- `enabled(locator, opts)`, `disabled(locator, opts)`, `checked(locator, opts)`, `unchecked(locator, opts)`
- `url(session, predicate, opts)` — native, filter on `browsingContext.load` events

Each returns `:ok | {:error, %Bobbidi.Error{}}`. Pure return shape — soft-fail behaviour is the consumer's job (LLM tool wrappers translate to whatever shape they want; per F10 in the research findings).

### 1.7 Snapshot

`Bobbidi.Snapshot`:
- `capture(session, opts) :: {:ok, session, %Snapshot{}}` returning:

```elixir
%Bobbidi.Snapshot{
  generation: monotonic_int,
  captured_at: timestamp,
  context: ctx,
  elements: [
    %Bobbidi.Snapshot.Element{
      index: int,
      tag: "button",
      role: "button" | nil,
      accessible_name: "Submit" | nil,
      text: "Submit",
      bbox: {x, y, w, h},
      selector: "..." | nil,
      attrs: %{"id" => "...", "data-testid" => "..."},
      visible: bool,
      enabled: bool,
      shared_ref: "..." | nil
    }
  ]
}
```

- `Bobbidi.Locator.snapshot_index(session, snapshot, idx)` builds a locator that resolves to that element. Stale snapshots return `{:error, :stale_snapshot}`.

The snapshot is the LLM tool-call substrate AND a structured page-state dump for debugging/recording. Indexes address the snapshot for LLM tool calls (`{"click": {"index": 42}}`); `selector + bbox + role + text` enable replay/repair.

### 1.8 Bridge for recorder events

`Bobbidi.Bridge`:
- `install(session, opts)` — registers a `script.message` channel id, installs a recorder preload script, returns `{:ok, %Bobbidi.Bridge.Handle{channel_id, preload_id}}`. By default uses the session's helpers channel; can use a separate channel.
- `uninstall(handle)` — removes preload, unregisters
- `subscribe(session, handle, pid, opts \\ [])` — calls `Bibbidi.Connection.subscribe(conn, "script.message", pid, wrap: &Bobbidi.Bridge.maybe_decode/1)`. The wrap fn returns a `%Bobbidi.Recorded.X{}` struct if the message matches the bridge's channel; passthrough otherwise. User can opt out of auto-decode by passing their own `wrap:`.
- `decode(message) :: {:ok, %Recorded.X{}} | :not_recorded` — pure function for users who'd rather decode in their own pid.

`Bobbidi.Recorded.*` structs (Phase 1 set):
- `%Click{ts, target, x, y, modifiers}`
- `%Input{ts, target, value, sensitive}`
- `%Submit{ts, target}`
- `%Navigation{ts, url, kind}` — `kind: :pushstate | :replacestate | :load | :popstate`
- `%KeyPress{ts, target, key, modifiers}`
- `%FocusChange{ts, target_in, target_out}`

`target` is `%Bobbidi.Recorded.Target{tag, selector, accessible_name, text, shared_ref}` populated from the channel-delivered DOM node reference.

`defguard is_bobbidi_recorded_event(msg)` matches any `%Bobbidi.Recorded.*{}`.

### 1.9 JS escape hatch

`Bobbidi.JS`:
- `eval(session, expr, opts)` — `Script.evaluate`, returns RemoteValue unwrapped to Elixir term
- `eval_json(session, expr, opts)` — assumes JS returns a JSON string, parses
- `call(session, fn_decl, opts)` — `Script.callFunction` with `target:`, `arguments:`, `await_promise:` opts

Auto-wait does NOT apply to `Bobbidi.JS.*`. Heavily documented.

### 1.10 Telemetry

`[:bobbidi, :action, :start | :stop | :exception]` events per high-level action, with `action_name`, `locator_summary`, `session_id`, `helpers_mode`, `bidi_commands`, timing. Wraps bibbidi's protocol-level telemetry rather than replacing it.

### Implementation order within Phase 1

Suggested sequencing for the next session(s) writing this:

1. **Foundations.** `%Bobbidi.Error{}`, `%Bobbidi.Session{}`, `%Bobbidi.Element{}`. Pure data, no behaviour yet.
2. **JS escape hatch.** `Bobbidi.JS.{eval, eval_json, call}`. Required by everything else.
3. **Native actions.** `Bobbidi.Navigation.*`, `Bobbidi.Input.*`, `Bobbidi.Cookies.*`, `Bobbidi.Tabs.*`, `Bobbidi.Capture.{screenshot, print, outer_html}`. No helpers needed.
4. **Locator scaffolding.** `%Locator{}`, `%Step.*{}`, the three protocols. Implement `Selector.Css`, `Selector.Xpath`, `Selector.SharedRef`, `Picker.First`, `Picker.Nth`. `Locator.resolve/1` works for native-only locators.
5. **Helpers preload.** Build the preload-script JS asset (actionability + filter helpers). `Session.ready/1` installs and captures handle. Realm-change re-install path.
6. **Helpers-dependent locator components.** `Selector.AccessibilityRole`, `Selector.InnerText`, `Selector.TestId`, `Filter.HasText`, `Filter.Visible`, `Filter.Has`. `Locator.within/2`.
7. **Auto-wait actionability checks.** `Bobbidi.Wait.for_actionable/2` (browser-mode by default).
8. **High-level actions.** `Bobbidi.click/2`, `Bobbidi.fill/3`, etc., wrapping Locator + actionability + Input.
9. **Wait/Expect.** `Bobbidi.Wait.{for_url, for_load_state, for_navigation}`. `Bobbidi.Expect.*`.
10. **Snapshot.** Helpers JS + `Bobbidi.Snapshot.capture/2` + `Selector.SnapshotIndex`.
11. **Bridge.** Recorder JS + channel decode + `Recorded.*` structs + `Bobbidi.Bridge.{install, subscribe, decode}`.
12. **Telemetry.** Wrap actions with `:telemetry.span/3`.
13. **Frame scoping.** `Locator.frame/2` and the session "exit frame" helper.
14. **Inline mode.** Implement `helpers: :inline` by inlining each helper's JS at call sites. Fall-back tested against the same test suite.
15. **None mode.** Runtime gate that rejects helper-requiring calls; error messages name native alternatives.

Steps 1-3 are bibbidi-only and can land before bibbidi 0.4 is finished if necessary (with a compat layer for the events shape). 4 onwards needs bibbidi 0.4.

## Phase 2

- **`Bobbidi.Network`** — `route(session, pattern, fn)`, `on_request(session, fn)`, `on_response(session, fn)`, `wait_for_response(session, predicate, opts)`. Uses `network.beforeRequestSent` + `continueRequest`/`provideResponse`.
- **`Bobbidi.Selector.Strategy`** — pure functions `from_element(snapshot_element) :: [{kind, value, priority}]` generating `[id, test_id, aria_label, role+text, text_exact, placeholder, xpath]` strategies for record-time use. Phase-1-adjacent if `plans/workflow-orchestration.md` consumers want it sooner.
- **More wait strategies**: `for_event(session, method, predicate)`, `for_function(session, expr)`, `for_response`, `for_request`.
- **`Bobbidi.Accessibility.tree(session, opts)`** — wraps `BrowsingContext.LocateNodes` accessibility kind for full AX tree; alternative element identification surface for LLM agents.
- **Channel-based derived events**: bobbidi-installed `MutationObserver` / `IntersectionObserver` that emit `%Bobbidi.Derived.*{}` on a channel — `%Derived.ElementVisible{}`, `%Derived.DomStable{}` (the `NetworkIdle` derived event remains Elixir-side).
- **`Bobbidi.Capture.markdown(session, opts)`** — clean text extraction with lazy-load handling.
- **File upload via real BiDi extensions** where chromium-bidi exposes them; DataTransfer shim remains as documented fallback.

## Phase 3+

- Elaborate dialog handling — `expect_dialog/2` returning a ref + `handle_dialog/3`. The Wallaby-style "callback that triggers the dialog inside" is supported as a wrapper at the adapter layer.
- Multiplexed waits — one preload-side observer serving many concurrent waits.
- Test-fixture utilities — `Bobbidi.Fixture` for HTML templating in tests.
- WebDriver-Classic compatibility shims for migrating Wallaby-Selenium tests (separate package?).

## Out of scope (forever) for bobbidi proper

- **Connection ownership / supervision.** Belongs in the consumer.
- **Browser process lifecycle.** `Bibbidi.Browser` already does this; bobbidi assumes a running session.
- **Pool management.** Wallaby and Cerberus solve this at their layer.
- **LLM tool definitions.** Snapshot + Locator gives them everything they need.
- **Bot-detection patches.** Separate library (BOO).
- **Workflow record/replay/repair framework.** See `plans/workflow-orchestration.md`.
- **Op/Runner pipeline.** Same — orchestration territory. The constraint that drops on bobbidi: all actions accept and return data that's fully serializable (locators, sessions, snapshots, recorded events — no opaque pids in nested fields, no anonymous functions in step descriptions).

PhoenixTest doesn't need its own adapter — it's in-process and doesn't drive a browser. The path for PhoenixTest-style API on a real browser is via Cerberus, which already covers it.

## Testing strategy

### Unit tests (`mix test`)

Use `Bibbidi.MockTransport` (already exists). Test:
- Locator resolution emits the expected BiDi commands in the expected order
- Auto-wait actionability checks fire before action commands
- Strict-mode violations return correct error structs
- Helpers install captures + reuses the handle
- Channel decode functions produce correct `Recorded.*` structs from sample channel payloads
- `helpers: :none` mode rejects calls with the right error
- Per-subscribe `wrap:` from bibbidi 0.4 is honored by `Bobbidi.Bridge.subscribe`

### Integration tests (`mix test --include integration`)

Real Firefox + Chrome via BiDi. Static HTML fixtures served by Bandit. Test:
- Navigate → fill → click → assert
- Auto-wait works (deliberately delayed elements)
- Snapshot capture against pages with various interactive elements
- Recorder bridge captures clicks/inputs/navigations across page reloads
- Channel-delivered helpers handle survives navigations (re-install path)
- Frame switching
- Tab management
- File upload (DataTransfer shim)
- `helpers: :inline` matches `helpers: :preload` behaviour

### Acceptance tests against real consumers

- Port `packages/autopilot` and `packages/playbook` to use bobbidi. Treat awkwardness as design feedback. Their JS soup collapses dramatically; if it doesn't, the API is wrong.
- Port `Cerberus.Driver.Browser.BiDi` from raw `Bibbidi.Connection.send_command/4` to bobbidi. See `plans/adapter-cerberus.md`.

## File manifest

```
packages/bobbidi/
├── lib/
│   ├── bobbidi.ex                       # high-level actions + module docs
│   └── bobbidi/
│       ├── session.ex                   # struct + ready/1 + with_scope/2
│       ├── locator.ex                   # struct + builder fns + resolve/1
│       ├── element.ex                   # %Bobbidi.Element{}
│       ├── error.ex                     # %Bobbidi.Error{}
│       ├── selector/
│       │   ├── css.ex
│       │   ├── xpath.ex
│       │   ├── inner_text.ex
│       │   ├── accessibility_role.ex
│       │   ├── test_id.ex
│       │   ├── coords.ex
│       │   ├── snapshot_index.ex
│       │   └── shared_ref.ex
│       ├── filter/
│       │   ├── has_text.ex
│       │   ├── has.ex
│       │   ├── visible.ex
│       │   ├── enabled.ex
│       │   ├── editable.ex
│       │   └── attribute.ex
│       ├── picker/
│       │   ├── first.ex
│       │   ├── last.ex
│       │   ├── nth.ex
│       │   └── all.ex
│       ├── navigation.ex                # navigate, reload, go_back, ...
│       ├── input.ex                     # click_at, type_keys, ...
│       ├── capture.ex                   # screenshot, print, outer_html
│       ├── cookies.ex
│       ├── tabs.ex
│       ├── snapshot.ex                  # capture/2 + %Snapshot{} + %Snapshot.Element{}
│       ├── bridge.ex                    # install/2, subscribe/3, decode/1
│       ├── js.ex                        # eval/2, eval_json/2, call/2
│       ├── wait.ex                      # for_url, for_load_state, for_actionable
│       ├── expect.ex                    # web-first matchers
│       ├── recorded/
│       │   ├── click.ex
│       │   ├── input.ex
│       │   ├── submit.ex
│       │   ├── navigation.ex
│       │   ├── key_press.ex
│       │   ├── focus_change.ex
│       │   └── target.ex
│       ├── helpers/
│       │   ├── preload.ex               # builds the IIFE preload script
│       │   ├── inline.ex                # builds inline JS for actionability checks
│       │   └── js_assets/               # raw .js files compiled in
│       ├── guards.ex                    # is_bobbidi_event/1, is_bobbidi_recorded_event/1, ...
│       └── telemetry.ex
├── test/
│   ├── test_helper.exs
│   ├── support/
│   │   └── mock_helpers.ex
│   ├── bobbidi/
│   │   ├── session_test.exs
│   │   ├── locator_test.exs
│   │   ├── selector/...
│   │   ├── filter/...
│   │   ├── snapshot_test.exs
│   │   ├── bridge_test.exs
│   │   ├── wait_test.exs
│   │   ├── expect_test.exs
│   │   └── ...
│   └── integration/
│       ├── navigation_test.exs
│       ├── auto_wait_test.exs
│       ├── snapshot_test.exs
│       ├── recorder_test.exs
│       └── fixtures/
│           └── *.html
├── mix.exs
├── README.md
├── CHANGELOG.md
└── LICENSE.md
```

## Open questions

1. **Cross-browser actionability.** Stable-bbox check requires `requestAnimationFrame`; some browsers fire rAF differently in headless mode. Test matrix needs Firefox-headed, Firefox-headless, Chrome-headed, Chrome-headless.
2. **Channel sharing vs. dedicated channels.** Helpers + recorder + derived events on one channel (simpler, single decode dispatch) or three channels (cleaner separation, slightly more setup). Default to one; offer split via opts.
3. **Selector composability vs. `locateNodes` round-trip count.** A `Locator.role().has_text().first()` chain may resolve via one `locateNodes` (if BiDi supports the combination) or multiple round-trips. Worth measuring; might motivate a "compile to one round-trip when possible" optimization in Phase 2.
4. **`Bobbidi.Element` lifetime when navigating.** When user holds an `Element` struct with a `shared_ref` and the page navigates, the ref goes stale. v1 requires user to re-locate. Phase 3 ergonomic win: auto-refresh on next use via embedded selector.
5. **Iframe scope escape.** `Locator.frame/2` rebinds context; `Locator.session(loc).default_frame()` for "go back to top" is the candidate. Confirm in design.
6. **`Bobbidi.Capture.markdown` phase.** Phase 1 if helpers extraction is small; Phase 2 if it needs a real markdown JS library.

## References

- `plans/bibbidi-0.4.md` — events refactor bobbidi depends on
- `plans/adapter-cerberus.md`
- `plans/adapter-jido-browser.md`
- `plans/adapter-wallaby.md`
- `plans/workflow-orchestration.md`
