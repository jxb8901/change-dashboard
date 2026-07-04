# Change Dashboard

Lightweight Bash-first terminal dashboard for local production change verification.

## Start

```bash
./bin/change-dashboard
```

Use a custom config:

```bash
./bin/change-dashboard config/sample.conf
```

## Current Status

V1 local dashboard is implemented.

The dashboard entrypoint starts from the repo, accepts a Bash source config file, validates panel layout, renders panels in the terminal, runs configured commands, and refreshes on a global interval.
