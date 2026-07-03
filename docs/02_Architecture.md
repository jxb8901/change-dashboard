# Architecture

## Components

Dashboard
 -> Config Loader
 -> Panel Manager
 -> Command Executor
 -> Renderer
 -> Terminal

## Responsibilities

### Dashboard
- Owns the main loop.
- Handles `q`, Ctrl+C, and terminal cleanup.
- Runs a global synchronous refresh cycle.
- Does not contain business logic.

### Config Loader
- Sources a Bash config file.
- Reads global settings such as refresh interval.
- Reads indexed panel arrays.
- Validates required panel fields.

### Panel Manager
- Builds panel definitions from config.
- Validates panel count and geometry.
- Calculates the minimum terminal size required by the configured layout.

### Command Executor
- Runs one shell command per panel.
- Runs commands in panel order.
- Captures stdout for display.
- Returns a short error message when a command fails.

### Renderer
- Clears and redraws the full terminal screen each refresh.
- Draws panel borders, titles, and clipped content.
- Does not execute commands.

## Panel Model
Each panel has:
- title
- command
- x
- y
- width
- height

## V1 Refresh Model
- One global refresh interval.
- Default interval: 2 seconds.
- All panels refresh together.
- No per-panel scheduler.
- No background command execution.
