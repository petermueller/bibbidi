# Adapter: Jido.Browser

[Jido](https://github.com/agentjido/jido) is an Elixir agent framework. **Jido.Browser** (local: `/Users/peter/work/jido_browser/`) is its way for Jido agents (code-driven OR LLM-driven) to control a browser. The maintainer is openly interested in bobbidi as an alternate adapter.

**Goal:** ship a `Jido.Browser.Adapter` implementation backed by bobbidi.

## The adapter contract

`Jido.Browser.Adapter` (`/Users/peter/work/jido_browser/lib/jido_browser/adapter.ex:1-128`):

**Required `@callback`s:**
- `start_session(opts) :: Session.t() | {:error, term}`
- `end_session(session) :: :ok | {:error, term}`
- `navigate(session, url, opts) :: {:ok, Session.t(), map} | {:error, term}`
- `click(session, selector, opts)` — same return shape
- `type(session, selector, text, opts)`
- `screenshot(session, opts) :: {:ok, Session.t(), %{bytes: binary, mime: String.t()}}`
- `extract_content(session, opts) :: {:ok, Session.t(), %{content: String.t(), format: atom}}`

**Optional callbacks:**
- `evaluate(session, expression, opts)` — covers ~70% of surface via JS shims (`jido_browser/lib/jido_browser.ex:236-327`)
- `command(session, action_atom, opts)` — catch-all for back/forward/reload/get_url/get_title/hover/focus/scroll/select_option/save_state/load_state/list_tabs/new_tab/switch_tab/close_tab/console/errors/snapshot/count/content/wait_for_selector/wait_for_navigation/get_text/get_attribute/is_visible

**Optional behaviour:** `Jido.Browser.PoolAdapter` (`jido_browser/lib/jido_browser/pool_adapter.ex:1-23`) for warm pools. **Skip for v1.**

The `Session` struct (`jido_browser/lib/jido_browser/session.ex:23-34`) carries `:id, :adapter, :connection, :runtime, :capabilities, :started_at, :opts`. The bobbidi adapter stores `Bobbidi.Session` in `connection`; pids for `Bibbidi.Connection` and `Bibbidi.Browser` go in `runtime`.

## Mapping to bobbidi

| Jido callback | Bobbidi mapping |
|---|---|
| `start_session/1` | Bring up `Bibbidi.Browser` + `Bibbidi.Connection`, `Bobbidi.Session.new/3 \|> ready/1`, return Jido session struct |
| `end_session/1` | Stop bibbidi connection + browser |
| `navigate/3` | `Bobbidi.Navigation.navigate/3` |
| `click/3` | `selector` → `Bobbidi.Locator.css/2` → `Bobbidi.click/2` |
| `type/4` | `selector` → locator → `Bobbidi.fill/3` (or `press_sequentially/3` if `mode: :sequential` in opts) |
| `screenshot/2` | `Bobbidi.Capture.screenshot/2` — return raw bytes (decoded from base64) + `mime: "image/png"` |
| `extract_content/2` | `:markdown` via `Bobbidi.Capture.markdown/2`; `:html` via `outer_html/2`; `:text` via locator + `Bobbidi.text/2` |
| `evaluate/3` | `Bobbidi.JS.eval/3` |
| `command/3` | Atom-keyed dispatch — see below |

## `command/3` dispatch table

Implementing `command/3` unlocks ~25 additional Jido operations. The bobbidi adapter implements native handlers where possible:

| Jido `command/3` action | Bobbidi mapping |
|---|---|
| `:back, :forward, :reload` | `Bobbidi.Navigation.{go_back, go_forward, reload}` |
| `:get_url, :get_title` | `Bobbidi.Navigation.{current_url, current_title}` |
| `:list_tabs, :new_tab, :switch_tab, :close_tab` | `Bobbidi.Tabs.*` |
| `:hover, :focus, :scroll, :select_option` | `Bobbidi.hover/2`, etc. |
| `:wait_for_selector, :wait_for_navigation` | `Bobbidi.Wait.*` |
| `:get_text, :get_attribute, :is_visible` | `Bobbidi.text/2`, `Bobbidi.attribute/3`, `Bobbidi.Expect.visible/2` |
| `:count, :content` | locator-based count; `Bobbidi.Capture.outer_html/2` |
| `:save_state, :load_state` | Cookies + storage. Partial parity initially; full state requires CDP. Document v1 limitations. |
| `:console, :errors` | Subscribe to `log.entryAdded`, accumulate, return |
| `:snapshot` | `Bobbidi.Snapshot.capture/2`. Open: index/ref scheme alignment (see open questions) |

**Note:** Jido's facade has a JS-fallback pattern (`jido_browser/lib/jido_browser.ex:707-713`) — for unimplemented `command/3` actions, it falls back to `evaluate/3` with a hand-written JS shim. **A bobbidi adapter that only implements `evaluate/3` automatically gets ~70% of the surface for free.** Worth implementing `command/3` for the fast paths but the floor is low.

## Where the adapter lives

Three options:

1. **Separate package `bobbidi_jido`** — cleanest. Maintained alongside bobbidi, runtime-depends on Jido. Both bobbidi and Jido.Browser stay independent.
2. **Inside bobbidi behind `Code.ensure_loaded?(Jido.Browser.Adapter)`** — one repo, awkward conditional.
3. **Inside `jido_browser`** — requires Jido maintainer to depend on bobbidi.

**Recommendation: Option 1** — `bobbidi_jido` as a thin glue package.

## Pool adapter — defer

`Jido.Browser.PoolAdapter` adds `start_pool/1`, `start_supervised_pool/1`, `stop_pool/1`. Bibbidi has no concept of warm pools. **Don't implement v1**; document as future work. Jido.Browser users who need pooling stick with the `AgentBrowser` default adapter, or implement pooling at their consumer layer.

## LLM tool surface — Jido handles it

Each Jido `Action` module (e.g., `Jido.Browser.Actions.Click`) IS the LLM tool definition. Jido (not Jido.Browser) reads schema/name/description and renders JSON Schema for LLMs. The bobbidi adapter doesn't duplicate this — it just provides the underlying execution. **All existing Jido actions work against any adapter.**

This is the win: a Jido agent using bobbidi's adapter gets the same tool-call surface as one using AgentBrowser, with the only difference being the underlying browser-control mechanism.

## Action / tool integration patterns (for reference)

Jido `Action`s are modules using `use Jido.Action, name: ..., schema: ...` exposing `run(params, context)`. Examples: Navigate (`actions/navigate.ex:15-44`), Click (`actions/click.ex:15-48`), Evaluate (`actions/evaluate.ex:16-43`), Snapshot (`actions/snapshot.ex:21-65`).

Pattern uniform across actions:

1. Validate params via the `schema:` keyword list (Jido handles).
2. `ActionHelpers.get_session(context)` (`lib/jido_browser/action_helpers.ex:30-36`) pulls the session from `context[:session] | context[:browser_session] | context[:tool_context][:session]`.
3. Call `Jido.Browser.<op>(session, ...)` (the flat facade).
4. Return `{:ok, %{status: "success", ..., session: updated_session}}` so `Jido.Browser.Plugin.transform_result/3` can re-thread the session into skill state.

The plugin (`lib/jido_browser/plugin.ex:75-131`) registers all actions, defines `signal_routes/1` mapping `"browser.click"` → `Click`, exposes them as agent tools, and tracks last-URL/seen-URLs in skill state.

## Open questions for the maintainer

1. **The "Offline" adapter referenced in conversation doesn't exist by that name in the repo.** Closest matches: `Vibium` (legacy WebDriver BiDi via Go binary, feature-frozen, README:268) and `Web` (chrismccord/web CLI, feature-frozen, README:269). Was that a reference to one of these, an in-progress branch, or a different concept? Worth confirming before designing against it.
2. **Snapshot/refs**: AgentBrowser's `@eN` ref scheme (`agent_browser.ex:242-249`) is tightly coupled to its native daemon. Should the bobbidi adapter implement a (possibly different) ref scheme tied to `Bobbidi.Snapshot.Element.index`, or skip refs entirely and return content + selectors? The latter is cleaner but loses parity with AgentBrowser-trained agents.
3. **`extract_content` markdown library**: AgentBrowser uses `Html2Markdown`. Hard requirement for parity, or does Jido.Browser delegate the choice to the adapter?
4. **State save/load**: full parity requires browser profile + localStorage. BiDi has cookies + (some) storage. Is partial parity acceptable v1?
5. **PoolAdapter**: blocking for the bobbidi adapter to be listed as default-capable, or genuinely optional?
6. **Adapter package location**: separate `bobbidi_jido`, inside `jido_browser` with a conditional dep, or inside `bobbidi` behind `Code.ensure_loaded?`?
7. **Bibbidi version**: Jido.Browser doesn't currently depend on bibbidi. The bobbidi-jido package will pin `~> 0.4` (per `plans/bibbidi-0.4.md`). Confirm this is fine.

## Discord / community

The user has Discord MCP access to "The Swarm: Elixir AI Collective", guild `1323353012235796550`. Useful for:
- Confirming the Jido maintainer's current direction on adapter shape
- Asking about the "Offline" adapter mystery
- Coordinating release timing if bobbidi-jido lands
- Surfacing bobbidi's existence to Jido.Browser users

## References

- Jido.Browser repo: `/Users/peter/work/jido_browser/`
- Adapter contract: `jido_browser/lib/jido_browser/adapter.ex`
- AgentBrowser implementation: `jido_browser/lib/jido_browser/adapters/agent_browser.ex`
- Jido facade with JS fallback paths: `jido_browser/lib/jido_browser.ex:236-327`
- `plans/bobbidi.md` — bobbidi capabilities this adapter consumes
- `plans/bibbidi-0.4.md` — events refactor required
