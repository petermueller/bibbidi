# Browser lifecycle: orphaned Firefox processes

Status: open. Found 2026-10-30 while checking the `bibbidi-0.4-events` branch for release readiness. Blocks 0.4.

## Problem

`Bibbidi.Browser` promises in its moduledoc that `terminate/2` kills the browser OS process tree "when this process terminates for any reason (normal shutdown, crash, supervisor killing it)". It does not hold. The GenServer never calls `Process.flag(:trap_exit, true)`, so when any *linked* process exits, the Browser dies immediately and `terminate/2` is skipped. `kill_tree/1` and the profile-dir cleanup never run.

The Port closes when its owner dies, but Firefox only loses its stdout. It keeps running, reparented to PID 1, and in practice spins at ~90-100% CPU per instance.

Observed: a single `mix test.all` run leaked one headless Firefox per integration test module, nine in total, including modules whose tests all passed. ExUnit shuts down each module's `setup_all` process after its tests; that exit reaches the linked Browser before the `on_exit` callback's `Browser.stop/1` can run. The same mechanism applies to any supervisor shutting the Browser down, which is the usage the README recommends.

## Compounding bug: launch timeout mismatch

`Browser.url/1` is a plain `GenServer.call/2` with the default 5 s timeout, while the launch runs in `handle_continue/2` with a 15 s budget (`@launch_timeout`). `Connection.start_link(browser: browser)` calls `Browser.url/1` right away. On a cold or loaded machine Firefox takes longer than 5 s to print its BiDi URL, the call times out, the Connection fails to start, the caller exits, and (via the bug above) the half-launched Firefox is orphaned.

The two bugs feed each other: each orphan eats a core, every later launch gets slower, every later launch times out and leaks another orphan.

## Fog

- Why does an orphaned headless Firefox spin at full CPU after losing stdout? Not investigated; a `--headless` quirk, or the remote agent retrying.
- `IntegrationCase` tears down with `Browser.stop/1` in `on_exit`, which runs after ExUnit has already shut down the `setup_all` process. Whatever the fix, the test teardown ordering needs to be reconciled with it.
- Satellite packages (`bibbidi_runic`, `bibbidi_playwright_trace`) launch browsers in their own tests; check whether they leak the same way.
