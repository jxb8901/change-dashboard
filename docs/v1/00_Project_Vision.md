# Project Vision

## Goal
Provide a lightweight Linux terminal dashboard for production change verification on a single local host.

## Target Users
- Production Support
- Application Support
- System Engineers

## V1 Scope
- Runs on the current Linux machine.
- Executes local shell commands configured by the user.
- Displays command output in terminal panels.
- Uses a configurable panel layout.
- Refreshes the full screen on a fixed interval.

## Principles
- Keep It Simple
- Zero Dependency First
- Dashboard displays data only
- Configuration over Code
- MVP First

## Non-goals
- Not a monitoring platform.
- No historical storage.
- No alert engine in V1.
- No remote SSH in V1.
- No business logic in dashboard code.
