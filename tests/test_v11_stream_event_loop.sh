#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v11-event.XXXXXX")"
trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

command -v perl >/dev/null 2>&1 || exit 0

source "$TEST_ROOT/bin/lhc"
NO_COLOR=1

INPUT_FIFO="$TEST_TEMP_DIR/input"
EMIT_FILE="$TEST_TEMP_DIR/emitted"
DRAW_FILE="$TEST_TEMP_DIR/drawn"
mkfifo "$INPUT_FIFO"
export EMIT_FILE

PANEL_TITLES[0]='Event stream'
PANEL_COMMANDS[0]="sleep 0.2; perl -MTime::HiRes -e 'open my \$fh, \">\", \$ENV{EMIT_FILE} or die \$!; printf \$fh \"%.6f\\n\", Time::HiRes::time(); print \"event-token\\n\"; close \$fh'"
PANEL_STREAM[0]=1
PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=36; PANEL_HEIGHTS[0]=6
PANEL_TITLES[1]='Unchanged panel'
PANEL_COMMANDS[1]='printf "stable\\n"'
PANEL_X[1]=38; PANEL_Y[1]=1; PANEL_WIDTHS[1]=30; PANEL_HEIGHTS[1]=6

validate_config || fail_test 'event-loop configuration was rejected'
TERMINAL_ROWS=20; TERMINAL_COLS=100; resolve_panel_dimensions
calculate_required_terminal_size
initialize_loading_dashboard

eval "$(declare -f draw_frame_value | sed 's/^draw_frame_value/event_original_draw_frame_value/')"
draw_frame_value() {
  if [[ "$2" == *event-token* && ! -s "$DRAW_FILE" ]]; then
    perl -MTime::HiRes -e 'printf "%.6f\n", Time::HiRes::time()' >"$DRAW_FILE"
    printf 'q' >&0
  fi
  event_original_draw_frame_value "$@"
}

exec 7<&0
exec 0<>"$INPUT_FIFO"
render_dashboard >/dev/null
run_dashboard_loop >/dev/null
exec 0<&-
exec 0<&7
exec 7<&-

[[ -s "$EMIT_FILE" ]] || fail_test 'stream did not publish an emission timestamp'
[[ -s "$DRAW_FILE" ]] || fail_test 'stream did not reach the real renderer'
LATENCY_MS="$(perl -e '$start = <>; $end = <>; printf "%.0f\n", ($end - $start) * 1000' \
  "$EMIT_FILE" "$DRAW_FILE")"
[[ "$LATENCY_MS" =~ ^[0-9]+$ ]] || fail_test "invalid latency: $LATENCY_MS"
(( LATENCY_MS < 100 )) || fail_test "event render latency exceeded 100ms: ${LATENCY_MS}ms"
cleanup_panel_commands

(
  source "$TEST_ROOT/bin/lhc"
  PANEL_COMMAND_STREAM_CAPACITIES[0]=3
  PANEL_COMMAND_LAST_OUTPUTS[0]=''
  append_stream_event_line 0 one
  append_stream_event_line 0 two
  append_stream_event_line 0 three
  append_stream_event_line 0 four
  get_stream_job_output 0
  [[ "$FUNCTION_RESULT" == $'two\nthree\nfour' ]] ||
    fail_test "event ring lost or reordered lines: [$FUNCTION_RESULT]"
)

if grep -Eq 'STREAM_EVENT_POLL_SECONDS|sleep "\$STREAM_EVENT_POLL_SECONDS"' "$TEST_ROOT/bin/lhc"; then
  fail_test 'stream path still contains the fixed polling interval'
fi

printf 'PASS: event-driven stream wakeup, real-render latency, and bounded ring buffer\n'
