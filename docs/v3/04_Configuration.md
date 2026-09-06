# Configuration

V3 adds two optional indexed arrays to the V2 Bash source config.

## Fixed-Width Table

```bash
PANEL_TABLE_COLUMNS[0]="name depth state"
PANEL_TABLE_WIDTHS[0]="12 8 10"
```

Widths are exact terminal character widths. The count must match the configured
columns. LHC adds a one-character gap between columns, so the configured widths
plus all gaps must fit the panel content area.

## Transpose

```bash
PANEL_TABLE_COLUMNS[1]="HOST QUEUE STATUS"
PANEL_TABLE_LAYOUT[1]="transpose"
PANEL_TABLE_WIDTHS[1]="14 12"
```

The three `PANEL_TABLE_COLUMNS` tokens are the actual source-field names. A
command row must therefore contain three values, for example:

```text
app01 27 READY
app02 4 OK
```

Transpose widths represent the rendered field-name and field-value cells, not
the number or names of source fields. The command may return zero or more rows;
each row is rendered as a consecutive field-name/value block without a
separate table-header row. Rules, if configured, reference `HOST`, `QUEUE`, or
`STATUS` directly.

## Color Control

```bash
NO_COLOR=1 ./bin/lhc example/v3-ux.conf
```

Any non-empty `NO_COLOR` value disables ANSI warning and error colors.
