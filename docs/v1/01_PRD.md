# Product Requirements

## Background
After monthly production changes, engineers must verify application and system signals on Linux servers.

V1 focuses on running the dashboard locally on one server at a time.

## V1 Requirements
- Linux terminal dashboard.
- Bash-first implementation.
- No external runtime dependencies.
- Configuration is a Bash source file.
- Panel count and layout are configurable.
- Each panel has title, command, x, y, width, and height.
- Each refresh cycle runs all panel commands in order.
- Default refresh interval is 2 seconds.
- Redraw the full screen after command execution.
- Display stdout from each command.
- On command failure, show a short error message in the panel.
- Exit with `q` or Ctrl+C.
- Restore terminal state on normal exit and interrupt.
- Fail at startup with a clear message if terminal size is smaller than configured layout requires.

## Out of Scope for V1
- Remote SSH execution.
- Per-panel refresh intervals.
- Parallel/background command execution.
- Command timeout policy.
- Detailed stderr policy.
- Alert engine.
- Historical storage.
- Automatic layout scaling.

## Future
Color, alarms, remote SSH, history, command timeout policy, per-panel refresh, and richer error handling.
