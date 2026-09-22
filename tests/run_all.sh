#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

tests=(
  test_cli_options.sh
  test_v4_ssh.sh
  test_v5_features.sh
  test_v5_stream.sh
  test_v5_shutdown.sh
  test_v6_ssh_lifecycle.sh
  test_v7_scheduler_timeout.sh
  test_v8_dirty_snapshot.sh
  test_v9_ssh_starting_recovery.sh
  test_v10_output_sanitization.sh
  test_v11_stream_event_loop.sh
)

printf 'Running %d regression suites\n' "${#tests[@]}"
for test_script in "${tests[@]}"; do
  printf '\n==> %s\n' "$test_script"
  bash "$TEST_ROOT/tests/$test_script"
done

printf '\nPASS: all standard regression suites\n'
