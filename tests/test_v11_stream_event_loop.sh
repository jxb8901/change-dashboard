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

run_rate_case() {
  local rate="$1" count="$2" case_dir
  local input_fifo sample_file sample_fifo final_file timeout_file

  case_dir="$TEST_TEMP_DIR/rate-$rate"
  input_fifo="$case_dir/input"
  sample_file="$case_dir/samples"
  sample_fifo="$case_dir/sample-input"
  final_file="$case_dir/final"
  timeout_file="$case_dir/timeout"

  mkdir -p "$case_dir"
  mkfifo "$input_fifo" "$sample_fifo"
  LHC_EVENT_COUNT="$count" LHC_EVENT_RATE="$rate" \
    bash "$TEST_ROOT/tests/fixtures/lhc_event_loop_case.sh" rate "$TEST_ROOT" \
    "$input_fifo" "$sample_file" "$final_file" "$timeout_file" "$count" "$sample_fifo" ||
    fail_test "${rate} lps event-loop case failed"

  [[ -s "$sample_file" ]] || fail_test "${rate} lps stream produced no renderer samples"
  [[ -s "$final_file" ]] || fail_test "${rate} lps stream produced no final panel output"
  [[ ! -e "$timeout_file" ]] || fail_test "${rate} lps stream exceeded its bounded test interval"

  perl -e '
    my ($minimum, $last_expected, $file) = @ARGV;
    open my $fh, "<", $file or die $!;
    my @lines = <$fh>;
    my $previous = 0;
    for my $line (@lines) {
      chomp $line;
      my ($seq) = split / /, $line;
      die "sample sequence is not numeric\\n" unless $seq =~ /^[0-9]+$/;
      die "sample sequence was reordered: previous $previous got $seq\\n" unless $seq > $previous;
      $previous = $seq;
    }
    die "too few renderer samples: expected at least $minimum got " . scalar(@lines) . "\\n"
      unless scalar(@lines) >= $minimum;
    die "renderer did not catch up to final event: expected $last_expected got $previous\\n"
      unless $previous == $last_expected;
  ' 25 "$count" "$sample_file" || fail_test "${rate} lps samples lost, reordered, or lagged"

  perl -e '
    my ($first_expected, $expected_count, $file) = @ARGV;
    open my $fh, "<", $file or die $!;
    my @lines = <$fh>;
    my $next = $first_expected;
    for my $line (@lines) {
      chomp $line;
      my ($seq) = $line =~ /^event-([0-9]+) /;
      die "final sequence is not numeric\\n" unless defined $seq;
      die "final sequence lost or reordered: expected $next got $seq\\n" unless $seq == $next;
      $next++;
    }
    die "final visible sequence count mismatch: expected $expected_count got " . scalar(@lines) . "\\n"
      unless scalar(@lines) == $expected_count;
  ' $((count - 5)) 6 "$final_file" || fail_test "${rate} lps final stream output lost or reordered lines"

  perl -e '
    my ($rate, $file) = @ARGV;
    open my $fh, "<", $file or die $!;
    my @values;
    while (<$fh>) {
      my (undef, $value) = split / /;
      push @values, $value + 0;
    }
    @values = sort { $a <=> $b } @values;
    my $count = scalar @values;
    die "no latency values\\n" unless $count;
    my $p50 = $values[int(($count * 0.50 + 0.999999)) - 1];
    my $p95 = $values[int(($count * 0.95 + 0.999999)) - 1];
    my $max = $values[$count - 1];
    printf "PASS: %s lps samples=%d p50=%.1fms p95=%.1fms max=%.1fms\\n", $rate, $count, $p50, $p95, $max;
    die "p95 render latency exceeded 100ms: $p95 ms\\n" if $p95 >= 100;
  ' "$rate" "$sample_file" || fail_test "${rate} lps p95 latency or backlog bound failed"
}

run_rate_case 10 50
run_rate_case 50 50

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

(
  source "$TEST_ROOT/bin/lhc"
  PANEL_ORDER=(0)
  PANEL_STREAM[0]=1
  PANEL_COMMAND_ACTIVE[0]=1
  PANEL_COMMAND_JOB_COUNT=1
  PANEL_COMMAND_PANEL_INDEXES[0]=0
  PANEL_COMMAND_STREAMS[0]=1
  PANEL_COMMAND_STREAM_CAPACITIES[0]=6
  PANEL_COMMAND_STREAM_CHANGED[0]=0
  PANEL_COMMAND_LAST_OUTPUTS[0]=$'line-1\nline-2\nline-3\nline-4\nline-5\nline-6'
  STREAM_EVENT_CHANNEL_ACTIVE=1
  TERMINAL_ROWS=20
  TERMINAL_COLS=80
  RESIZED_HEIGHT=8

  read_terminal_size() { :; }
  resolve_panel_dimensions() { PANEL_EFFECTIVE_HEIGHTS[0]="$RESIZED_HEIGHT"; }
  calculate_required_terminal_size() {
    REQUIRED_COLS=1
    REQUIRED_TERMINAL_ROWS=1
  }
  validate_effective_panel_layout() { return 0; }
  render_dashboard() { :; }

  process_terminal_resize || fail_test 'initial stream resize was rejected'
  [[ "${PANEL_COMMAND_STREAM_CAPACITIES[0]}" == 6 ]] ||
    fail_test 'initial stream capacity was not recorded'

  RESIZED_HEIGHT=5
  process_terminal_resize || fail_test 'stream shrink resize was rejected'
  [[ "${PANEL_COMMAND_STREAM_CAPACITIES[0]}" == 3 ]] ||
    fail_test 'stream shrink did not update the job capacity'
  [[ "${PANEL_COMMAND_LAST_OUTPUTS[0]}" == $'line-4\nline-5\nline-6' ]] ||
    fail_test "stream shrink did not trim the existing ring: [${PANEL_COMMAND_LAST_OUTPUTS[0]}]"

  append_stream_event_line 0 line-7
  [[ "${PANEL_COMMAND_LAST_OUTPUTS[0]}" == $'line-5\nline-6\nline-7' ]] ||
    fail_test "stream shrink did not persist for new lines: [${PANEL_COMMAND_LAST_OUTPUTS[0]}]"

  RESIZED_HEIGHT=8
  process_terminal_resize || fail_test 'stream grow resize was rejected'
  [[ "${PANEL_COMMAND_STREAM_CAPACITIES[0]}" == 6 ]] ||
    fail_test 'stream grow did not update the job capacity'
  append_stream_event_line 0 line-8
  [[ "${PANEL_COMMAND_LAST_OUTPUTS[0]}" == $'line-5\nline-6\nline-7\nline-8' ]] ||
    fail_test "stream grow did not expand the ring for new lines: [${PANEL_COMMAND_LAST_OUTPUTS[0]}]"
)

SCHEDULER_TEMP_DIR="$TEST_TEMP_DIR/scheduler"
mkdir -p "$SCHEDULER_TEMP_DIR"
SCHEDULER_COUNT_FILE="$SCHEDULER_TEMP_DIR/count"
SCHEDULER_INPUT_FIFO="$SCHEDULER_TEMP_DIR/input"
mkfifo "$SCHEDULER_INPUT_FIFO"
export SCHEDULER_COUNT_FILE
bash "$TEST_ROOT/tests/fixtures/lhc_event_loop_case.sh" scheduler "$TEST_ROOT" \
  "$SCHEDULER_INPUT_FIFO" "$SCHEDULER_COUNT_FILE" ||
  fail_test 'scheduler deadline event-loop case failed'

SHUTDOWN_DIR="$TEST_TEMP_DIR/shutdown"
mkdir -p "$SHUTDOWN_DIR"
SHUTDOWN_INPUT_FIFO="$SHUTDOWN_DIR/input"
SHUTDOWN_MARKER="$SHUTDOWN_DIR/clean"
mkfifo "$SHUTDOWN_INPUT_FIFO"
bash "$TEST_ROOT/tests/fixtures/lhc_event_loop_case.sh" shutdown "$TEST_ROOT" \
  "$SHUTDOWN_INPUT_FIFO" "$SHUTDOWN_MARKER" ||
  fail_test 'burst shutdown event-loop case failed'
[[ -f "$SHUTDOWN_MARKER" ]] || fail_test 'burst shutdown did not complete cleanup marker'

if grep -Eq 'STREAM_EVENT_POLL_SECONDS|sleep "\$STREAM_EVENT_POLL_SECONDS"' "$TEST_ROOT/bin/lhc"; then
  fail_test 'stream path still contains the fixed polling interval'
fi

printf 'PASS: event-driven stream p95, sustained rates, scheduler deadline, burst shutdown, and bounded ring buffer\n'
