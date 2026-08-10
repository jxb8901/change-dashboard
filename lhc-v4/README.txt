# Change Dashboard

Lightweight Bash-first terminal dashboard for local production change verification.

## Start

```bash
./bin/lhc
```

Use a custom config:

```bash
./bin/lhc example/sample.conf
```

Run the V2 threshold example:

```bash
./bin/lhc example/v2-threshold.conf
```

Run the V3 UX example:

```bash
./bin/lhc example/v3-ux.conf
```

Review the V4 SSH example before replacing its placeholder SSH targets:

```bash
less example/v4-ssh.conf
```

## Current Status

V4.6 multi-server SSH execution is implemented alongside partial refresh,
fixed-width tables, and multi-row transpose layout.

The dashboard remains compatible with V1 raw-output configs. It accepts a Bash
source config file, validates panel layout and optional table rules, runs local
and SSH commands concurrently, renders completed panels progressively, and
refreshes globally.

## SSH Panels

Declare SSH targets once, then reference their aliases from a panel:

```bash
SSH_SERVERS[0]="APP01|ops@app01"
SSH_SERVERS[1]="APP02|ops@app02"

PANEL_COMMANDS[0]="/opt/checks/check_queue.sh"
PANEL_SSH_ALIASES[0]="APP01 APP02"
PANEL_TABLE_COLUMNS[0]="SERVER APP DEPTH STATUS"
PANEL_TABLE_WIDTHS[0]="8 8 8 10"
```

The alias is also the displayed server value. For table panels, the first
configured column is reserved for that alias; the remote command emits only the
remaining fields. Raw panels prefix every physical line with the alias.

Servers within a panel run concurrently and are aggregated in configured alias
order. SSH uses `BatchMode=yes`, `ConnectTimeout=10`, and
`StrictHostKeyChecking=yes`; configure keys, known hosts, ports, identities,
and jump hosts before starting LHC. See
[`docs/v4/01_SSH_Design.md`](docs/v4/01_SSH_Design.md) for the complete contract.

Run the V4 regression test without real SSH servers:

```bash
./tests/test_v4_ssh.sh
```
