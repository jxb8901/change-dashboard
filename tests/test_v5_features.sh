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
PANEL_INFO_RULES[0]="COUNT:==1"

validate_config || fail_test "v5 configuration should be valid"
assert_equal "1" "$AUTO_PANEL_HEIGHT_INDEX" "only final panel may omit height"
TERMINAL_ROWS=30
TERMINAL_COLS=100
resolve_auto_panel_dimensions
assert_equal "23" "${PANEL_EFFECTIVE_HEIGHTS[1]}" "final panel uses remaining terminal height"
if has_array_index PANEL_HEIGHTS 1; then
  fail_test "auto height resolution must not overwrite the source configuration"
fi
# Make the previously final panel explicit before adding another panel to this
# unit-test fixture.
PANEL_HEIGHTS[1]="${PANEL_EFFECTIVE_HEIGHTS[1]}"

resolve_table_widths 0
assert_equal "8 19" "$RESOLVED_WIDTHS" "omitted final table width fills remaining space"
condition_matches "READY" "~REA" || fail_test "contains rule should match"
condition_matches "READY" "!~FAIL" || fail_test "not-contains rule should match"
condition_matches "READY" "!~REA" && fail_test "not-contains rule should reject matching text"
evaluate_cell 0 "COUNT" "1"
assert_equal "INFO" "$FUNCTION_RESULT" "info rule should match table fields"
NO_COLOR=""
status_sequence INFO
assert_equal $'\033[30;42m' "$FUNCTION_RESULT" "info status should use green"

PANEL_TITLES[2]="Raw messages"
PANEL_COMMANDS[2]="printf 'ok WARN WARN\nhealthy\n'"
PANEL_X[2]=1; PANEL_Y[2]=15; PANEL_WIDTHS[2]=30; PANEL_HEIGHTS[2]=6
PANEL_WARN_RULES[2]="MESSAGE:~WARN"
PANEL_ERROR_RULES[2]="MESSAGE:~failed"
PANEL_INFO_RULES[2]="MESSAGE:~healthy"
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
get_raw_line_rules 2 "service healthy"
assert_equal "INFO" "$RAW_LINE_STYLE" "raw info severity should match"
assert_equal "healthy" "$RAW_LINE_KEYWORDS" "raw info keyword is selected"

unset 'PANEL_HEIGHTS[0]'
PANEL_HEIGHTS[1]=5
if validate_config >/dev/null 2>&1; then
  fail_test "non-final panel must not omit height"
fi

(
  source "$TEST_ROOT/bin/lhc"

  PANEL_TITLES[0]="Top"
  PANEL_COMMANDS[0]="printf ready"
  PANEL_X[0]="0%"
  PANEL_Y[0]="0%"
  PANEL_WIDTHS[0]="50%"
  PANEL_HEIGHTS[0]="50%"
  PANEL_TABLE_COLUMNS[0]="STATE COUNT"
  PANEL_TABLE_WIDTHS[0]="8"

  PANEL_TITLES[1]="Bottom"
  PANEL_COMMANDS[1]="printf ready"
  PANEL_X[1]="0%"
  PANEL_Y[1]="50%"
  PANEL_WIDTHS[1]="100%"
  PANEL_HEIGHTS[1]="50%"

  PANEL_TITLES[2]="Mixed"
  PANEL_COMMANDS[2]="printf ready"
  PANEL_X[2]=5
  PANEL_Y[2]="0%"
  PANEL_WIDTHS[2]="25%"
  PANEL_HEIGHTS[2]=5

  PANEL_TITLES[3]="Auto bottom"
  PANEL_COMMANDS[3]="printf ready"
  PANEL_X[3]="0%"
  PANEL_Y[3]="50%"
  PANEL_WIDTHS[3]="100%"

  validate_config || fail_test "percentage configuration should be valid"
  TERMINAL_ROWS=30
  TERMINAL_COLS=100
  resolve_panel_dimensions
  validate_effective_panel_layout || fail_test "resolved percentage layout should be valid"

  assert_equal "1" "${PANEL_EFFECTIVE_X[0]}" "0% X resolves to first column"
  assert_equal "1" "${PANEL_EFFECTIVE_Y[0]}" "0% Y resolves to first row"
  assert_equal "50" "${PANEL_EFFECTIVE_WIDTHS[0]}" "50% width resolves against terminal columns"
  assert_equal "14" "${PANEL_EFFECTIVE_HEIGHTS[0]}" "50% height floors against usable rows"
  assert_equal "15" "${PANEL_EFFECTIVE_Y[1]}" "50% Y resolves against usable rows"
  assert_equal "14" "${PANEL_EFFECTIVE_HEIGHTS[1]}" "50% height floors against usable rows"
  assert_equal "5" "${PANEL_EFFECTIVE_X[2]}" "mixed integer X remains absolute"
  assert_equal "25" "${PANEL_EFFECTIVE_WIDTHS[2]}" "mixed percentage width resolves independently"
  assert_equal "5" "${PANEL_EFFECTIVE_HEIGHTS[2]}" "mixed integer height remains absolute"
  assert_equal "15" "${PANEL_EFFECTIVE_Y[3]}" "final panel percentage Y resolves against usable rows"
  assert_equal "15" "${PANEL_EFFECTIVE_HEIGHTS[3]}" "final auto height fills to the footer"
  assert_equal "8 39" "$(resolve_table_widths 0; printf '%s' "$RESOLVED_WIDTHS")" "table width follows percentage panel width"

  TERMINAL_ROWS=40
  TERMINAL_COLS=80
  resolve_panel_dimensions
  validate_effective_panel_layout || fail_test "resized percentage layout should be valid"
  assert_equal "40" "${PANEL_EFFECTIVE_WIDTHS[0]}" "resize recomputes percentage width"
  assert_equal "19" "${PANEL_EFFECTIVE_HEIGHTS[0]}" "resize recomputes percentage height"
  assert_equal "20" "${PANEL_EFFECTIVE_Y[1]}" "resize recomputes percentage Y"
  assert_equal "19" "${PANEL_EFFECTIVE_HEIGHTS[1]}" "resize recomputes percentage height"
  assert_equal "20" "${PANEL_EFFECTIVE_Y[3]}" "resize recomputes final auto Y"
  assert_equal "20" "${PANEL_EFFECTIVE_HEIGHTS[3]}" "resize recomputes final auto height"
  assert_equal "8 29" "$(resolve_table_widths 0; printf '%s' "$RESOLVED_WIDTHS")" "table width recomputes after resize"
)

(
  source "$TEST_ROOT/bin/lhc"
  PANEL_TITLES[0]="Full"
  PANEL_COMMANDS[0]="printf ready"
  PANEL_X[0]="0%"
  PANEL_Y[0]="0%"
  PANEL_WIDTHS[0]="100%"
  PANEL_HEIGHTS[0]="100%"
  validate_config || fail_test "100% geometry should be syntactically valid"
  TERMINAL_ROWS=25
  TERMINAL_COLS=80
  resolve_panel_dimensions
  validate_effective_panel_layout || fail_test "100% geometry should fill the usable terminal"
  assert_equal "80" "${PANEL_EFFECTIVE_WIDTHS[0]}" "100% width fills terminal"
  assert_equal "24" "${PANEL_EFFECTIVE_HEIGHTS[0]}" "100% height leaves footer row"
)

expect_invalid_geometry() {
  local field="$1" value="$2"
  (
    source "$TEST_ROOT/bin/lhc"
    PANEL_TITLES[0]="Invalid"
    PANEL_COMMANDS[0]="printf ready"
    PANEL_X[0]=1
    PANEL_Y[0]=1
    PANEL_WIDTHS[0]=20
    PANEL_HEIGHTS[0]=5
    case "$field" in
      x) PANEL_X[0]="$value" ;;
      y) PANEL_Y[0]="$value" ;;
      width) PANEL_WIDTHS[0]="$value" ;;
      height) PANEL_HEIGHTS[0]="$value" ;;
    esac
    validate_config >/dev/null 2>&1
  )
}

for invalid_geometry in \
  "x 101%" \
  "x 0" \
  "y 50.5%" \
  "width 0%" \
  "height -1%"; do
  invalid_field="${invalid_geometry%% *}"
  invalid_value="${invalid_geometry#* }"
  if expect_invalid_geometry "$invalid_field" "$invalid_value"; then
    fail_test "invalid geometry should be rejected: $invalid_field=$invalid_value"
  fi
done

(
  source "$TEST_ROOT/bin/lhc"
  PANEL_TITLES[0]="Narrow table"
  PANEL_COMMANDS[0]="printf ready"
  PANEL_X[0]="0%"
  PANEL_Y[0]="0%"
  PANEL_WIDTHS[0]="50%"
  PANEL_HEIGHTS[0]=5
  PANEL_TABLE_COLUMNS[0]="STATE COUNT"
  PANEL_TABLE_WIDTHS[0]="47 2"
  validate_config || fail_test "narrow table configuration should pass syntax validation"
  TERMINAL_ROWS=20
  TERMINAL_COLS=100
  resolve_panel_dimensions
  if validate_effective_panel_layout >/dev/null 2>&1; then
    fail_test "resolved percentage panel should reject table widths that no longer fit"
  fi
)

(
  source "$TEST_ROOT/bin/lhc"
  PANEL_TITLES[0]="Out of bounds"
  PANEL_COMMANDS[0]="printf ready"
  PANEL_X[0]="100%"
  PANEL_Y[0]="0%"
  PANEL_WIDTHS[0]=4
  PANEL_HEIGHTS[0]=3
  validate_config || fail_test "100% position should pass syntax validation"
  TERMINAL_ROWS=20
  TERMINAL_COLS=80
  resolve_panel_dimensions
  if validate_effective_panel_layout >/dev/null 2>&1; then
    fail_test "100% position with non-zero size should be rejected after resolution"
  fi
)

(
  source "$TEST_ROOT/bin/lhc"
  PANEL_TITLES[0]="Too narrow"
  PANEL_COMMANDS[0]="printf ready"
  PANEL_X[0]="0%"
  PANEL_Y[0]="0%"
  PANEL_WIDTHS[0]="1%"
  PANEL_HEIGHTS[0]=3
  validate_config || fail_test "small percentage width should pass syntax validation"
  TERMINAL_ROWS=20
  TERMINAL_COLS=80
  resolve_panel_dimensions
  if validate_effective_panel_layout >/dev/null 2>&1; then
    fail_test "percentage width below the minimum should be rejected after resolution"
  fi
)

printf 'PASS: v5 rules and automatic panel dimensions\n'
