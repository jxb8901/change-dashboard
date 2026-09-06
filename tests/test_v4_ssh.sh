#!/usr/bin/env bash

set -u

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v4-test.XXXXXX")" || exit 1
FAKE_SSH_LOG="$TEST_TEMP_DIR/ssh.log"
export FAKE_SSH_LOG
export PATH="$TEST_ROOT/tests/fixtures:$PATH"

# shellcheck source=../../bin/lhc
source "$TEST_ROOT/bin/lhc"

cleanup_test() {
  cleanup_panel_commands
  rm -rf "$TEST_TEMP_DIR"
}
trap cleanup_test EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" description="$3"
  [[ "$actual" == "$expected" ]] || fail_test "$description: expected [$expected], got [$actual]"
}

assert_contains() {
  local content="$1" expected="$2" description="$3"
  [[ "$content" == *"$expected"* ]] || fail_test "$description: missing [$expected]"
}

SSH_SERVERS=(
  "SLOW|slow"
  "FAST|fast"
  "FAIL|fail"
  "RAW|raw"
  "EMPTY|empty"
)

PANEL_TITLES[0]="SSH Table"
PANEL_COMMANDS[0]='case "$FAKE_SSH_TARGET" in slow) sleep 1; printf "FPP 2 10\nAPI 0 4\n" ;; fast) printf "FPP 3 11\n" ;; esac'
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=45
PANEL_HEIGHTS[0]=10
PANEL_TABLE_COLUMNS[0]="SERVER APP EAIQ ICLQ"
PANEL_TABLE_WIDTHS[0]="8 8 6 6"
PANEL_ERROR_RULES[0]="ICLQ:>10"
PANEL_SSH_ALIASES[0]="SLOW FAST FAIL"

PANEL_TITLES[1]="SSH Raw"
PANEL_COMMANDS[1]='case "$FAKE_SSH_TARGET" in raw) printf '\''literal=$HOME semi=; quote="ok"\nsecond line\n'\'' ;; empty) : ;; esac'
PANEL_X[1]=1
PANEL_Y[1]=12
PANEL_WIDTHS[1]=60
PANEL_HEIGHTS[1]=8
PANEL_SSH_ALIASES[1]="RAW EMPTY FAIL"

PANEL_TITLES[2]="SSH Transpose"
PANEL_COMMANDS[2]='case "$FAKE_SSH_TARGET" in fast) printf "FPP 3 11\nAPI 1 5\n" ;; slow) sleep 1; printf "FPP 2 10\nAPI 0 4\n" ;; esac'
PANEL_X[2]=62
PANEL_Y[2]=1
PANEL_WIDTHS[2]=30
PANEL_HEIGHTS[2]=20
PANEL_TABLE_COLUMNS[2]="SERVER APP EAIQ ICLQ"
PANEL_TABLE_LAYOUT[2]="transpose"
PANEL_TABLE_WIDTHS[2]="8 12"
PANEL_SSH_ALIASES[2]="FAST SLOW"

validate_config || fail_test "valid V4 configuration was rejected"
initialize_loading_dashboard

RENDER_COUNT=0
RENDER_ORDER=""
declare -a TEST_PANEL_RECORDED=()
render_dashboard() {
  local panel_index
  RENDER_COUNT=$((RENDER_COUNT + 1))
  for panel_index in "${PANEL_ORDER[@]}"; do
    [[ "${PANEL_OUTPUTS[$panel_index]:-Loading...}" == "Loading..." ]] && continue
    [[ "${TEST_PANEL_RECORDED[$panel_index]:-0}" -eq 1 ]] && continue
    TEST_PANEL_RECORDED[$panel_index]=1
    RENDER_ORDER="${RENDER_ORDER}${panel_index} "
  done
}

SECONDS=0
run_panel_commands || fail_test "V4 command scheduler failed"
while (( RENDER_COUNT < 3 )); do
  run_panel_commands || fail_test "V4 scheduler polling failed"
  sleep 0.05
done
ELAPSED="$SECONDS"
(( ELAPSED <= 2 )) || fail_test "SSH jobs did not run concurrently: ${ELAPSED}s"
assert_equal "3" "$RENDER_COUNT" "each panel should render exactly once after aggregation"
assert_equal "1" "${RENDER_ORDER%% *}" "fast panel should render while slow panels are still loading"

EXPECTED_TABLE=$'SLOW FPP 2 10\nSLOW API 0 4\nFAST FPP 3 11\nFAIL SSH_FAILED - -'
assert_equal "$EXPECTED_TABLE" "${PANEL_TABLE_ROWS[0]}" "table aggregation order"
assert_equal "table" "${PANEL_RENDER_MODES[0]}" "table render mode"
assert_equal "ERROR" "${PANEL_STATUSES[0]}" "table failure status"
get_table_status_line 0 4
assert_equal "ERROR ERROR ERROR ERROR" "$FUNCTION_RESULT" "synthetic failure row status"

EXPECTED_RAW=$'RAW literal=$HOME semi=; quote="ok"\nRAW second line\nEMPTY No data\nFAIL SSH_FAILED (exit 255)'
assert_equal "$EXPECTED_RAW" "${PANEL_OUTPUTS[1]}" "raw aggregation and command quoting"
assert_equal "failed" "${PANEL_RENDER_MODES[1]}" "raw failure render mode"

EXPECTED_TRANSPOSE=$'FAST FPP 3 11\nFAST API 1 5\nSLOW FPP 2 10\nSLOW API 0 4'
assert_equal "$EXPECTED_TRANSPOSE" "${PANEL_TABLE_ROWS[2]}" "multi-row transpose aggregation"
assert_equal "transpose" "${PANEL_RENDER_MODES[2]}" "transpose render mode"

TRANSPOSE_CAPTURE=""
frame_add() {
  local text="$4"
  [[ -n "$text" ]] && TRANSPOSE_CAPTURE="${TRANSPOSE_CAPTURE}${text}|"
}
build_transpose_frame 2
EXPECTED_CAPTURE="SERVER|FAST|APP|FPP|EAIQ|3|ICLQ|11|SERVER|FAST|APP|API|EAIQ|1|ICLQ|5|SERVER|SLOW|APP|FPP|EAIQ|2|ICLQ|10|SERVER|SLOW|APP|API|EAIQ|0|ICLQ|4|"
assert_equal "$EXPECTED_CAPTURE" "$TRANSPOSE_CAPTURE" "transpose renders one block per source row"

SSH_LOG_CONTENT="$(<"$FAKE_SSH_LOG")"
assert_contains "$SSH_LOG_CONTENT" "-o BatchMode=yes" "BatchMode SSH option"
assert_contains "$SSH_LOG_CONTENT" "-o ConnectTimeout=10" "connect timeout SSH option"
assert_contains "$SSH_LOG_CONTENT" "-o StrictHostKeyChecking=yes" "host key SSH option"
assert_contains "$SSH_LOG_CONTENT" "-o ControlMaster=auto" "SSH control master option"
assert_contains "$SSH_LOG_CONTENT" "-o ControlPersist=yes" "SSH control persist option"
assert_contains "$SSH_LOG_CONTENT" "-o ControlPath=" "SSH control path option"
assert_contains "$SSH_LOG_CONTENT" "bash -s" "remote Bash invocation"

MASTER_COUNT="$(printf '%s\n' "$SSH_LOG_CONTENT" | awk '$1 == "master" { count += 1 } END { print count + 0 }')"
CHANNEL_COUNT="$(printf '%s\n' "$SSH_LOG_CONTENT" | awk '$1 == "channel" { count += 1 } END { print count + 0 }')"
assert_equal "5" "$MASTER_COUNT" "one SSH master per target"
assert_equal "3" "$CHANNEL_COUNT" "additional SSH commands use logical channels"

for panel_index in "${PANEL_ORDER[@]}"; do
  PANEL_NEXT_RUN_SECONDS[$panel_index]=0
done
while (( RENDER_COUNT < 6 )); do
  run_panel_commands || fail_test "second SSH refresh failed"
  sleep 0.05
done
SSH_LOG_CONTENT="$(<"$FAKE_SSH_LOG")"
MASTER_COUNT="$(printf '%s\n' "$SSH_LOG_CONTENT" | awk '$1 == "master" { count += 1 } END { print count + 0 }')"
CHANNEL_COUNT="$(printf '%s\n' "$SSH_LOG_CONTENT" | awk '$1 == "channel" { count += 1 } END { print count + 0 }')"
assert_equal "5" "$MASTER_COUNT" "SSH masters persist across refreshes"
assert_equal "11" "$CHANNEL_COUNT" "refreshes use new logical channels"

COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
cleanup_panel_commands
[[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_test "command temporary directory was not removed"
assert_equal "0" "$PANEL_COMMAND_JOB_COUNT" "cleanup resets job count"

ORIGINAL_SERVER="${SSH_SERVERS[1]}"
SSH_SERVERS[1]="SLOW|duplicate"
if validate_ssh_configs >/dev/null 2>&1; then
  fail_test "duplicate registry alias was accepted"
fi
SSH_SERVERS[1]="$ORIGINAL_SERVER"

ORIGINAL_ALIASES="${PANEL_SSH_ALIASES[0]}"
PANEL_SSH_ALIASES[0]="SLOW UNKNOWN"
if validate_ssh_configs >/dev/null 2>&1; then
  fail_test "unknown panel alias was accepted"
fi
PANEL_SSH_ALIASES[0]="$ORIGINAL_ALIASES"

ORIGINAL_COLUMNS="${PANEL_TABLE_COLUMNS[0]}"
PANEL_TABLE_COLUMNS[0]="SERVER"
if validate_ssh_configs >/dev/null 2>&1; then
  fail_test "SSH table without command-output column was accepted"
fi
PANEL_TABLE_COLUMNS[0]="$ORIGINAL_COLUMNS"

PANEL_OUTPUTS[8]=$'FAST too many fields here'
PANEL_TABLE_COLUMNS[8]="SERVER APP VALUE"
PANEL_TABLE_LAYOUT[8]="table"
PANEL_SSH_FAILURE_ROWS[8]=""
prepare_panel_output 8
assert_equal "raw" "${PANEL_RENDER_MODES[8]}" "malformed SSH table falls back to raw"

PANEL_OUTPUTS[9]=$'one 1\ntwo 2'
PANEL_TABLE_COLUMNS[9]="NAME VALUE"
PANEL_TABLE_LAYOUT[9]="transpose"
PANEL_TABLE_WIDTHS[9]="8 10"
PANEL_WIDTHS[9]=30
PANEL_HEIGHTS[9]=8
PANEL_SSH_FAILURE_ROWS[9]=""
unset 'PANEL_SSH_ALIASES[9]'
prepare_panel_output 9
assert_equal "transpose" "${PANEL_RENDER_MODES[9]}" "local multi-row transpose render mode"
assert_equal $'one 1\ntwo 2' "${PANEL_TABLE_ROWS[9]}" "local multi-row transpose rows"

TRANSPOSE_CAPTURE=""
build_transpose_frame 9
EXPECTED_LOCAL_CAPTURE="NAME|one|VALUE|1|NAME|two|VALUE|2|"
assert_equal "$EXPECTED_LOCAL_CAPTURE" "$TRANSPOSE_CAPTURE" "local transpose renders one block per source row"

PANEL_COMMAND_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v4-cleanup.XXXXXX")" || fail_test "cleanup temp dir"
PANEL_COMMAND_JOB_COUNT=0
PANEL_COMMAND_PIDS=()
PANEL_COMMAND_OUTPUT_FILES=()
PANEL_COMMAND_STATUS_FILES=()
PANEL_COMMAND_INPUT_FILES=()
PANEL_COMMAND_ERROR_FILES=()
PANEL_COMMANDS[0]='sleep 30'
start_panel_command_job 0 "SLOW" "slow"
sleep 0.1
SECONDS=0
INTERRUPT_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
cleanup_panel_commands
(( SECONDS <= 2 )) || fail_test "cleanup did not promptly terminate an active SSH job"
[[ ! -e "$INTERRUPT_TEMP_DIR" ]] || fail_test "active-job cleanup left its temporary directory"

printf 'PASS: local/SSH execution, aggregation, multi-row transpose, and validation\n'
