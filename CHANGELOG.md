# Changelog

## v0.2.0

### Features

- **Encodable protocol** — `Bibbidi.Encodable` with `method/1` and `params/1` for encoding command structs into BiDi wire format
- **Command structs** — one struct per BiDi command (~60 total), each implementing `Encodable`, generated from the CDDL spec
- **Zoi schemas on command structs** — every command struct exposes `schema/0`, `opts_schema/0`, and `result_schema/0` for runtime validation, introspection, and auto-generated documentation
- **Typed facade specs** — facade functions use real CDDL-derived typespecs (e.g. `String.t()`) instead of `term()`, and `CommandName.opts()` / `CommandName.result()` instead of `keyword()` / `map()`
- **Opts validation** — facade functions validate keyword options via `Zoi.parse!/2` before constructing command structs
- **`Connection.execute/2,3`** — accepts `Encodable` structs directly; existing function-based API is fully backwards-compatible
- **Telemetry** — `[:bibbidi, :command, :start|:stop|:exception]` events on `Connection.execute/2` and `[:bibbidi, :event, :received]` on incoming BiDi events. `Bibbidi.Telemetry` documents all events, measurements, and metadata.
- **`mix bibbidi.gen.workflow`** — Igniter generator that scaffolds a Multi-style Op pipeline builder, Operation record, and sequential Runner into the consumer's project
- **`examples/op_workflow/`** — standalone Mix project demonstrating the Op builder pattern for composing BiDi commands
- **`mix bibbidi.cddl.inspect`** — dev task for inspecting parsed CDDL rules, resolved fields, and extracted commands; now shows CDDL type info in `--fields` and `--commands` output

### Breaking

- **`Bibbidi.Types.*` modules removed** — type information now lives directly on command structs (`@type t`, `@type opts`, `@type result`). Delete any `alias Bibbidi.Types.*` references.
- **`Connection.send_command/4` is now a documented low-level escape hatch** — use `Connection.execute/2` for normal usage. `send_command/4` does not emit telemetry or go through `Encodable`; it's useful for vendor extensions or commands not yet in the spec.
- **`Commands.Session.end_session/1` renamed to `Commands.Session.session_end/1`** — `end` is a reserved word; the generated facade uses the `session_end` name. `Bibbidi.Session.end_session/1` is unchanged.
- **`Commands.Session.unsubscribe/3` changed to `Commands.Session.unsubscribe/2`** — `events` moved from a required positional arg into the keyword opts. `Bibbidi.Session.unsubscribe/3` is unchanged.
- **`Script.evaluate/4` changed to `Script.evaluate/5`** — `await_promise` moved from an option (defaulting to `true`) to a required positional arg. Update calls: `Script.evaluate(conn, expr, target)` → `Script.evaluate(conn, expr, target, true)`.
- **`Script.call_function/4` changed to `Script.call_function/5`** — `await_promise` moved from an option (defaulting to `true`) to a required positional arg, inserted before `target`. Update calls: `Script.call_function(conn, fn_decl, target, opts)` → `Script.call_function(conn, fn_decl, true, target, opts)`.
- **`Bibbidi.Transport` behaviour** — added required `send_pong/1` callback. Custom transport implementations must add this function.
- **All facade functions now validate opts with Zoi** — passing unrecognized or wrongly-typed keyword options will raise from `Zoi.parse!/3` instead of being silently ignored.

### Changed

- CDDL code generator migrated to Igniter for proper diffing, dry-run support, and formatting
- Command module functions now construct structs internally and route through `Connection.execute/2`
- Command structs use `Zoi.Struct.enforce_keys/1` and `Zoi.Struct.struct_fields/1` instead of manual `@enforce_keys` / `defstruct`
- Interactive Livebook example updated to use command structs and `Connection.execute/2`

### Fixed

- Regenerated `Session.Unsubscribe` struct — was empty, now correctly includes `events` and `subscriptions` fields from the CDDL choice type
- `Bibbidi.Session.unsubscribe/3` no longer passes `subscriptions: nil` when the option is not provided

## v0.1.0

Initial release.

### Features

- **Core** — `Bibbidi.Connection` GenServer with WebSocket command/response correlation and event dispatch
- **Protocol** — Pure JSON encode/decode via `Bibbidi.Protocol`
- **Transport** — Swappable transport behaviour (`Bibbidi.Transport`) with `Bibbidi.Transport.MintWS` default implementation
- **Browser** — `Bibbidi.Browser` GenServer for launching and managing browser OS processes
- **Session** — `Bibbidi.Session` functional module for session lifecycle (new, end, status, subscribe/unsubscribe)
- **Commands** — Builder modules for all BiDi protocol domains:
  - `BrowsingContext` — navigate, getTree, create, close, captureScreenshot, print, reload, setViewport, handleUserPrompt, activate, traverseHistory, locateNodes
  - `Script` — evaluate, callFunction, getRealms, disown, addPreloadScript, removePreloadScript
  - `Session` — new, end, status, subscribe, unsubscribe
  - `Input` — performActions, releaseActions, setFiles
  - `Network` — intercepts, data collectors, request/response control, cache, headers
  - `Storage` — getCookies, setCookie, deleteCookies
  - `Browser` — close, user contexts, client windows, download behavior
  - `Emulation` — viewport, geolocation, locale, network conditions, timezone, user agent, and more
  - `WebExtension` — install, uninstall
- **Types & Events** — Generated from the W3C CDDL spec via `mix bibbidi.gen`
- **CDDL tooling** — Parser and code generator for the WebDriver BiDi CDDL spec (`mix bibbidi.download_spec`, `mix bibbidi.gen`)
- **Interactive Livebook** — `examples/interactive_browser.livemd` with Kino.Screen UI for navigation, clicking, JS console, screenshots, viewport presets, and live event log
