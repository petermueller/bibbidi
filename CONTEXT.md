# Bibbidi

A low-level Elixir client for the W3C WebDriver BiDi protocol: WebSocket transport, command/response correlation, event dispatch, and the lifecycle of the browser OS process it talks to. One context covers all three packages (`bibbidi`, `bibbidi_runic`, `bibbidi_playwright_trace`).

## Language

### Browser lifecycle

**Browser**:
The BEAM process that owns one browser OS process and knows how to launch it (binary, flags, profile) and how to read its BiDi URL.
_Avoid_: browser process (ambiguous with the OS process), runtime

**Launcher**:
The pluggable strategy a Browser uses to run an executable so that its lifetime is bound to a BEAM process: start it, stream its output, kill its whole process tree on stop. One Launcher is the default; others are optional adapters.
_Avoid_: runtime, supervisor, runner, backend

**Orphan**:
A browser OS process that outlives the BEAM process that owns it.
_Avoid_: zombie (a zombie is a dead process awaiting reaping; an orphan is alive and running)

**Provider**:
Reserved. The strategy that hands out a ready BiDi connection without necessarily owning an OS process (a remote grid, a pool, an already-running browser). Not yet designed; named so the Launcher is not mistaken for it.
_Avoid_: adapter (too broad: both Launchers and Providers are adapters)
