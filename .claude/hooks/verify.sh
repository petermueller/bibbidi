#!/usr/bin/env bash
#
# Stop hook: enforce bibbidi's "verify before finishing" rule.
#
# Runs   mix compile --warnings-as-errors && mix format --check-formatted && mix test.all
# from packages/bibbidi/ whenever the working tree has uncommitted changes under
# lib/ or test/. If any step fails, the hook blocks the stop (exit 2) and feeds the
# failure back to Claude so it keeps working instead of finishing on a broken tree.
#
# Design notes:
#   * Only fires when Elixir source/test files actually changed — chat-only and
#     read-only turns stop instantly.
#   * Honors a loop guard (stop_hook_active) so a single block can't spiral.
#   * Escape hatches:
#       - touch .claude/.skip-verify        (persistent: disable until removed)
#       - export BBD_SKIP_VERIFY=1          (per-session)
#       - export BBD_VERIFY_FAST=1          (skip integration; run unit `mix test`)
#
set -uo pipefail

input="$(cat)"

# jq is used elsewhere in this repo's tooling; fall back gracefully if absent.
stop_active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null || echo false)"
[ "$stop_active" = "true" ] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PKG_DIR="$PROJECT_DIR/packages/bibbidi"

# Nothing to verify if the package isn't here.
[ -d "$PKG_DIR" ] || exit 0

# Escape hatches.
[ -f "$PROJECT_DIR/.claude/.skip-verify" ] && exit 0
[ "${BBD_SKIP_VERIFY:-}" = "1" ] && exit 0

# Only run when lib/ or test/ have uncommitted changes (staged or unstaged, incl. untracked).
changed="$(git -C "$PROJECT_DIR" status --porcelain -- \
  packages/bibbidi/lib packages/bibbidi/test 2>/dev/null)"
[ -z "$changed" ] && exit 0

if [ "${BBD_VERIFY_FAST:-}" = "1" ]; then
  test_cmd="mix test"
else
  test_cmd="mix test.all"
fi

# Run the gate, capturing output for the failure message.
out="$(cd "$PKG_DIR" && \
  mix compile --warnings-as-errors 2>&1 && \
  mix format --check-formatted 2>&1 && \
  eval "$test_cmd" 2>&1)"
status=$?

[ $status -eq 0 ] && exit 0

# Block the stop. stderr is fed back to Claude on a Stop hook.
{
  echo "Verification gate failed before finishing (compile --warnings-as-errors -> format --check-formatted -> $test_cmd)."
  echo "Fix the issue below, then continue. To bypass: touch .claude/.skip-verify, or set BBD_SKIP_VERIFY=1; for unit-only, set BBD_VERIFY_FAST=1."
  echo "----"
  printf '%s\n' "$out" | tail -40
} >&2
exit 2
