#!/usr/bin/env bash

set -u

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for option in -h --help --usage; do
  output="$("$TEST_ROOT/bin/lhc" "$option")" || fail_test "$option should exit successfully"
  [[ "$output" == *"Usage: lhc [config-file]"* ]] || fail_test "$option should print usage"
  [[ "$output" == *"-h, --help, --usage"* ]] || fail_test "$option should list all help aliases"
done

printf 'PASS: CLI help and usage options\n'
