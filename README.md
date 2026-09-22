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

Show usage and available options:

```bash
./bin/lhc --help
./bin/lhc --usage
```

With no option or config path, LHC starts with `example/sample.conf`.

Run the V2 threshold example:

```bash
./bin/lhc example/v2-threshold.conf
```

Run the V3 UX example:

```bash
./bin/lhc example/v3-ux.conf
```

Run the V5.4/V5.3 percentage-layout example:

```bash
./bin/lhc example/v5-percentage.conf
```

User manuals:

- [繁體中文使用手冊](docs/USER_MANUAL_ZH-HK.md)
- [English User Manual](docs/USER_MANUAL_EN.md)

Review the V4 SSH example before replacing its placeholder SSH targets:

```bash
less example/v4-ssh.conf
```

## Current Status

V5.8.2 includes a blocking stream event channel, in-memory bounded stream rings,
and asynchronous per-target SSH polling-master lifecycle and reliable stream
shutdown/process handling on top of the V5.2 multi-server SSH execution,
partial refresh, continuous raw/table
stream panels with event-driven redraws, fixed-width tables, multi-row
transpose layout, automatic sizing, and percentage-based responsive panel
geometry.

Stream producers publish complete-line deltas to a coalesced per-job event
queue. The main shell remains the only terminal drawer and blocks on the
stream wakeup channel; when no event is pending it waits for the next scheduler
deadline instead of waking on a fixed 50ms poll. A burst updates the affected
panel from its in-memory ring without rewriting and rereading a full snapshot
for every line. Local and dedicated SSH streams use the same path.
After a terminal resize, active stream capacities are recomputed immediately;
existing event-mode rings are trimmed in memory and subsequent lines use the
new visible bound.

During shutdown LHC gives active local/SSH commands and stream collectors a
short TERM grace period, escalates to KILL when necessary, reaps wrappers
within a bound, and closes SSH control masters. Completed refresh jobs are
removed from active scheduler state. SSH polling masters are created explicitly
per target with bounded `ControlPersist=30`; master creation runs in a
per-target background lifecycle worker, so slow or unreachable targets do not
block local panels or keyboard input. Polling commands use independent channels
over that master, while continuous streams use dedicated non-multiplexed
connections. LHC checks master readiness before polling, recreates stale/dead
masters with one worker per target, backs off failed targets, and retries a
failed polling transport once.
An abnormal termination therefore cannot leave a master indefinitely.

If an SSH polling worker dies while its target is still STARTING, LHC verifies
worker ownership, removes only its stale PID/identity metadata and lock, and
creates one replacement worker. Command output is sanitized before rendering:
CSI/OSC terminal controls are removed, tabs become one space, carriage returns
are removed, and other C0 controls are discarded except newline. Cell sizing
still uses Bash character counts rather than terminal-cell wcwidth, so CJK
and emoji can require extra width in aligned tables; use ASCII fields when
exact alignment is required.

Press `q` or `Ctrl-C` for normal shutdown. `Ctrl-Z` suspends a foreground Unix
job and cannot run cleanup; use `q` or `Ctrl-C` to leave the dashboard cleanly.

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

The alias is also the displayed server value. For table and transpose panels,
the first configured field is the synthetic server-identity field (normally
`SERVER`); the remote command emits only the remaining actual data fields. Raw
panels prefix every physical line with the alias. Transpose panels show each
configured field name with its value and do not add a separate table-header row.

Servers within a panel run concurrently and are aggregated in configured alias
order. SSH uses `BatchMode=yes`, `ConnectTimeout=10`, and
`StrictHostKeyChecking=yes`; configure keys, known hosts, ports, identities,
and jump hosts before starting LHC. Polling commands share one explicit master
per target; stream commands do not share that master. See
[`docs/v4/01_SSH_Design.md`](docs/v4/01_SSH_Design.md) for the complete contract.

Run the V4 regression test without real SSH servers:

```bash
./tests/test_v4_ssh.sh
```

Run the V5 raw-stream regression test without real SSH servers:

```bash
bash tests/test_v5_stream.sh
```

Run the Issue #7 event-loop regression test. It exercises the real renderer,
checks a sub-100ms local event path, verifies bounded ring ordering, and
guards against reintroducing the fixed polling interval:

```bash
bash tests/test_v11_stream_event_loop.sh
```

For a repeatable latency comparison, run the benchmark harness. It uses the
same timestamp producer for plain `tail -f`, plain `tail -F`, and an LHC raw
stream panel, and reports p50/p95/max latency, user/sys CPU time, peak CPU,
peak process count, and dropped lines:

```bash
LHC_BENCHMARK_COUNT=50 bash tests/benchmark_stream_event_loop.sh
```

Representative 50-sample output from a macOS run on 2026-09-22 was:

| path | rate | p50 / p95 / max | user / sys | peak CPU | peak processes | dropped |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tail -f` | 10 | 0.1 / 0.1 / 0.1 ms | 0.00 / 0.00 s | 0.3% | 4 | 0 |
| `tail -F` | 10 | 0.1 / 0.2 / 0.3 ms | 0.00 / 0.00 s | 0.3% | 4 | 0 |
| LHC | 10 | 28.8 / 30.9 / 35.8 ms | 0.84 / 0.74 s | 0.4% | 10 | 0 |
| `tail -f` | 50 | 0.0 / 0.1 / 0.2 ms | 0.00 / 0.00 s | 0.4% | 4 | 0 |
| `tail -F` | 50 | 0.1 / 0.1 / 2.6 ms | 0.00 / 0.00 s | 0.2% | 4 | 0 |
| LHC | 50 | 27.0 / 33.3 / 35.0 ms | 0.79 / 0.70 s | 0.3% | 11 | 0 |

The LHC acceptance regression below uses the production event/render path,
collects 50 samples at both 10 and 50 lines/second, and enforces p95 <100ms.
Plain tail is a transport baseline and does not parse, rule-check, or draw
terminal panels; benchmark CPU and process values are machine-dependent.

Run the V5.3 shutdown and process-lifecycle regression test:

```bash
bash tests/test_v5_shutdown.sh
```

Run the V5.5 SSH master lifecycle regression test:

```bash
bash tests/test_v6_ssh_lifecycle.sh
bash tests/test_v9_ssh_starting_recovery.sh
bash tests/test_v10_output_sanitization.sh
```
