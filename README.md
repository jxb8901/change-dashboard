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

Task 1 project skeleton is implemented.

The dashboard entrypoint starts from the repo and accepts a Bash source config file. Terminal lifecycle, config validation, rendering, command execution, and refresh behavior are implemented in later tasks.
