# Adapter: Wallaby (and Wallabidi)

[Wallaby](https://github.com/elixir-wallaby/wallaby) (local: `/Users/peter/work/wallaby/`) is the canonical Elixir browser-test framework. **Wallabidi** (local: `/Users/peter/work/wallabidi/`) is a fork that added a WebDriver BiDi adapter.

**Goal:** bobbidi-on-bibbidi should be a viable replacement for Wallabidi's BiDi adapter, AND bobbidi should be plausible as a Wallaby driver via a separate adapter package.

The lift is bigger than for Cerberus or Jido. Wallaby's driver behaviour is `@moduledoc false` (private), Wallabidi forked rather than extended, and the element/session model assumes WebDriver-Classic semantics that don't translate cleanly to BiDi.

## Recommendation: bobbidi is what a Wallaby driver wraps, not the driver itself

Bobbidi remains protocol-shaped: `(session, ...)` → `{:ok, _} | {:error, _}`. A separate **`bobbidi_wallaby`** package implements `@behaviour Wallaby.Driver` on top.

This avoids polluting bobbidi with WebDriver-Classic concerns (element URLs, session HTTP endpoints, hackney pools) that don't exist in BiDi.

## Wallaby driver behaviour

`/Users/peter/work/wallaby/lib/wallaby/driver.ex` — private `@moduledoc false` behaviour. Callbacks:

- **Lifecycle**: `start_session/1`, `end_session/1`
- **Navigation**: `visit/2`, `current_url/1`, `current_path/1`, `page_title/1`, `page_source/1`
- **Cookies**: `cookies/1`, `set_cookie/3,4`
- **Windows**: `window_handle/1`, `window_handles/1`, `focus_window/2`, `close_window/1`, `maximize_window/1`, `get_window_size/1`, `set_window_size/3`, `get_window_position/1`, `set_window_position/3`
- **Frames**: `focus_frame/2`, `focus_parent_frame/1`
- **Dialogs**: `accept_alert/2`, `accept_confirm/2`, `accept_prompt/3`, `dismiss_confirm/2`, `dismiss_prompt/2`
- **Element ops**: `click/1`, `clear/1`, `set_value/2`, `text/1`, `attribute/2`, `displayed/1`, `selected/1`, `send_keys/2`
- **Queries**: `find_elements/2` taking `Wallaby.Query.compiled() :: {:css, _} | {:xpath, _}`
- **Scripting/screenshot**: `execute_script/3`, `execute_script_async/3`, `take_screenshot/1`

**Undeclared functions used in `Wallaby.Browser` directly** (not in the behaviour but called via `driver.<fn>` — a real driver must implement these de facto):
`hover`, `double_click`, `button_down/up`, `move_mouse_to`, `touch_down/up/move/scroll`, `tap`, `element_size`, `element_location` — see `wallaby/lib/wallaby/browser.ex:803,815,847`.

Wallabidi additionally extended with `release_server_session/1` (optional callback, `wallabidi/lib/wallabidi/driver.ex:35-37`).

## Wallabidi's BiDi adapter — what bobbidi_wallaby supersedes

Wallabidi's `Wallabidi.Chrome` (`wallabidi/lib/wallabidi/chrome.ex`, ~387 lines) + `Wallabidi.BiDiClient` (~1814 lines) implement:

- Pool of chromium-bidi WebSocket slots
- Own WebSocket client (`websocket_client.ex`) and command builder (`commands.ex`, ~475 lines)
- Element identity via `bidi_shared_id` plus a fragile WebDriver-id fallback through process dictionary (`bidi_client.ex:577-594`)
- Click via JS `el.click()` with scroll-into-view + focus (`bidi_client.ex:228`) — *bobbidi's pointer-action click is more faithful to user input*
- Browsing-context resolution via process dictionary (`bidi_client.ex:18-22`) — process state held implicitly
- Stale-realm retries with manual backoff (`bidi_client.ex:496-516`)
- Visibility computation in JS (`bidi_client.ex:418-455`)
- File upload via `DataTransfer` JS shim — real BiDi has no upload command, so the file content is empty bytes
- LiveView-specific helpers: `await_liveview_connected`, `prepare_patch`/`await_patch`/`drain_patches`, `settle`, `intercept_request` (`bidi_client.ex:1343-1738`)
- An additional protocol abstraction `Wallabidi.Protocol` (`lib/wallabidi/protocol.ex`) with callbacks `eval/2`, `eval_async/3`, `current_url/1`, `subscribe/2`, `unsubscribe/2`, `wire_methods/1`. CDP and BiDi implementations both exist.

Most of this collapses against bobbidi:

- **Pool**: out of scope for bobbidi; bobbidi_wallaby manages session-per-test the way Wallaby's `SessionStore` does for other drivers.
- **WebSocket client / command builder**: bobbidi (and bibbidi 0.4) supersede these.
- **Element identity**: `Bobbidi.Element` carries `shared_ref + selector + bbox`. The WebDriver-id fallback goes away.
- **Click via pointer actions**: bobbidi's default — more faithful, penetrates cross-origin iframes.
- **Process-dictionary state**: replaced by `Bobbidi.Session` mutable returns. This is a real win — the Wallabidi `Process.put`-based focus tracking is a maintenance smell.
- **Stale-realm retries**: bobbidi's locator re-resolves on every action, eliminating most stale-ref scenarios; explicit retry primitive available in `Bobbidi.Wait`.
- **Subscribe**: `Wallabidi.Protocol.BiDi.subscribe` (`protocol/bidi.ex:43-73`) already does the F3 atomic subscribe (server-side `session.subscribe` + WS-side route). Bobbidi's `Bobbidi.Events.subscribe/3` is the same shape.

## Mapping driver callbacks to bobbidi

| Wallaby callback | Bobbidi mapping |
|---|---|
| `start_session/1` | Set up bibbidi connection, `Bobbidi.Session.new/3 \|> ready/1`, return `%Wallaby.Session{}` with bobbidi session embedded |
| `end_session/1` | Tear down connection |
| `visit/2` | `Bobbidi.Navigation.navigate/3` |
| `current_url/1`, `current_path/1`, `page_title/1` | `Bobbidi.Navigation.{current_url, current_title}` |
| `page_source/1` | `Bobbidi.Capture.outer_html/2` |
| `cookies/1`, `set_cookie/3,4` | `Bobbidi.Cookies.*` |
| `window_handle/1`, `window_handles/1`, `focus_window/2`, `close_window/1` | `Bobbidi.Tabs.*` |
| `focus_frame/2`, `focus_parent_frame/1` | `Bobbidi.Locator.frame/2` and a session "exit frame" helper |
| `click/1`, `clear/1`, `set_value/2` | `Bobbidi.click/2`, `Bobbidi.fill/3` (clear=true), `Bobbidi.fill/3` |
| `text/1`, `attribute/2` | `Bobbidi.text/2`, `Bobbidi.attribute/3` |
| `displayed/1`, `selected/1` | `Bobbidi.Expect.visible/2` (boolean variant), `Bobbidi.Expect.checked/2` |
| `send_keys/2` | `Bobbidi.Input.type_keys/3` (page-level) or `Bobbidi.press_sequentially/3` (element-level) |
| `find_elements/2` | `Bobbidi.Locator.{css,xpath}/2 \|> Locator.resolve/1` returning `[%Wallaby.Element{}]` constructed from `[%Bobbidi.Element{}]` |
| `execute_script/3`, `execute_script_async/3` | `Bobbidi.JS.call/3` |
| `take_screenshot/1` | `Bobbidi.Capture.screenshot/2` |
| Dialogs (`accept_alert/2` etc.) | Subscribe to `BrowsingContext.UserPromptOpened`, run user callback, send `BrowsingContext.HandleUserPrompt`. Wallaby's callback shape adapted at the adapter layer. |
| `hover`, `double_click`, `button_down/up`, `move_mouse_to`, `touch_*`, `tap` | `Bobbidi.Input.*` (pointer + touch). Phase 1 covers pointer; touch maybe Phase 2. |
| `element_size`, `element_location` | `Bobbidi.bounding_box/1` |

## Element struct adaptation

Wallaby's `%Wallaby.Element{url, session_url, parent, id, driver, screenshots}` (`wallaby/lib/wallaby/element.ex:30`) embeds the WebDriver element URL — doesn't exist in BiDi. The adapter constructs `%Wallaby.Element{}` with synthetic fields:
- `id` → `Bobbidi.Element.shared_ref`
- `driver` → `Bobbidi.Wallaby` (the adapter module)
- `url` / `session_url` → unused (or stubbed for compat) — element ops dispatch to driver, which uses the embedded `Bobbidi.Element` to do real work.

**Document this divergence:** Wallaby code that pattern-matches on element URL fields will break. That's a real cost; the alternative (rewriting BiDi to expose an HTTP-addressable element resource) is worse.

Wallabidi already chose this divergence in spirit — it added `:bidi_shared_id` to the Element struct (`wallabidi/lib/wallabidi/element.ex:30,45`) — but kept the WebDriver-id fallback. bobbidi_wallaby drops the fallback entirely.

## Wait/retry model

Wallaby's `retry/2` busy-loops until `:max_wait_time` (`browser.ex:147-165`) with no backoff. Stale-reference errors don't count against the deadline (`:138-142` — known infinite-loop risk).

Bobbidi diverges:
- Auto-wait built into actions (Visible+Stable+Enabled+ReceivesEvents) by default.
- Explicit `Bobbidi.Wait` and `Bobbidi.Expect` primitives with per-call timeouts.
- Stale-reference is normalized to `%Bobbidi.Error{reason: :stale_reference}` and counted against the deadline.

For Wallaby compatibility: the adapter's `find_elements/2` wraps bobbidi's resolution in Wallaby's `retry/2` semantics where Wallaby user code expects them. The adapter exposes a per-test config to opt into bobbidi's stricter semantics for new tests. Wallaby idiomatic tests continue to work; new bobbidi-aware tests get the better behavior.

## Things that DON'T translate cleanly

1. **Element-as-HTTP-resource model**. WebDriver-Classic treats elements as `session_url + id` URLs. BiDi has SharedReferences in (context, realm) scope. The adapter fakes the URL; tests pattern-matching on URL fields break. Document.
2. **Implicit retry on stale ref without deadline**. Wallaby docs say "may loop forever". BiDi staleness is more frequent than WebDriver-Classic due to realm-change rules. Adapter applies a hard deadline (some multiple of `session.default_timeout`). Document the divergence.
3. **`attach_file` via path**. WebDriver has native upload; BiDi doesn't. Wallabidi's `DataTransfer` JS shim creates an empty File object — not a real upload. bobbidi_wallaby inherits this limitation; document. For real uploads, recommend a CDP-fallback adapter or chromium-bidi's file-upload extension.
4. **`accept_alert(fn)` callback shape**. Wallaby's callback triggers the dialog inside the fn. BiDi's natural shape is "subscribe → trigger → handle". The adapter wraps the natural shape into Wallaby's callback. Slight overhead; transparent to user.
5. **xpath via `document.evaluate`**. Wallabidi reimplements xpath in JS. BiDi's `locateNodes` supports xpath natively — use that, skip the JS shim.
6. **`Wallaby.Query` form-field locators by label text**. These compile to xpath strings (`wallaby/lib/wallaby/query.ex:469-491`). The adapter accepts `Wallaby.Query.compile/1` outputs and translates to `Bobbidi.Locator.{css,xpath}/2` directly. Bobbidi's richer locator selectors (`AccessibilityRole`, `InnerText`) are not directly exposed via Wallaby — opt-in via custom Wallaby selectors at the framework level.
7. **Visibility filtering as default in driver** (`bidi_client.ex:418-455`). Wallaby's `validate_visibility` lives in the framework. bobbidi_wallaby returns all matches; Wallaby's framework filters as it always has.

## Where the adapter lives

**Separate package: `bobbidi_wallaby`.** Depends on `bobbidi` and `wallaby`. Coordinated releases at minor-version cadence.

Why separate (not in bobbidi): Wallaby has framework-specific concerns (SessionStore, Ecto sandbox integration, Phoenix-specific helpers, query-compile output format) that bobbidi shouldn't absorb. Adapter handles the impedance mismatch.

## Path for Wallabidi users

Wallabidi users currently write code against `Wallabidi.*` modules. A bobbidi_wallaby-based path doesn't help them directly — they're on a fork. The migration story is:

- Either: Wallabidi maintainer adopts bobbidi internally (simplifies their fork, reduces JS surface).
- Or: Wallabidi users migrate back to upstream Wallaby + bobbidi_wallaby (loses Wallabidi's LiveView-specific helpers unless ported).

This is a maintainer-coordination question, not a bobbidi-design question. Surface to the Wallabidi maintainer when bobbidi ships.

## LiveView helpers — port-or-not

Wallabidi's `await_liveview_connected`, `prepare_patch`/`await_patch`/`drain_patches`, `settle`, `on_console`, `intercept_request` (`bidi_client.ex:1343-1738`) are LiveView-specific. They're not exposed through Wallaby's `Browser` module — they're called from helper modules.

If bobbidi_wallaby targets LiveView users, port these (with bobbidi exposing the underlying primitives where they're missing — e.g., the network-event subscription for `intercept_request` lands in `Bobbidi.Network` Phase 2). If LiveView is out of scope for v1, defer.

LiveView users are a meaningful Wallaby segment, so likely worth porting.

## Open questions

1. **Element URL fakery**: stub or omit? Stubbed gives compatibility for tests pattern-matching on URL fields; omitted is cleaner but breaks more.
2. **Wallaby `retry/2` integration**: wrap bobbidi resolution in Wallaby's retry? Or rely on bobbidi's per-call timeouts only? Probably both — Wallaby's API expects the retry behavior.
3. **LiveView helpers**: port to bobbidi_wallaby (with bobbidi exposing the underlying primitives), or leave Wallabidi-only?
4. **Pool management**: Wallaby has `Wallaby.SessionStore`; bobbidi_wallaby has to integrate. Verify that `start_session/1` returning a per-test session works with SessionStore's lifecycle monitoring.
5. **Driver default**: Wallaby defaults to `:chrome` via env; Wallabidi defaults to `:chrome_cdp`. bobbidi_wallaby's default — `:firefox`, `:chrome`, or autodetect?
6. **`fill_in` semantics**: Wallabidi does a *silent clear* (no input/change events) before `set_value` to avoid double-firing `phx-change` (`wallabidi/lib/wallabidi/element.ex:68-77`). Match that behavior, or use bobbidi's standard `fill` which fires events?

## References

- Wallaby repo: `/Users/peter/work/wallaby/`
- Wallabidi repo: `/Users/peter/work/wallabidi/`
- Wallaby driver behaviour: `wallaby/lib/wallaby/driver.ex` (private)
- Wallaby browser API: `wallaby/lib/wallaby/browser.ex`
- Wallabidi BiDi adapter: `wallabidi/lib/wallabidi/chrome.ex`, `wallabidi/lib/wallabidi/bidi_client.ex`
- Wallabidi LiveView helpers: `wallabidi/lib/wallabidi/bidi_client.ex:1343-1738`
- `plans/bobbidi.md` — bobbidi capabilities this adapter consumes
- `plans/bibbidi-0.4.md` — events refactor required
