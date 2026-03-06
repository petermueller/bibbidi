# Changelog

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
