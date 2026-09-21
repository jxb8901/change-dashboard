#!/usr/bin/env bash

set -eu

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$TEST_ROOT/bin/lhc"

fail_test() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_equal() {
  local expected="$1" actual="$2" description="$3"
  [[ "$actual" == "$expected" ]] ||
    fail_test "$description: expected [$expected], got [$actual]"
}

PANEL_TITLES[0]='Raw one'
PANEL_COMMANDS[0]="sleep 0.05; printf 'raw-ready\\n'"
PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=20; PANEL_HEIGHTS[0]=6

PANEL_TITLES[1]='Table two'
PANEL_COMMANDS[1]="printf 'READY 1\\n'"
PANEL_X[1]=22; PANEL_Y[1]=1; PANEL_WIDTHS[1]=20; PANEL_HEIGHTS[1]=6
PANEL_TABLE_COLUMNS[1]='STATE COUNT'
PANEL_TABLE_WIDTHS[1]='8'

PANEL_TITLES[2]='Transpose three'
PANEL_COMMANDS[2]="sleep 0.10; printf 'READY 2 BLUE\\n'"
PANEL_X[2]=43; PANEL_Y[2]=1; PANEL_WIDTHS[2]=20; PANEL_HEIGHTS[2]=6
PANEL_TABLE_COLUMNS[2]='STATE COUNT COLOR'
PANEL_TABLE_LAYOUT[2]='transpose'
PANEL_TABLE_WIDTHS[2]='9 8'

PANEL_TITLES[3]='Raw four'
PANEL_COMMANDS[3]="sleep 0.15; printf 'raw-four\\n'"
PANEL_X[3]=64; PANEL_Y[3]=1; PANEL_WIDTHS[3]=20; PANEL_HEIGHTS[3]=6

PANEL_TITLES[4]='Table five'
PANEL_COMMANDS[4]="sleep 0.20; printf 'OK 3\\n'"
PANEL_X[4]=85; PANEL_Y[4]=1; PANEL_WIDTHS[4]=20; PANEL_HEIGHTS[4]=6
PANEL_TABLE_COLUMNS[4]='STATUS COUNT'
PANEL_TABLE_WIDTHS[4]='8'

validate_config || fail_test 'dirty snapshot configuration was rejected'
TERMINAL_ROWS=10
TERMINAL_COLS=105
resolve_panel_dimensions
calculate_required_terminal_size
validate_effective_panel_layout || fail_test 'dirty snapshot layout was rejected'
initialize_loading_dashboard

# Startup remains a full render and builds every panel frame once.
render_dashboard >/dev/null
for index in "${PANEL_ORDER[@]}"; do
  assert_equal '1' "${PANEL_FRAME_BUILD_COUNTS[$index]:-0}" \
    "startup frame build count for panel $index"
done

# Snapshot completions arrive independently. Each completion must rebuild only
# the completed panel, not all five panels.
complete=0
for ((attempt = 0; attempt < 80; attempt++)); do
  run_panel_commands >/dev/null 2>&1 || fail_test 'snapshot scheduler failed'
  complete=1
  for index in "${PANEL_ORDER[@]}"; do
    [[ "${PANEL_COMMAND_ACTIVE[$index]:-1}" -eq 0 ]] || complete=0
  done
  (( complete == 1 )) && break
  sleep 0.02
done
(( complete == 1 )) || fail_test 'snapshot panels did not complete'

for index in "${PANEL_ORDER[@]}"; do
  assert_equal '2' "${PANEL_FRAME_BUILD_COUNTS[$index]:-0}" \
    "snapshot completion rebuilt only panel $index"
done

assert_equal 'raw-ready' "${PANEL_OUTPUTS[0]}" 'raw snapshot output'
assert_equal 'table' "${PANEL_RENDER_MODES[1]}" 'table snapshot mode'
assert_equal 'READY 1' "${PANEL_TABLE_ROWS[1]}" 'table snapshot output'
assert_equal 'transpose' "${PANEL_RENDER_MODES[2]}" 'transpose snapshot mode'
assert_equal 'READY 2 BLUE' "${PANEL_TABLE_ROWS[2]}" 'transpose snapshot output'
assert_equal 'raw-four' "${PANEL_OUTPUTS[3]}" 'second raw snapshot output'
assert_equal 'table' "${PANEL_RENDER_MODES[4]}" 'second table snapshot mode'
assert_equal 'OK 3' "${PANEL_TABLE_ROWS[4]}" 'second table snapshot output'

# A forced redraw still rebuilds the complete dashboard after the dirty path.
FORCE_FULL_REDRAW=1
render_dashboard >/dev/null
for index in "${PANEL_ORDER[@]}"; do
  assert_equal '3' "${PANEL_FRAME_BUILD_COUNTS[$index]:-0}" \
    "forced full redraw count for panel $index"
done

# The resize path still requests a full redraw after recalculating geometry.
read_terminal_size() { return 0; }
RESIZE_PENDING=1
process_terminal_resize >/dev/null
for index in "${PANEL_ORDER[@]}"; do
  assert_equal '4' "${PANEL_FRAME_BUILD_COUNTS[$index]:-0}" \
    "resize redraw count for panel $index"
done

cleanup_panel_commands
printf 'PASS: snapshot completion uses dirty-panel rendering\n'
