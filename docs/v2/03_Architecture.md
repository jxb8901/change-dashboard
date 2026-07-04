# Architecture

Dashboard
 -> Config Loader
 -> Panel Manager
 -> Command Executor
 -> Table Parser
 -> Threshold Evaluator
 -> Renderer
 -> Terminal

## Config Loader
- Loads V1 panel arrays.
- Loads optional V2 table arrays.
- Validates table columns and threshold rule syntax.

## Command Executor
- Runs one shell command per panel in configured order.
- Captures stdout.
- Marks failed commands as failed panel output.

## Table Parser
- Parses stdout as whitespace-separated rows when table columns are configured.
- Requires each row to match the configured column count.
- Falls back to raw display mode on parse mismatch.

## Threshold Evaluator
- Applies warning and error rules per configured column.
- Produces cell severities and panel worst status.

## Renderer
- Draws panel borders, titles, and content.
- Renders table headers for parsed table panels.
- Colors cells and panel border/title by severity.
- Keeps V1 raw rendering for non-table panels and parse fallback.

## Principles
- Keep It Simple.
- Shell First.
- Configuration over Code.
- No external dependencies.
