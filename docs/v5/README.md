# V5 Requirements

- SSH multiplexing keeps one OpenSSH transport per target during one LHC
  process while commands retain independent sessions/channels.
- `field:~keyword` and `field:!~keyword` warning/error rules use actual
  `PANEL_TABLE_COLUMNS` field names.
- `PANEL_INFO_RULES` uses the same rule syntax and displays matching cells or
  raw keywords in green. Severity precedence is `ERROR > WARN > INFO > OK`.
- Raw panels use the reserved `MESSAGE` field with `MESSAGE:~keyword` or
  `MESSAGE:!~keyword`; all matching `~` keyword occurrences are highlighted
  while the rest of the line remains unstyled.
- The final panel may omit `PANEL_HEIGHTS[index]` to use the maximum available
  height above the footer.
- Omitting only the final `PANEL_TABLE_WIDTHS[index]` value makes the rightmost
  field fill the remaining content width. An entirely omitted width list keeps
  equal-width behavior.
- `PANEL_X`, `PANEL_Y`, `PANEL_WIDTHS`, and `PANEL_HEIGHTS` accept either the
  existing character value or a percentage value such as `50%`; percentage
  positions and sizes are recalculated after terminal resize.
- Percentage X/width values use terminal columns. Percentage Y/height values
  use terminal rows excluding the footer. Values are rounded down; the normal
  minimum-size and bounds checks still apply.
- `PANEL_STREAM[index]=1` enables continuous raw or `table` output for local or
  SSH panels. The rolling data-row buffer is limited by the panel's effective
  height; a table header consumes one content row. `transpose` stream panels
  are rejected. Each complete newline-terminated output line wakes the main
  renderer immediately; `REFRESH_INTERVAL` only controls restart after the
  command exits.
