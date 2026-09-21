#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v9-starting.XXXXXX")" || exit 1
FAKE_SSH_LOG="$TEST_TEMP_DIR/ssh.log"
DELAY_FILE="$TEST_TEMP_DIR/delay-master"
export FAKE_SSH_LOG
export FAKE_SSH_MASTER_DELAY_FILE="$DELAY_FILE"
export FAKE_SSH_MASTER_DELAY_FILE_SECONDS=3
export PATH="$TEST_ROOT/tests/fixtures:$PATH"
: >"$DELAY_FILE"

cleanup_test_temp() {
  rm -rf "$TEST_TEMP_DIR"
}
trap cleanup_test_temp EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" description="$3"
  [[ "$actual" == "$expected" ]] ||
    fail_test "$description: expected [$expected], got [$actual]"
}

(
  source "$TEST_ROOT/bin/lhc"
  SSH_SERVERS=("APP|app")
  PANEL_TITLES[0]='STARTING recovery'
  PANEL_COMMANDS[0]='printf "starting-recovered\\n"'
  PANEL_SSH_ALIASES[0]='APP'
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=36; PANEL_HEIGHTS[0]=8

  validate_config || fail_test 'STARTING recovery configuration was rejected'
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }

  run_panel_commands || fail_test 'initial scheduler tick failed'
  CONTROL_PATH="${SSH_CONTROL_PATHS[0]}"

  observed_starting=0
  for ((attempt = 0; attempt < 100; attempt++)); do
    read_ssh_master_state "$CONTROL_PATH"
    if [[ "$FUNCTION_RESULT" == "STARTING" && -s "${CONTROL_PATH}.worker-pid" ]]; then
      observed_starting=1
      break
    fi
    sleep 0.02
  done
  [[ "$observed_starting" -eq 1 ]] ||
    fail_test 'SSH master never exposed STARTING with a worker PID'

  old_worker_pid="$(<"${CONTROL_PATH}.worker-pid")"
  kill -KILL "$old_worker_pid" 2>/dev/null || true
  wait "$old_worker_pid" 2>/dev/null || true
  rm -f "$DELAY_FILE"

  completed=0
  for ((attempt = 0; attempt < 260; attempt++)); do
    run_panel_commands || fail_test 'scheduler failed during STARTING recovery'
    read_ssh_master_state "$CONTROL_PATH"
    master_count="$(awk '$1 == "master" { count += 1 } END { print count + 0 }' "$FAKE_SSH_LOG")"
    if [[ "$FUNCTION_RESULT" == "READY" &&
      "${PANEL_COMMAND_ACTIVE[0]:-1}" -eq 0 &&
      "${PANEL_OUTPUTS[0]:-}" == "APP starting-recovered" &&
      "$master_count" -ge 2 ]]; then
      completed=1
      break
    fi
    sleep 0.02
  done
  [[ "$completed" -eq 1 ]] ||
    fail_test 'dead STARTING worker was not replaced and completed'

  new_worker_pid="$(<"${CONTROL_PATH}.worker-pid")"
  [[ "$new_worker_pid" != "$old_worker_pid" ]] ||
    fail_test 'replacement reused the dead STARTING worker PID record'
  [[ ! -e "${CONTROL_PATH}.lock" ]] ||
    fail_test 'STARTING recovery left a stale lock'
  [[ ! -e "${CONTROL_PATH}.recover" && ! -e "${CONTROL_PATH}.retry-after" ]] ||
    fail_test 'STARTING recovery left stale retry metadata'

  assert_equal "2" "$master_count" 'STARTING recovery master count'
  cleanup_panel_commands
)

printf 'PASS: dead STARTING SSH workers are recovered safely\n'
