#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SAMPLE_COUNT="${LHC_BENCHMARK_COUNT:-50}"
TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v11-benchmark.XXXXXX")"
trap 'rm -rf "$TEST_TEMP_DIR"' EXIT

fail_benchmark() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

command -v perl >/dev/null 2>&1 || exit 0
command -v tail >/dev/null 2>&1 || fail_benchmark 'tail is required'
[[ -x /usr/bin/time ]] || fail_benchmark '/usr/bin/time is required'

PROCESS_METRICS_AVAILABLE=1
ps -axo pid=,ppid=,%cpu= >/dev/null 2>&1 || PROCESS_METRICS_AVAILABLE=0

stats_for_file() {
  perl -e '
    my ($file) = @ARGV;
    open my $fh, "<", $file or die $!;
    my @values;
    while (<$fh>) {
      my (undef, $value) = split / /;
      push @values, $value + 0;
    }
    @values = sort { $a <=> $b } @values;
    my $count = scalar @values;
    die "no latency samples\\n" unless $count;
    my $p50 = $values[int(($count * 0.50 + 0.999999)) - 1];
    my $p95 = $values[int(($count * 0.95 + 0.999999)) - 1];
    my $max = $values[$count - 1];
    printf "%.1f %.1f %.1f %d\n", $p50, $p95, $max, $count;
  ' "$1"
}

descendant_count() {
  local root="$1"
  ps -axo pid=,ppid= | awk -v root="$root" '
    { pid[++n] = $1; parent[$1] = $2 }
    END {
      seen[root] = 1
      changed = 1
      while (changed) {
        changed = 0
        for (i = 1; i <= n; i++) {
          if (!seen[pid[i]] && seen[parent[pid[i]]]) {
            seen[pid[i]] = 1
            changed = 1
          }
        }
      }
      count = 0
      for (i = 1; i <= n; i++) count += seen[pid[i]]
      print count
    }
  '
}

sample_process_metrics() {
  local pid="$1" cpu process_count

  (( PROCESS_METRICS_AVAILABLE == 1 )) || return 0
  cpu="$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d '[:space:]')"
  [[ "$cpu" =~ ^[0-9]+([.][0-9]+)?$ ]] || cpu=0
  if awk -v left="$cpu" -v right="$PEAK_CPU" 'BEGIN { exit !(left > right) }'; then
    PEAK_CPU="$cpu"
  fi
  process_count="$(descendant_count "$pid" 2>/dev/null || printf '0')"
  [[ "$process_count" =~ ^[0-9]+$ ]] || process_count=0
  if (( process_count > PEAK_PROCESSES )); then
    PEAK_PROCESSES="$process_count"
  fi
}

time_value() {
  awk -v key="$1" '$1 == key { print $2; exit }' "$2"
}

report_case() {
  local label="$1" rate="$2" sample_file="$3" time_file="$4" expected="$5"
  local stats p50 p95 max samples user sys dropped processes cpu

  stats="$(stats_for_file "$sample_file")"
  set -- $stats
  p50="$1"; p95="$2"; max="$3"; samples="$4"
  user="$(time_value user "$time_file")"
  sys="$(time_value sys "$time_file")"
  dropped=$((expected - samples))
  if (( PROCESS_METRICS_AVAILABLE == 1 )); then
    processes="$PEAK_PROCESSES"
    cpu="$PEAK_CPU"
  else
    processes=unavailable
    cpu=unavailable
  fi
  printf '%s rate=%s samples=%s p50=%sms p95=%sms max=%sms user=%ss sys=%ss peak_cpu=%s%% peak_processes=%s dropped=%s\n' \
    "$label" "$rate" "$samples" "$p50" "$p95" "$max" "$user" "$sys" "$cpu" "$processes" "$dropped"
}

run_tail_case() {
  local mode="$1" rate="$2" case_dir case_label
  local source_file output_fifo pid_file sample_file time_file
  local tail_pid producer_pid attempts lines

  case_label=follow
  [[ "$mode" == "-F" ]] && case_label=follow-name
  case_dir="$TEST_TEMP_DIR/tail-$case_label-$rate"
  source_file="$case_dir/source"
  output_fifo="$case_dir/output.fifo"
  pid_file="$case_dir/tail.pid"
  sample_file="$case_dir/samples"
  time_file="$case_dir/time"

  mkdir -p "$case_dir"
  : >"$source_file"
  mkfifo "$output_fifo"
  BENCH_TAIL_MODE="$mode" BENCH_SOURCE_FILE="$source_file" \
    BENCH_OUTPUT_FIFO="$output_fifo" BENCH_TAIL_PID_FILE="$pid_file" \
    BENCH_SAMPLE_FILE="$sample_file" BENCH_SAMPLE_COUNT="$SAMPLE_COUNT" \
    /usr/bin/time -p sh -c '
      tail -n 0 "$BENCH_TAIL_MODE" "$BENCH_SOURCE_FILE" >"$BENCH_OUTPUT_FIFO" &
      tail_pid=$!
      printf "%s\n" "$tail_pid" >"$BENCH_TAIL_PID_FILE"
      perl -MTime::HiRes -e '\''
        $| = 1;
        open my $out, ">", $ENV{BENCH_SAMPLE_FILE} or die $!;
        open my $pid_fh, "<", $ENV{BENCH_TAIL_PID_FILE} or die $!;
        my $tail_pid = <$pid_fh>;
        chomp $tail_pid;
        close $pid_fh;
        my $limit = $ENV{BENCH_SAMPLE_COUNT};
        my $count = 0;
        while (<STDIN>) {
          chomp;
          my ($sequence, $timestamp) = split / /;
          printf $out "%s %.6f\n", $sequence, (Time::HiRes::time() - $timestamp) * 1000;
          if (++$count >= $limit) {
            kill "KILL", $tail_pid;
            last;
          }
        }
        close $out;
      '\'' <"$BENCH_OUTPUT_FIFO"
      wait "$tail_pid" 2>/dev/null || true
    ' >/dev/null 2>"$time_file" &
  tail_pid=$!
  sleep 0.05
  LHC_EVENT_COUNT="$SAMPLE_COUNT" LHC_EVENT_RATE="$rate" \
    perl "$TEST_ROOT/tests/fixtures/stream_event_producer.pl" >>"$source_file" &
  producer_pid=$!

  PEAK_CPU=0
  PEAK_PROCESSES=0
  for ((attempt = 0; attempt < 600; attempt++)); do
    sample_process_metrics "$tail_pid"
    lines="$(wc -l <"$sample_file" | tr -d '[:space:]')"
    [[ "$lines" =~ ^[0-9]+$ ]] || lines=0
    (( lines >= SAMPLE_COUNT )) && break
    sleep 0.05
  done
  wait "$producer_pid"
  [[ "$lines" -ge "$SAMPLE_COUNT" ]] || fail_benchmark "$mode at ${rate}lps dropped all output before completion"
  wait "$tail_pid" 2>/dev/null || true
  report_case "tail$mode" "$rate" "$sample_file" "$time_file" "$SAMPLE_COUNT"
}

run_lhc_case() {
  local rate="$1" case_dir
  local input_fifo sample_fifo sample_file final_file timeout_file time_file lhc_pid

  case_dir="$TEST_TEMP_DIR/lhc-$rate"
  input_fifo="$case_dir/input"
  sample_fifo="$case_dir/sample-input"
  sample_file="$case_dir/samples"
  final_file="$case_dir/final"
  timeout_file="$case_dir/timeout"
  time_file="$case_dir/time"

  mkdir -p "$case_dir"
  mkfifo "$input_fifo" "$sample_fifo"
  /usr/bin/time -p env LHC_EVENT_COUNT="$SAMPLE_COUNT" LHC_EVENT_RATE="$rate" \
    bash "$TEST_ROOT/tests/fixtures/lhc_event_loop_case.sh" rate "$TEST_ROOT" \
    "$input_fifo" "$sample_file" "$final_file" "$timeout_file" "$SAMPLE_COUNT" \
    "$sample_fifo" >"$case_dir/output" 2>"$time_file" &
  lhc_pid=$!
  PEAK_CPU=0
  PEAK_PROCESSES=0
  while kill -0 "$lhc_pid" 2>/dev/null; do
    sample_process_metrics "$lhc_pid"
    sleep 0.05
  done
  wait "$lhc_pid" || fail_benchmark "LHC benchmark case failed at ${rate}lps"
  [[ ! -e "$timeout_file" ]] || fail_benchmark "LHC benchmark watchdog expired at ${rate}lps"
  report_case lhc "$rate" "$sample_file" "$time_file" "$SAMPLE_COUNT"
}

printf 'benchmark_count=%s\n' "$SAMPLE_COUNT"
for rate in 10 50; do
  run_tail_case -f "$rate"
  run_tail_case -F "$rate"
  run_lhc_case "$rate"
done
