# Test Plan

Manual-first test plan for V2.

## V1 Compatibility
- Run existing sample config.
- Expected: panels render raw output and refresh globally.

## Normal Table
- Configure table columns and rows that do not match any rule.
- Expected: cells render with default terminal color.

## Warning Cell
- Configure a warning threshold and matching value.
- Expected: matching cell renders yellow and panel border/title renders yellow.

## Error Cell
- Configure an error threshold and matching value.
- Expected: matching cell renders red and panel border/title renders red.

## Severity Priority
- Configure both warning and error matches in one panel.
- Expected: panel uses error color.

## Command Failed
- Configure a command that exits non-zero.
- Expected: panel shows `Command failed` and panel border/title renders red.

## Parse Fallback
- Configure table columns but output a row with mismatched field count.
- Expected: raw command output renders with no threshold coloring.

## Long Output
- Configure more table rows or longer values than the panel can display.
- Expected: content remains clipped to panel width and height.

## Refresh Continues
- Use changing command output.
- Expected: table values and colors update on global refresh.
