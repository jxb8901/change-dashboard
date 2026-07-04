# UI Design

## Style
- Similar to `top` or `htop`.
- Single terminal screen.
- Plain text first.
- Color is optional future work.

## Layout
Panel layout is fully configured.

Each panel defines:
- title
- x
- y
- width
- height

Coordinates are terminal character positions.

## Sample Production Layout
Top row:
- APP Queue
- APP Conn
- APP Exception
- Timeout/Exception

Bottom row:
- Transaction List

This layout is a sample config, not hardcoded behavior.

## Rendering Rules
- Draw all panels on each refresh.
- Clip content that exceeds panel width or height.
- Do not wrap long lines in V1.
- Keep panel titles visible.
- If configured layout does not fit the terminal, fail startup with a clear message.
