# V5 Requirements

- V5.5 creates one explicit, bounded SSH polling master per target through a
  Bash 3.2-safe background lifecycle worker. Targets move through
  `STARTING`, `READY`, and `FAILED` state; failed targets use retry backoff.
  Polling command wrappers wait for readiness without blocking the scheduler,
  launch the actual SSH channel directly, and retry a dead transport at most
  once. Continuous SSH streams use dedicated non-multiplexed connections.

- SSH polling commands keep one explicit OpenSSH transport per target during
  one LHC process while retaining independent sessions/channels; streams use
  dedicated connections.
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
- V5.3 gives every active command job an explicit lifecycle and records the
  wrapper, command, and stream collector identities. Completed jobs are
  reaped and removed from scheduler state, so repeated refreshes do not grow
  historical PID arrays.
- Shutdown is bounded: LHC sends `TERM`, waits briefly, sends `KILL` to
  TERM-resistant children, then stops and reaps wrappers. SSH control masters
  use bounded `ControlPersist=30`, are explicitly closed with `-O exit`, and
  are never used by stream connections. Master workers and actual SSH child
  processes are tracked with PID/identity files and cleaned up separately.
  Only a live process with the recorded parent and identity is eligible for a
  cleanup signal.
- `q` and `Ctrl-C` remain connected to the keyboard wait even when continuous
  stream events are arriving. `Ctrl-Z` is documented Unix suspension behavior
  and is not a cleanup path.
