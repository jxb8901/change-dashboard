#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v10-output.XXXXXX")" || exit 1
export FAKE_SSH_LOG="$TEST_TEMP_DIR/ssh.log"
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
  [[ "$actual" == "$expected" ]] ||
    fail_test "$description: expected [$expected], got [$actual]"
}

(
  source "$TEST_ROOT/bin/lhc"

  sanitize_terminal_output 'plain ASCII'
  assert_equal 'plain ASCII' "$FUNCTION_RESULT" 'ASCII output changed'

  control_input=$'A\033[31mB\033[0m\033[2JC\033]0;title\aD\rE\tF\a\b\f\v\nG'
  sanitize_terminal_output "$control_input"
  assert_equal $'ABCDE F\nG' "$FUNCTION_RESULT" 'CSI/OSC/control sanitization'

  st_input=$'before\033]title\033\\after'
  sanitize_terminal_output "$st_input"
  assert_equal 'beforeafter' "$FUNCTION_RESULT" 'OSC ST sanitization'

  STREAM_SNAPSHOT="$TEST_TEMP_DIR/stream.snapshot"
  printf '\033[36mstream\033[0m\tvalue\r\n' >"$STREAM_SNAPSHOT"
  read_stream_snapshot "$STREAM_SNAPSHOT"
  assert_equal 'stream value' "$FUNCTION_RESULT" 'stream snapshot sanitization'

  PANEL_TITLES[0]='Raw output'
  PANEL_COMMANDS[0]="printf '\\033[31mraw\\033[0m\\033[2J\\033[H\\rready\\tline\\a\\n'"
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=28; PANEL_HEIGHTS[0]=6

  PANEL_TITLES[1]='Table output'
  PANEL_COMMANDS[1]="printf '\\033[32mREADY\\033[0m\\t1\\r\\n'"
  PANEL_X[1]=30; PANEL_Y[1]=1; PANEL_WIDTHS[1]=28; PANEL_HEIGHTS[1]=6
  PANEL_TABLE_COLUMNS[1]='STATE COUNT'
  PANEL_TABLE_WIDTHS[1]='10'
  PANEL_ERROR_RULES[1]='STATE:==READY'

  PANEL_TITLES[2]='Transpose output'
  PANEL_COMMANDS[2]="printf '\\033]0;dashboard-title\\aREADY 2 BLUE\\n'"
  PANEL_X[2]=59; PANEL_Y[2]=1; PANEL_WIDTHS[2]=28; PANEL_HEIGHTS[2]=6
  PANEL_TABLE_COLUMNS[2]='STATE COUNT COLOR'
  PANEL_TABLE_LAYOUT[2]='transpose'
  PANEL_TABLE_WIDTHS[2]='10 10'

  SSH_SERVERS=("APP|app")
  PANEL_TITLES[3]='SSH table output'
  PANEL_COMMANDS[3]="printf '\\033[35mAPPSTATE\\033[0m\\t2\\r\\n'"
  PANEL_SSH_ALIASES[3]='APP'
  PANEL_X[3]=88; PANEL_Y[3]=1; PANEL_WIDTHS[3]=30; PANEL_HEIGHTS[3]=6
  PANEL_TABLE_COLUMNS[3]='SERVER STATE COUNT'
  PANEL_TABLE_WIDTHS[3]='8 12'
  PANEL_ERROR_RULES[3]='STATE:==APPSTATE'

  validate_config || fail_test 'output sanitization configuration was rejected'
  TERMINAL_ROWS=10; TERMINAL_COLS=120; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }

  complete=0
  for ((attempt = 0; attempt < 160; attempt++)); do
    run_panel_commands || fail_test 'output sanitization scheduler failed'
    complete=1
    for index in "${PANEL_ORDER[@]}"; do
      [[ "${PANEL_COMMAND_ACTIVE[$index]:-1}" -eq 0 ]] || complete=0
    done
    (( complete == 1 )) && break
    sleep 0.02
  done
  (( complete == 1 )) || fail_test 'sanitized panels did not complete'

  assert_equal 'rawready line' "${PANEL_OUTPUTS[0]}" 'raw output sanitization'
  assert_equal 'table' "${PANEL_RENDER_MODES[1]}" 'table mode after sanitization'
  assert_equal 'READY 1' "${PANEL_TABLE_ROWS[1]}" 'table row after sanitization'
  assert_equal 'ERROR' "${PANEL_STATUSES[1]}" 'table rule after sanitization'
  assert_equal 'transpose' "${PANEL_RENDER_MODES[2]}" 'transpose mode after sanitization'
  assert_equal 'READY 2 BLUE' "${PANEL_TABLE_ROWS[2]}" 'transpose row after sanitization'
  assert_equal 'table' "${PANEL_RENDER_MODES[3]}" 'SSH table mode after sanitization'
  assert_equal 'APP APPSTATE 2' "${PANEL_TABLE_ROWS[3]}" 'SSH row after sanitization'
  assert_equal 'ERROR' "${PANEL_STATUSES[3]}" 'SSH table rule after sanitization'

  cleanup_panel_commands
)

printf 'PASS: terminal control output is sanitized consistently\n'
