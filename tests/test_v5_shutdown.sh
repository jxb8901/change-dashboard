#!/usr/bin/env bash

set -u

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-v5-shutdown.XXXXXX")" || exit 1
FAKE_SSH_LOG="$TEST_TEMP_DIR/ssh.log"
export FAKE_SSH_LOG
export PATH="$TEST_ROOT/tests/fixtures:$PATH"
PROCESS_INSPECTION_AVAILABLE=1
ps -p "$$" -o pid= >/dev/null 2>&1 || PROCESS_INSPECTION_AVAILABLE=0

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" description="$3"
  [[ "$actual" == "$expected" ]] || fail_test "$description: expected [$expected], got [$actual]"
}

assert_file_contains() {
  local file="$1" expected="$2" description="$3"
  grep -Fq -- "$expected" "$file" || fail_test "$description: missing [$expected]"
}

assert_pids_gone() {
  local pid_file="$1" description="$2" pid_record pid remaining_pid alive attempt

  [[ -s "$pid_file" ]] || fail_test "$description: no process PIDs were recorded"
  # Some managed sandboxes deny process-table access even for known PIDs. The
  # production cleanup still exercises its ownership checks; on a normal host
  # this assertion verifies every recorded child, wrapper, and fake-SSH PID.
  (( PROCESS_INSPECTION_AVAILABLE == 1 )) || return 0
  for ((attempt = 0; attempt < 200; attempt++)); do
    alive=0
    remaining_pid=""
    while IFS= read -r pid_record; do
      [[ -n "$pid_record" ]] || continue
      pid="${pid_record##*:}"
      if kill -0 "$pid" 2>/dev/null; then
        alive=1
        remaining_pid="$pid_record"
        break
      fi
    done <"$pid_file"
    (( alive == 0 )) && return 0
    sleep 0.01
  done
  fail_test "$description: process $remaining_pid remains"
}

cleanup_test() {
  if [[ -n "${UNRELATED_PID:-}" ]]; then
    kill -KILL "$UNRELATED_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_TEMP_DIR"
}
trap cleanup_test EXIT

make_local_stream_config() {
  local file="$1"

  printf '%s\n' \
    'REFRESH_INTERVAL=1' \
    'PANEL_TITLES[0]="Local stream"' \
    'PANEL_STREAM[0]=1' \
    "PANEL_COMMANDS[0]='printf \"child:%s\\n\" \"\$\$\" >> \"\$LHC_TEST_PID_FILE\"; printf \"wrapper:%s\\n\" \"\$PPID\" >> \"\$LHC_TEST_PID_FILE\"; while true; do printf \"local-tick\\n\"; sleep 0.005; done'" \
    'PANEL_X[0]=1' \
    'PANEL_Y[0]=1' \
    'PANEL_WIDTHS[0]=30' \
    'PANEL_HEIGHTS[0]=8' >"$file"
}

make_ssh_stream_config() {
  local file="$1"

  printf '%s\n' \
    'REFRESH_INTERVAL=1' \
    'SSH_SERVERS[0]="A|a"' \
    'PANEL_TITLES[0]="SSH stream"' \
    'PANEL_STREAM[0]=1' \
    'PANEL_COMMANDS[0]='"'"'printf "remote:%s\\n" "$$" >> "$LHC_TEST_PID_FILE"; printf "fake-ssh:%s\\n" "$PPID" >> "$LHC_TEST_PID_FILE"; while true; do sleep 1; done'"'"'' \
    'PANEL_SSH_ALIASES[0]="A"' \
    'PANEL_X[0]=1' \
    'PANEL_Y[0]=1' \
    'PANEL_WIDTHS[0]=30' \
    'PANEL_HEIGHTS[0]=8' \
    'PANEL_TITLES[1]="SSH polling"' \
    'PANEL_COMMANDS[1]='"'"'printf "polling:%s\\n" "$$" >> "$LHC_TEST_PID_FILE"; while true; do sleep 1; done'"'"'' \
    'PANEL_SSH_ALIASES[1]="A"' \
    'PANEL_X[1]=1' \
    'PANEL_Y[1]=10' \
    'PANEL_WIDTHS[1]=30' \
    'PANEL_HEIGHTS[1]=8' >"$file"
}

make_slow_ssh_config() {
  local file="$1"

  printf '%s\n' \
    'REFRESH_INTERVAL=1' \
    'PANEL_TITLES[0]="Local while SSH starts"' \
    "PANEL_COMMANDS[0]='printf \"local:%s\\n\" \"\$\$\" >> \"\$LHC_TEST_PID_FILE\"'" \
    'PANEL_X[0]=1' \
    'PANEL_Y[0]=1' \
    'PANEL_WIDTHS[0]=30' \
    'PANEL_HEIGHTS[0]=8' \
    'SSH_SERVERS[1]="DOWN|down"' \
    'PANEL_TITLES[1]="Slow SSH"' \
    'PANEL_COMMANDS[1]='"'"'printf "unreachable\\n"'"'"'' \
    'PANEL_SSH_ALIASES[1]="DOWN"' \
    'PANEL_X[1]=1' \
    'PANEL_Y[1]=10' \
    'PANEL_WIDTHS[1]=30' \
    'PANEL_HEIGHTS[1]=8' >"$file"
}

make_ctrl_c_config() {
  local file="$1"

  printf '%s\n' \
    'REFRESH_INTERVAL=1' \
    'PANEL_TITLES[0]="Ctrl-C command"' \
    'PANEL_STREAM[0]=0' \
    "PANEL_COMMANDS[0]='printf \"child:%s\\n\" \"\$\$\" >> \"\$LHC_TEST_PID_FILE\"; printf \"wrapper:%s\\n\" \"\$PPID\" >> \"\$LHC_TEST_PID_FILE\"; while true; do printf \"interrupt-tick\\n\"; sleep 0.05; done'" \
    'PANEL_X[0]=1' \
    'PANEL_Y[0]=1' \
    'PANEL_WIDTHS[0]=30' \
    'PANEL_HEIGHTS[0]=8' >"$file"
}

run_q_case() {
  local name="$1" config="$2" output="$TEST_TEMP_DIR/$1.out"
  local pid_file="$TEST_TEMP_DIR/$1.pids"
  local ssh_pid_file="$TEST_TEMP_DIR/$1.ssh-pids"
  local timeout_file="$TEST_TEMP_DIR/$1.timeout"
  local dashboard_pid watchdog_pid rc
  rm -f "$pid_file" "$ssh_pid_file" "$timeout_file"
  export LHC_TEST_PID_FILE="$pid_file"
  export FAKE_SSH_PID_FILE="$ssh_pid_file"
  set +e
  { sleep 2; printf 'q'; } |
    LINES=20 COLUMNS=80 TERM=xterm bash "$TEST_ROOT/bin/lhc" "$config" >"$output" 2>"$output.err" &
  dashboard_pid=$!
  (
    sleep 5
    : >"$timeout_file"
    kill -TERM "$dashboard_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!
  wait "$dashboard_pid"
  rc=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null
  set -e
  assert_equal "0" "$rc" "$name q exit status"
  [[ ! -e "$timeout_file" ]] || fail_test "$name q shutdown exceeded five seconds"
  assert_file_contains "$output" $'\033[?25h' "$name cursor restoration"
  assert_file_contains "$output" $'\033[0m' "$name terminal attribute reset"
  assert_pids_gone "$pid_file" "$name q cleanup"
  if [[ "$name" == "ssh" || "$name" == "silent-ssh" || "$name" == "slow-ssh" ]]; then
    assert_pids_gone "$ssh_pid_file" "$name fake-SSH cleanup"
  fi
  unset LHC_TEST_PID_FILE FAKE_SSH_PID_FILE
}

LOCAL_CONFIG="$TEST_TEMP_DIR/local.conf"
SSH_CONFIG="$TEST_TEMP_DIR/ssh.conf"
SLOW_SSH_CONFIG="$TEST_TEMP_DIR/slow-ssh.conf"
CTRL_C_CONFIG="$TEST_TEMP_DIR/ctrl-c.conf"
make_local_stream_config "$LOCAL_CONFIG"
make_ssh_stream_config "$SSH_CONFIG"
make_slow_ssh_config "$SLOW_SSH_CONFIG"
make_ctrl_c_config "$CTRL_C_CONFIG"
run_q_case "local" "$LOCAL_CONFIG"
run_q_case "ssh" "$SSH_CONFIG"
export FAKE_SSH_MASTER_DELAY_SECONDS=3
export FAKE_SSH_MASTER_FAIL_TARGET=down
run_q_case "slow-ssh" "$SLOW_SSH_CONFIG"
unset FAKE_SSH_MASTER_DELAY_SECONDS FAKE_SSH_MASTER_FAIL_TARGET
assert_file_contains "$FAKE_SSH_LOG" "-O exit" "SSH control master close request"

if command -v script >/dev/null 2>&1 && command -v perl >/dev/null 2>&1 && (( PROCESS_INSPECTION_AVAILABLE == 1 )); then
  TTY_OUTPUT="$TEST_TEMP_DIR/tty.out"
  TTY_TYPESCRIPT="$TEST_TEMP_DIR/tty.typescript"
  TTY_PID_FILE="$TEST_TEMP_DIR/tty.pids"
  export LHC_TEST_PID_FILE="$TTY_PID_FILE"
  set +e
  script -q "$TTY_TYPESCRIPT" /bin/bash -c "stty rows 20 cols 80; exec /usr/bin/perl -e '\$SIG{INT}=\"DEFAULT\"; exec @ARGV' -- '$TEST_ROOT/bin/lhc' '$CTRL_C_CONFIG'" \
    >"$TTY_OUTPUT" 2>"$TTY_OUTPUT.err" &
  TTY_SCRIPT_PID=$!
  TTY_DASHBOARD_PID=""
  for ((attempt = 0; attempt < 100; attempt++)); do
    TTY_DASHBOARD_PID="$(ps -axo pid=,ppid=,command= | awk -v parent="$TTY_SCRIPT_PID" '$2 == parent && $0 ~ /\/bin\/lhc/ { print $1; exit }')"
    if [[ "$TTY_DASHBOARD_PID" =~ ^[1-9][0-9]*$ && -s "$TTY_PID_FILE" ]]; then
      break
    fi
    sleep 0.02
  done
  if [[ ! "$TTY_DASHBOARD_PID" =~ ^[1-9][0-9]*$ ]]; then
    kill -TERM "$TTY_SCRIPT_PID" 2>/dev/null || true
    wait "$TTY_SCRIPT_PID" 2>/dev/null || true
    fail_test "Ctrl-C dashboard PID was not discovered"
  fi
  # A terminal Ctrl-C targets the foreground process group. The macOS
  # script(1) wrapper can leave one extra bash layer between itself and lhc,
  # so signal the discovered foreground group rather than only its leader.
  kill -INT -"$TTY_DASHBOARD_PID" 2>/dev/null || true
  wait "$TTY_SCRIPT_PID"
  TTY_RC=$?
  set -e
  (( TTY_RC != 0 )) || fail_test "Ctrl-C pseudo-terminal case unexpectedly succeeded"
  assert_file_contains "$TTY_TYPESCRIPT" $'\033[?25h' "Ctrl-C cursor restoration"
  assert_file_contains "$TTY_TYPESCRIPT" $'\033[0m' "Ctrl-C terminal attribute reset"
  assert_pids_gone "$TTY_PID_FILE" "Ctrl-C cleanup"
  unset LHC_TEST_PID_FILE
elif command -v script >/dev/null 2>&1; then
  printf 'SKIP: Ctrl-C pseudo-terminal case requires process inspection and perl\n'
fi

(
  # The child ignores TERM; cleanup must escalate without an unbounded wait.
  source "$TEST_ROOT/bin/lhc"
  PANEL_TITLES[0]='TERM-resistant stream'
  PANEL_COMMANDS[0]='trap "" TERM; while true; do sleep 1; done'
  PANEL_STREAM[0]=1
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=30; PANEL_HEIGHTS[0]=8
  validate_config || fail_test "TERM-resistant stream configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  run_panel_commands || fail_test "TERM-resistant stream did not start"
  for ((attempt = 0; attempt < 20; attempt++)); do
    [[ -s "${PANEL_COMMAND_CHILD_PID_FILES[0]}" ]] && break
    sleep 0.02
  done
  [[ -s "${PANEL_COMMAND_CHILD_PID_FILES[0]}" ]] || fail_test "child PID was not published"
  CHILD_PID="$(<"${PANEL_COMMAND_CHILD_PID_FILES[0]}")"
  WRAPPER_PID="${PANEL_COMMAND_PIDS[0]}"
  SECONDS=0
  cleanup_panel_commands 2>/dev/null
  (( SECONDS <= 2 )) || fail_test "bounded cleanup exceeded two seconds: ${SECONDS}s"
  process_is_running "$CHILD_PID" && fail_test "TERM-resistant child survived cleanup"
  process_is_running "$WRAPPER_PID" && fail_test "job wrapper survived cleanup"
  assert_equal "0" "$PANEL_COMMAND_JOB_COUNT" "cleanup resets active job state"
)

(
  # Repeated completed snapshots must be compacted instead of accumulating
  # historical PIDs and result metadata.
  source "$TEST_ROOT/bin/lhc"
  REFRESH_INTERVAL=1
  PANEL_TITLES[0]='Repeated snapshot'
  PANEL_COMMANDS[0]='printf "done\\n"'
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=30; PANEL_HEIGHTS[0]=8
  validate_config || fail_test "repeated snapshot configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  for ((cycle = 0; cycle < 20; cycle++)); do
    PANEL_NEXT_RUN_SECONDS[0]=0
    for ((attempt = 0; attempt < 40; attempt++)); do
      run_panel_commands || fail_test "snapshot scheduler failed on cycle $cycle"
      [[ "${PANEL_COMMAND_ACTIVE[0]:-0}" -eq 0 ]] && break
      sleep 0.02
    done
    [[ "${PANEL_COMMAND_ACTIVE[0]:-1}" -eq 0 ]] || fail_test "snapshot did not complete on cycle $cycle"
    assert_equal "0" "$PANEL_COMMAND_JOB_COUNT" "active job records remain bounded on cycle $cycle"
  done
  cleanup_panel_commands
)

(
  # A PID record from a completed job must not be enough to signal an
  # unrelated process that happens to be alive under a different parent.
  source "$TEST_ROOT/bin/lhc"
  PANEL_TITLES[0]='PID ownership'
  PANEL_COMMANDS[0]='while true; do sleep 1; done'
  PANEL_STREAM[0]=1
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=30; PANEL_HEIGHTS[0]=8
  validate_config || fail_test "PID ownership configuration was rejected"
  TERMINAL_ROWS=20; TERMINAL_COLS=80; resolve_panel_dimensions
  initialize_loading_dashboard
  render_dashboard() { :; }
  run_panel_commands || fail_test "PID ownership stream did not start"
  for ((attempt = 0; attempt < 20; attempt++)); do
    [[ -s "${PANEL_COMMAND_CHILD_PID_FILES[0]}" && -s "${PANEL_COMMAND_CHILD_IDENTITY_FILES[0]}" ]] && break
    sleep 0.02
  done
  [[ -s "${PANEL_COMMAND_CHILD_PID_FILES[0]}" ]] || fail_test "PID ownership child PID was not published"
  ORIGINAL_IDENTITY="$(<"${PANEL_COMMAND_CHILD_IDENTITY_FILES[0]}")"
  sleep 30 &
  UNRELATED_PID=$!
  printf '%s\n' "$UNRELATED_PID" >"${PANEL_COMMAND_CHILD_PID_FILES[0]}"
  printf '%s\n' "$ORIGINAL_IDENTITY" >"${PANEL_COMMAND_CHILD_IDENTITY_FILES[0]}"
  cleanup_panel_commands
  process_is_running "$UNRELATED_PID" || fail_test "PID ownership guard signalled unrelated process"
  kill -KILL "$UNRELATED_PID" 2>/dev/null || true
  UNRELATED_PID=""
)

printf 'PASS: q/INT shutdown, bounded escalation, PID lifecycle, ownership checks, and SSH master cleanup\n'
