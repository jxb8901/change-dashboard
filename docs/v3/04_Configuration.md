# Configuration

V3 adds two optional indexed arrays to the V2 Bash source config.

## Fixed-Width Table

```bash
PANEL_TABLE_COLUMNS[0]="name depth state"
PANEL_TABLE_WIDTHS[0]="12 8 10"
```

Widths are exact terminal character widths. The count must match the configured columns and the total must fit the panel content area.

## Transpose

```bash
PANEL_TABLE_COLUMNS[1]="host queue status"
PANEL_TABLE_LAYOUT[1]="transpose"
PANEL_TABLE_WIDTHS[1]="14 12"
```

Transpose widths represent the rendered key and value columns. The command must return at most one row.

## Color Control

```bash
NO_COLOR=1 ./bin/lhc config/v3-ux.conf
```

Any non-empty `NO_COLOR` value disables ANSI warning and error colors.
