#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_CONFIG="$ROOT_DIR/config/sample.conf"
TERMINAL_ACTIVE=0
REFRESH_INTERVAL=2
PANEL_COUNT=0
TERMINAL_ROWS=0
TERMINAL_COLS=0
REQUIRED_ROWS=0
REQUIRED_COLS=0
CONDITION_OPERATOR=""
CONDITION_VALUE=""

declare -a PANEL_TITLES=()
declare -a PANEL_COMMANDS=()
declare -a PANEL_X=()
declare -a PANEL_Y=()
declare -a PANEL_WIDTHS=()
declare -a PANEL_HEIGHTS=()
declare -a PANEL_ORDER=()
declare -a PANEL_OUTPUTS=()
declare -a PANEL_TABLE_COLUMNS=()
declare -a PANEL_WARN_RULES=()
declare -a PANEL_ERROR_RULES=()
declare -a PANEL_RENDER_MODES=()
declare -a PANEL_STATUSES=()
declare -a PANEL_TABLE_HEADERS=()
declare -a PANEL_TABLE_ROWS=()
declare -a PANEL_TABLE_CELL_STATUSES=()

usage() {
  printf 'Usage: %s [config-file]\n' "${0##*/}"
  printf '\n'
  printf 'Starts the local change dashboard.\n'
  printf 'Default config: %s\n' "$DEFAULT_CONFIG"
}

setup_terminal() {
  TERMINAL_ACTIVE=1
  # Clear the screen and move the cursor to the top-left corner.
  printf '\033[2J\033[H'
  # Hide the cursor while the dashboard owns the terminal.
  printf '\033[?25l'
}

cleanup_terminal() {
  if [[ "$TERMINAL_ACTIVE" -eq 1 ]]; then
    # Show the cursor again before returning control to the shell.
    printf '\033[?25h'
    # Reset terminal text attributes such as color or bold.
    printf '\033[0m'
    printf '\n'
    TERMINAL_ACTIVE=0
  fi
}

handle_interrupt() {
  cleanup_terminal
  exit 130
}

error() {
  printf 'Error: %s\n' "$*" >&2
}

has_array_index() {
  local array_name="$1"
  local index="$2"

  eval '[[ ${'"$array_name"'['"$index"']+set} ]]'
}

is_positive_integer() {
  [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

is_non_negative_integer() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

load_config() {
  local config_file="$1"

  if [[ ! -f "$config_file" ]]; then
    error "config file not found: $config_file"
    return 1
  fi

  REFRESH_INTERVAL=2
  PANEL_COUNT=0
  PANEL_TITLES=()
  PANEL_COMMANDS=()
  PANEL_X=()
  PANEL_Y=()
  PANEL_WIDTHS=()
  PANEL_HEIGHTS=()
  PANEL_ORDER=()
  PANEL_OUTPUTS=()
  PANEL_TABLE_COLUMNS=()
  PANEL_WARN_RULES=()
  PANEL_ERROR_RULES=()
  PANEL_RENDER_MODES=()
  PANEL_STATUSES=()
  PANEL_TABLE_HEADERS=()
  PANEL_TABLE_ROWS=()
  PANEL_TABLE_CELL_STATUSES=()

  # Config is trusted deployment input and may contain shell commands.
  # shellcheck source=/dev/null
  source "$config_file"

  if ! is_positive_integer "$REFRESH_INTERVAL"; then
    error "REFRESH_INTERVAL must be a positive integer"
    return 1
  fi

  validate_config
}

validate_config() {
  local index

  if [[ "${#PANEL_TITLES[@]}" -eq 0 ]]; then
    error "at least one panel must be configured"
    return 1
  fi

  for index in "${!PANEL_TITLES[@]}"; do
    validate_panel "$index" || return 1
  done

  validate_no_extra_panel_indexes PANEL_COMMANDS || return 1
  validate_no_extra_panel_indexes PANEL_X || return 1
  validate_no_extra_panel_indexes PANEL_Y || return 1
  validate_no_extra_panel_indexes PANEL_WIDTHS || return 1
  validate_no_extra_panel_indexes PANEL_HEIGHTS || return 1
  validate_optional_panel_indexes PANEL_TABLE_COLUMNS || return 1
  validate_optional_panel_indexes PANEL_WARN_RULES || return 1
  validate_optional_panel_indexes PANEL_ERROR_RULES || return 1

  validate_table_configs || return 1

  build_panel_model
}

validate_no_extra_panel_indexes() {
  local array_name="$1"
  local index

  eval 'for index in "${!'"$array_name"'[@]}"; do
    if ! has_array_index PANEL_TITLES "$index"; then
      error "'"$array_name"'[$index] has no matching PANEL_TITLES[$index]"
      return 1
    fi
  done'
}

validate_optional_panel_indexes() {
  local array_name="$1"
  local index

  eval 'for index in "${!'"$array_name"'[@]}"; do
    if ! has_array_index PANEL_TITLES "$index"; then
      error "'"$array_name"'[$index] has no matching PANEL_TITLES[$index]"
      return 1
    fi
  done'
}

validate_panel() {
  local index="$1"

  require_panel_field PANEL_TITLES "$index" || return 1
  require_panel_field PANEL_COMMANDS "$index" || return 1
  require_panel_field PANEL_X "$index" || return 1
  require_panel_field PANEL_Y "$index" || return 1
  require_panel_field PANEL_WIDTHS "$index" || return 1
  require_panel_field PANEL_HEIGHTS "$index" || return 1

  if [[ -z "${PANEL_TITLES[$index]}" ]]; then
    error "PANEL_TITLES[$index] must not be empty"
    return 1
  fi

  if [[ -z "${PANEL_COMMANDS[$index]}" ]]; then
    error "PANEL_COMMANDS[$index] must not be empty"
    return 1
  fi

  if ! is_positive_integer "${PANEL_X[$index]}"; then
    error "PANEL_X[$index] must be a positive integer"
    return 1
  fi

  if ! is_positive_integer "${PANEL_Y[$index]}"; then
    error "PANEL_Y[$index] must be a positive integer"
    return 1
  fi

  if ! is_positive_integer "${PANEL_WIDTHS[$index]}"; then
    error "PANEL_WIDTHS[$index] must be a positive integer"
    return 1
  fi

  if (( PANEL_WIDTHS[index] < 4 )); then
    error "PANEL_WIDTHS[$index] must be at least 4"
    return 1
  fi

  if ! is_positive_integer "${PANEL_HEIGHTS[$index]}"; then
    error "PANEL_HEIGHTS[$index] must be a positive integer"
    return 1
  fi

  if (( PANEL_HEIGHTS[index] < 3 )); then
    error "PANEL_HEIGHTS[$index] must be at least 3"
    return 1
  fi
}

validate_table_configs() {
  local index

  for index in "${!PANEL_TABLE_COLUMNS[@]}"; do
    validate_table_columns "$index" || return 1
    validate_rule_list "$index" "WARN" "${PANEL_WARN_RULES[$index]:-}" || return 1
    validate_rule_list "$index" "ERROR" "${PANEL_ERROR_RULES[$index]:-}" || return 1
  done

  for index in "${!PANEL_WARN_RULES[@]}"; do
    if ! has_array_index PANEL_TABLE_COLUMNS "$index"; then
      error "PANEL_WARN_RULES[$index] requires PANEL_TABLE_COLUMNS[$index]"
      return 1
    fi
  done

  for index in "${!PANEL_ERROR_RULES[@]}"; do
    if ! has_array_index PANEL_TABLE_COLUMNS "$index"; then
      error "PANEL_ERROR_RULES[$index] requires PANEL_TABLE_COLUMNS[$index]"
      return 1
    fi
  done
}

validate_table_columns() {
  local index="$1"
  local columns="${PANEL_TABLE_COLUMNS[$index]}"
  local column
  local seen=" "

  if [[ -z "$columns" ]]; then
    error "PANEL_TABLE_COLUMNS[$index] must not be empty"
    return 1
  fi

  for column in $columns; do
    if [[ "$column" == *:* ]]; then
      error "table column must not contain colon: $column"
      return 1
    fi

    if [[ "$seen" == *" $column "* ]]; then
      error "duplicate table column in PANEL_TABLE_COLUMNS[$index]: $column"
      return 1
    fi

    seen="${seen}${column} "
  done
}

validate_rule_list() {
  local index="$1"
  local severity="$2"
  local rules="$3"
  local rule
  local column
  local condition

  for rule in $rules; do
    if [[ "$rule" != *:* ]]; then
      error "$severity rule must use column:condition format: $rule"
      return 1
    fi

    column="${rule%%:*}"
    condition="${rule#*:}"

    if ! table_has_column "$index" "$column"; then
      error "$severity rule references unknown column for panel $index: $column"
      return 1
    fi

    if ! validate_condition "$condition"; then
      error "$severity rule has invalid condition for panel $index: $condition"
      return 1
    fi
  done
}

table_has_column() {
  local index="$1"
  local target="$2"
  local column

  for column in ${PANEL_TABLE_COLUMNS[$index]}; do
    if [[ "$column" == "$target" ]]; then
      return 0
    fi
  done

  return 1
}

validate_condition() {
  local condition="$1"

  parse_condition "$condition" || return 1
  if [[ -z "$CONDITION_VALUE" ]]; then
    return 1
  fi

  case "$CONDITION_OPERATOR" in
    '>'|'>='|'<'|'<='|'=='|'!=')
      return 0
      ;;
  esac

  return 1
}

parse_condition() {
  local condition="$1"
  local operator
  local value

  case "$condition" in
    '>='*) operator='>='; value="${condition#>=}" ;;
    '<='*) operator='<='; value="${condition#<=}" ;;
    '=='*) operator='=='; value="${condition#==}" ;;
    '!='*) operator='!='; value="${condition#!=}" ;;
    '>'*) operator='>'; value="${condition#>}" ;;
    '<'*) operator='<'; value="${condition#<}" ;;
    *) return 1 ;;
  esac

  CONDITION_OPERATOR="$operator"
  CONDITION_VALUE="$value"
}

require_panel_field() {
  local array_name="$1"
  local index="$2"

  if ! has_array_index "$array_name" "$index"; then
    error "$array_name[$index] is required"
    return 1
  fi
}

build_panel_model() {
  local index

  PANEL_ORDER=()
  for index in "${!PANEL_TITLES[@]}"; do
    if ! is_non_negative_integer "$index"; then
      error "panel index must be a non-negative integer: $index"
      return 1
    fi
    PANEL_ORDER+=("$index")
  done

  PANEL_COUNT="${#PANEL_ORDER[@]}"
}

calculate_required_terminal_size() {
  local index
  local panel_right
  local panel_bottom

  REQUIRED_COLS=0
  REQUIRED_ROWS=0

  for index in "${PANEL_ORDER[@]}"; do
    panel_right=$((PANEL_X[index] + PANEL_WIDTHS[index] - 1))
    panel_bottom=$((PANEL_Y[index] + PANEL_HEIGHTS[index] - 1))

    if (( panel_right > REQUIRED_COLS )); then
      REQUIRED_COLS="$panel_right"
    fi

    if (( panel_bottom > REQUIRED_ROWS )); then
      REQUIRED_ROWS="$panel_bottom"
    fi
  done
}

read_terminal_size() {
  local size

  size="$(stty size 2>/dev/null || true)"
  if [[ -n "$size" ]]; then
    TERMINAL_ROWS="${size%% *}"
    TERMINAL_COLS="${size##* }"
  else
    TERMINAL_ROWS="${LINES:-0}"
    TERMINAL_COLS="${COLUMNS:-0}"
  fi

  if ! is_positive_integer "$TERMINAL_ROWS" || ! is_positive_integer "$TERMINAL_COLS"; then
    error "unable to determine terminal size"
    return 1
  fi
}

validate_terminal_size() {
  calculate_required_terminal_size
  read_terminal_size || return 1

  if (( TERMINAL_COLS < REQUIRED_COLS || TERMINAL_ROWS < REQUIRED_ROWS )); then
    error "terminal too small: need ${REQUIRED_COLS}x${REQUIRED_ROWS}, have ${TERMINAL_COLS}x${TERMINAL_ROWS}"
    return 1
  fi
}

move_cursor() {
  local row="$1"
  local col="$2"

  printf '\033[%s;%sH' "$row" "$col"
}

repeat_char() {
  local char="$1"
  local count="$2"
  local output=""

  while (( count > 0 )); do
    output="${output}${char}"
    count=$((count - 1))
  done

  printf '%s' "$output"
}

clip_text() {
  local text="$1"
  local width="$2"

  printf '%s' "${text:0:width}"
}

status_color() {
  case "$1" in
    ERROR|FAILED) printf '\033[31m' ;;
    WARN) printf '\033[33m' ;;
    *) printf '' ;;
  esac
}

reset_color() {
  printf '\033[0m'
}

print_colored() {
  local status="$1"
  local text="$2"
  local color

  color="$(status_color "$status")"
  if [[ -n "$color" ]]; then
    printf '%s%s' "$color" "$text"
    reset_color
  else
    printf '%s' "$text"
  fi
}

draw_text_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local text="$4"

  move_cursor "$row" "$col"
  clip_text "$text" "$width"
}

draw_colored_text_at() {
  local row="$1"
  local col="$2"
  local width="$3"
  local text="$4"
  local status="$5"

  move_cursor "$row" "$col"
  print_colored "$status" "$(clip_text "$text" "$width")"
}

draw_panel_border() {
  local x="$1"
  local y="$2"
  local width="$3"
  local height="$4"
  local status="${5:-OK}"
  local row
  local inner_width=$((width - 2))

  move_cursor "$y" "$x"
  print_colored "$status" "+"
  print_colored "$status" "$(repeat_char '-' "$inner_width")"
  print_colored "$status" "+"

  row=$((y + 1))
  while (( row < y + height - 1 )); do
    move_cursor "$row" "$x"
    print_colored "$status" "|"
    move_cursor "$row" "$((x + width - 1))"
    print_colored "$status" "|"
    row=$((row + 1))
  done

  move_cursor "$((y + height - 1))" "$x"
  print_colored "$status" "+"
  print_colored "$status" "$(repeat_char '-' "$inner_width")"
  print_colored "$status" "+"
}

render_panel_content() {
  local index="$1"
  local x="${PANEL_X[$index]}"
  local y="${PANEL_Y[$index]}"
  local width="${PANEL_WIDTHS[$index]}"
  local height="${PANEL_HEIGHTS[$index]}"
  local content="${PANEL_OUTPUTS[$index]:-}"
  local row=0
  local line
  local content_width=$((width - 2))
  local content_height=$((height - 2))

  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( row >= content_height )); then
      break
    fi

    draw_text_at "$((y + 1 + row))" "$((x + 1))" "$content_width" "$line"
    row=$((row + 1))
  done <<< "$content"
}

render_table_content() {
  local index="$1"
  local x="${PANEL_X[$index]}"
  local y="${PANEL_Y[$index]}"
  local width="${PANEL_WIDTHS[$index]}"
  local height="${PANEL_HEIGHTS[$index]}"
  local content_width=$((width - 2))
  local content_height=$((height - 2))
  local row=0
  local line
  local status_line
  local col=0
  local cell
  local cell_status
  local cell_width=0
  local column_count=0

  for cell in ${PANEL_TABLE_HEADERS[$index]}; do
    column_count=$((column_count + 1))
  done

  if (( column_count > 0 )); then
    cell_width=$((content_width / column_count))
  fi

  if (( cell_width < 1 )); then
    render_panel_content "$index"
    return
  fi

  for cell in ${PANEL_TABLE_HEADERS[$index]}; do
    draw_colored_text_at "$((y + 1))" "$((x + 1 + col * cell_width))" "$cell_width" "$cell" OK
    col=$((col + 1))
  done

  row=1
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( row >= content_height )); then
      break
    fi

    status_line="$(get_table_status_line "$index" "$row")"
    col=0
    for cell in $line; do
      cell_status="$(get_status_at_position "$status_line" "$col")"
      draw_colored_text_at "$((y + 1 + row))" "$((x + 1 + col * cell_width))" "$cell_width" "$cell" "$cell_status"
      col=$((col + 1))
    done

    row=$((row + 1))
  done <<< "${PANEL_TABLE_ROWS[$index]}"
}

render_panel() {
  local index="$1"
  local x="${PANEL_X[$index]}"
  local y="${PANEL_Y[$index]}"
  local width="${PANEL_WIDTHS[$index]}"
  local height="${PANEL_HEIGHTS[$index]}"
  local title=" ${PANEL_TITLES[$index]} "
  local status="${PANEL_STATUSES[$index]:-OK}"

  draw_panel_border "$x" "$y" "$width" "$height" "$status"
  draw_colored_text_at "$y" "$((x + 2))" "$((width - 4))" "$title" "$status"

  if [[ "${PANEL_RENDER_MODES[$index]:-raw}" == "table" ]]; then
    render_table_content "$index"
  else
    render_panel_content "$index"
  fi
}

render_dashboard() {
  local index

  printf '\033[2J\033[H'

  for index in "${PANEL_ORDER[@]}"; do
    render_panel "$index"
  done

  move_cursor "$((REQUIRED_ROWS + 1))" 1
  printf 'Refresh: %ss | Press q to exit.' "$REFRESH_INTERVAL"
}

run_panel_commands() {
  local index
  local output

  PANEL_OUTPUTS=()
  PANEL_RENDER_MODES=()
  PANEL_STATUSES=()
  PANEL_TABLE_HEADERS=()
  PANEL_TABLE_ROWS=()
  PANEL_TABLE_CELL_STATUSES=()

  for index in "${PANEL_ORDER[@]}"; do
    if output="$(bash -c "${PANEL_COMMANDS[$index]}" 2>/dev/null)"; then
      PANEL_OUTPUTS[$index]="$output"
      prepare_panel_output "$index"
    else
      PANEL_OUTPUTS[$index]="Command failed"
      PANEL_RENDER_MODES[$index]="raw"
      PANEL_STATUSES[$index]="FAILED"
    fi
  done
}

prepare_panel_output() {
  local index="$1"

  PANEL_RENDER_MODES[$index]="raw"
  PANEL_STATUSES[$index]="OK"

  if has_array_index PANEL_TABLE_COLUMNS "$index"; then
    parse_table_output "$index" || return 0
    evaluate_table_output "$index"
  fi
}

parse_table_output() {
  local index="$1"
  local output="${PANEL_OUTPUTS[$index]}"
  local columns="${PANEL_TABLE_COLUMNS[$index]}"
  local column_count=0
  local row_field_count
  local line
  local field
  local table_rows=""

  for line in $columns; do
    column_count=$((column_count + 1))
  done

  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    row_field_count=0
    for field in $line; do
      row_field_count=$((row_field_count + 1))
    done

    if (( row_field_count != column_count )); then
      PANEL_RENDER_MODES[$index]="raw"
      PANEL_STATUSES[$index]="OK"
      return 1
    fi

    table_rows="${table_rows}${line}"$'\n'
  done <<< "$output"

  PANEL_RENDER_MODES[$index]="table"
  PANEL_TABLE_HEADERS[$index]="$columns"
  PANEL_TABLE_ROWS[$index]="${table_rows%$'\n'}"
}

evaluate_table_output() {
  local index="$1"
  local line
  local row=1
  local col
  local cell
  local column
  local cell_status
  local status_line
  local status_rows=""
  local panel_status="OK"

  while IFS= read -r line || [[ -n "$line" ]]; do
    col=0
    status_line=""
    for cell in $line; do
      column="$(get_column_at_position "$index" "$col")"
      cell_status="$(evaluate_cell "$index" "$column" "$cell")"
      status_line="${status_line}${cell_status} "
      panel_status="$(worst_status "$panel_status" "$cell_status")"
      col=$((col + 1))
    done

    status_rows="${status_rows}${status_line% }"$'\n'
    row=$((row + 1))
  done <<< "${PANEL_TABLE_ROWS[$index]}"

  PANEL_TABLE_CELL_STATUSES[$index]="${status_rows%$'\n'}"
  PANEL_STATUSES[$index]="$panel_status"
}

get_column_at_position() {
  local index="$1"
  local target="$2"
  local position=0
  local column

  for column in ${PANEL_TABLE_COLUMNS[$index]}; do
    if (( position == target )); then
      printf '%s' "$column"
      return 0
    fi
    position=$((position + 1))
  done
}

get_table_status_line() {
  local index="$1"
  local row="$2"
  local current_row=1
  local line

  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( current_row == row )); then
      printf '%s' "$line"
      return 0
    fi
    current_row=$((current_row + 1))
  done <<< "${PANEL_TABLE_CELL_STATUSES[$index]:-}"
}

get_status_at_position() {
  local status_line="$1"
  local target="$2"
  local position=0
  local status

  for status in $status_line; do
    if (( position == target )); then
      printf '%s' "$status"
      return 0
    fi
    position=$((position + 1))
  done

  printf 'OK'
}

evaluate_cell() {
  local index="$1"
  local column="$2"
  local value="$3"

  if rule_list_matches "$value" "$column" "${PANEL_ERROR_RULES[$index]:-}"; then
    printf 'ERROR'
    return 0
  fi

  if rule_list_matches "$value" "$column" "${PANEL_WARN_RULES[$index]:-}"; then
    printf 'WARN'
    return 0
  fi

  printf 'OK'
}

rule_list_matches() {
  local value="$1"
  local target_column="$2"
  local rules="$3"
  local rule
  local column
  local condition

  for rule in $rules; do
    column="${rule%%:*}"
    condition="${rule#*:}"
    if [[ "$column" == "$target_column" ]] && condition_matches "$value" "$condition"; then
      return 0
    fi
  done

  return 1
}

condition_matches() {
  local value="$1"
  local condition="$2"
  local operator
  local expected

  parse_condition "$condition" || return 1
  operator="$CONDITION_OPERATOR"
  expected="$CONDITION_VALUE"

  case "$operator" in
    '=='|'!=')
      if is_number "$value" && is_number "$expected"; then
        compare_numbers "$value" "$operator" "$expected"
      elif [[ "$operator" == '==' ]]; then
        [[ "$value" == "$expected" ]]
      else
        [[ "$value" != "$expected" ]]
      fi
      ;;
    '>'|'>='|'<'|'<=')
      is_number "$value" && is_number "$expected" && compare_numbers "$value" "$operator" "$expected"
      ;;
    *) return 1 ;;
  esac
}

is_number() {
  [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]
}

compare_numbers() {
  local left="$1"
  local operator="$2"
  local right="$3"

  awk -v l="$left" -v r="$right" 'BEGIN {
    if ("'"$operator"'" == ">") exit !(l > r)
    if ("'"$operator"'" == ">=") exit !(l >= r)
    if ("'"$operator"'" == "<") exit !(l < r)
    if ("'"$operator"'" == "<=") exit !(l <= r)
    if ("'"$operator"'" == "==") exit !(l == r)
    if ("'"$operator"'" == "!=") exit !(l != r)
    exit 1
  }'
}

worst_status() {
  local current="$1"
  local candidate="$2"

  if [[ "$current" == "ERROR" || "$candidate" == "ERROR" ]]; then
    printf 'ERROR'
  elif [[ "$current" == "WARN" || "$candidate" == "WARN" ]]; then
    printf 'WARN'
  else
    printf 'OK'
  fi
}

wait_for_quit_or_timeout() {
  local timeout="$1"
  local key

  if IFS= read -rsn1 -t "$timeout" key; then
    [[ "$key" == "q" ]]
    return
  fi

  return 1
}

run_dashboard_loop() {
  while true; do
    run_panel_commands
    render_dashboard

    if wait_for_quit_or_timeout "$REFRESH_INTERVAL"; then
      return 0
    fi
  done
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    return 0
  fi

  local config_file="${1:-$DEFAULT_CONFIG}"

  if ! load_config "$config_file"; then
    return 1
  fi

  if ! validate_terminal_size; then
    return 1
  fi

  trap cleanup_terminal EXIT
  trap handle_interrupt INT

  setup_terminal
  run_dashboard_loop
}

main "$@"
