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
- In transpose layout, exactly two widths define key and value cells.
- Width totals must fit within `PANEL_WIDTHS[index] - 2`.
- Text is truncated and padded to its exact cell width.
- A fixed one-character gap separates adjacent columns.
- Numeric values are right-aligned; headers and text values are left-aligned.

## Transpose
- `PANEL_TABLE_LAYOUT[index]="transpose"` enables key/value display.
- The command may produce zero or more parsed data rows; each row is rendered
  as one consecutive key/value block.
- A field-count mismatch uses raw-output fallback.
- Rules retain their original source-column mapping.

## Resilience
- Successful empty output displays `No data`.
- `SIGWINCH` triggers terminal-size reevaluation outside the signal handler.
- A too-small terminal pauses command execution until the size recovers.
- `q` and Ctrl+C restore terminal state.
