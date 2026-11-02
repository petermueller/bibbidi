# Research: NetRunner as a Launcher backend

Resolves [#10](https://github.com/petermueller/bibbidi/issues/10), part of the
Browser-lifecycle map [#7](https://github.com/petermueller/bibbidi/issues/7).
Researched 2026-11-02 against `net_runner` 1.6.0 (the only 1.6.x release).

## Question

Can `net_runner` back a Bibbidi **Launcher** (run Firefox, bind its lifetime to
a BEAM process, stream its output, kill its whole process tree on stop, leave
no **Orphan**), and what does it cost?

## Sources

Primary sources only. Line numbers refer to the `v1.6.0` tag
(`85ee1e6`, master at research time).

- HexDocs: [NetRunner](https://net-runner.hexdocs.pm/NetRunner.html),
  [NetRunner.Process](https://net-runner.hexdocs.pm/NetRunner.Process.html),
  [NetRunner.Daemon](https://net-runner.hexdocs.pm/NetRunner.Daemon.html),
  [NetRunner.Command](https://net-runner.hexdocs.pm/NetRunner.Command.html),
  [README](https://net-runner.hexdocs.pm/readme.html),
  [CHANGELOG](https://net-runner.hexdocs.pm/changelog.html)
- Repository <https://github.com/nyo16/net_runner>:
  `c_src/shepherd.c`, `c_src/net_runner_nif.c`, `c_src/protocol.h`,
  `lib/net_runner/process.ex`, `lib/net_runner/process/exec.ex`,
  `lib/net_runner/daemon.ex`, `lib/net_runner/watcher.ex`,
  `lib/net_runner/application.ex`, `mix.exs`, `mix.lock`, `Makefile`,
  `.github/workflows/ci.yml`, `docs/architecture.md`, `docs/decisions.md`,
  `docs/comparison.md`, `CHANGELOG.md`, `CLAUDE.md`
- hex.pm API: <https://hex.pm/api/packages/net_runner>,
  <https://hex.pm/api/packages/net_runner/releases/1.6.0>
- GitHub API: `repos/nyo16/net_runner`, `.../contributors`, `.../issues?state=all`
- Firefox source (which stream carries the BiDi URL):
  [`remote/webdriver-bidi/WebDriverBiDi.sys.mjs`](https://hg.mozilla.org/mozilla-central/file/tip/remote/webdriver-bidi/WebDriverBiDi.sys.mjs)
- Local verification: a scratch Mix project (outside the repo) depending on
  `{:net_runner, "~> 1.6"}`, run on this machine (macOS, Darwin 27.0.0,
  Apple clang 21, GNU make 3.81, Erlang/OTP 28.2, Elixir 1.19.4) against
  `sh`/`sleep`/`python3` only. Firefox was not run.

## Findings

### Architecture in one paragraph

`NetRunner.Process` is a GenServer that `Port.open`s the C **shepherd**
binary (`priv/shepherd`) with `:nouse_stdio`, hands it a per-spawn random
token over fd 3, and listens on a private Unix domain socket. The shepherd
connects, echoes the token, `fork()`s the child, makes the child the leader of
its own process group (`setpgid(0,0)` in the child plus `setpgid(child, child)`
in the parent, `shepherd.c:1363-1366,1553`), passes the child's stdin/stdout/
stderr pipe fds to the BEAM via `SCM_RIGHTS` (plus a pidfd on Linux), sends
`MSG_CHILD_STARTED` with the child's pid, and only then releases an "exec gate"
so the child `execvp`s (`shepherd.c:1558-1582`, ADR-15). The shepherd never
execs away; it stays as a watchdog in a `poll()` loop over the UDS and a
SIGCHLD self-pipe (`shepherd.c:965-1007`). The BEAM reads the pipes through a
NIF with `enif_select` (`net_runner_nif.c`). Spawn costs two `fork`+`exec`
(README "Performance": ~4.4-7.2 ms on an M1 Max), irrelevant next to a Firefox
launch.

### Kill mechanism: child exit, GenServer crash, BEAM death

**Child exits on its own.** SIGCHLD wakes the loop; the shepherd checks with
`waitid(P_PID, …, WEXITED|WNOHANG|WNOWAIT)` (does *not* reap, so the zombie
pins the pid/pgid), then `kill(-child_pid, SIGKILL)` sweeps whatever is left in
the child's process group, reaps, and sends `MSG_CHILD_EXITED`
(`finish_child_exit`, `shepherd.c:936-946`; ADR-14 in `docs/decisions.md`).
This is a 1.6.0 behaviour change: background members of the child's group die
with the leader, no grace (CHANGELOG 1.6.0 "H2").

**GenServer stops or crashes.**
- Orderly `terminate/2` closes the pipes, then the UDS socket, then the Port
  (`process.ex:702-724`). Closing the UDS is what kills: the shepherd sees
  `POLLHUP`, drains any command the BEAM queued first (so a `kill(:sigkill)`
  right before `stop/1` is honoured, CHANGELOG 1.6.0 "H3"), then runs the
  ladder `SIGTERM group → wait up to kill_timeout (WNOWAIT) → SIGKILL group →
  reap` (`kill_child`, `shepherd.c:805-815`; `read_commands`, `913-934`).
- A brutal kill of the GenServer (`Process.exit(pid, :kill)`) skips
  `terminate/2`, but the UDS `:socket` and the Port are owned by that process
  and the VM closes them on exit, so the shepherd takes the same `POLLHUP`
  path. Verified locally: `sh -c "sleep 300 & sleep 300 & wait"` plus both
  grandchildren were gone 1.5 s after `Process.exit(proc, :kill)` with
  `kill_timeout: 300`.
- Belt and braces: `NetRunner.Watcher` monitors the GenServer and, on `:DOWN`,
  sends exactly one SIGTERM probe via the NIF if `kill(pid, 0)` still succeeds;
  it deliberately does **not** escalate to SIGKILL, to avoid a pid-reuse race
  (`watcher.ex:52-76`). The NIF resource's owner monitor closes the raw fds
  when the owning process dies (`net_runner_nif.c:98-130`), so the child sees
  EOF/SIGPIPE.
- The optional `:owner` pid (`NetRunner.Process.start/3`, `set_owner/2`):
  when the owner goes `:DOWN` the GenServer SIGKILLs the child and stops
  (`on_owner_down`, `process.ex:644-652`). Verified locally: a `spawn`ed owner
  that `exit(:boom)`ed took `sleep 300` and the GenServer with it.

**BEAM dies hard (SIGKILL/OOM).** The shepherd is a separate OS process whose
only link to the VM is the UDS; the kernel closes it, `POLLHUP` fires, same
ladder as above (`architecture.md` "Zombie Prevention", Layer 1). Verified
locally with `kill -9` on the `beam.smp` running `Process.start("sh", ["-c",
"sleep 298 & sleep 298 & wait"], kill_timeout: 500)`: shepherd, `sh` and both
`sleep`s were gone 0.3 s later; no leftover `sleep 298` on the host. Note the
grace in this path is the shepherd's `--kill-timeout` (default 5 000 ms,
`protocol.h:DEFAULT_KILL_TIMEOUT_MS`; 1..60 000 via the `:kill_timeout`
option, `exec.ex:415-423`): a TERM-ignoring child outlives the dead VM by up
to that long before SIGKILL.

**Shepherd dies first (SIGKILL/OOM/crash).** The Port exits without a
`MSG_CHILD_EXITED`; the GenServer then `killpg(child, SIGKILL)`s the group,
signals the leader through its pidfd on Linux, and reports status 137
(`finish_orphaned`, `process.ex:1247-1266`; CHANGELOG 1.5.0 "A child is no
longer orphaned when its shepherd dies"). On Linux the child additionally has
`prctl(PR_SET_PDEATHSIG, SIGKILL)` set right after `fork()` so the kernel kills
it the moment the shepherd dies (`die_with_shepherd`, `shepherd.c:148-156`).
Signals to the shepherd itself (SIGTERM/INT/HUP/QUIT, e.g. `systemctl stop`)
also run the ladder since 1.6.0 (`shepherd.c:1240-1255`).

**pidfd.** Opened with `pidfd_open` while the child is parked and passed as
the optional last `SCM_RIGHTS` fd (`shepherd.c:1469-1479,1566`); the BEAM uses
`pidfd_send_signal` for direct kills so a reaped pid can never be re-hit
(`net_runner_nif.c:669-710`, ADR-16). Linux ≥ 5.3 only; everywhere else the
direct-kill path is "probe `kill(pid,0)` then `kill`", with the race window
acknowledged in the code comments (`process.ex:661-668`). Direct kills are
the fallback only; while the shepherd lives, `kill/2` goes over the UDS as
`CMD_KILL` and the shepherd signals the *group* (`shepherd.c:837-842`).

### stdout/stderr delivery (finding the BiDi URL)

Firefox prints the line Bibbidi parses with `Cu.printStderr(\`WebDriver BiDi
listening on ${this.address}\n\`)` (`WebDriverBiDi.sys.mjs:263`), i.e. on
**stderr**. `Bibbidi.Browser` currently papers over this with the Port option
`:stderr_to_stdout`. NetRunner keeps the two pipes separate, which matters:

- `NetRunner.Process.read/2` blocks until data or EOF and returns raw chunks
  (up to 64 KiB, not lines; `process.ex:141-156`). Bibbidi's existing
  `buffer <> data` + regex loop handles that. But `read/2` is **stdout only**.
- stderr defaults to `stderr: :consume`: an internal drain keeps only the last
  8 KiB as `stderr_tail/1` (`process.ex:298-313`), no stream. To stream it,
  start with `stderr: :disabled` and run your own `read_stderr/2` /
  `read_stderr_batch/3` loop (`process.ex:158-198`), and keep draining *both*
  pipes for Firefox's lifetime or it blocks on a full pipe.
- `NetRunner.Daemon` does exactly that: it forces `stderr: :disabled`, runs
  one drain task per pipe, and calls `on_output.(chunk)` for every chunk of
  either stream (`daemon.ex:3-12,72-76,277-366`). `on_output` is called from
  the drain task, not the Daemon process; raises/exits are caught and logged
  (`daemon.ex:342-357`). Verified locally: a `fun/1` posting to a test pid
  received `"line one\nWebDriver BiDi listening on ws://127.0.0.1:9333\n"` and
  then `"stderr line\n"`.
- Daemon lifecycle fits a browser: it traps exits, so a supervisor `:shutdown`
  runs `terminate/2`, which is `Proc.shutdown(proc, 3_000, 1_000)` (SIGTERM,
  3 s, SIGKILL, 1 s) followed by `Proc.stop/1` (`daemon.ex:44-46,221-231`);
  when the child exits it stops with `{:shutdown, {:exit_status, status}}`
  (`daemon.ex:160-172`). `Daemon.start_link/1` links to the caller.

### OS pid access

`NetRunner.Process.os_pid/1` returns the pid from `MSG_CHILD_STARTED`
(`protocol.h`), which is the pid of the exec'd command itself (the shepherd
never execs into it), i.e. Firefox's pid. `NetRunner.Daemon.os_pid/1` caches
the same value (`daemon.ex:79-80,122-127`). Verified in `ps`: BEAM → shepherd
(own pgid) → child with `PGID == PID`. This replaces the current
`:erlang.port_info(port, :os_pid)` and makes `kill_tree/1`'s `pgrep -P`
recursion unnecessary: the group kill reaches every descendant that stayed in
the group.

### macOS behaviour

Compiles and runs on this Mac with no extra setup (`mix deps.compile` built
`priv/shepherd` and `priv/net_runner_nif.so` in about one second with
`-D_DARWIN_C_SOURCE`, `Makefile:49-52`). CI covers `macos-latest`
(Elixir 1.18.4 / OTP 28.3.3, `ci.yml`). All local probes above passed on macOS.

Linux-only features that are compiled out or accepted-and-ignored on macOS:
`PR_SET_PDEATHSIG` (`shepherd.c:149-155`), pidfd (`1472-1478`), cgroups
(`705-710`, README "No-op on macOS"), `no_new_privs` (README), `close_range`
(`1386-1388`), pipe-buffer growth `F_SETPIPE_SZ` (`1625-1646`),
`PR_SET_DUMPABLE` (`1674-1679`), static shepherd linking (`Makefile:66`).
What remains is the core of what a Launcher needs: the out-of-VM shepherd,
`POLLHUP` detection, and process-group kills. ADR-14 states "Zero orphans"
holds "without cgroups, on Linux and macOS" for descendants that stay in the
group. The one macOS-only weakness is the pid-reuse window in the direct-kill
fallback after a shepherd crash (`process.ex:661-668`), a narrow and unusual
path.

### Build requirements for consumers

- `mix.exs`: `compilers: [:elixir_make] ++ Mix.compilers()`, single runtime
  dependency `{:elixir_make, "~> 0.10.0", runtime: false}`; dev-only `ex_doc`,
  `dialyxir`, `credo`, `stream_data`. **No `muontrap`** anywhere in `mix.exs`
  or `mix.lock` (confirmed). hex.pm release 1.6.0 lists `build_tools:
  ["mix", "make"]` and the one requirement `elixir_make ~> 0.10.0`.
- Toolchain: a C compiler (`cc`, gcc or clang) and `make` at `mix deps.compile`
  time; ERTS headers come from the running `erl` (`Makefile:14`). Two source
  files, each compiled and linked in one command, output to `priv/`.
  `-Werror` is opt-in (`WERROR=1`), so consumers compile warning-tolerant.
- Requires Elixir `~> 1.17`, OTP 27+ (README). Bibbidi is `~> 1.19`, fine.
- `NetRunner.Application` must run (it owns `NetRunner.WatcherSupervisor` and
  `NetRunner.TaskSupervisor`, `application.ex`); as a regular dependency it is
  started automatically. The NIF loads at module load (`@on_load`,
  `nif.ex`). A NIF bug can crash the whole VM; the NIF here is small (808
  lines) and is exercised in CI under ASan/UBSan.
- Cross-target releases are documented (README "Building for another
  target"); the Makefile picks platform flags from the build host's `uname`.

### Maturity, maintenance, bus factor

- First release 1.0.0 on 2026-02-26; 11 releases to 1.6.0 on 2026-11-01
  (hex.pm). Three of them (1.4.1, 1.5.0, 1.6.0) shipped within ~28 hours on
  2026-10-31/11-01, the day before this research. 1.6.0 carries a documented
  **behaviour change** in a minor (group swept on child exit, "H2"), 1.5.0 a
  **Breaking** note (UTF-8 `:env`), and 1.4.0 broke unprefixed `cgroup_path`
  in a minor (issue #24, fixed in 1.4.1). Changelog is detailed and honest
  about this.
- hex.pm: one owner (`nmaroulis`), `maintainers: ["Niko"]`; 2 749 downloads
  all-time, 1 336 recent. GitHub: 57 stars, 4 forks, created 2026-02-26,
  37 commits; contributors `nyo16` 30 commits, `mjrusso` 3 (cwd/env, static
  builds), dependabot 4. 3 issues ever (2 opened by the maintainer), 30 PRs.
  **Bus factor: 1.**
- Engineering signals are strong for its age: CI matrix of Ubuntu x86/arm,
  macOS, Alpine/musl, OTP 27-29, ASan+UBSan run of the test suite, Dialyzer,
  Credo, a "package tarball compiles standalone" job, 28 test files including
  `zombie_test`, `teardown_test`, `supervision_test`,
  `shepherd_hardening_test`; 17 ADRs; a stated threat model (ADR-13: contains
  careless children, not same-uid adversaries). The repo's `CLAUDE.md` and
  changelog ("six-slice audit", `/phx:perf`) show heavily AI-assisted
  development with a strict third-party-PR policy ("never build or run
  third-party PR code on the host").
- Minor doc drift: `docs/comparison.md` still says "BEAM scheduler safe: Yes
  (dirty IO)" while ADR-6 moved all NIF calls to normal schedulers.

### Behaviour with children that fork their own trees

- The child leads its own process group; every kill path signals the group,
  so descendants that stay in it (Firefox's content processes, if they do not
  change group) die with it. Verified: `sh` + two `sleep` grandchildren on
  `kill/2`, on GenServer brutal kill, and on BEAM SIGKILL.
- A descendant that calls `setsid()`/`setpgid()` leaves the group and
  **survives** on macOS. Verified with a `python3 -c "os.setsid(); execvp
  sleep"` grandchild: the in-group sibling died, the `setsid`'d one lived.
  On Linux `cgroup_path:` closes this via `cgroup.kill` (Linux ≥ 5.14), but it
  needs cgroup v2 with a writable, delegated `/sys/fs/cgroup/net_runner`
  subtree and fails closed otherwise (README "cgroup Support"), which is the
  map's L3 territory, not the default guarantee.
- Firefox-specific check still owed in the prototype: confirm with
  `ps -o pid,pgid` that Firefox's helper processes share the launcher's pgid
  on both OSes. Bibbidi's current `pgrep -P` walk is the fallback if not.

## Sketch: `Bibbidi.Browser.Launcher.NetRunner`

Two viable shapes. The Daemon shape is smaller because it already drains both
pipes and owns the TERM→KILL ladder.

```elixir
defmodule Bibbidi.Browser.Launcher.NetRunner do
  # Launcher callbacks are the ones the (not yet grilled) behaviour will name;
  # the NetRunner calls underneath are what matters here.

  def start(firefox_path, args, opts) do
    browser = self()                       # Bibbidi.Browser, trapping exits

    {:ok, daemon} =
      NetRunner.Daemon.start_link(
        cmd: firefox_path,
        args: args,
        on_output: fn chunk -> send(browser, {:launcher_output, chunk}) end,
        process_opts: [kill_timeout: Keyword.get(opts, :kill_timeout, 2_000)]
      )

    {:ok, %{daemon: daemon, os_pid: NetRunner.Daemon.os_pid(daemon)}}
  end

  # Browser keeps its existing buffer <> chunk + ~r/WebDriver BiDi listening on (ws:\S+)/
  # loop over {:launcher_output, chunk}; chunks carry stdout and stderr interleaved.

  def stop(%{daemon: daemon}) do
    GenServer.stop(daemon)   # Daemon.terminate/2: SIGTERM, 3 s, SIGKILL, 1 s, then Proc.stop
  end

  # If Firefox dies on its own, Browser receives
  # {:EXIT, daemon, {:shutdown, {:exit_status, status}}} and stops itself.
end
```

Process-level alternative, when Bibbidi wants to own the ladder and the
reader loops:

```elixir
{:ok, proc} = NetRunner.Process.start_link(firefox_path, args,
                stderr: :disabled, kill_timeout: 2_000, owner: self())
os_pid = NetRunner.Process.os_pid(proc)
# one Task per pipe: NetRunner.Process.read_batch(proc) / read_stderr_batch(proc)
# forwarding chunks to the Browser until :eof; keep both running for Firefox's life.
# stop: NetRunner.Process.shutdown(proc, term_grace, kill_grace); NetRunner.Process.stop(proc)
```

Either way the pure-Elixir `kill_tree/1`, `Port.close/1` and
`:erlang.port_info(:os_pid)` go away for this Launcher; profile-dir cleanup
stays in `Bibbidi.Browser`.

## Verdict

**Fits, with caveats.** NetRunner's shepherd is an out-of-VM watchdog that
kills the child's whole process group on child exit, GenServer stop or crash,
and BEAM SIGKILL, works on macOS and Linux today, exposes Firefox's OS pid, and
(via `Daemon` or `Process` with `stderr: :disabled`) streams the stderr line
Bibbidi needs. Local probes confirmed every path except Firefox itself.

Caveats:

1. **The BiDi URL is on stderr.** Use `NetRunner.Daemon`'s `on_output`, or
   `NetRunner.Process` with `stderr: :disabled` plus your own readers of both
   pipes. Default `stderr: :consume` would swallow the line into an 8 KiB tail.
2. **macOS gets process-group kills only.** No `PR_SET_PDEATHSIG`, pidfd or
   cgroups; a `setsid()`'d descendant escapes. That is the same guarantee level
   as the planned pure-Elixir default (L2); the extra value over it is a
   hardened, audited watchdog, and L3 (cgroups) on Linux with delegation.
3. **Bus factor 1, eight months old, fast-moving.** Three releases in 28
   hours before this research, a behaviour change and a breaking note inside
   minors. Pin `~> 1.6.0` and read the changelog on every bump.
4. **C toolchain at build time and a NIF inside the VM.** Acceptable only as
   an `optional: true` dependency, as the map already decided.
5. **Chunks, not lines; two streams interleaved.** Keep the buffer+regex loop.
6. **Grace period is the shepherd's, on the BEAM-death path.** Choose
   `:kill_timeout` for Firefox explicitly (default 5 s before SIGKILL).
7. Firefox helper processes must share the pgid for the group kill to cover
   them; verify in the prototype with `ps -o pgid`.
