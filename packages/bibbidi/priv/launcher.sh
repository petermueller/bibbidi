#!/bin/sh
# Bibbidi default Launcher wrapper (prototype, issue #8).
#
# Usage: launcher.sh <executable> [args...]
#
# Runs <executable> as a child and binds its lifetime to this script's stdin:
#   * stdin EOF (Port closed, owner died, or BEAM SIGKILLed) -> TERM the whole
#     process group, wait $BIBBIDI_LAUNCHER_GRACE seconds, then KILL it.
#   * child exits on its own -> sweep the rest of the group, exit with its status
#     so the Port owner receives {:exit_status, n}.
#
# Erlang's erl_child_setup puts every port child in its own process group
# (pgid == pid), so this script is the group leader and `kill -- -$$` reaches
# the executable and every descendant it forks. If for some reason we are NOT
# a group leader (run by hand from a terminal), we fall back to walking the
# descendant tree so we never signal the caller's own group.
#
# Env:
#   BIBBIDI_LAUNCHER_GRACE  seconds between TERM and KILL (default 2)
#   BIBBIDI_LAUNCHER_RM_RF  directory to remove once the child is dead
#                           (basename must start with "bibbidi-")
#
# stdout/stderr are inherited by the child untouched, so the executable's
# own output (the "WebDriver BiDi listening on" line) streams through as-is.
# This script only ever prints one line, the banner below.

set -u

grace="${BIBBIDI_LAUNCHER_GRACE:-2}"
rm_dir="${BIBBIDI_LAUNCHER_RM_RF:-}"

pgid=$(ps -o pgid= -p $$ 2>/dev/null | tr -d '[:space:]')
[ -n "$pgid" ] || pgid="$$"

if [ "$pgid" = "$$" ]; then
  mode=group
else
  mode=tree
fi

# Keep a copy of the real stdin on fd 3. POSIX gives background jobs
# /dev/null as stdin when job control is off (dash does it unconditionally,
# bash unless the job redirects fd 0 itself), so the watchdog below must read
# from fd 3, not fd 0, or it would see EOF immediately. This is the portable
# version of Wallaby's `exec 0<&0 "$(...)"` trick.
exec 3<&0

# Fork the child BEFORE installing our own signal ignores: `trap ''` sets
# SIG_IGN, which survives exec, so a child forked after it would ignore TERM.
"$@" </dev/null 3<&- &
child=$!

# Ignore the signals we are about to send to our own group, so this shell and
# the watchdog survive long enough to escalate TERM -> KILL and to clean up.
trap '' TERM HUP INT

echo "BIBBIDI_LAUNCHER pid=$$ pgid=$pgid mode=$mode child=$child"

# The child owns stdout/stderr from here on. Silence the shell's own stderr so
# bash's "line N: PID Killed: 9" job notices don't land in the Port stream.
exec 2>/dev/null

# Descendants of $1 (recursive), excluding this shell. POSIX ps only.
descendants() {
  ps -A -o pid=,ppid= 2>/dev/null | awk -v root="$1" -v me="$$" '
    { kids[$2] = kids[$2] " " $1 }
    function walk(p,   n, i, arr) {
      n = split(kids[p], arr, " ")
      for (i = 1; i <= n; i++) if (arr[i] != "" && arr[i] != me) { print arr[i]; walk(arr[i]) }
    }
    END { walk(root) }'
}

# signal <SIG>: deliver to everything we own except this shell.
signal() {
  if [ "$mode" = group ]; then
    # Group signal includes $$ and the watchdog; both ignore TERM/HUP/INT.
    # No `--`: dash's builtin kill rejects it ("Illegal number: --"); both
    # dash and bash accept a negative pid after the signal instead.
    kill "-$1" "-$pgid" 2>/dev/null
  else
    pids=$(descendants "$child")
    # shellcheck disable=SC2086
    [ -n "$pids" ] && kill "-$1" $pids 2>/dev/null
  fi
  return 0
}

cleanup_dir() {
  case "$rm_dir" in
    "") ;;
    */bibbidi-*) [ -d "$rm_dir" ] && rm -rf "$rm_dir" ;;
    *) echo "BIBBIDI_LAUNCHER refusing to rm_rf $rm_dir" >&2 ;;
  esac
}

# Watchdog: block on stdin until EOF, then TERM -> grace -> KILL the group.
# Runs in a subshell so the main shell can `wait` on the child. It is itself
# in our group, so the final KILL also takes the watchdog down; if the main
# shell is already gone by then (BEAM died), the watchdog still does cleanup.
(
  trap '' TERM HUP INT
  while IFS= read -r _line; do :; done <&3
  signal TERM
  sleep "$grace"
  if [ "$mode" = group ]; then
    # Remove the dir before the KILL takes this subshell down too.
    cleanup_dir
    kill -KILL "-$pgid" 2>/dev/null
  else
    pids=$(descendants "$child")
    # shellcheck disable=SC2086
    [ -n "$pids" ] && kill -KILL $pids 2>/dev/null
    cleanup_dir
  fi
) 3<&3 &
watchdog=$!
exec 3<&-

wait "$child"
status=$?

# Child is gone (own exit, or TERM from the watchdog / the Elixir side).
# Sweep anything it left in the group, stop the watchdog, clean up, report.
kill -KILL "$watchdog" 2>/dev/null
if [ "$mode" = group ]; then
  pids=$(ps -A -o pid=,pgid= 2>/dev/null | awk -v g="$pgid" -v me="$$" '$2==g && $1!=me {print $1}')
else
  pids=$(descendants "$child")
fi
# shellcheck disable=SC2086
[ -n "$pids" ] && kill -KILL $pids 2>/dev/null
cleanup_dir
exit "$status"
