#!/usr/bin/env bash

set -eu

MODE="$1"
TEST_ROOT="$2"
INPUT_FIFO="$3"

fail_case() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

source "$TEST_ROOT/bin/lhc"
STREAM_REFRESH_PID="$$"

case "$MODE" in
  rate)
    SAMPLE_FILE="$4"
    FINAL_FILE="$5"
    TIMEOUT_FILE="$6"
    COUNT="$7"
    SAMPLE_FIFO="$8"
    RATE="${LHC_EVENT_RATE:-1}"
    PANEL_TITLES[0]="${RATE} lps event stream"
    PANEL_COMMANDS[0]="perl '$TEST_ROOT/tests/fixtures/stream_event_producer.pl'"
    PANEL_STREAM[0]=1
    # Keep the latency case at a normal dashboard height. The separate final
    # suffix assertion proves that a sustained producer does not lose events
    # beyond the intentional visible-ring truncation.
    PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=64; PANEL_HEIGHTS[0]=8

    validate_config || fail_case "${RATE} lps event-loop configuration was rejected"
    TERMINAL_ROWS=20; TERMINAL_COLS=90; resolve_panel_dimensions
    calculate_required_terminal_size
    initialize_loading_dashboard

    perl -MTime::HiRes -e \
      '$|=1; while (<STDIN>) { chomp; my ($sequence, $timestamp) = split / /; printf "%s %.6f\n", $sequence, (Time::HiRes::time() - $timestamp) * 1000; }' \
      <"$SAMPLE_FIFO" >"$SAMPLE_FILE" &
    SAMPLE_SINK_PID=$!
    exec 6>"$SAMPLE_FIFO"
    RENDERED_SEQUENCES=""

    record_render_sample() {
      local text="$1" sequence timestamp target_sequence
      target_sequence="$(printf '%04d' "$COUNT")"
      if [[ "$text" =~ ^event-([0-9]+)[[:space:]]+([0-9]+\.[0-9]+) ]]; then
        sequence="${BASH_REMATCH[1]}"
        timestamp="${BASH_REMATCH[2]}"
        if [[ " $RENDERED_SEQUENCES " != *" $sequence "* ]]; then
          printf '%s %s\n' "$sequence" "$timestamp" >&6
          RENDERED_SEQUENCES="$RENDERED_SEQUENCES $sequence"
        fi
        if [[ "$sequence" == "$target_sequence" ]]; then
          printf 'q' >&0
        fi
      fi
    }

    eval "$(declare -f draw_frame_value | sed 's/^draw_frame_value/event_original_draw_frame_value/')"
    draw_frame_value() {
      record_render_sample "$2"
      event_original_draw_frame_value "$@"
    }

    exec 7<&0
    exec 0<>"$INPUT_FIFO"
    render_dashboard >/dev/null
    (
      sleep 15
      : >"$TIMEOUT_FILE"
      printf 'q' >"$INPUT_FIFO"
    ) &
    WATCHDOG_PID=$!
    run_dashboard_loop >/dev/null
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
    exec 0<&-
    exec 0<&7
    exec 7<&-
    exec 6>&-
    wait "$SAMPLE_SINK_PID"

    [[ ! -e "$TIMEOUT_FILE" ]] || fail_case "${RATE} lps event loop watchdog expired"
    printf '%s\n' "${PANEL_OUTPUTS[0]:-}" >"$FINAL_FILE"
    COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
    cleanup_panel_commands
    [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_case "${RATE} lps cleanup left command temp directory"
    ;;

  scheduler)
    COUNT_FILE="$4"
    REFRESH_INTERVAL=1
    PANEL_TITLES[0]='Scheduler deadline'
    PANEL_COMMANDS[0]='printf "tick\\n" >>"$SCHEDULER_COUNT_FILE"'
    PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=32; PANEL_HEIGHTS[0]=6
    validate_config || fail_case 'scheduler deadline configuration was rejected'
    TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
    initialize_loading_dashboard
    render_dashboard() { :; }
    DASHBOARD_EVENT_LOOP_ACTIVE=0
    run_panel_commands || fail_case 'initial scheduler tick failed'
    for ((attempt = 0; attempt < 40; attempt++)); do
      [[ "${PANEL_COMMAND_ACTIVE[0]:-1}" -eq 0 ]] && break
      sleep 0.05
      run_panel_commands || fail_case 'initial scheduler completion failed'
    done
    [[ "${PANEL_COMMAND_ACTIVE[0]:-1}" -eq 0 ]] || fail_case 'initial scheduler command did not complete'

    # The completion marker was deliberately not published to the wake FIFO.
    # The next wait must therefore be released by the scheduler deadline, not
    # by a stream event or a fixed idle poll.
    DASHBOARD_EVENT_LOOP_ACTIVE=1
    PANEL_NEXT_RUN_SECONDS[0]=$((SECONDS + 1))
    get_dashboard_wait_seconds
    WAIT_SECONDS="$FUNCTION_RESULT"
    [[ "$WAIT_SECONDS" == 1 ]] || fail_case "unexpected scheduler wait: $WAIT_SECONDS"
    START_TIME="$(date +%s)"
    wait_for_dashboard_event "$WAIT_SECONDS" || true
    END_TIME="$(date +%s)"
    (( END_TIME > START_TIME )) || fail_case 'scheduler deadline wait returned before its deadline'

    PANEL_NEXT_RUN_SECONDS[0]=0
    run_panel_commands || fail_case 'scheduler did not fire after its deadline'
    TICKS="$(wc -l <"$COUNT_FILE" | tr -d '[:space:]')"
    (( TICKS >= 2 )) || fail_case "scheduler deadline did not fire while idle: ${TICKS} ticks"
    cleanup_panel_commands
    ;;

  shutdown)
    CLEANUP_MARKER="$4"
    PANEL_TITLES[0]='Burst shutdown'
    PANEL_COMMANDS[0]='i=1; while (( i <= 10 )); do printf "burst-%s\\n" "$i"; i=$((i + 1)); done'
    PANEL_STREAM[0]=1
    PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=40; PANEL_HEIGHTS[0]=8
    validate_config || fail_case 'burst shutdown configuration was rejected'
    TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
    initialize_loading_dashboard
    render_dashboard() { :; }
    exec 7<&0
    exec 0<>"$INPUT_FIFO"
    render_dashboard >/dev/null
    (
      sleep 0.2
      printf 'q' >"$INPUT_FIFO"
    ) &
    WATCHDOG_PID=$!
    run_dashboard_loop >/dev/null
    kill "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
    exec 0<&-
    exec 0<&7
    exec 7<&-
    COMMAND_TEMP_DIR="$PANEL_COMMAND_TEMP_DIR"
    cleanup_panel_commands
    [[ ! -e "$COMMAND_TEMP_DIR" ]] || fail_case 'burst shutdown left event queue/temp files'
    : >"$CLEANUP_MARKER"
    ;;

  *)
    fail_case "unknown event-loop case: $MODE"
    ;;
esac
