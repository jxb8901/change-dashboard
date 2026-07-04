# Coding Guidelines

- Prefer Bash
- No external dependency
- Separate rendering from command execution
- No business logic in dashboard
- Small functions
- Reusable panel abstraction

## Config
- Load config by sourcing a Bash file.
- Treat config as trusted deployment input.
- Validate required globals and panel arrays after loading.
- Keep production-specific commands outside dashboard code.

## Rendering
- Renderer only draws terminal UI.
- Renderer does not run commands.
- Clip panel content to configured width and height.
- Keep terminal cleanup in traps.

## Execution
- Executor runs configured commands.
- Executor captures stdout.
- Executor reports a short panel error on failure.
- Do not add timeout or parallel execution in V1.

## Main Loop
- Use one global refresh interval.
- Run all panels synchronously in configured order.
- Redraw the full screen each cycle.
- Exit cleanly on `q` and Ctrl+C.
