# Adapter: Cerberus

[Cerberus](https://github.com/...) (local: `/Users/peter/work/cerberus/`) is a session-first testing framework supporting multiple drivers (`:phoenix` for static/live, `:browser` for real browser). Its browser driver currently calls `Bibbidi.Connection.send_command/4` directly with raw method+params strings, bypassing bibbidi's typed command structs and reimplementing locator resolution and actionability in custom JS preload scripts.

**Goal:** bobbidi serves as the engine under Cerberus's browser driver, replacing the hand-rolled BiDi calls.

## Status quo

- Cerberus depends on `{:bibbidi, "~> 0.1.0"}` (`cerberus/mix.exs:34`). Will need bumping for bibbidi 0.4 (see `plans/bibbidi-0.4.md`).
- `Cerberus.Driver.Browser.BiDi` (`cerberus/lib/cerberus/driver/browser/bidi.ex`) imports `Bibbidi.Connection`, calls `start_link/1` and `send_command/4` directly (lines 158, 231-237), consumes `{:bibbidi_event, method, params}` (lines 115-119).
- `cerberus/lib/cerberus/driver/browser/expressions.ex` — ~700 lines of JS implementing actionability + locator resolution as preload helpers.
- `cerberus/lib/cerberus/driver/browser/action_helpers.ex` and `assertion_helpers.ex` — wire those JS helpers into the driver callbacks.
- The browser driver is its own subsystem: `runtime.ex` (chromedriver/Chrome lifecycle), `browsing_context_process.ex`, `user_context_process.ex`, `browsing_context_supervisor.ex`. Chrome only by policy (`cerberus/CLAUDE.md:25-28`).

## Cerberus.Driver behaviour

`@behaviour Cerberus.Driver` (`cerberus/lib/cerberus/driver.ex:30-58`):

- **Lifecycle**: `new_session/1`, `open_tab/1`, `switch_tab/2`, `close_tab/1`, `default_timeout_ms/1`
- **Page state**: `open_browser/2`, `render_html/2`, `unwrap/2`, `within/3`, `visit/3`
- **Actions**: `click/3`, `fill_in/4`, `select/3`, `choose/3`, `check/3`, `uncheck/3`, `upload/4`, `submit_active_form/2`, `submit/3`
- **Assertions**: `assert_has/3`, `refute_has/3`, `assert_value/4`, `refute_value/4`, `assert_download/3`, `assert_path/3`, `refute_path/3`, `run_path_assertion/5`

Return shape: `op_ok :: {:ok, session, observed}` or `op_error :: {:error, session, observed, reason}`. Session implements `Cerberus.Session` protocol (`scope/1`, `with_scope/2`).

`Cerberus.Locator` (`cerberus/lib/cerberus/locator.ex:13-29`) is a discriminated AST: leaf kinds (`:text`, `:label`, `:placeholder`, `:title`, `:alt`, `:testid`, `:css`, `:role`) and composites (`:scope`, `:and`, `:or`, `:not`). Composition via `scope/2`, `and_/2`, `or_/2`, `not_/2`, `filter/2`, `closest/2`. Sigil `~l` is the idiomatic surface (`cerberus/MIGRATE_FROM_PHOENIX_TEST.md:96-104`).

## Mapping Cerberus callbacks to bobbidi

| Cerberus callback | Bobbidi mapping |
|---|---|
| `new_session/1` | `Bobbidi.Session.new(conn, ctx) \|> Bobbidi.Session.ready/1` |
| `open_tab/1`, `switch_tab/2`, `close_tab/1` | `Bobbidi.Tabs.{new, switch, close}` |
| `visit/3` | `Bobbidi.Navigation.navigate/3` |
| `render_html/2` | `Bobbidi.Capture.outer_html/2` |
| `within/3` | `Bobbidi.Locator.within/2` |
| `click/3` | `Bobbidi.click/2` (auto-wait) |
| `fill_in/4` | `Bobbidi.fill/3` |
| `select/3` | `Bobbidi.select_option/3` |
| `choose/3`, `check/3`, `uncheck/3` | `Bobbidi.click/2` on the radio/checkbox locator |
| `upload/4` | `Bobbidi.upload/3` (DataTransfer shim — documented as best-effort) |
| `submit_active_form/2` | Adapter tracks `meta.last_form_locator` → `Bobbidi.JS.eval` to invoke `form.submit()` |
| `submit/3` | Locate form via locator, then submit |
| `assert_has/3`, `refute_has/3` | `Bobbidi.Expect.visible/2` / `Bobbidi.Expect.detached/2` (or count-based) |
| `assert_value/4`, `refute_value/4` | `Bobbidi.Expect.value/3` |
| `assert_path/3`, `refute_path/3` | `Bobbidi.Expect.url/3` |
| `assert_download/3` | Subscribe to `BrowsingContext.DownloadWillBegin` + assertion (Phase 2 of bobbidi) |
| `default_timeout_ms/1` | `session.default_timeout` |

A small **`Cerberus.Locator → Bobbidi.Locator` translator** inside the adapter handles AST conversion. Bobbidi shouldn't know about Cerberus.

## Gaps to fill before adapter can ship

Bobbidi requirements identified by mapping the Cerberus surface:

1. **Iframe scoping in locators.** `within(session, iframe_locator, fn)` switches BiDi context. Bobbidi needs `Locator.frame/2` (Phase 1 — already in bobbidi plan).
2. **`assert_download` event correlation.** Cerberus subscribes to download-related events. Bobbidi needs subscribe convenience for `BrowsingContext.DownloadWillBegin` + a `Bobbidi.Expect.download/2` matcher (Phase 2).
3. **`active_form` tracking.** PhoenixTest-style "form being filled" lives at the adapter layer. Bobbidi doesn't manage this. Adapter uses `Bobbidi.Session.meta` for it.
4. **Telemetry-friendly `observed` map.** Cerberus's `{:ok, session, observed}` carries `observed` for telemetry/profiling. Bobbidi action returns can populate `observed` (timing, BiDi commands invoked, helpers used) — confirm bobbidi's telemetry events provide enough data.
5. **AST translation discoverability.** Cerberus may want bobbidi to expose `Bobbidi.Locator.Builder` (or similar) functions that take maps/keyword-lists, not just the pipe builders, to make the translator code simpler. Investigate.

## Migration approach

1. Land bobbidi Phase 1 (with Phase 2 download-event support if `assert_download` is on the must-port list).
2. Bump Cerberus's `mix.exs`: `{:bibbidi, "~> 0.4"}` and `{:bobbidi, "~> 0.1"}`.
3. Rewrite `Cerberus.Driver.Browser.BiDi` to delegate to bobbidi:
   - `send_command/4` calls → `Bobbidi.<Module>.<fn>` calls
   - Custom JS preload helpers → bobbidi's helpers install (closure-only)
   - Custom locator JS → `Bobbidi.Locator` resolution
4. Keep `Cerberus.Locator → Bobbidi.Locator` translator as the boundary — at adapter ingress.
5. Run Cerberus's existing test suite. Failures = bobbidi gaps. File issues, fix.
6. Once green: deprecate Cerberus's `expressions.ex` / `action_helpers.ex` / `assertion_helpers.ex` (or extract them as a contribution into bobbidi's preload helpers).

Estimated outcome: Cerberus's browser driver shrinks substantially (especially the JS preload — bobbidi absorbs the actionability layer).

## Where the adapter lives

Two options:

1. **Inside Cerberus**: rewrite `Cerberus.Driver.Browser.BiDi` to depend on bobbidi. Cerberus owns the adapter, releases it as part of Cerberus.
2. **Separate `bobbidi_cerberus` package**: cleaner separation but introduces a coordination tax for releases.

**Recommendation: Option 1.** Cerberus already considers bibbidi a dependency; adding bobbidi is the same scope. Splitting only makes sense if multiple maintainers want their own pace.

## Open questions for the maintainer

1. **Bibbidi 0.4 coordination**: Cerberus is on `~> 0.1.0`. The events refactor (see `plans/bibbidi-0.4.md`) requires pattern-match updates in `bidi.ex:115-119`. Coordinate timing?
2. **JS helper sharing**: `expressions.ex` / `action_helpers.ex` / `assertion_helpers.ex` is large and load-bearing. Appetite to extract its actionability logic into a stand-alone JS asset (or contribute it into bobbidi's preload helpers) so Wallaby/Jido adapters can share?
3. **Native vs. raw `send_command/4`**: Cerberus currently uses raw method+params strings. Migrating to bibbidi's typed command structs (e.g. `%BrowsingContext.Navigate{}`) is a separate concern from migrating to bobbidi. Both at once, or sequence?
4. **`active_form` semantics**: PhoenixTest tracks "active form" implicitly. Cerberus tracks `active_form_selector` and dispatches change events. Is bobbidi's `meta` map sufficient, or should bobbidi expose a "last interacted element" hook?
5. **Locator translator location**: should `Cerberus.Locator → Bobbidi.Locator` live in Cerberus, in bobbidi (as `Bobbidi.Locator.from_cerberus/1`), or in a third module? Probably Cerberus side — bobbidi shouldn't know about Cerberus.
6. **Scope-to-iframe story** (`cerberus.ex:570-572`): when `within` is called with a locator that resolves to an iframe, Cerberus rebinds the browsing context. Bobbidi's `Locator.frame/2` handles the same — but does Cerberus want bobbidi to detect "this locator is an iframe and silently rebind", or is the explicit `frame` builder sufficient?
7. **Default-timeout-per-driver** (`Cerberus.Driver.default_timeout_ms/1`): bobbidi has per-session and per-call timeouts. The adapter just returns `session.default_timeout`. Confirm this satisfies Cerberus's expectation.

## References

- Cerberus repo: `/Users/peter/work/cerberus/`
- Cerberus driver behaviour: `cerberus/lib/cerberus/driver.ex`
- Cerberus browser driver: `cerberus/lib/cerberus/driver/browser/`
- Migration guide from PhoenixTest: `cerberus/MIGRATE_FROM_PHOENIX_TEST.md`
- Cerberus architecture notes: `cerberus/docs/architecture.md`
- `plans/bobbidi.md` — bobbidi capabilities this adapter consumes
- `plans/bibbidi-0.4.md` — events refactor required
