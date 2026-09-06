# Functional Specification

## Partial Refresh
- The first render clears and draws the complete dashboard.
- Later renders compare padded visible cells with the previous frame.
- Only changed or removed cells are written to the terminal.
- Static borders and titles use default terminal colors.

## Color
- Warning values use black text on yellow background.
- Error values and command failures use white text on red background.
- Color covers the complete cell width and is reset after each cell.
- A non-empty `NO_COLOR` environment variable disables color sequences.

## Widths
- `PANEL_TABLE_WIDTHS[index]` is optional.
- In table layout, one positive width is required per source column.
- In transpose layout, exactly two widths define the field-name and field-value
  display cells; they are not source-field definitions.
- Width totals must fit within `PANEL_WIDTHS[index] - 2`.
- Text is truncated and padded to its exact cell width.
- A fixed one-character gap separates adjacent columns.
- Numeric values are right-aligned; headers and text values are left-aligned.

## Transpose
- `PANEL_TABLE_LAYOUT[index]="transpose"` enables field-name/value display.
- `PANEL_TABLE_COLUMNS[index]` contains the actual source-field names in source
  order.
- The command may produce zero or more parsed data rows; each row is rendered
  as one consecutive field-name/value block.
- Transpose does not add a separate table-header row; source-field names are
  shown as labels inside each block.
- A field-count mismatch uses raw-output fallback.
- Rules reference the actual source-field names, not the display-cell names.

## Resilience
- Successful empty output displays `No data`.
- `SIGWINCH` triggers terminal-size reevaluation outside the signal handler.
- A too-small terminal pauses command execution until the size recovers.
- `q` and Ctrl+C restore terminal state.
