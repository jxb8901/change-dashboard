#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v6-ssh.XXXXXX")" || exit 1
FAKE_SSH_LOG="$TEST_TEMP_DIR/ssh.log"
export FAKE_SSH_LOG
export PATH="$TEST_ROOT/tests/fixtures:$PATH"

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
  [[ "$actual" == "$expected" ]] || fail_test "$description: expected [$expected], got [$actual]"
}

(
  source "$TEST_ROOT/bin/lhc"
  PANEL_TITLES[0]='Timeout validation'
  PANEL_COMMANDS[0]='true'
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=8

  SSH_CONTROL_PERSIST_SECONDS=0
  if validate_config >/dev/null 2>&1; then
    fail_test "zero SSH_CONTROL_PERSIST_SECONDS was accepted"
  fi
  SSH_CONTROL_PERSIST_SECONDS=30
  SSH_CONNECT_TIMEOUT_SECONDS=301
  if validate_config >/dev/null 2>&1; then
    fail_test "oversized SSH_CONNECT_TIMEOUT_SECONDS was accepted"
  fi
)

wait_for_panel() {
  local panel_index="$1" attempts

  for ((attempts = 0; attempts < 80; attempts++)); do
    run_panel_commands || fail_test "SSH scheduler failed"
    [[ "${PANEL_COMMAND_ACTIVE[$panel_index]:-1}" -eq 0 ]] && return 0
    sleep 0.02
  done
  fail_test "panel $panel_index did not finish"
}

(
  source "$TEST_ROOT/bin/lhc"
  SSH_SERVERS=("APP|app")
  PANEL_TITLES[0]='Polling recovery'
  PANEL_COMMANDS[0]='printf "healthy\\n"'
  PANEL_SSH_ALIASES[0]='APP'
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=8

  validate_config || fail_test "polling recovery configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  wait_for_panel 0
  assert_equal "APP healthy" "${PANEL_OUTPUTS[0]}" "initial polling output"

  CONTROL_PATH="${SSH_CONTROL_PATHS[0]}"
  rm -rf "${CONTROL_PATH}.fake-state"
  PANEL_NEXT_RUN_SECONDS[0]=0
  wait_for_panel 0
  assert_equal "APP healthy" "${PANEL_OUTPUTS[0]}" "polling output after stale-master recovery"
  cleanup_panel_commands
)

RECOVERY_DROP_FILE="$TEST_TEMP_DIR/drop-first-channel"
export FAKE_SSH_DROP_FIRST_CHANNEL_FILE="$RECOVERY_DROP_FILE"
(
  source "$TEST_ROOT/bin/lhc"
  SSH_SERVERS=("APP|app")
  PANEL_TITLES[0]='Channel recovery'
  PANEL_COMMANDS[0]='printf "recovered\\n"'
  PANEL_SSH_ALIASES[0]='APP'
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=8

  validate_config || fail_test "channel recovery configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  wait_for_panel 0
  assert_equal "APP recovered" "${PANEL_OUTPUTS[0]}" "polling output after channel recovery"
  cleanup_panel_commands
)
unset FAKE_SSH_DROP_FIRST_CHANNEL_FILE

(
  source "$TEST_ROOT/bin/lhc"
  SSH_SERVERS=("APP|app")
  PANEL_TITLES[0]='Polling panel'
  PANEL_COMMANDS[0]='printf "polling\\n"'
  PANEL_SSH_ALIASES[0]='APP'
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=8
  PANEL_TITLES[1]='Dedicated stream'
  PANEL_COMMANDS[1]='while true; do printf "stream\\n"; sleep 0.02; done'
  PANEL_SSH_ALIASES[1]='APP'
  PANEL_STREAM[1]=1
  PANEL_X[1]=35; PANEL_Y[1]=1; PANEL_WIDTHS[1]=32; PANEL_HEIGHTS[1]=8

  validate_config || fail_test "mixed polling/stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=100; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  for ((attempt = 0; attempt < 80; attempt++)); do
    run_panel_commands || fail_test "mixed polling/stream scheduler failed"
    [[ "${PANEL_COMMAND_ACTIVE[0]:-1}" -eq 0 && -n "${PANEL_OUTPUTS[1]:-}" ]] && break
    sleep 0.02
  done
  assert_equal "APP polling" "${PANEL_OUTPUTS[0]}" "polling panel output"
  [[ "${PANEL_OUTPUTS[1]}" == *stream* ]] || fail_test "dedicated stream output was not collected"
  cleanup_panel_commands
)

MASTER_COUNT="$(awk '$1 == "master" { count += 1 } END { print count + 0 }' "$FAKE_SSH_LOG")"
CHANNEL_COUNT="$(awk '$1 == "channel" { count += 1 } END { print count + 0 }' "$FAKE_SSH_LOG")"
DEDICATED_COUNT="$(awk '$1 == "dedicated" { count += 1 } END { print count + 0 }' "$FAKE_SSH_LOG")"
assert_equal "5" "$MASTER_COUNT" "explicit polling master creation and recovery"
assert_equal "5" "$CHANNEL_COUNT" "polling channels including one retry"
assert_equal "1" "$DEDICATED_COUNT" "stream uses a dedicated SSH connection"

printf 'PASS: explicit polling masters, stale/channel recovery, and dedicated SSH streams\n'
