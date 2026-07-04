# Configuration

V1 uses a Bash source config file.

The dashboard sources the file, then reads indexed arrays.

## Required Globals

```bash
REFRESH_INTERVAL=2
```

## Required Panel Arrays

All panel arrays use the same zero-based index.

```bash
PANEL_TITLES[0]="APP Queue"
PANEL_COMMANDS[0]="printf 'queue_depth=0\noldest_age=0s\n'"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=30
PANEL_HEIGHTS[0]=8
```

Required arrays:
- `PANEL_TITLES`
- `PANEL_COMMANDS`
- `PANEL_X`
- `PANEL_Y`
- `PANEL_WIDTHS`
- `PANEL_HEIGHTS`

## Sample Config

```bash
REFRESH_INTERVAL=2

PANEL_TITLES[0]="APP Queue"
PANEL_COMMANDS[0]="printf 'queue_depth=0\noldest_age=0s\n'"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=30
PANEL_HEIGHTS[0]=8

PANEL_TITLES[1]="APP Conn"
PANEL_COMMANDS[1]="printf 'active=12\nidle=3\n'"
PANEL_X[1]=32
PANEL_Y[1]=1
PANEL_WIDTHS[1]=30
PANEL_HEIGHTS[1]=8

PANEL_TITLES[2]="APP Exception"
PANEL_COMMANDS[2]="printf 'exceptions=0\nlast=none\n'"
PANEL_X[2]=63
PANEL_Y[2]=1
PANEL_WIDTHS[2]=30
PANEL_HEIGHTS[2]=8

PANEL_TITLES[3]="Timeout/Exception"
PANEL_COMMANDS[3]="printf 'timeouts=0\nerrors=0\n'"
PANEL_X[3]=94
PANEL_Y[3]=1
PANEL_WIDTHS[3]=30
PANEL_HEIGHTS[3]=8

PANEL_TITLES[4]="Transaction List"
PANEL_COMMANDS[4]="printf 'ID     STATUS\n1001   OK\n1002   OK\n'"
PANEL_X[4]=1
PANEL_Y[4]=10
PANEL_WIDTHS[4]=123
PANEL_HEIGHTS[4]=15
```

## Rules
- Config is trusted input.
- Config may contain shell commands.
- Production commands belong in config or panel scripts, not dashboard code.
- Missing panel fields are configuration errors.
- The configured layout must fit the terminal at startup.
