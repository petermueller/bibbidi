# Why an orphaned headless Firefox spins at full CPU

Research ticket: [#11](https://github.com/petermueller/bibbidi/issues/11), part of the
Browser-lifecycle Launcher map [#7](https://github.com/petermueller/bibbidi/issues/7).
Date: 2026-11-02. Machine: macOS 27.0.1 (26A434), Apple Silicon, 14 cores,
Elixir 1.19.4 / OTP 28.2, Firefox 144.0.2 until it auto-updated to 157.0 at 17:27:53
local time in the middle of the experiment (every variant below records which build it ran on).

## Question

`plans/browser-lifecycle.md` records that a headless Firefox which loses its owning
`Bibbidi.Browser` (Port closed, process reparented to PID 1) "keeps running ... and in
practice spins at ~90-100% CPU per instance". Why, and does the answer change which
signal or flag the default Launcher should use?

Candidate causes named in the ticket: the remote agent retrying a write to a dead pipe,
an EPIPE loop on stdout, a headless compositor spin.

## Answer in one paragraph

None of the three candidates holds. Losing the stdout/stderr pipe, losing stdin, losing the
BiDi client, and losing the parent process (alone or all together) leave a
*successfully started* headless Firefox 157 idle at 0.3-0.7% CPU (variants A-G below).
The only 100% spin reproduced is a **failed-startup spin**: when Firefox cannot read its
app-data directory `~/Library/Application Support/Firefox` (macOS 27 TCC-protects it, and a
Firefox launched from a terminal, a BEAM, or a `launchctl` job that lacks Full Disk Access
is denied even with `--profile <own dir>`), `XRE_mainStartup` calls `ProfileMissingDialog`,
which on Firefox 144 opens a modal `nsIPromptService.Alert`. Headless mode cannot render
or dismiss the dialog, so the main thread sits in `AppWindow::ShowModal ->
NS_ProcessNextEvent -> nsAppShell::ProcessNextNativeEvent` pumping the Cocoa event loop at
~99% CPU forever, the profile dir stays empty, and the BiDi banner is never printed
(variant 1, symbolicated stack below). Firefox 155+ added a headless guard: it prints
`Could not find profile folder.` to stderr and exits 1 within ~200 ms instead. The
"orphans" that burned a core each were therefore most likely Firefoxes whose launch had
already failed; orphaning them merely prevented `kill_tree/1` from cleaning them up.
Whether a Firefox 144 that *had* started successfully could spin after orphaning could not
be re-tested (144 is no longer on the machine), and remains the one open gap; every
mechanism tested on 157 says no.

## Experiment

### Launch methods

| method | what it models | why needed |
|---|---|---|
| `elixir launch.exs` (scratch script mirroring `Bibbidi.Browser.handle_continue/2`: `Port.open({:spawn_executable, firefox}, [:binary, :stderr_to_stdout, args: [--headless, --remote-debugging-port P, --profile DIR]])`, then `kill -9` the BEAM) | the real Bibbidi orphan | faithful reproduction |
| direct `firefox ...` from the shell with stdout to a file | control without a BEAM | isolate the pipe from the parent |
| `launchctl submit -o/-e` | parent is launchd (the orphan's end state) | rule out the shell's process context |
| `open --stdout FIFO --stderr FIFO [--stdin FIFO] -n -a Firefox.app --args ...`, FIFOs drained by a background `cat` (the "reader", standing in for the Port owner) | a normal LaunchServices TCC context with stdio I control | the only way to get a *working* Firefox from this session's context; killing the `cat` makes the pipe readerless exactly as a dead Port does |

`--stdout/--stderr/--stdin` must precede `-a` or `open` silently gives Firefox `/dev/null`.

Every profile dir was `/var/folders/.../T/bibbidi-research-cpu-<variant>`, every PID was
recorded at launch, only those PIDs were killed, and survivors were checked with
`pgrep -f bibbidi-research-cpu-` (another session was launching its own headless Firefoxes
on the machine at the same time; its `pkill -9 -f Firefox.app` sweeps between about 17:21
and 17:38 killed my variants 1 and 2, which is why they are listed as "died, cause
external" rather than measured to completion).

### Measurement

`ps -o pid,ppid,stat,pcpu,etime,comm`, ten 1-second `top -l 11 -s 1 -pid` samples averaged
(`cpu10.sh`), `lsof -d 0,1,2` for the stdio fds, and `sample <pid> 3`. XUL frames in the
`sample` output were symbolicated through Mozilla's public symbolication service
(`https://symbolication.services.mozilla.com/symbolicate/v5`, module `XUL`, debug id from
`dwarfdump --uuid`). Signal timing: `kill -SIG`, then poll `kill -0` every 100 ms.

### Context problem discovered on the way

From this session's shell (a child of the Claude desktop app, no Full Disk Access),
`ls ~/Library/Application\ Support/Firefox` fails with `Operation not permitted` even
with the tool sandbox disabled. Firefox resolves that directory for `profiles.ini` /
`installs.ini` bookkeeping even when `--profile` points elsewhere
(`nsXREDirProvider::GetUserDataDirectory`), so from this context Firefox 157 exits with
`Could not find profile folder.` and Firefox 144 spins (variant 1). Setting
`MOZ_APP_DATA=<writable dir>` (read by `GetFileFromEnv("MOZ_APP_DATA")` in
`toolkit/xre/nsXREDirProvider.cpp` line 1238 at `FIREFOX_157_0_RELEASE`) redirects that
lookup and makes the direct `Port.open` launch succeed (variant G). The same failure
and the same fix are documented for Playwright in microsoft/playwright#42768.

### Variant table

CPU numbers are the mean of ten 1-second `top` samples unless noted. "reader" = the
process holding the read end of Firefox's stdout/stderr pipe.

| # | build | launch | headless | `--remote-debugging-port` | BiDi session | what was taken away | CPU before | CPU after | result |
|---|---|---|---|---|---|---|---|---|---|
| 1 | 144.0.2 | BEAM `Port.open` (Bibbidi-exact), from this session's shell | yes | yes | never (banner never printed) | nothing yet | **99.1% `ps`, 99.5% `top`, 2047/2053 samples on main thread** | - | **failed-startup spin**: profile dir empty after 3 min, no listener on the port, `ProfileMissingDialog` modal loop (stack below). Process later vanished inside the other session's `pkill` window |
| 2 | 144.0.2 (launched ~1 min before the auto-update) | `open -n -a Firefox` (LaunchServices context), stdio `/dev/null`, parent launchd | yes | yes | no | nothing (already parent-less, no pipe) | 0.0-3.4%, `sleeping`, main thread in `mach_msg2_trap`/`kevent` | - | idle. Listener up, `WebDriverBiDiServer.json` written. Died later, cause external (`pkill` window) |
| 3 | 157.0 | direct `firefox` from this shell, stdout to file | yes | yes | - | - | - | - | `*** You are running in headless mode.` / `Could not find profile folder.`, exit within seconds; same with profile under `/private/tmp` and `~/.cache` |
| 6 | 157.0 | `launchctl submit` of the Elixir launcher (parent launchd, no TCC grant) | yes | yes | - | - | - | - | same `Could not find profile folder.` exit; rules out the shell, confirms TCC |
| 7 | 157.0 | `open`, stdout+stderr to regular files | yes | yes | no | nothing | 0.4-0.7% (one 4.1% blip) | - | idle baseline; banner `WebDriver BiDi listening on ws://127.0.0.1:59907` arrives on **stderr** |
| A | 157.0 | `open`, stdout+stderr on a FIFO with reader | yes | yes | no | reader `kill -9` (pipe now readerless) | 15.2% (startup tail) | 0.5%, 0.6% after 20 s more | **no spin** |
| C | 157.0 | `open`, FIFO | **no (headed)** | yes | no | reader killed | 0.0% | 0.0%, 0.0% | no spin |
| D | 157.0 | `open`, FIFO | yes | **no** | - | reader killed | 12.3% (startup tail) | 0.3%, 0.4% | no spin |
| F | 157.0 | `open`, stdin FIFO + stdout/stderr FIFO | yes | yes | no | **stdin writer killed first** (stdin EOF), then reader killed | 0.9% | 0.3% after stdin EOF; 0.4% / 1.7% after stdout reader killed | no spin; stdin EOF does not make Firefox exit either |
| E | 157.0 | `open`, FIFO, profile `user.js` with `remote.log.level=Trace`, `devtools.console.stdout.*=true`, `browser.dom.window.dump.enabled=true` | yes | yes | **yes, opened after the reader was killed** (so RemoteAgent Trace logging is written into the dead pipe) | reader killed, then session traffic | 2.3% | 2.1% during session setup, 0.7% after | no spin; EPIPE writes are swallowed |
| **G** | 157.0 | **BEAM `Port.open` (Bibbidi-exact) with `MOZ_APP_DATA` set** | yes | yes | **yes** (`Session.new` + `browsingContext.navigate` from a second BEAM) | (i) client BEAM `kill -9`; (ii) owning BEAM `kill -9` -> Firefox PPID becomes 1, fds 0/1/2 are pipes with no reader | 4.6% (startup tail), 0.5% with session open | 0.5% after (i); 1.3% then 0.6% after (ii), 30 s later still 0.6% | **the faithful orphan does not spin** |

Signal behaviour (all on 157.0, fully started instances):

| signal | target | time to exit | notes |
|---|---|---|---|
| SIGTERM | A (orphan, dead pipe), C (headed), G (faithful orphan), 7, E | 124-184 ms | identical to SIGKILL within the 100 ms polling grain; `.parentlock` left in the profile; `plugin-container` children gone with the parent |
| SIGKILL | D, F | 128-134 ms | same |

Firefox installs no SIGTERM handler (`toolkit/xre/nsSigHandlers.cpp`, `nsAppRunner.cpp`;
bug 1598832 comment "Firefox doesn't trap signals"), so SIGTERM is just the default
disposition: immediate death, no shutdown path, no profile flush. The only graceful quits
are the BiDi `browser.close` command or Marionette `Marionette:Quit`.

### Where variant 1 spins (symbolicated `sample`, 2053 samples over 3 s, Firefox 144.0.2)

```
Thread DispatchQueue_1: com.apple.main-thread
  XRE_main
    XREMain::XRE_mainStartup(bool*)
      ProfileMissingDialog(nsINativeAppSupport*)          <- nsAppRunner.cpp:5020/5036
        nsXPCWrappedJS::CallMethod -> js::Interpret -> XPC_WN_CallMethod   (Prompter.sys.mjs alert())
          nsWindowWatcher::OpenWindow -> OpenWindowInternal
            mozilla::AppWindow::ShowModal()                2047 / 2053 samples
              NS_ProcessNextEvent                          1161
                nsAppShell::OnProcessNextEvent / ProcessNextNativeEvent
                  SLEventSourceCounterForEventType -> CGSEventSourceForID -> CGSScoreboard (SkyLight)
                  +[NSRunLoop currentRunLoop], _CFAutoreleasePoolPop, objc_msgSend ...
```

No frame from the remote agent, the WebSocket transport, stdio writers, or the compositor
appears in the hot path. The leaf frames (`CGEventSourceCounterForEventType` polling, run
loop bookkeeping) are the Cocoa app shell being spun with nothing to wait on because the
modal has no native window to block in.

Firefox 144.0.2 source (`toolkit/xre/nsAppRunner.cpp` at `FIREFOX_144_0_2_RELEASE`, lines
2706-2766): `ProfileMissingDialog` has a `MOZ_WIDGET_ANDROID` branch that prints and
aborts, a background-task branch, and otherwise `ps->Alert(nullptr, missingTitle,
missingMessage)` unconditionally. The same function at `FIREFOX_157_0_RELEASE` (lines
2798-2802) adds:

```cpp
  if (gfxPlatform::IsHeadless()) {
    // Nothing can dismiss a modal dialog in headless mode, so report the
    // failure on stderr and exit instead of spinning in the event loop.
    Output(true, "Could not find profile folder.\n");
    return NS_ERROR_ABORT;
  }
```

which is the behaviour variants 3 and 6 show. `ProfileLockedDialog` already had the
equivalent guard in 144 ("TODO: make a way to turn off all dialogs when headless").

## Sources

Primary, read directly:

- `toolkit/xre/nsAppRunner.cpp` at tags `FIREFOX_144_0_2_RELEASE` and `FIREFOX_157_0_RELEASE`
  (hg.mozilla.org/releases/mozilla-release): `ProfileMissingDialog`, `ProfileLockedDialog`
  headless guards, `XRE_mainStartup` call sites. No `signal(`/`sigaction` for SIGTERM/SIGPIPE.
- `toolkit/xre/nsXREDirProvider.cpp` at `FIREFOX_157_0_RELEASE`:
  `GetUserDataDirectory` honours `MOZ_APP_DATA` / `MOZ_LOCAL_APP_DATA`.
- `toolkit/components/prompts/src/Prompter.sys.mjs` at `FIREFOX_144_0_2_RELEASE`: no headless
  branch; a parent-less `alert()` opens a modal window.
- `nsprpub/pr/src/md/unix/unix.c` `_PR_UnixInit`: `sigaction(SIGPIPE, SIG_IGN)` process-wide.
  This is why a readerless stdout pipe is survivable (EPIPE instead of death).
- `mozglue/misc/Debug.cpp` `vprintf_stderr`, `xpcom/base/nsDebugImpl.cpp`: stdio writes are
  unchecked `fputs/fflush`; no retry loop. Matches variant E.
- `remote/components/RemoteAgent.sys.mjs`, `remote/webdriver-bidi/WebDriverBiDi.sys.mjs`,
  `remote/webdriver-bidi/WebDriverBiDiConnection.sys.mjs` (mozilla-firefox/firefox main):
  the agent starts at `final-ui-startup`, stops only on `quit-application`; connection close
  only unregisters the session; the only quit path is the client's `browser.close`. The
  banner is `Cu.printStderr("WebDriver BiDi listening on ...")`.
- `erts/emulator/sys/unix/erl_child_setup.c` at `OTP-28.2` (erlang/otp): when the socket to
  the VM closes (`res == 0`, "uds was closed!") it `_exit(0)`s without signalling children,
  and `start_new_child` resets SIGTERM to `SIG_DFL` before `execve`. A `Port.open` child
  is therefore orphaned, not killed, when the BEAM dies.
- Firefox Remote Protocol docs: https://firefox-source-docs.mozilla.org/remote/Security.html
  and .../Prefs.html: `--remote-debugging-port`, `--remote-allow-hosts`,
  `--remote-allow-origins`; no pref or flag relates to client disconnect, idle, or quit.
- Bugzilla (REST quicksearch): bug 1739363 "When WebDriver BiDi client disconnects the active
  session is not removed" (NEW since 2021; Firefox keeps running by design); bug 1598832
  (Remote Agent shutdown; "Firefox doesn't trap signals"); bug 1574362 (headless
  `firefox-bin` high CPU on Linux 68-72, unreproduced, IPC broken-pipe noise, closest
  prior report, not this mechanism); bug 1066812 (content children self-destruct when the
  parent dies, which matches the observed disappearance of `plugin-container` children);
  bug 1403934 (headless macOS process lingering idle on a hidden dialog, Fx 57). Searches
  for `EPIPE`, `SIGPIPE`, "stdout closed", "headless orphan", "remote agent disconnect",
  "webdriver bidi CPU", `ProfileMissingDialog`, "headless modal dialog spin" return no bug
  describing the orphan-CPU symptom.
- geckodriver / mozrunner (`testing/geckodriver/src/{marionette,browser}.rs`,
  `testing/mozbase/rust/mozrunner/src/runner.rs`): graceful path is
  `Marionette:Quit [eForceQuit]` then wait up to `moz:shutdownTimeout` (default 90 s) then
  `Child::kill()` = SIGKILL; **no SIGTERM is ever sent**; stdio is inherited, never a pipe.
- Playwright (`packages/playwright-core/src/server/firefox/firefox.ts`, `browserType.ts`,
  `processLauncher`): `Browser.close` over the protocol, 30 s, then `SIGKILL` to the
  process group (`detached: true`, `process.kill(-pid)`); stdin `ignore`, stdout/stderr
  piped and drained.
- microsoft/playwright#42768 (opened 2026-09-18, closed 2026-10-19): identical symptom and
  stack (`SLEventSourceCounterForEventType -> CGSEventSourceForID -> CGSScoreboard`),
  identical root cause (TCC on `~/Library/Application Support/Firefox` on macOS 27, denied
  when the terminal is the responsible process), identical version split (146/153 hang
  until timeout, 155/156 exit `Could not find profile folder.` in ~200 ms), upstream fix
  https://phabricator.services.mozilla.com/D326501, workaround = point the app-data lookup
  elsewhere (`CFFIXED_USER_HOME` there, `MOZ_APP_DATA` here).

Searched and not found: a Firefox headless-mode page on firefox-source-docs (none exists;
the MDN "Headless mode" page is gone); any Mozilla statement that headless Firefox needs a
graceful quit to flush the profile.

## Cause, and how sure

**Reproduced cause of a 100% spin:** a startup-failure modal (`ProfileMissingDialog`) on
Firefox builds without the headless guard (144 confirmed, Playwright reports 146 and 153),
triggered on macOS 27 whenever the launching process lacks Full Disk Access, because
Firefox opens the TCC-protected `~/Library/Application Support/Firefox` even with
`--profile`. The spin is in the Cocoa app shell pumping an event loop for a modal that can
never be dismissed; it has nothing to do with stdout, EPIPE, the remote agent, or the
compositor. Such a process never prints the BiDi banner, so under the current
`Bibbidi.Browser` it is exactly the half-launched Firefox that the 5 s `Browser.url/1`
timeout leaves behind when the caller exits and the un-trapped Browser dies without
running `kill_tree/1`. The two bugs in `plans/browser-lifecycle.md` then feed each other
precisely as described, except that the launches were not slow, they had failed.

**Not reproduced:** any spin in a Firefox that had started successfully. On 157, the faithful
orphan (variant G: Bibbidi-exact `Port.open`, BiDi session opened, client BEAM killed,
owning BEAM killed, PPID 1, readerless pipes) idles at 0.6%, and so do the dead-pipe,
dead-stdin, headed, no-remote-port, and forced-EPIPE variants.

**Open gap:** the plan's observation was on 144 with tests that passed, i.e. launches that
succeeded. Firefox 144 could not be re-tested after the auto-update, and nothing in the 144
source diff touches post-startup behaviour, so the best explanation for those orphans is
that the run mixed successful launches with failed ones (every failed launch is a spinner,
and from a non-FDA shell every launch fails), or that the dev's shell was in the same TCC
situation as this one. If a successfully started orphan is ever seen at 100% again,
`sample <pid> 3` plus the symbolication service used here will settle it in minutes.

## Implications for the Launcher design

1. **The orphan state is benign; the leak is still the bug.** No flag, signal, or stdio
   trick is needed to stop an orphan from spinning. The Launcher's job remains exactly what
   #7 settled: bind the browser's lifetime to the BEAM process and kill the process group
   when the owner goes away, including on BEAM SIGKILL (which `erl_child_setup` does not
   handle for us).
2. **Fail fast on launch failure instead of waiting 15 s.** Watch the Port for
   `exit_status` and treat `Could not find profile folder.` on stderr as a terminal error
   (`{:error, :profile_inaccessible}` or similar). On 155+ Firefox exits in ~200 ms; on
   older builds the process spins and only the timeout catches it, so the timeout path must
   still kill the tree (it does today, but only when the GenServer survives long enough,
   which is the #7 problem).
3. **Set `MOZ_APP_DATA` (and probably `MOZ_LOCAL_APP_DATA`) to a bibbidi-owned temp dir**
   when spawning. It removes the TCC dependency on the launching process (Claude Code
   shells, CI agents, editors without Full Disk Access), stops bibbidi's Firefox from
   touching the user's real `profiles.ini`/`installs.ini`, and costs nothing. Clean it up
   with the profile dir. This is a flag-level change in `Bibbidi.Browser`, not in the
   Launcher contract.
4. **SIGTERM before SIGKILL buys nothing for Firefox.** TERM is an untrapped signal: same
   ~130 ms death, same `.parentlock` left behind, no profile flush. A grace period is only
   meaningful if the Connection first sends `browser.close` (the only graceful path, as
   geckodriver's `Marionette:Quit` and Playwright's `Browser.close` do). Recommendation
   for the default Launcher: `browser.close` when a live Connection exists and the stop is
   orderly, otherwise straight to SIGKILL of the process group, matching both reference
   drivers. The "does Firefox need TERM to flush the profile" item in #7 can be closed:
   it does not, because TERM does not flush anything.
5. **Closing stdin first does nothing to Firefox** (variant F); it neither exits nor
   changes behaviour on stdin EOF. The stdin-EOF trick in the planned `sh` wrapper is for
   the wrapper's own lifetime detection, which is fine, but do not expect Firefox to
   cooperate.
6. **Children clean themselves up.** `plugin-container` processes exited with their parent
   in every variant (bug 1066812 behaviour), so `kill_tree/1`'s `pgrep -P` walk is
   belt-and-braces, not load-bearing. Killing the process group covers it anyway.
7. **Keep `:stderr_to_stdout`.** The readiness banner is written with `Cu.printStderr`;
   without merging stderr the Launcher never sees it.
8. **Leak detection should match on the profile-dir prefix** in the command line
   (`pgrep -f bibbidi-firefox-`), not on `firefox`, so it coexists with other Firefoxes on
   the machine and with other test sessions.
9. **Update hygiene.** A long-lived orphan is a full Firefox: it can auto-update the
   installed `Firefox.app` under everyone else's feet (the update to 157 landed mid-run).
   `--remote-debugging-port` sets `app.update.disabledForTesting=true` via the recommended
   prefs, but only once the remote agent is up, which a failed launch never reaches.
   Another reason to kill failed launches promptly.
