#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

  PANEL_TITLES[0]="Local stream"
  PANEL_COMMANDS[0]='i=1; while (( i <= 4 )); do printf "line-%s\n" "$i"; i=$((i + 1)); sleep 0.04; done'
  PANEL_STREAM[0]=1
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=5

  validate_config || fail_test "local stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  RENDER_COUNT=0
  render_dashboard() { RENDER_COUNT=$((RENDER_COUNT + 1)); }

  for ((attempt = 0; attempt < 40; attempt++)); do
    run_panel_commands || fail_test "local stream scheduler failed"
    [[ "${PANEL_COMMAND_ACTIVE[0]:-0}" -eq 0 ]] && break
    sleep 0.03
  done

  assert_equal $'line-2\nline-3\nline-4' "${PANEL_OUTPUTS[0]}" "local stream keeps visible-height ring"
  [[ "${PANEL_COMMAND_ACTIVE[0]:-1}" -eq 0 ]] || fail_test "local stream did not finish"
  (( RENDER_COUNT > 0 )) || fail_test "local stream never rendered an update"
  COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
  cleanup_panel_commands
  [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_test "local stream cleanup left temp directory"
)

(
  source "$TEST_ROOT/bin/lhc"

  PANEL_TITLES[0]="Unbounded stream"
  PANEL_COMMANDS[0]='while true; do printf "tick\n"; sleep 1; done'
  PANEL_STREAM[0]=1
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=5

  validate_config || fail_test "long-running stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  run_panel_commands || fail_test "long-running stream scheduler failed"
  COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
  sleep 0.1
  cleanup_panel_commands
  [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_test "long-running stream cleanup left temp directory"
)

TAIL_TEST_FILE="$(mktemp "${TMPDIR:-/tmp}/lhc-v5-tail.XXXXXX")" || exit 1
(
  source "$TEST_ROOT/bin/lhc"

  PANEL_TITLES[0]="Tail follow"
  PANEL_COMMANDS[0]="tail -f \"$TAIL_TEST_FILE\""
  PANEL_STREAM[0]=1
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=5

  validate_config || fail_test "tail -f stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  run_panel_commands || fail_test "tail -f scheduler failed to start"
  printf 'tail-1\ntail-2\ntail-3\ntail-4\n' >>"$TAIL_TEST_FILE"

  for ((attempt = 0; attempt < 40; attempt++)); do
    run_panel_commands || fail_test "tail -f scheduler failed while reading"
    [[ "${PANEL_OUTPUTS[0]:-}" == $'tail-2\ntail-3\ntail-4' ]] && break
    sleep 0.03
  done
  assert_equal $'tail-2\ntail-3\ntail-4' "${PANEL_OUTPUTS[0]}" "tail -f rolling output"
  COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
  cleanup_panel_commands
  [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_test "tail -f cleanup left temp directory"
)
rm -f "$TAIL_TEST_FILE"

(
  source "$TEST_ROOT/bin/lhc"

  PANEL_TITLES[0]="Table stream"
  PANEL_COMMANDS[0]='i=1; while (( i <= 4 )); do printf "svc-%s %s OK\n" "$i" "$i"; i=$((i + 1)); sleep 0.04; done'
  PANEL_STREAM[0]=1
  PANEL_TABLE_COLUMNS[0]="SERVICE COUNT STATUS"
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=48; PANEL_HEIGHTS[0]=6

  validate_config || fail_test "local table stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }

  for ((attempt = 0; attempt < 50; attempt++)); do
    run_panel_commands || fail_test "local table stream scheduler failed"
    [[ "${PANEL_COMMAND_ACTIVE[0]:-0}" -eq 0 ]] && break
    sleep 0.03
  done

  assert_equal "table" "${PANEL_RENDER_MODES[0]}" "local table stream render mode"
  assert_equal "SERVICE COUNT STATUS" "${PANEL_TABLE_HEADERS[0]}" "local table stream header"
  assert_equal $'svc-2 2 OK\nsvc-3 3 OK\nsvc-4 4 OK' "${PANEL_TABLE_ROWS[0]}" "local table stream rolling rows"
  COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
  cleanup_panel_commands
  [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_test "local table stream cleanup left temp directory"
)

TABLE_TEST_FILE="$(mktemp "${TMPDIR:-/tmp}/lhc-v5-table.XXXXXX")" || exit 1
(
  source "$TEST_ROOT/bin/lhc"

  PANEL_TITLES[0]="Malformed table stream"
  PANEL_COMMANDS[0]="tail -f \"$TABLE_TEST_FILE\""
  PANEL_STREAM[0]=1
  PANEL_TABLE_COLUMNS[0]="SERVICE COUNT STATUS"
  PANEL_TABLE_LAYOUT[0]="table"
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=48; PANEL_HEIGHTS[0]=6

  validate_config || fail_test "malformed table stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  run_panel_commands || fail_test "malformed table stream scheduler failed to start"

  printf 'good-1 1 OK\nbad-row\ngood-2 2 OK\n' >>"$TABLE_TEST_FILE"
  for ((attempt = 0; attempt < 40; attempt++)); do
    run_panel_commands || fail_test "malformed table stream scheduler failed"
    [[ "${PANEL_RENDER_MODES[0]:-}" == "raw" ]] && break
    sleep 0.03
  done
  assert_equal "raw" "${PANEL_RENDER_MODES[0]}" "malformed table stream falls back to raw"

  printf 'good-3 3 OK\ngood-4 4 OK\ngood-5 5 OK\n' >>"$TABLE_TEST_FILE"
  for ((attempt = 0; attempt < 40; attempt++)); do
    run_panel_commands || fail_test "table stream recovery scheduler failed"
    [[ "${PANEL_RENDER_MODES[0]:-}" == "table" &&
       "${PANEL_TABLE_ROWS[0]:-}" == $'good-3 3 OK\ngood-4 4 OK\ngood-5 5 OK' ]] && break
    sleep 0.03
  done
  assert_equal "table" "${PANEL_RENDER_MODES[0]}" "table stream recovers after malformed row rolls out"
  assert_equal $'good-3 3 OK\ngood-4 4 OK\ngood-5 5 OK' "${PANEL_TABLE_ROWS[0]}" "table stream recovery rows"
  COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
  cleanup_panel_commands
  [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_test "malformed table stream cleanup left temp directory"
)
rm -f "$TABLE_TEST_FILE"

(
  source "$TEST_ROOT/bin/lhc"

  PANEL_TITLES[0]="Invalid stream table"
  PANEL_COMMANDS[0]='printf "A 1\n"'
  PANEL_STREAM[0]=1
  PANEL_TABLE_COLUMNS[0]="NAME VALUE"
  PANEL_TABLE_LAYOUT[0]="transpose"
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=5

  if validate_config >/dev/null 2>&1; then
    fail_test "stream table configuration was accepted"
  fi
)

STREAM_TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v5-stream.XXXXXX")" || exit 1
FAKE_SSH_LOG="$STREAM_TEST_TEMP_DIR/ssh.log"
export FAKE_SSH_LOG
PATH="$TEST_ROOT/tests/fixtures:$PATH"
export PATH

(
  source "$TEST_ROOT/bin/lhc"

  SSH_SERVERS=("A|a" "B|b" "FAIL|fail")
  PANEL_TITLES[0]="SSH stream"
  PANEL_COMMANDS[0]='case "$FAKE_SSH_TARGET" in a) printf "a-1\n"; sleep 0.04; printf "a-2\n" ;; b) printf "b-1\n"; sleep 0.08; printf "b-2\n" ;; esac'
  PANEL_SSH_ALIASES[0]="A B FAIL"
  PANEL_STREAM[0]=1
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=48; PANEL_HEIGHTS[0]=8

  validate_config || fail_test "SSH stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=100; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }

  for ((attempt = 0; attempt < 50; attempt++)); do
    run_panel_commands || fail_test "SSH stream scheduler failed"
    [[ "${PANEL_COMMAND_ACTIVE[0]:-0}" -eq 0 ]] && break
    sleep 0.03
  done

  EXPECTED=$'A a-1\nA a-2\nB b-1\nB b-2\nFAIL SSH_FAILED (exit 255)'
  assert_equal "$EXPECTED" "${PANEL_OUTPUTS[0]}" "SSH stream alias order and failure output"
  assert_equal "failed" "${PANEL_RENDER_MODES[0]}" "SSH stream failure mode"
  COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
  cleanup_panel_commands
  [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_test "SSH stream cleanup left temp directory"
)

(
  source "$TEST_ROOT/bin/lhc"

  SSH_SERVERS=("A|a" "FAIL|fail" "B|b")
  PANEL_TITLES[0]="SSH table stream"
  PANEL_COMMANDS[0]='case "$FAKE_SSH_TARGET" in a) printf "api 1 OK\n" ;; b) printf "cache-1 1 OK\ncache-2 2 OK\ncache-3 3 OK\ncache-4 4 OK\n" ;; esac'
  PANEL_SSH_ALIASES[0]="A FAIL B"
  PANEL_STREAM[0]=1
  PANEL_TABLE_COLUMNS[0]="SERVER APP COUNT STATUS"
  PANEL_TABLE_LAYOUT[0]="table"
  PANEL_TABLE_WIDTHS[0]="8 12 8"
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=60; PANEL_HEIGHTS[0]=8

  validate_config || fail_test "SSH table stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=100; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }

  for ((attempt = 0; attempt < 60; attempt++)); do
    run_panel_commands || fail_test "SSH table stream scheduler failed"
    [[ "${PANEL_COMMAND_ACTIVE[0]:-0}" -eq 0 ]] && break
    sleep 0.03
  done

  assert_equal "table" "${PANEL_RENDER_MODES[0]}" "SSH table stream render mode"
  assert_equal $'FAIL SSH_FAILED - -\nB cache-1 1 OK\nB cache-2 2 OK\nB cache-3 3 OK\nB cache-4 4 OK' "${PANEL_TABLE_ROWS[0]}" "SSH table stream rows"
  assert_equal "1" "${PANEL_SSH_FAILURE_ROWS[0]}" "SSH table stream failure row"
  assert_equal "ERROR" "${PANEL_STATUSES[0]}" "SSH table stream failure status"
  COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
  cleanup_panel_commands
  [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_test "SSH table stream cleanup left temp directory"
)

rm -rf "$STREAM_TEST_TEMP_DIR"

EVENT_TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v5-event.XXXXXX")" || exit 1
EVENT_FIFO="$EVENT_TEST_TEMP_DIR/input.fifo"
EVENT_STDIN_FIFO="$EVENT_TEST_TEMP_DIR/stdin.fifo"
EVENT_Q_STDIN_FIFO="$EVENT_TEST_TEMP_DIR/q-stdin.fifo"
EVENT_SNAPSHOT="$EVENT_TEST_TEMP_DIR/snapshot"
mkfifo "$EVENT_FIFO" "$EVENT_STDIN_FIFO" "$EVENT_Q_STDIN_FIFO" || exit 1
source "$TEST_ROOT/bin/lhc"
STREAM_REFRESH_PENDING=0
trap handle_stream_refresh USR1
exec 8<&0
exec 0<>"$EVENT_STDIN_FIFO"
stream_collect "$EVENT_FIFO" "$EVENT_SNAPSHOT" 3 "$$" &
COLLECTOR_PID=$!
(
  sleep 0.1
  printf 'event-line\n' >"$EVENT_FIFO"
) &
WRITER_PID=$!

wait_for_quit_or_timeout 1 || true
[[ "$STREAM_REFRESH_PENDING" -eq 1 ]] || fail_test "stream event did not interrupt the main wait"
assert_equal "event-line" "$(<"$EVENT_SNAPSHOT")" "stream event snapshot"
wait "$WRITER_PID"
wait "$COLLECTOR_PID"
exec 0<&8
trap - USR1

exec 8<&0
exec 0<>"$EVENT_Q_STDIN_FIFO"
exec 9>"$EVENT_Q_STDIN_FIFO"
handle_stream_refresh_with_q() {
  STREAM_REFRESH_PENDING=1
  printf 'q' >&9
}
trap handle_stream_refresh_with_q USR1
(
  sleep 0.1
  kill -USR1 "$$"
) &
Q_SIGNAL_PID=$!
if ! wait_for_quit_or_timeout 1; then
  fail_test "q was not handled after a stream signal interrupted the keyboard wait"
fi
wait "$Q_SIGNAL_PID"
exec 9>&-
exec 0<&8
trap - USR1
rm -rf "$EVENT_TEST_TEMP_DIR"
printf 'PASS: local and SSH raw streams, event-driven refresh, bounded buffers, validation, and cleanup\n'
