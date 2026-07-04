# Change Dashboard

Lightweight Bash-first terminal dashboard for local production change verification.

## Start

```bash
./bin/lhc.sh
```

Use a custom config:

```bash
./bin/lhc.sh config/sample.conf
```

Run the V2 threshold example:

```bash
./bin/lhc.sh config/v2-threshold.conf
```

## Current Status

V2 table parsing and configurable warning/error coloring are implemented.

The dashboard remains compatible with V1 raw-output configs. It accepts a Bash
source config file, validates panel layout and optional table rules, runs local
commands synchronously, renders panels in the terminal, and refreshes globally.
