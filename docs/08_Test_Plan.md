# Test Plan

Manual-first test plan for V1.

## Start
- Start dashboard with sample config.
- Expected: screen clears and configured panels render.

## Refresh
- Use a sample command whose output changes over time.
- Expected: output updates after the global refresh interval.

## Command Failure
- Configure one panel command to return non-zero.
- Expected: dashboard keeps running and that panel shows a short error message.

## Configurable Layout
- Change panel title, position, width, and height in config.
- Expected: dashboard reflects the changed layout on restart.

## Small Terminal
- Start dashboard in a terminal smaller than configured layout.
- Expected: startup fails with a clear message and restores terminal state.

## Exit With q
- Start dashboard, press `q`.
- Expected: dashboard exits and terminal prompt is usable.

## Exit With Ctrl+C
- Start dashboard, press Ctrl+C.
- Expected: dashboard exits and terminal prompt is usable.

## Long Output
- Configure a command with long lines and more rows than the panel can show.
- Expected: content is clipped to panel width and height.

## Dependency Check
- Run on a base Linux shell with Bash and standard terminal capabilities.
- Expected: no external packages are required.
