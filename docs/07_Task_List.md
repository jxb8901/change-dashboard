# Tasks

## Task 1: Project Skeleton
- Create executable dashboard entrypoint.
- Create sample Bash config.
- Create sample panel command placeholders if needed.
- Acceptance: dashboard can be started from the repo.

## Task 2: Terminal Lifecycle
- Clear screen on start.
- Hide cursor while running.
- Restore terminal on `q`.
- Restore terminal on Ctrl+C.
- Acceptance: shell prompt remains usable after exit.

## Task 3: Bash Config Loader
- Source the config file.
- Read `REFRESH_INTERVAL`.
- Read panel arrays.
- Validate required panel fields.
- Acceptance: missing required fields produce a clear startup error.

## Task 4: Panel Model
- Build panel definitions from indexed arrays.
- Support any configured panel count.
- Validate x, y, width, and height.
- Acceptance: changing sample config changes panel layout.

## Task 5: Terminal Size Check
- Calculate required terminal width and height from configured panels.
- Fail startup if terminal is too small.
- Acceptance: too-small terminal shows a clear error and exits cleanly.

## Task 6: Renderer
- Draw panel borders and titles.
- Render stdout inside panels.
- Clip long lines and excess rows.
- Acceptance: configured panels render without wrapping or overlap when layout fits.

## Task 7: Command Executor
- Run each panel command in order.
- Capture stdout.
- Show a short error message when a command fails.
- Acceptance: a failing command does not crash the dashboard.

## Task 8: Refresh Loop
- Run all panel commands synchronously.
- Redraw the full screen every cycle.
- Use `REFRESH_INTERVAL`, defaulting to 2 seconds.
- Acceptance: panel output updates on refresh.

## Task 9: V1 Review
- Verify no external dependencies.
- Verify no business logic in dashboard code.
- Run manual test plan.
- Acceptance: all V1 manual tests pass.
