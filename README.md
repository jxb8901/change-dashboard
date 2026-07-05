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

## Current Status

V3 partial refresh, fixed-width tables, and transpose layout are implemented.

The dashboard remains compatible with V1 raw-output configs. It accepts a Bash
source config file, validates panel layout and optional table rules, runs local
commands synchronously, renders panels in the terminal, and refreshes globally.
