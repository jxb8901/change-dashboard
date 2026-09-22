#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for required_command in ssh sshd ssh-keygen ssh-keyscan sed awk ps tr; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'SKIP: real OpenSSH integration requires %s\n' "$required_command"
    exit 0
  fi
done

TEST_TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lhc-real-ssh.XXXXXX")" || exit 1
SSHD_PID=""
WATCHDOG_PID=""
CLIENT_HOME="$TEST_TEMP_DIR/home"
SSH_DIR="$CLIENT_HOME/.ssh"
HOST_ALIAS="lhc-issue10"
TEST_USER="$(id -un)"
HOST_KEY="$TEST_TEMP_DIR/ssh_host_ed25519_key"
CLIENT_KEY="$TEST_TEMP_DIR/client_ed25519"
AUTHORIZED_KEYS="$TEST_TEMP_DIR/authorized_keys"
SSHD_CONFIG="$TEST_TEMP_DIR/sshd_config"
SSHD_LOG="$TEST_TEMP_DIR/sshd.log"
KNOWN_HOSTS="$SSH_DIR/known_hosts"
CLIENT_CONFIG="$SSH_DIR/config"
REMOTE_CONNECTION_LOG="$TEST_TEMP_DIR/remote-connections.log"
CONTROL_DIR="$TEST_TEMP_DIR/control"
SSH_WRAPPER_DIR="$TEST_TEMP_DIR/bin"
SSH_WRAPPER="$SSH_WRAPPER_DIR/ssh"
REAL_OPENSSH_SKIP_FILE="$TEST_TEMP_DIR/skip"
REAL_OPENSSH_TIMEOUT_SECONDS="${REAL_OPENSSH_TIMEOUT_SECONDS:-90}"
CURRENT_STAGE="setup"

stage() {
  CURRENT_STAGE="$1"
  printf 'STAGE: %s\n' "$CURRENT_STAGE" >&2
}

start_watchdog() {
  (
    sleep "$REAL_OPENSSH_TIMEOUT_SECONDS"
    printf '%s\n' "real OpenSSH test exceeded ${REAL_OPENSSH_TIMEOUT_SECONDS}s" >&2
    kill -TERM "$$" 2>/dev/null || true
  ) &
  WATCHDOG_PID=$!
}

stop_watchdog() {
  if [[ -n "$WATCHDOG_PID" ]]; then
    kill -TERM "$WATCHDOG_PID" 2>/dev/null || true
    wait "$WATCHDOG_PID" 2>/dev/null || true
    WATCHDOG_PID=""
  fi
}

cleanup_test_temp() {
  stop_watchdog
  if [[ -n "$SSHD_PID" ]]; then
    kill -TERM "$SSHD_PID" 2>/dev/null || true
    wait "$SSHD_PID" 2>/dev/null || true
    SSHD_PID=""
  fi
  [[ "${KEEP_TEST_TEMP_DIR:-0}" == 1 ]] || rm -rf "$TEST_TEMP_DIR"
}
trap cleanup_test_temp EXIT
start_watchdog

fail_test() {
  printf 'FAIL [stage=%s]: %s\n' "$CURRENT_STAGE" "$*" >&2
  if [[ -s "$SSHD_LOG" ]]; then
    printf '%s\n' '--- sshd log ---' >&2
    sed -n '1,160p' "$SSHD_LOG" >&2 || true
  fi
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" description="$3"
  [[ "$actual" == "$expected" ]] ||
    fail_test "$description: expected [$expected], got [$actual]"
}

run_bounded_ssh() {
  local label="$1" output_file error_file command_pid attempt status state

  shift
  output_file="$TEST_TEMP_DIR/direct-ssh-$label.out"
  error_file="$TEST_TEMP_DIR/direct-ssh-$label.err"
  : >"$output_file"
  : >"$error_file"

  "$SSH_BIN" "$@" >"$output_file" 2>"$error_file" &
  command_pid=$!
  for ((attempt = 0; attempt < 200; attempt++)); do
    state="$(ps -p "$command_pid" -o stat= 2>/dev/null | tr -d '[:space:]')"
    if ! kill -0 "$command_pid" 2>/dev/null || [[ -z "$state" || "$state" == *Z* ]]; then
      if wait "$command_pid" 2>/dev/null; then
        status=0
      else
        status=$?
      fi
      BOUNDED_SSH_OUTPUT="$(<"$output_file")"
      BOUNDED_SSH_ERROR="$(<"$error_file")"
      return "$status"
    fi
    sleep 0.05
  done

  printf 'TIMEOUT: direct ssh operation [%s] exceeded 10s\n' "$label" >&2
  kill -TERM "$command_pid" 2>/dev/null || true
  for ((attempt = 0; attempt < 20; attempt++)); do
    kill -0 "$command_pid" 2>/dev/null || break
    sleep 0.05
  done
  kill -KILL "$command_pid" 2>/dev/null || true
  wait "$command_pid" 2>/dev/null || true
  BOUNDED_SSH_OUTPUT="$(<"$output_file")"
  BOUNDED_SSH_ERROR="$(<"$error_file")"
  return 124
}

mkdir -p "$SSH_DIR" "$CONTROL_DIR"
chmod 700 "$SSH_DIR"
ssh-keygen -q -t ed25519 -N '' -f "$HOST_KEY"
ssh-keygen -q -t ed25519 -N '' -f "$CLIENT_KEY"
printf '%s\n' "$(<"$CLIENT_KEY.pub")" >"$AUTHORIZED_KEYS"
chmod 600 "$AUTHORIZED_KEYS" "$CLIENT_KEY" "$HOST_KEY" "$CLIENT_KEY.pub"

PORT=$((40000 + ($$ % 10000)))
printf '%s\n' \
  "Port $PORT" \
  'ListenAddress 127.0.0.1' \
  "HostKey $HOST_KEY" \
  "PidFile $TEST_TEMP_DIR/sshd.pid" \
  "AuthorizedKeysFile $AUTHORIZED_KEYS" \
  'PasswordAuthentication no' \
  'KbdInteractiveAuthentication no' \
  'PubkeyAuthentication yes' \
  'PermitRootLogin no' \
  'UsePAM no' \
  'StrictModes no' \
  'UseDNS no' \
  "AllowUsers $TEST_USER" \
  'LogLevel VERBOSE' >"$SSHD_CONFIG"

SSH_BIN="$(command -v ssh)"
SSHD_BIN="$(command -v sshd)"
stage "sshd startup"
"$SSHD_BIN" -t -f "$SSHD_CONFIG" || fail_test 'sshd configuration validation failed'
"$SSHD_BIN" -D -e -f "$SSHD_CONFIG" >"$SSHD_LOG" 2>&1 &
SSHD_PID=$!

SCAN_OUTPUT=""
for ((attempt = 0; attempt < 80; attempt++)); do
  SCAN_OUTPUT="$(ssh-keyscan -T 1 -p "$PORT" 127.0.0.1 2>/dev/null | sed '/^#/d' || true)"
  if [[ -n "$SCAN_OUTPUT" ]]; then
    printf '%s\n' "$SCAN_OUTPUT" |
      sed "s/\[127\.0\.0\.1\]:$PORT/$HOST_ALIAS/g" >"$KNOWN_HOSTS"
    break
  fi
  sleep 0.05
done
if [[ ! -s "$KNOWN_HOSTS" ]]; then
  if grep -Eq 'sandbox initialization failed|Operation not permitted' "$SSHD_LOG"; then
    printf 'SKIP: local sshd sandbox prevents pre-authentication; CI runs this on Linux\n'
    exit 0
  fi
  fail_test 'sshd did not accept connections'
fi

printf '%s\n' \
  "Host $HOST_ALIAS" \
  '  HostName 127.0.0.1' \
  "  Port $PORT" \
  "  User $TEST_USER" \
  "  IdentityFile $CLIENT_KEY" \
  '  IdentitiesOnly yes' \
  "  UserKnownHostsFile $KNOWN_HOSTS" \
  "  HostKeyAlias $HOST_ALIAS" >"$CLIENT_CONFIG"
chmod 600 "$CLIENT_CONFIG" "$KNOWN_HOSTS"
export HOME="$CLIENT_HOME"

mkdir -p "$SSH_WRAPPER_DIR"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  "exec \"$SSH_BIN\" -F \"$CLIENT_CONFIG\" \"\$@\"" >"$SSH_WRAPPER"
chmod 700 "$SSH_WRAPPER"
PATH="$SSH_WRAPPER_DIR:$PATH"
export PATH

stage "authentication"
run_bounded_ssh auth -F "$CLIENT_CONFIG" -T \
  -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
  "$HOST_ALIAS" printf 'ssh-ready\\n' ||
  fail_test "real OpenSSH authentication failed: [$BOUNDED_SSH_ERROR]"
SSH_READY="$BOUNDED_SSH_OUTPUT"
assert_equal 'ssh-ready' "$SSH_READY" 'real OpenSSH authentication'

POLLING_COMMAND="printf 'polling %s\\n' \"\$SSH_CONNECTION\" >> '$REMOTE_CONNECTION_LOG'; printf 'polling-ok\\n'"
STREAM_COMMAND="printf 'stream %s\\n' \"\$SSH_CONNECTION\" >> '$REMOTE_CONNECTION_LOG'; i=1; while true; do printf 'stream-%s\\n' \"\$i\"; i=\$((i + 1)); sleep 0.1; done"

wait_for_panel() {
  local panel_index="$1"
  for ((attempt = 0; attempt < 180; attempt++)); do
    run_panel_commands || fail_test "SSH scheduler failed for panel $panel_index"
    [[ "${PANEL_COMMAND_ACTIVE[$panel_index]:-1}" -eq 0 ]] && return 0
    sleep 0.05
  done
  fail_test "panel $panel_index did not finish"
}

master_pid_from_check() {
  local check_output pid
  run_bounded_ssh check -T \
    -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1 \
    -o ControlPath="$CONTROL_PATH" -O check "$HOST_ALIAS" || return 1
  check_output="$BOUNDED_SSH_OUTPUT$BOUNDED_SSH_ERROR"
  pid="${check_output#*pid=}"
  pid="${pid%%)*}"
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  MASTER_CHECK_OUTPUT="$check_output"
  MASTER_PID="$pid"
}

unique_connection_count() {
  awk '{ key = $2 FS $3 FS $4 FS $5; if (!seen[key]++) count++ } END { print count + 0 }' \
    "$REMOTE_CONNECTION_LOG"
}

(
  source "$TEST_ROOT/bin/lhc"
  stage "dashboard startup and dedicated stream"
  SSH_SERVERS=("LOCAL|$HOST_ALIAS")
  SSH_CONTROL_PERSIST_SECONDS=5
  SSH_CONNECT_TIMEOUT_SECONDS=5
  SSH_MASTER_RETRY_BACKOFF_SECONDS=1
  PANEL_TITLES[0]='Real polling'
  PANEL_COMMANDS[0]="$POLLING_COMMAND"
  PANEL_SSH_ALIASES[0]='LOCAL'
  PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=42; PANEL_HEIGHTS[0]=8
  PANEL_TITLES[1]='Dedicated real stream'
  PANEL_COMMANDS[1]="$STREAM_COMMAND"
  PANEL_SSH_ALIASES[1]='LOCAL'
  PANEL_STREAM[1]=1
  PANEL_X[1]=45; PANEL_Y[1]=1; PANEL_WIDTHS[1]=42; PANEL_HEIGHTS[1]=8

  validate_config || fail_test 'real OpenSSH dashboard configuration was rejected'
  TERMINAL_ROWS=20; TERMINAL_COLS=100; resolve_panel_dimensions
  initialize_loading_dashboard
  PANEL_COMMAND_TEMP_DIR="$CONTROL_DIR"
  render_dashboard() { :; }

  for ((attempt = 0; attempt < 180; attempt++)); do
    run_panel_commands || fail_test 'real OpenSSH scheduler failed during startup'
    [[ "${PANEL_COMMAND_ACTIVE[0]:-1}" -eq 0 && -n "${PANEL_OUTPUTS[1]:-}" ]] && break
    sleep 0.05
  done
  if [[ "${PANEL_OUTPUTS[0]:-}" == *'SSH_FAILED'* ]] &&
     grep -Eq 'BSM audit.*Operation not permitted|sandbox initialization failed' "$SSHD_LOG"; then
    : >"$REAL_OPENSSH_SKIP_FILE"
    exit 0
  fi
  assert_equal "LOCAL polling-ok" "${PANEL_OUTPUTS[0]}" 'initial real polling output'
  [[ "${PANEL_OUTPUTS[1]}" == *stream-* ]] || fail_test 'dedicated real stream produced no output'

  stage "master creation and check"
  CONTROL_PATH="${SSH_CONTROL_PATHS[0]}"
  master_pid_from_check || fail_test 'real polling master was not available for -O check'
  FIRST_MASTER_PID="$MASTER_PID"
  [[ "$MASTER_CHECK_OUTPUT" == *'Master running'* ]] ||
    fail_test "unexpected real master check output: [$MASTER_CHECK_OUTPUT]"

  stage "channel reuse"
  PANEL_NEXT_RUN_SECONDS[0]=0
  wait_for_panel 0
  assert_equal "LOCAL polling-ok" "${PANEL_OUTPUTS[0]}" 'reused real polling channel output'
  master_pid_from_check || fail_test 'real polling master disappeared before persist expiry'
  assert_equal "$FIRST_MASTER_PID" "$MASTER_PID" 'ControlMaster channel reuse'
  [[ "$(unique_connection_count)" == 2 ]] ||
    fail_test 'polling and dedicated stream did not use separate physical connections'

  stage "bounded ControlPersist expiry"
  sleep 6
  if master_pid_from_check; then
    fail_test 'bounded ControlPersist master did not expire'
  fi

  stage "master recreation after expiry"
  PANEL_NEXT_RUN_SECONDS[0]=0
  wait_for_panel 0
  master_pid_from_check || fail_test 'polling master was not recreated after expiry'
  EXPIRED_MASTER_PID="$MASTER_PID"
  [[ "$EXPIRED_MASTER_PID" != "$FIRST_MASTER_PID" ]] ||
    fail_test 'ControlPersist expiry did not create a replacement master'

  stage "master death recovery"
  kill -KILL "$EXPIRED_MASTER_PID" 2>/dev/null || true
  for ((attempt = 0; attempt < 40; attempt++)); do
    if ! master_pid_from_check; then
      break
    fi
    sleep 0.05
  done
  master_pid_from_check 2>/dev/null && fail_test 'dead real master still answered -O check'

  PANEL_NEXT_RUN_SECONDS[0]=0
  wait_for_panel 0
  master_pid_from_check || fail_test 'polling master was not recreated after process death'
  DEATH_RECOVERY_PID="$MASTER_PID"
  [[ "$DEATH_RECOVERY_PID" != "$EXPIRED_MASTER_PID" ]] ||
    fail_test 'master process death did not create a replacement master'
  assert_equal "LOCAL polling-ok" "${PANEL_OUTPUTS[0]}" 'polling output after master death recovery'

  stage "explicit shutdown"
  cleanup_panel_commands
  if master_pid_from_check; then
    fail_test 'explicit LHC shutdown left a real ControlMaster running'
  fi
  [[ "${SSH_CONTROL_STATES[0]:-}" == CLOSED ]] ||
    fail_test 'explicit LHC shutdown did not close the real master state'
)

if [[ -e "$REAL_OPENSSH_SKIP_FILE" ]]; then
  printf 'SKIP: local sshd sandbox prevents ControlMaster sessions; CI runs this on Linux\n'
  exit 0
fi

printf 'PASS: real OpenSSH master creation, channel reuse, expiry, dedicated stream isolation, death recovery, and shutdown\n'
