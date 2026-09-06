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
