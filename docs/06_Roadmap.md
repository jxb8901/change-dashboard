# Roadmap

## V0.1 Terminal Shell
- Start dashboard.
- Clear and restore terminal.
- Exit with `q` and Ctrl+C.

## V0.2 Config Loader
- Source Bash config.
- Read refresh interval.
- Read panel arrays.
- Validate required panel fields.

## V0.3 Renderer
- Draw configured panels.
- Clip panel content.
- Reject terminal sizes smaller than configured layout.

## V0.4 Command Execution
- Run one command per panel.
- Capture stdout.
- Show short error message on command failure.

## V0.5 Refresh Loop
- Run global synchronous refresh.
- Default interval is 2 seconds.
- Redraw full screen each cycle.

## V1.0 Local Production Verification
- Single-host local dashboard.
- Configurable panel layout.
- No external dependencies.
- No business logic in dashboard code.
- Manual acceptance tests pass.
