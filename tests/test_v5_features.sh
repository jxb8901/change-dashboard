#!/usr/bin/env bash

set -u

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TEST_ROOT/bin/lhc"

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" description="$3"
  [[ "$actual" == "$expected" ]] || fail_test "$description: expected [$expected], got [$actual]"
}

PANEL_TITLES[0]="Top"
PANEL_COMMANDS[0]="printf 'READY 1\n'"
PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=30; PANEL_HEIGHTS[0]=5
PANEL_TITLES[1]="Bottom"
PANEL_COMMANDS[1]="printf 'READY 2\n'"
PANEL_X[1]=1; PANEL_Y[1]=7; PANEL_WIDTHS[1]=30

PANEL_TABLE_COLUMNS[0]="STATE COUNT"
PANEL_TABLE_LAYOUT[0]="table"
PANEL_TABLE_WIDTHS[0]="8"
PANEL_WARN_RULES[0]="STATE:~READY"
PANEL_ERROR_RULES[0]="STATE:!~READY"

validate_config || fail_test "v5 configuration should be valid"
assert_equal "1" "$AUTO_PANEL_HEIGHT_INDEX" "only final panel may omit height"
TERMINAL_ROWS=30
TERMINAL_COLS=100
resolve_auto_panel_dimensions
assert_equal "23" "${PANEL_HEIGHTS[1]}" "final panel uses remaining terminal height"

resolve_table_widths 0
assert_equal "8 19" "$RESOLVED_WIDTHS" "omitted final table width fills remaining space"
condition_matches "READY" "~REA" || fail_test "contains rule should match"
condition_matches "READY" "!~FAIL" || fail_test "not-contains rule should match"
condition_matches "READY" "!~REA" && fail_test "not-contains rule should reject matching text"

PANEL_TITLES[2]="Raw messages"
PANEL_COMMANDS[2]="printf 'ok WARN WARN\nhealthy\n'"
PANEL_X[2]=1; PANEL_Y[2]=15; PANEL_WIDTHS[2]=30; PANEL_HEIGHTS[2]=6
PANEL_WARN_RULES[2]="MESSAGE:~WARN"
PANEL_ERROR_RULES[2]="MESSAGE:~failed"
validate_config || fail_test "raw MESSAGE rules should be valid"
PANEL_OUTPUTS[2]=$'ok WARN WARN\nhealthy'
prepare_panel_output 2
RAW_CAPTURE=""
frame_add() {
  RAW_CAPTURE="${RAW_CAPTURE}${4}:${5}|"
}
render_raw_line 2 1 1 20 "ok WARN WARN"
assert_equal "ok :OK|WARN:WARN| :OK|WARN:WARN|:OK|" "$RAW_CAPTURE" "raw warning highlights all keywords"
get_raw_line_rules 2 "service failed"
assert_equal "ERROR" "$RAW_LINE_STYLE" "raw error severity wins"
assert_equal "failed" "$RAW_LINE_KEYWORDS" "raw error keyword is selected"

unset 'PANEL_HEIGHTS[0]'
PANEL_HEIGHTS[1]=5
if validate_config >/dev/null 2>&1; then
  fail_test "non-final panel must not omit height"
fi

printf 'PASS: v5 rules and automatic panel dimensions\n'
