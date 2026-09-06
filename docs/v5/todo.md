# V5 Requirements

- Keep SSH multiplexing enabled: one OpenSSH transport per SSH target during a
  single LHC process, with independent sessions/channels for commands.
- Support `field:~keyword` (contains) and `field:!~keyword` (does not contain)
  warning/error rules. `field` must be an actual name in
  `PANEL_TABLE_COLUMNS`.
- Allow the final panel to omit `PANEL_HEIGHTS[index]`; resolve it to the
  maximum available height below `PANEL_Y[index]`, leaving the footer row.
- Allow `PANEL_TABLE_WIDTHS[index]` to omit only its final width; resolve the
  rightmost field width to all remaining content width after configured widths
  and column gaps. An entirely omitted width list keeps equal-width behavior.
