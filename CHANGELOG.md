# Changelog

## v0.2.0

### Features

- **Encodable protocol** — `Bibbidi.Encodable` with `method/1` and `params/1` for encoding command structs into BiDi wire format
- **Command structs** — one struct per BiDi command (~60 total), each implementing `Encodable`, generated from the CDDL spec
- **`Connection.execute/2,3`** — accepts `Encodable` structs directly; existing function-based API is fully backwards-compatible
- **Telemetry** — `[:bibbidi, :command, :start|:stop|:exception]` events on `Connection.execute/2` and `[:bibbidi, :event, :received]` on incoming BiDi events. `Bibbidi.Telemetry` documents all events, measurements, and metadata.
- **`mix bibbidi.gen.workflow`** — Igniter generator that scaffolds a Multi-style Op pipeline builder, Operation record, and sequential Runner into the consumer's project
- **`examples/op_workflow/`** — standalone Mix project demonstrating the Op builder pattern for composing BiDi commands
- **`mix bibbidi.cddl.inspect`** — dev task for inspecting parsed CDDL rules, resolved fields, and extracted commands

### Changed

- CDDL code generator migrated to Igniter for proper diffing, dry-run support, and formatting
- Command module functions now construct structs internally and route through `Connection.execute/2`
- Interactive Livebook example updated to use command structs and `Connection.execute/2`

### Fixed

- Regenerated `Session.Unsubscribe` struct — was empty, now correctly includes `events` and `subscriptions` fields from the CDDL choice type

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
