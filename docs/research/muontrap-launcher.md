# Research: MuonTrap as a Launcher backend

Resolves [#9](https://github.com/petermueller/bibbidi/issues/9), part of map [#7](https://github.com/petermueller/bibbidi/issues/7).
Researched 2026-11-02 against `muontrap` v2.0.1 (the latest release).

## Question

Can `muontrap` (v2.x) back a Bibbidi **Launcher** (run Firefox so its lifetime is bound to a BEAM
process, stream its stdout, kill the whole process tree on stop), and what does it cost?

A Launcher MUST deliver stdout lines back to Elixir (Bibbidi parses the
`WebDriver BiDi listening on ws://...` line) and SHOULD expose Firefox's OS pid.

## Sources

Primary sources only. Source-line references are to the v2.0.1 tag; the Hex tarball for 2.0.1 was
fetched with `mix hex.package fetch muontrap 2.0.1 --unpack` and its `lib/` and `c_src/` are
byte-identical to the GitHub `main` HEAD (`5d1c639`, 2026-10-11), so the two can be cited interchangeably.

- Hexdocs README: <https://muontrap.hexdocs.pm/readme.html>
- Hexdocs `MuonTrap`: <https://muontrap.hexdocs.pm/MuonTrap.html>
- Hexdocs `MuonTrap.Daemon`: <https://muontrap.hexdocs.pm/MuonTrap.Daemon.html>
- GitHub repo: <https://github.com/fhunleth/muontrap>
  - C wrapper: <https://github.com/fhunleth/muontrap/blob/v2.0.1/c_src/muontrap.c>
  - Daemon GenServer: <https://github.com/fhunleth/muontrap/blob/v2.0.1/lib/muontrap/daemon.ex>
  - Port plumbing (private module): <https://github.com/fhunleth/muontrap/blob/v2.0.1/lib/muontrap/port.ex>
  - Options validation: <https://github.com/fhunleth/muontrap/blob/v2.0.1/lib/muontrap/options.ex>
  - Build: <https://github.com/fhunleth/muontrap/blob/v2.0.1/mix.exs>, <https://github.com/fhunleth/muontrap/blob/v2.0.1/c_src/Makefile>
  - CHANGELOG: <https://github.com/fhunleth/muontrap/blob/v2.0.1/CHANGELOG.md>
  - CI matrix: <https://github.com/fhunleth/muontrap/blob/v2.0.1/.circleci/config.yml>
  - Issues: [#60](https://github.com/fhunleth/muontrap/issues/60) (killing chatty children),
    [#106](https://github.com/fhunleth/muontrap/issues/106) (exit handling in trap_exit callers)
- hex.pm API: <https://hex.pm/api/packages/muontrap>, <https://hex.pm/api/packages/muontrap/releases/2.0.1>
- Local confirmation on this macOS machine (Darwin 27, arm64, Apple clang 21, GNU Make 3.81,
  Elixir 1.19.4 / OTP 28): a scratch Mix project with `{:muontrap, "~> 2.0"}`, plus two scripts
  using `/bin/sh` + `sleep` as a Firefox stand-in. Firefox was not run. Nothing was added to
  bibbidi's `mix.exs`.

## Findings

### 1. Kill mechanism and BEAM-SIGKILL coverage

**How the wrapper detects "the Erlang side is gone".** `MuonTrap.Daemon` opens an Erlang port on the
compiled `priv/muontrap` binary with `:use_stdio` (`lib/muontrap/port.ex` `port_options/2`;
`lib/muontrap/daemon.ex` `start_port/1`). The wrapper's main loop `child_wait_loop()` polls its own
stdin for `POLLIN | POLLHUP`; on `POLLHUP` it logs "stdin closed. Exiting..." and leaves the loop
(`c_src/muontrap.c` ~L838-866). EOF on a stdin `read()` inside `process_acks()` is treated the same
way (~L727-733). The Erlang side closes that pipe whenever the port closes, which happens whenever
the owning Erlang process (the `Daemon` GenServer) dies for any reason. `MuonTrap.Daemon` defines no
`terminate/2`; it relies entirely on the port link.

**What it kills.** After the loop exits, `main()` calls `kill_child_nicely(pid)` if the child is
still running (~L1163-1166):

1. `kill(child, SIGTERM)` to the **immediate child pid only** (~L631).
2. Wait up to `brutal_kill_wait_ms` for `SIGCHLD` (default **500 ms**, static at ~L81;
   set with `--delay-to-sigkill` / the `:delay_to_sigkill` option, documented on `MuonTrap.cmd/3`).
3. If still alive, `kill(child, SIGKILL)` (~L639) and wait up to `brutal_kill_wait_ms` again.

There is **no process group**: the source contains no `setsid`, `setpgid`, `killpg`, `prctl` or
`PR_SET_PDEATHSIG` (grep of `c_src/muontrap.c`, confirmed empty). The only multi-process kill is
`cleanup_all_children()`, which reads pids from the cgroup's `cgroup.procs` file (or writes
`cgroup.kill` on kernel 5.14+) and runs **only when a cgroup path was given**
(`if (cgroup_path) { cleanup_all_children(); destroy_cgroups(); }`, ~L1169-1172).

**BEAM SIGKILL / OOM.** When the BEAM dies hard, the kernel closes its end of the pipe, the wrapper
sees `POLLHUP`, and runs the same TERM-then-KILL sequence. This is the library's core promise
("kills OS processes if the Elixir process running them crashes", README) and it covers the
BEAM-death case for the immediate child without any Elixir code running. The v1.3.3 fix (CHANGELOG,
issue #60) specifically closed a race where a child spamming stdout while the Erlang side died
prevented cleanup; the current loop keeps polling stdin even when the stdio window is exhausted.

**Confirmed locally** (`beamkill.sh` in the scratch project): started
`MuonTrap.Daemon` on `sh -c "echo started; exec sleep 300"`, `kill -9` the `beam.smp`, after 1.5 s
both the `muontrap` wrapper and the `sleep` child were gone.

**Grace period caveat.** The default 500 ms TERM-to-KILL window is short for Firefox if it needs to
flush its profile on SIGTERM (an open item in #7, "The default's TERM-then-KILL grace period").
It is tunable per daemon via `:delay_to_sigkill`; worst-case wrapper lifetime after HUP is
2 x `delay_to_sigkill`.

### 2. Stdout line delivery to Elixir

Two supported routes:

- **`MuonTrap.cmd/3` with `:into`** (README FAQ "How do I watch stdout?"): streams raw chunks into a
  `Collectable` while **blocking the caller until the command exits**. Wrong shape for a
  long-running browser unless wrapped in a Task, and it yields chunks, not lines.
- **`MuonTrap.Daemon` with `:logger_fun`** (added v1.6.0, 2025-01-24; documented on
  `MuonTrap.Daemon`): a 1-arity function or `{m, f, args}` that "replace[s] the default logging
  behavior". The Daemon splits incoming port data on `"\n"`, calls `logger_fun` **once per complete
  line**, and buffers the trailing partial line (`split_and_log/2`, `process_data/1` in
  `daemon.ex`). The partial-line buffer is capped at `@max_data_to_buffer 256` bytes
  (`trim_buffer/1`), so an unterminated line longer than 256 bytes is truncated; the BiDi URL line
  is far shorter and newline-terminated, so this does not bite. `logger_fun` runs **inside the
  Daemon process**; a Launcher passes `fn line -> send(launcher_pid, {:stdout_line, line}) end`
  and must not raise in it (a raise crashes the Daemon).

Setting `:logger_fun` (or `:log_output`) is also what makes the wrapper capture stdout at all:
`port.ex` maps either key to `--capture-output`; without it the child's stdout goes to `/dev/null`
in `fork_exec()` (~L205-212). Add `stderr_to_stdout: true` (maps to `--capture-stderr`) so the
listening line is seen whichever stream Firefox writes it to (today `Bibbidi.Browser` uses
`:stderr_to_stdout` on its own port, so the stream is not pinned down).

**Flow control.** Captured output is window-limited (`--stdio-window`, default 10 KB, ~L100) and
the Elixir side must acknowledge bytes (`MuonTrap.Port.report_bytes_handled/2`). The Daemon does
this automatically on every `{:data, ...}` message. If a Launcher instead drove the binary directly
via the public `MuonTrap.muontrap_path/0`, it would have to re-implement the ack byte protocol from
the **private** `MuonTrap.Port` (`@moduledoc false`); failing to ack would stop the wrapper reading
after 10 KB and eventually block Firefox on a full stdout pipe. Use the Daemon.

**Is `:logger_fun` a hack?** It is a documented, stable option that happens to be named for its
original purpose. Repurposing it as a line channel is a semantic mismatch, not an abuse of
internals, and the maintainer's own README answer to "how do I watch stdout" for daemons is this
option family.

**Confirmed locally** (`tree_test.exs`): `logger_fun` received
`"WebDriver BiDi listening on ws://127.0.0.1:9999/session-fake"` as a single line, no trailing newline.

### 3. OS pid of Firefox (not the wrapper)

`MuonTrap.Daemon.os_pid/1` is documented as "Return the OS pid to the muontrap executable" and is
implemented as `Port.info(port, :os_pid)`, i.e. the **wrapper's** pid. There is no API for the
child's pid; the wrapper never reports it back over the port. The process shape is
`beam -> muontrap -> firefox`, so the Launcher has to derive it: `pgrep -P <wrapper_pid>`
(portable; what `Bibbidi.Browser.kill_tree/1` already does) or `/proc/<pid>/task/<pid>/children`
on Linux. The wrapper `fork()`s before entering its poll loop, so the child exists by the time the
first stdout line arrives; resolving the pid after the BiDi line is observed is race-free in practice.

**Confirmed locally**: `os_pid/1` returned the `muontrap` pid; `pgrep -P` on it returned the
immediate child.

### 4. macOS support (no cgroups)

Compiles and runs on macOS. The C code is portable POSIX with one `#if defined(__linux__)` branch
using `splice(2)` and a `read`/`write` fallback elsewhere (~L668-710). CI runs the suite on macOS
(Xcode 16.4 and 26.6, `macos.m1.medium.gen1`) since 2.0.0-rc.1 (PR #102, CHANGELOG 2.0.0 "expand
CI tests to cover Ubuntu releases and macOS versions"); the README says to run
`mix test --exclude cgroup` on macOS.

Without cgroups, MuonTrap's guarantee shrinks to **the immediate child only** (section 1), and the
module doc is explicit: "MuonTrap does not require cgroups but keep in mind that OS processes can
escape." On macOS there is no containment story at all; the wrapper is then equivalent to a
TERM-then-KILL of one pid on stdin-HUP, which is **weaker than the planned default Launcher**
(`sh` wrapper killing the process group).

**Confirmed locally**: `mix compile` built `_build/dev/lib/muontrap/priv/muontrap` (Mach-O arm64,
55 KB) in 1.7 s with stock `/usr/bin/cc` and `/usr/bin/make`.

### 5. Build requirements for consumers

- `compilers: [:elixir_make | Mix.compilers()]`, dep `{:elixir_make, "~> 0.6", runtime: false}`
  (`mix.exs`; hex.pm lists it as the sole requirement, `build_tools: ["mix", "make"]`).
- A C compiler (`$(CC)`, default `cc`) and `make`; `CFLAGS` default `-O2 -Wall -Wextra -std=c99
  -D_GNU_SOURCE` (`c_src/Makefile`). On macOS the Xcode Command Line Tools suffice.
- `elixir: "~> 1.11"`; no runtime deps; Apache-2.0.
- Package ships `c_src/*.[ch]`, `c_src/Makefile`, `Makefile`; the binary is built into the
  dependency's `priv/` at `mix deps.compile`. Cross-compiling requires setting `CC` (Makefile header).
- For bibbidi: as an `optional: true` dep (per #7), consumers who do not opt in pay nothing;
  those who do need a toolchain. Release builds (`mix release`) include the compiled `priv/muontrap`.

### 6. Maturity, maintenance cadence, release history

- First Hex release 0.1.0 on 2018-02-25; 36 releases to date (hex.pm).
- 1.0.0 2021-10-21; 1.x line through 1.8.0 (2026-05-06); 2.0.0 on 2026-08-13 after three RCs
  (2.0.0-rc.0 2026-06-01); **2.0.1 on 2026-10-06** (fixes parallel `make`, an Argus warning).
  Roughly 2-4 releases per year, with a bump in 2026 around the cgroup v2 rewrite.
- 2.0 is breaking only for cgroup v1 users; the CHANGELOG encourages library authors to accept both
  `~> 1.0` and `~> 2.0`. A `maint-v1.x` branch exists.
- hex.pm: ~994k total downloads, ~158k "recent", ~19k/week, ~890/day. GitHub: 274 stars, 26 forks,
  last push 2026-10-11. Author/maintainer Frank Hunleth (Nerves core team); contributors credited
  per release in the CHANGELOG (Jon Carstens, Ben Youngblood, and others).
- Issue tracker: 17 issues total, all closed; 1 open PR (a test fix). CI: Alpine images for Elixir
  1.11-1.20 / OTP 23-29, Ubuntu 22.04/24.04/26.04, macOS, plus a real-cgroup job on Ubuntu 24.04.
- One signal on review process: in #106 (2026-08) the maintainer attributed an undesirable line in a
  merged PR to LLM-authored code that slipped review, and fixed it in the 2.0.0 RC cycle (PR #108).
  Noted here, not weighted heavily.

### 7. Subprocess-tree behaviour (Firefox forks content processes)

- **Without cgroups** (macOS, or Linux without a writable cgroup v2 parent): the wrapper signals
  only its immediate child. Grandchildren are not signalled, are not in a dedicated process group,
  and are not tracked. **Confirmed locally**: a `sleep 300 &` grandchild of the wrapped `sh`
  survived `Process.exit(daemon, :kill)` while the wrapper and the `sh` child died.
  Whether Firefox's content processes die when their parent is SIGKILLed is Firefox's own
  behaviour, not MuonTrap's, and was **not verified** (no Firefox runs in this ticket). The
  current `Bibbidi.Browser.kill_tree/1` explicitly recurses children via `pgrep -P`, so the
  project already treats this as something the Launcher must handle.
- **With cgroups** (Linux, cgroup v2, a parent cgroup the BEAM user can write to, controllers
  enabled in `cgroup.subtree_control`): every descendant is placed in the cgroup at `fork_exec()`
  (`move_pid_to_cgroups`, ~L170) and torn down with `cgroup.kill` (kernel 5.14+) or a per-pid
  SIGKILL loop that re-reads `cgroup.procs` every 1 ms for up to `delay_to_sigkill` to catch
  processes spawned mid-kill (`cleanup_all_children`, ~L584-623). The README sells exactly this:
  "when MuonTrap tears down the cgroup, every descendant process inside it dies too", and
  `pids_max` as fork-bomb protection for "a compromised browser". This is the L3 story #7 reserves
  for native adapters, and it is Linux-only and needs one-time root setup (`mkdir`/`chown` under
  `/sys/fs/cgroup`, or a systemd slice with `Delegate=yes`).
- Known long-running-child issues in the tracker: #60 / v1.3.3 (chatty child blocking cleanup;
  fixed), #98 / 2.0.0 (`:epipe` when output races exit; fixed), #106 (exit handling in callers
  that trap exits; fixed in 2.0.0). None concern descendant trees; the README's "Applicability"
  section only warns off interactive/signal-driven programs.

## Sketch: `Bibbidi.Browser.Launcher.MuonTrap`

What the adapter would call, assuming the Launcher behaviour settles on roughly
`start(exe, args, opts) -> {:ok, handle}`, stdout lines delivered to the caller, `os_pid(handle)`,
`stop(handle)`:

```elixir
defmodule Bibbidi.Browser.Launcher.MuonTrap do
  @moduledoc false
  # Requires {:muontrap, "~> 2.0", optional: true}. Compile-guarded on Code.ensure_loaded?(MuonTrap.Daemon).

  def start(exe, args, opts) do
    owner = self()
    delay = Keyword.get(opts, :delay_to_sigkill, 5_000)   # default 500 ms is tight for Firefox

    daemon_opts =
      [
        stderr_to_stdout: true,                            # --capture-stderr
        logger_fun: fn line -> send(owner, {:launcher_stdout, line}) end,  # --capture-output, 1 call per line
        delay_to_sigkill: delay,
        exit_status_to_reason: fn status -> {:browser_exited, status} end,
        env: Keyword.get(opts, :env, [])
      ] ++ linux_cgroup_opts(opts)                         # cgroup_base:/cgroup: only when the user asks

    # Linked: when the Browser GenServer dies the Daemon dies, the port closes, the wrapper HUPs and
    # TERM->KILLs Firefox. Browser must trap exits so a Firefox crash arrives as {:EXIT, daemon, reason}.
    {:ok, daemon} = MuonTrap.Daemon.start_link(exe, args, daemon_opts)
    {:ok, %{daemon: daemon}}
  end

  # Called by Browser once the "WebDriver BiDi listening on" line was received (child exists by then).
  def os_pid(%{daemon: daemon}) do
    wrapper = MuonTrap.Daemon.os_pid(daemon)                # pid of priv/muontrap, not Firefox
    case System.cmd("pgrep", ["-P", Integer.to_string(wrapper)]) do
      {out, 0} -> out |> String.trim() |> String.to_integer()
      _ -> nil
    end
  end

  def stop(%{daemon: daemon}) do
    # Stopping the Daemon closes the port; the wrapper does SIGTERM, waits delay_to_sigkill, SIGKILL.
    # Without cgroups only Firefox's main process is signalled: on macOS keep a pgrep -P sweep of the
    # Firefox pid's children as a belt-and-braces step, or accept that Firefox tears its own content
    # processes down.
    GenServer.stop(daemon, :normal, 2 * 5_000)
  end

  defp linux_cgroup_opts(opts) do
    case Keyword.get(opts, :cgroup) do
      nil -> []
      cfg -> [cgroup_base: Keyword.fetch!(opts, :cgroup_base), cgroup: cfg]  # e.g. %{pids_max: 200, memory_max: ...}
    end
  end
end
```

Notes on the sketch:

- Bibbidi keeps all Firefox knowledge (binary discovery, `--remote-debugging-port`, profile dir,
  regex) in `Bibbidi.Browser`; the adapter only forwards `exe`/`args`.
- `MuonTrap.Options.validate/4` runs `System.find_executable/1` on `exe`; an absolute path to the
  Firefox binary passes.
- The Daemon logs `Logger.info/error` on child exit; harmless but visible.
- `MuonTrap.Daemon.child_spec/1` defaults to `restart: :permanent, shutdown: 500`; the adapter
  should `start_link` directly (as above) rather than put the Daemon under a supervisor, so Firefox
  is never auto-restarted behind the Browser's back.

## Verdict

**Fits with caveats.**

- Delivers the two MUST/SHOULD requirements: stdout **lines** via `MuonTrap.Daemon`'s `:logger_fun`
  (documented, per-line, with acks handled), and an OS pid, though only the **wrapper's** pid; the
  Firefox pid needs one `pgrep -P`.
- Covers the BEAM-SIGKILL/OOM case for Firefox's **main process** with no Elixir code running
  (stdin HUP -> SIGTERM -> `delay_to_sigkill` -> SIGKILL), confirmed locally.
- Caveat 1 (the big one): **no process-tree kill without Linux cgroup v2.** On macOS, and on Linux
  without a writable cgroup parent, only the immediate child is signalled; grandchildren survive
  (confirmed). That is strictly weaker than the planned pure-Elixir default (process-group kill
  from an `sh` wrapper). MuonTrap's added value over the default is therefore **Linux-only**:
  atomic `cgroup.kill` of every descendant, `pids_max`, memory/CPU caps, i.e. the L3 tier #7
  reserves for native adapters. It needs one-time root setup of a cgroup parent.
- Caveat 2: the default 500 ms TERM-to-KILL grace is likely too short for Firefox; set
  `:delay_to_sigkill` explicitly.
- Caveat 3: `:logger_fun` is a logging hook used as a line channel; stable and documented, but
  runs in the Daemon process and truncates unterminated lines at 256 bytes (irrelevant for the
  BiDi URL line).
- Caveat 4: consumers who opt in need `cc` + `make` (`elixir_make`); confirmed trivial on macOS
  with Command Line Tools.
- Maturity is not a concern: 8 years of releases, active in 2026 (2.0.1 in October), Nerves
  ecosystem, broad CI including macOS.
