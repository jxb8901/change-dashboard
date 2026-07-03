# ADR

## ADR-001
Use Bash first.
Reason: zero dependency.

## ADR-002
Dashboard only displays command output.
Reason: business checks belong in panel commands or deployment config.

## ADR-003
Use Bash source config with indexed arrays.
Reason: no parser dependency and easy shell integration.

## ADR-004
Panel layout is fully configurable in V1.
Reason: production dashboard layouts vary by application and terminal size.

## ADR-005
Use global synchronous full-screen refresh in V1.
Reason: simplest execution model and easiest terminal rendering.

## ADR-006
V1 runs commands only on the local host.
Reason: remote SSH adds connection, credential, timeout, and failure complexity.

## ADR-007
Command failure handling is minimal in V1.
Reason: failed panels should not crash the dashboard, but detailed stderr and timeout policy can wait.
