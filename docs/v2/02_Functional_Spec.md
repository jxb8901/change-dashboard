# Functional Specification

## FR-001 Table Columns
- `PANEL_TABLE_COLUMNS[index]` enables table parsing for a panel.
- Column names are whitespace-separated.
- Column names must be non-empty and unique within the panel.
- Command output rows must have the same field count as configured columns to be parsed as a table.
- If parsing fails, display raw command output with no threshold coloring.

## FR-002 Threshold Rules
- Warning rules use `PANEL_WARN_RULES[index]`.
- Error rules use `PANEL_ERROR_RULES[index]`.
- Rule token format is `column:condition`.
- Rule tokens are whitespace-separated.
- Unknown rule columns are config errors.
- Invalid condition syntax is a config error.

## FR-003 Conditions
- Numeric conditions support `>`, `>=`, `<`, `<=`, `==`, and `!=`.
- String conditions support `==` and `!=`.
- Numeric comparison applies only when both the cell value and condition value are numeric.
- Missing rule means `OK`.

## FR-004 Severity
- Cell severity is `OK`, `WARN`, or `ERROR`.
- Error wins over warning.
- Panel status is the worst cell status.
- Command failure is displayed as `Command failed` and colors the panel red.

## FR-005 Rendering
- Warning cells render yellow.
- Error cells render red.
- OK cells render with default terminal color.
- Panel border/title color follows panel status.
- Panel title does not include status text.
- Colors use ANSI basic colors and reset after colored segments.

## FR-006 Refresh
- V2 keeps V1 global synchronous refresh.
- No background commands.
- No per-panel scheduler.
