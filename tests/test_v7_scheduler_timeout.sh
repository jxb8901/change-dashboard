#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" description="$3"
  [[ "$actual" == "$expected" ]] ||
    fail_test "$description: expected [$expected], got [$actual]"
}

source "$TEST_ROOT/bin/lhc"

configure_local_panel() {
  PANEL_TITLES=()
  PANEL_COMMANDS=()
  PANEL_SSH_ALIASES=()
  PANEL_STREAM=()
  PANEL_X=()
  PANEL_Y=()
  PANEL_WIDTHS=()
  PANEL_HEIGHTS=()
  PANEL_TIMEOUT_SECONDS=()
  PANEL_COUNT=1
  PANEL_ORDER=(0)
  COMMAND_TIMEOUT_SECONDS=0
  REFRESH_INTERVAL=2
  PANEL_TITLES[0]="Timeout test"
  PANEL_COMMANDS[0]="sleep 5"
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=40; PANEL_HEIGHTS[0]=6
  validate_config || fail_test "timeout test configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
}

run_until_panel_finishes() {
  local attempt

  for ((attempt = 0; attempt < 50; attempt++)); do
    run_panel_commands || fail_test "scheduler returned an unexpected failure"
    [[ "${PANEL_COMMAND_ACTIVE[0]:-1}" -eq 0 ]] && return 0
    sleep 0.05
  done
  fail_test "panel did not finish within the bounded test window"
}

# Issue #4: scheduler-level failure must propagate and leave no active panel.
configure_local_panel
PANEL_COMMAND_TEMP_DIR=""
mktemp() { return 1; }
if run_panel_commands; then
  fail_test "mktemp scheduler failure was swallowed"
fi
assert_equal "0" "${PANEL_COMMAND_ACTIVE[0]:-1}" "mktemp failure rolled back panel activity"
unset -f mktemp
cleanup_panel_commands

# Issue #4: a failed stream job start must roll back a partially initialized panel.
configure_local_panel
PANEL_TITLES[1]="Second panel"
PANEL_COMMANDS[1]="sleep 5"
PANEL_STREAM[1]=1
PANEL_X[1]=42; PANEL_Y[1]=1; PANEL_WIDTHS[1]=36; PANEL_HEIGHTS[1]=6
validate_config || fail_test "stream start failure configuration was rejected"
resolve_panel_dimensions
mkfifo() { return 1; }
if run_panel_commands; then
  fail_test "mkfifo scheduler failure was swallowed"
fi
assert_equal "0" "${PANEL_COMMAND_ACTIVE[0]:-1}" "mkfifo failure rolled back panel activity"
assert_equal "0" "${PANEL_COMMAND_ACTIVE[1]:-1}" "partial panel start rolled back all activity"
unset -f mkfifo
FAILED_START_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
cleanup_panel_commands
[[ ! -e "$FAILED_START_TEMP_DIR" ]] || fail_test "partial start temp directory survived cleanup"

# Issue #4: the dashboard loop must return the scheduler failure to its caller.
configure_local_panel
if ( run_panel_commands() { return 1; }; run_dashboard_loop ); then
  fail_test "dashboard loop swallowed scheduler failure"
fi

# Issue #5: the global timeout replaces stale successful data with an error state.
configure_local_panel
COMMAND_TIMEOUT_SECONDS=1
PANEL_COMMANDS[0]="printf 'old success\\n'"
run_until_panel_finishes
assert_equal "old success" "${PANEL_OUTPUTS[0]}" "pre-timeout successful output"
PANEL_COMMANDS[0]="sleep 5"
PANEL_NEXT_RUN_SECONDS[0]=0
run_until_panel_finishes
assert_equal "TIMEOUT after 1s" "${PANEL_OUTPUTS[0]}" "local timeout message"
assert_equal "failed" "${PANEL_RENDER_MODES[0]}" "local timeout render mode"
assert_equal "TIMEOUT" "${PANEL_STATUSES[0]}" "local timeout status"
assert_equal "0" "$PANEL_COMMAND_JOB_COUNT" "timed-out local job was reaped"
cleanup_panel_commands

# Issue #5: a per-panel timeout overrides the unlimited global default and kills
# a TERM-resistant child through the existing bounded escalation path.
configure_local_panel
COMMAND_TIMEOUT_SECONDS=0
PANEL_TIMEOUT_SECONDS[0]=1
PANEL_COMMANDS[0]="trap '' TERM; sleep 5"
run_until_panel_finishes
assert_equal "TIMEOUT after 1s" "${PANEL_OUTPUTS[0]}" "panel timeout message"
assert_equal "0" "$PANEL_COMMAND_JOB_COUNT" "TERM-resistant job was reaped"
cleanup_panel_commands

# Issue #5: an SSH polling command is bounded without leaking its channel/master.
SSH_TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v7-ssh.XXXXXX")" || exit 1
FAKE_SSH_LOG="$SSH_TEST_TEMP_DIR/ssh.log"
export FAKE_SSH_LOG
PATH="$TEST_ROOT/tests/fixtures:$PATH"
export PATH
source "$TEST_ROOT/bin/lhc"
COMMAND_TIMEOUT_SECONDS=1
SSH_SERVERS=("APP|app")
PANEL_TITLES[0]="SSH timeout"
PANEL_COMMANDS[0]="trap '' TERM; sleep 5; printf remote"
PANEL_SSH_ALIASES[0]="APP"
PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=40; PANEL_HEIGHTS[0]=6
validate_config || fail_test "SSH timeout configuration was rejected"
TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
initialize_loading_dashboard
render_dashboard() { :; }
run_until_panel_finishes
assert_equal "TIMEOUT after 1s" "${PANEL_OUTPUTS[0]}" "SSH timeout message"
assert_equal "failed" "${PANEL_RENDER_MODES[0]}" "SSH timeout render mode"
assert_equal "0" "$PANEL_COMMAND_JOB_COUNT" "timed-out SSH job was reaped"
SSH_COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
cleanup_panel_commands
[[ ! -e "$SSH_COMMAND_TEMP_DIR" ]] || fail_test "SSH timeout cleanup left scheduler state"
rm -rf "$SSH_TEST_TEMP_DIR"

printf 'PASS: scheduler failure rollback and local/SSH command timeouts\n'
