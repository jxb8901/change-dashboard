# Change Dashboard V2 PRD

## Background
V1 provides a local terminal dashboard with command execution, panel rendering, and global synchronous refresh.

V2 helps engineers identify abnormal table values faster by coloring configured warning and error conditions.

## Goal
Add color threshold support for table-style panel output.

## Scope
- Whitespace-separated table output per panel.
- Config-defined table column names.
- Per-panel, per-column warning and error rules.
- ANSI color highlighting for warning and error cells.
- Panel border/title color based on worst cell status.
- Existing command failure display remains supported.
- Existing global synchronous refresh continues.

## Out of Scope
- Dashboard summary bar.
- History or trends.
- Remote execution.
- Root cause analysis.
- AI suggestion.
- Independent panel refresh.
- Plugin architecture.
- General rule engine.

## Compatibility
- Panels without table config keep V1 raw-output rendering.
- Existing V1 config arrays remain required.
- V2 table and threshold arrays are optional.
