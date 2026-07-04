# Task Breakdown

This task list defines the V1 implementation sequence.

Implement tasks in order. Do not introduce external dependencies. Keep production business logic outside dashboard code.

## Task 1: Project Skeleton

### Goal
Create the minimum runnable project structure for the dashboard.

### Scope
- Add the dashboard entrypoint.
- Add a sample Bash source config.
- Add harmless sample panel commands only if useful.
- Define how to start the dashboard from the repo.

### Inputs
- V1 requirements in `01_PRD.md`.
- Config format in `04_Configuration.md`.

### Outputs
- Executable dashboard script.
- Sample config file.
- Basic project layout.

### Acceptance
- Dashboard can be started from the repo.
- Startup does not require external packages.
- No production-specific command is hardcoded.

### Depends On
- None.

## Task 2: Terminal Lifecycle

### Goal
Make the dashboard safe to enter and exit from a terminal.

### Scope
- Clear screen on start.
- Hide cursor while dashboard is running.
- Restore cursor and terminal state on exit.
- Support exit with `q`.
- Support exit with Ctrl+C.

### Inputs
- Dashboard entrypoint from Task 1.

### Outputs
- Terminal setup and cleanup functions.
- Signal trap for interrupt cleanup.
- Key handling for `q`.

### Acceptance
- Pressing `q` exits cleanly.
- Pressing Ctrl+C exits cleanly.
- Shell prompt is usable after exit.
- Cursor is visible after exit.

### Depends On
- Task 1.

## Task 3: Bash Config Loader

### Goal
Load V1 dashboard configuration from a trusted Bash source file.

### Scope
- Source the config file.
- Read `REFRESH_INTERVAL`.
- Apply default refresh interval of 2 seconds when unset.
- Read indexed panel arrays:
  - `PANEL_TITLES`
  - `PANEL_COMMANDS`
  - `PANEL_X`
  - `PANEL_Y`
  - `PANEL_WIDTHS`
  - `PANEL_HEIGHTS`
- Validate required fields.

### Inputs
- Sample config from Task 1.
- Config rules in `04_Configuration.md`.

### Outputs
- Config loading function.
- Config validation function.
- Clear startup errors for invalid config.

### Acceptance
- Valid config loads successfully.
- Missing config file shows a clear error.
- Missing required panel field shows a clear error.
- Invalid or empty panel list shows a clear error.

### Depends On
- Task 1.

## Task 4: Panel Model

### Goal
Convert config arrays into validated panel definitions.

### Scope
- Support any configured panel count.
- Build panel records from matching array indexes.
- Validate panel geometry.
- Reject invalid x, y, width, or height.
- Preserve configured panel order.

### Inputs
- Loaded config from Task 3.

### Outputs
- Reusable panel abstraction.
- Panel count.
- Panel geometry data.

### Acceptance
- Changing config changes panel count.
- Changing config changes panel title and layout.
- Invalid geometry fails before rendering.
- Panel order follows array index order.

### Depends On
- Task 3.

## Task 5: Terminal Size Check

### Goal
Prevent broken rendering when the terminal is too small.

### Scope
- Calculate required terminal width and height from panel geometry.
- Read current terminal rows and columns.
- Fail startup when configured layout exceeds terminal size.
- Restore terminal state before exiting on failure.

### Inputs
- Panel model from Task 4.
- Current terminal size.

### Outputs
- Minimum terminal size calculation.
- Startup size validation.

### Acceptance
- Layout that fits the terminal starts normally.
- Too-small terminal shows a clear error.
- Too-small terminal exits cleanly.
- No automatic scaling is implemented.

### Depends On
- Task 4.

## Task 6: Renderer

### Goal
Draw configured panels and content on the terminal.

### Scope
- Clear/redraw the full screen.
- Draw panel borders.
- Draw panel titles.
- Draw command output inside panel bounds.
- Clip long lines.
- Clip excess rows.
- Do not wrap output in V1.

### Inputs
- Panel model from Task 4.
- Panel output text from Task 7, or placeholder text during early implementation.

### Outputs
- Rendering functions separated from command execution.

### Acceptance
- Panels render at configured positions.
- Panel titles remain visible.
- Long lines are clipped.
- Too many rows are clipped.
- Panels do not overlap when config geometry does not overlap.
- Renderer does not execute commands.

### Depends On
- Task 4.
- Task 5.

## Task 7: Command Executor

### Goal
Run configured panel commands and return displayable output.

### Scope
- Run one shell command per panel.
- Execute commands in configured panel order.
- Capture stdout.
- On non-zero exit, return a short error message for that panel.
- Do not implement timeout policy in V1.
- Do not implement stderr policy beyond minimal failure message in V1.
- Do not run commands in parallel in V1.

### Inputs
- Panel commands from Task 4.

### Outputs
- Panel output values for renderer.
- Panel error text for failed commands.

### Acceptance
- Successful command output appears in its panel.
- Failed command does not crash the dashboard.
- Failed command shows a short error message.
- Commands run synchronously in panel order.

### Depends On
- Task 4.

## Task 8: Refresh Loop

### Goal
Connect command execution and rendering into the V1 dashboard loop.

### Scope
- Use one global refresh interval.
- Default to 2 seconds when `REFRESH_INTERVAL` is unset.
- On each cycle:
  - run all panel commands synchronously
  - collect outputs
  - redraw the full screen
- Keep listening for `q` between refresh cycles.

### Inputs
- Terminal lifecycle from Task 2.
- Config loader from Task 3.
- Renderer from Task 6.
- Command executor from Task 7.

### Outputs
- Working V1 main loop.

### Acceptance
- Dashboard refreshes automatically.
- Output changes are visible on later refreshes.
- `q` exits without waiting for a new dashboard start.
- Ctrl+C exits cleanly during the loop.

### Depends On
- Task 2.
- Task 3.
- Task 6.
- Task 7.

## Task 9: Sample V1 Dashboard Config

### Goal
Provide a safe sample layout that demonstrates V1 behavior.

### Scope
- Define five sample panels:
  - `APP Queue`
  - `APP Conn`
  - `APP Exception`
  - `Timeout/Exception`
  - `Transaction List`
- Use harmless commands.
- Keep sample commands replaceable by deployment teams.

### Inputs
- Config format in `04_Configuration.md`.
- UI sample layout in `03_UI_Design.md`.

### Outputs
- Sample config for local testing.

### Acceptance
- Sample config starts successfully in a large enough terminal.
- Sample config demonstrates top-row and bottom-row panels.
- No production-specific business command is included.

### Depends On
- Task 3.
- Task 4.
- Task 6.

## Task 10: Manual V1 Acceptance

### Goal
Verify that V1 meets the documented product requirements.

### Scope
- Run the manual test plan.
- Confirm no external dependency was introduced.
- Confirm no business logic exists in dashboard code.
- Confirm out-of-scope features were not implemented.

### Inputs
- Test plan in `08_Test_Plan.md`.
- V1 requirements in `01_PRD.md`.

### Outputs
- Manual verification result.
- List of any defects found.

### Acceptance
- Start test passes.
- Refresh test passes.
- Command failure test passes.
- Configurable layout test passes.
- Small terminal test passes.
- `q` exit test passes.
- Ctrl+C exit test passes.
- Long output clipping test passes.
- Dependency check passes.

### Depends On
- Tasks 1 through 9.

## Implementation Order

1. Project Skeleton
2. Terminal Lifecycle
3. Bash Config Loader
4. Panel Model
5. Terminal Size Check
6. Renderer
7. Command Executor
8. Refresh Loop
9. Sample V1 Dashboard Config
10. Manual V1 Acceptance

## V1 Done Definition

V1 is complete when:
- All tasks are implemented in order.
- All acceptance criteria pass.
- Manual test plan passes.
- No external dependency is required.
- Dashboard code contains no production business logic.
- Config controls panel count, title, command, position, width, and height.
- Dashboard exits cleanly with `q` and Ctrl+C.
