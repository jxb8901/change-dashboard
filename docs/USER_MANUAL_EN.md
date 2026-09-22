# LHC User Manual

LHC (Local Change Dashboard) is a Bash terminal dashboard for running local or SSH checks on a schedule and displaying their results as raw output, a table, or a transposed field/value view. This manual describes the current behavior of `bin/lhc`.

## 1. Quick start

LHC requires Bash (including Bash 3.2) and an interactive terminal; SSH panels also require a working local OpenSSH `ssh` client. A configuration file is a Bash source file and LHC sources it directly, so only use trusted configuration files.

```bash
# Use the default configuration: example/sample.conf
./bin/lhc

# Use a specific configuration
./bin/lhc example/v3-ux.conf

# Show command help (`-h`, `--help`, or `--usage`)
./bin/lhc --help

# Disable ANSI warning/error colors
NO_COLOR=1 ./bin/lhc example/fpp.conf
```

Press `q` to exit the dashboard. `Ctrl+C` also exits. On normal exit, `q`, an interrupt, or a runtime failure, LHC stops running child commands, removes temporary files, and restores the cursor and terminal attributes. Active commands and stream collectors receive a bounded `TERM` grace period and then `KILL` if needed; SSH control masters are explicitly closed. `Ctrl-Z` only suspends the foreground Unix job and does not run cleanup, so use `q` or `Ctrl-C` to leave the dashboard.

When no file is supplied, LHC uses `example/sample.conf` relative to the project root containing the script.

`-h`, `--help`, and `--usage` are equivalent options. Each prints the usage text and exits without starting the dashboard. With no option or config path, LHC uses the default configuration and starts the dashboard.

## 2. Execution model

Each startup or refresh cycle works as follows:

1. Load and validate the Bash configuration.
2. Draw all panel borders and `Loading...` placeholders.
3. Start each due panel's local command or SSH jobs concurrently.
4. For a snapshot panel, parse and redraw as soon as all its jobs finish. For a
   stream panel, publish each complete output line as a delta into a bounded
   per-job event queue and redraw whenever the main loop receives a wakeup.
   The main shell is the only terminal drawer. It drains a burst into the
   in-memory ring and otherwise blocks until the next stream event or scheduler
   deadline; it does not use a fixed 50ms idle poll or rewrite a full snapshot
   file for every line.
5. If a snapshot command exceeds its configured timeout, terminate its owned
   process tree and display `TIMEOUT after Ns` as failed panel output. A timed
   out panel is scheduled again after `REFRESH_INTERVAL` seconds.
6. Schedule that panel's next run after `REFRESH_INTERVAL` seconds when its
   command set finishes; other panels have independent timers and are not
   blocked by it.

SSH jobs run concurrently, but results within one panel are aggregated in the order of `PANEL_SSH_ALIASES`, not completion order. LHC updates only changed frame cells; a terminal resize forces a complete redraw.

## 3. Minimal local configuration

Every panel uses the same zero-based index. The following is a raw-output panel:

```bash
REFRESH_INTERVAL=2
COMMAND_TIMEOUT_SECONDS=10

PANEL_TITLES[0]="Queue"
PANEL_COMMANDS[0]="printf 'queue=0\\noldest=0s\\n'"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=32
PANEL_HEIGHTS[0]=8
```

The command's stdout is displayed in the panel. A non-zero exit status displays `Command failed`. Local commands run through `bash -c`; stderr is captured for process handling and is not printed directly into the full-screen dashboard.

Coordinates are one-based, with `(1,1)` at the upper-left terminal cell. Width and height include the panel border. The minimum panel width is `4` and the minimum height is `3`. The terminal must contain the configured rightmost column and bottom row plus the footer; LHC does not automatically prevent panels from overlapping.

The final panel may omit `PANEL_HEIGHTS[i]`; LHC uses the maximum height from
`PANEL_Y[i]` to the row above the footer. Other panels must define height.
The automatic height is recalculated after terminal resize.

Command stdout is treated as display data before it reaches any raw, table, or
transpose renderer, including local and SSH aggregation. CSI and OSC terminal
control sequences are removed, tabs become one space, carriage returns are
removed, and other C0 controls are discarded except newline. Plain ASCII is
unchanged. Cell sizing remains based on Bash character counts rather than
terminal-cell wcwidth; CJK and emoji may therefore occupy more cells than LHC
allocates, so use ASCII values when exact table alignment is required.

`PANEL_X`, `PANEL_Y`, `PANEL_WIDTHS`, and `PANEL_HEIGHTS` also accept a
percentage such as `50%`. X and width percentages use terminal columns; Y and
height percentages use the terminal rows excluding the footer. `0%` means the
left or top boundary for a position. Percentage values are rounded down and
are resolved again from the original configuration after every resize. Integer
and percentage values may be mixed within one panel. The normal minimum-size
and bounds checks still apply.

## 4. Configuration reference

### 4.1 Global settings

| Variable | Required | Description |
| --- | --- | --- |
| `REFRESH_INTERVAL` | No | Positive integer seconds; default `2`. Each panel starts its next run this many seconds after its own command set finishes. |
| `COMMAND_TIMEOUT_SECONDS` | No | Non-negative integer seconds; default `0` (unlimited). Maximum runtime for snapshot commands; `PANEL_TIMEOUT_SECONDS[i]` can override it per panel. A timed out command displays `TIMEOUT after Ns` and the panel retries after `REFRESH_INTERVAL`. Bash 3.2 timing is integer-resolution and intentionally errs late by up to about one second. Stream commands are not limited by this setting. |
| `NO_COLOR` | Environment | Any non-empty value disables ANSI warning/error colors. |

`TMPDIR` is not a panel setting. When set, LHC creates its temporary command-output directory below it and removes that directory on exit; otherwise it uses `/tmp`.

### 4.2 Required fields for every panel

All six fields below must be set at the same index. A missing field, empty title/command, or invalid integer/percentage geometry value causes startup validation to fail.

| Variable | Example | Description |
| --- | --- | --- |
| `PANEL_TITLES[i]` | `"Queue"` | Panel title; must not be empty. |
| `PANEL_COMMANDS[i]` | `"check_queue.sh"` | Bash command to run; must not be empty. |
| `PANEL_X[i]` | `1` or `"0%"` | Left edge, one-based column for integers or percentage of terminal width. |
| `PANEL_Y[i]` | `1` or `"0%"` | Top edge, one-based row for integers or percentage of usable terminal height. |
| `PANEL_WIDTHS[i]` | `40` or `"50%"` | Total panel width, including borders; minimum `4` after resolution. |
| `PANEL_HEIGHTS[i]` | `8` or `"50%"` | Total panel height, including borders; minimum `3` after resolution. |

Panel indexes must be non-negative integers. An extra index (for example, `PANEL_COMMANDS[4]` without `PANEL_TITLES[4]`) is rejected.

For example, two panels can split the terminal horizontally and adapt to
resize:

```bash
PANEL_X[0]="0%"
PANEL_Y[0]="0%"
PANEL_WIDTHS[0]="50%"
PANEL_HEIGHTS[0]="100%"

PANEL_X[1]="50%"
PANEL_Y[1]="0%"
PANEL_WIDTHS[1]="50%"
PANEL_HEIGHTS[1]="100%"
```

The footer row remains reserved. A percentage that resolves below the minimum
size or outside the terminal causes startup validation to fail; after resize,
the dashboard pauses until the terminal is large enough.

### 4.2.1 Optional stream setting

| Variable | Example | Description |
| --- | --- | --- |
| `PANEL_STREAM[i]` | `1` | Enables continuous raw or `table` output for panel `i`; valid values are `0` and `1`, and the default is snapshot mode. The rolling buffer is derived from the panel's effective height. |
| `PANEL_TIMEOUT_SECONDS[i]` | `20` | Optional non-negative integer timeout for snapshot panel `i`; overrides `COMMAND_TIMEOUT_SECONDS`. `0` means unlimited. Bash 3.2 timing is conservative and may fire up to about one second late. Stream panels ignore command timeouts so long-running streams remain active. |

Timeouts apply to the complete local or SSH snapshot command set. LHC owns the
wrapper and child processes, sends `TERM`, and uses the normal bounded cleanup
escalation if a process does not exit. A timeout replaces stale successful data
with the explicit failed output `TIMEOUT after Ns`; the panel is retried after
`REFRESH_INTERVAL`. If a panel cannot start its temporary directory, FIFO, or
job, the scheduler reports an error and rolls back the partial start before
exiting.

### 4.3 Raw panels

A panel without `PANEL_TABLE_COLUMNS[i]` is a raw panel. Command stdout is displayed line by line; empty stdout displays `No data`. Lines do not wrap. Text wider than the panel is clipped, and lines beyond the visible height are not shown. Raw panels may use the reserved `MESSAGE` rule field with `~` or `!~`; for `~`, only every matching keyword occurrence is highlighted and the rest of the message stays unstyled.

Set `PANEL_STREAM[i]=1` to run a raw panel as a continuous stream. LHC reads
complete newline-terminated lines while the command is still running and keeps
the most recent `PANEL_EFFECTIVE_HEIGHTS[i] - 2` lines, so no separate stream
line-count setting is required. The same setting works for local and raw SSH
panels. Table stream panels are described below; transpose stream panels remain
unsupported. When the command exits, the final buffer remains visible and the panel is restarted after
`REFRESH_INTERVAL` seconds. A producer that buffers stdout may need a
line-buffering option such as `stdbuf -oL`. Stream notifications use a
panel-local frame rebuild and diff, so unrelated panels are not recalculated
for each new stream line; the full dashboard is rebuilt for the initial draw,
ordinary panel completion, and terminal resize.
When the terminal is resized, LHC recomputes the capacity of every active
stream job, trims the existing event-mode ring in memory immediately, and uses
the new capacity for subsequent lines.

```bash
PANEL_TITLES[0]="Deployment"
PANEL_COMMANDS[0]="printf 'release=2026.08\\nowner=change-team\\n'"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=40
PANEL_HEIGHTS[0]=7
```

Example continuous raw panel:

```bash
PANEL_TITLES[0]="Application log"
PANEL_COMMANDS[0]="tail -F /var/log/app.log"
PANEL_STREAM[0]=1
PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=60; PANEL_HEIGHTS[0]=12
```

### 4.4 Table panels

Setting `PANEL_TABLE_COLUMNS[i]` enables whitespace-delimited table parsing. Its whitespace-separated tokens are the names of the source data fields, not literal `key` and `value` labels. Every non-empty stdout line must contain exactly the configured number of fields.

```bash
PANEL_TITLES[1]="Queue Status"
PANEL_COMMANDS[1]="printf 'EAI 12 OK\\nICL 27 WARN\\nDB 55 DOWN\\n'"
PANEL_X[1]=42
PANEL_Y[1]=1
PANEL_WIDTHS[1]=48
PANEL_HEIGHTS[1]=8
PANEL_TABLE_COLUMNS[1]="NAME DEPTH STATUS"
PANEL_TABLE_WIDTHS[1]="12 8 12"
PANEL_WARN_RULES[1]="DEPTH:>20"
PANEL_ERROR_RULES[1]="DEPTH:>50 STATUS:==DOWN"
```

Rules:

- Column names are whitespace-separated, must be non-empty and unique, and must not contain `:`.
- Blank lines are skipped; a field value cannot contain whitespace. If any non-empty row has the wrong field count, the whole panel falls back to raw output and threshold colors are not applied.
- `PANEL_TABLE_LAYOUT[i]` may be omitted (default `table`) or set to `table` / `transpose`.
- In `table` layout, `PANEL_TABLE_WIDTHS[i]` contains one positive width per source column. If only the final width is omitted, it fills all remaining content width. If the list is omitted entirely, widths are divided equally.
- LHC inserts a fixed one-character gap between columns. Configured widths plus gaps must fit `PANEL_WIDTHS[i] - 2`.
- Numbers are right-aligned; headers and text are left-aligned. A number may have an optional minus sign, integer digits, and fractional digits, such as `-2`, `0`, or `12.50`.

A `table` panel may also set `PANEL_STREAM[i]=1`. Each complete newline-
terminated output line is appended as a new row, and only the newest rows that
fit below the rendered header are retained. No separate stream row-count
setting is required. The existing table parser, widths, and cell rules are
applied on every update. If a visible row has the wrong field count, the panel
temporarily falls back to raw output until that row rolls out of the buffer.
For SSH table streams, include the alias prefix as a source column such as
`SERVER`; aliases remain in configured order and SSH failures use the existing
synthetic failure row.

```bash
PANEL_TITLES[0]="Live Services"
PANEL_COMMANDS[0]="tail -F /tmp/services.tsv"
PANEL_STREAM[0]=1
PANEL_TABLE_COLUMNS[0]="SERVICE COUNT STATUS"
PANEL_TABLE_LAYOUT[0]="table"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=48
PANEL_HEIGHTS[0]=8
```

### 4.4.1 Stream latency verification

Run the Issue #7 regression check from the repository root:

```bash
bash tests/test_v11_stream_event_loop.sh
```

It measures 50 real local stream-to-render samples at both 10 and 50
lines/second, requires p95 below 100ms, verifies the bounded visible-ring
suffix and ordering, checks scheduler deadlines while no stream event arrives,
and exercises burst event-channel shutdown cleanup. For a reproducible
tail-versus-LHC comparison, run:

```bash
LHC_BENCHMARK_COUNT=50 bash tests/benchmark_stream_event_loop.sh
```

The harness uses the same timestamp producer for plain `tail -f`, plain
`tail -F`, and an LHC raw stream panel. It reports p50/p95/max latency,
user/sys CPU time, peak CPU, peak process count, and dropped lines. A
representative 50-sample macOS run on 2026-09-22 produced these results:

| path | rate | p50 / p95 / max | user / sys | peak CPU | peak processes | dropped |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `tail -f` | 10 | 0.1 / 0.1 / 0.1 ms | 0.00 / 0.00 s | 0.3% | 4 | 0 |
| `tail -F` | 10 | 0.1 / 0.2 / 0.3 ms | 0.00 / 0.00 s | 0.3% | 4 | 0 |
| LHC | 10 | 28.8 / 30.9 / 35.8 ms | 0.84 / 0.74 s | 0.4% | 10 | 0 |
| `tail -f` | 50 | 0.0 / 0.1 / 0.2 ms | 0.00 / 0.00 s | 0.4% | 4 | 0 |
| `tail -F` | 50 | 0.1 / 0.1 / 2.6 ms | 0.00 / 0.00 s | 0.2% | 4 | 0 |
| LHC | 50 | 27.0 / 33.3 / 35.0 ms | 0.79 / 0.70 s | 0.3% | 11 | 0 |

Plain tail is only a transport baseline and does not include LHC parsing,
rules, or terminal rendering; CPU and process values are machine-dependent.

Run the complete deterministic local suite with:

```bash
bash tests/run_all.sh
```

On Linux with `sshd`, the separate real-OpenSSH integration test verifies
master creation, channel reuse, bounded persistence expiry, dedicated stream
connections, master death recovery, and explicit shutdown:

```bash
bash tests/test_real_openssh.sh
```

If `PANEL_WARN_RULES`, `PANEL_ERROR_RULES`, or `PANEL_INFO_RULES` is set on a raw panel, rules must use `MESSAGE:~keyword` or `MESSAGE:!~keyword`. Table/transpose rules still require `PANEL_TABLE_COLUMNS[i]`. The layout must be `table` or `transpose`; widths must match the layout, except that only the final width may be omitted.

### 4.5 Transpose layout

Transpose displays each data row vertically as one `field name / field value` block. `PANEL_TABLE_COLUMNS[i]` must contain the actual source-field names, in source-field order. `PANEL_TABLE_WIDTHS[i]` contains the field-name width and optionally the field-value width; if the final width is omitted, it fills all remaining content width.

```bash
PANEL_TITLES[2]="Release Summary"
PANEL_COMMANDS[2]="printf 'READY 2 BLUE\\nDEGRADED 5 RED\\n'"
PANEL_X[2]=1
PANEL_Y[2]=10
PANEL_WIDTHS[2]=38
PANEL_HEIGHTS[2]=10
PANEL_TABLE_COLUMNS[2]="STATE COUNT COLOR"
PANEL_TABLE_LAYOUT[2]="transpose"
PANEL_TABLE_WIDTHS[2]="14 18"
PANEL_WARN_RULES[2]="COUNT:>3"
PANEL_ERROR_RULES[2]="STATE:==DEGRADED"
```

Both local and SSH transpose panels may contain zero or more data rows. For the example above, the display is `STATE READY`, `COUNT 2`, `COLOR BLUE`, then `STATE DEGRADED`, `COUNT 5`, `COLOR RED`. Transpose does not add a separate table-header row; the configured field names are repeated as labels inside each data block. A field-count mismatch falls back to raw output. SSH panels prepend the server alias to each row before rendering, so an SSH block starts with `SERVER <alias>` followed by the configured data fields.

### 4.6 Warning and error rules

Rule tokens use `source-field:condition` and are separated by whitespace. Rules reference the actual names in `PANEL_TABLE_COLUMNS[i]` in both `table` and `transpose` layouts; `field name` and `field value` are display concepts, not rule names. `field:~keyword` matches a field containing the keyword; `field:!~keyword` matches a field not containing it. `PANEL_INFO_RULES` uses the same syntax and displays matched cells or raw keywords in green:

```bash
PANEL_WARN_RULES[0]="DEPTH:>20 LATENCY:>=200 STATUS:!=OK"
PANEL_ERROR_RULES[0]="DEPTH:>50 STATUS:==DOWN"
PANEL_INFO_RULES[0]="STATUS:==READY"
```

Supported operators are `>`, `>=`, `<`, `<=`, `==`, `!=`, `~`, and `!~`. Severity precedence is `ERROR > WARN > INFO > OK`.

- `>`, `>=`, `<`, and `<=` match only when both the cell value and threshold are numeric.
- `==` and `!=` compare two numeric values numerically; other values are compared as strings.
- Field names must match exactly and must exist in `PANEL_TABLE_COLUMNS`.
- An error takes precedence over a warning. Panel severity is the worst cell status: `ERROR > WARN > OK`.
- Matching cells use a yellow background for warnings and a red background for errors. `NO_COLOR` preserves the evaluation but hides the colors.

### 4.7 Multi-server SSH panels

Declare targets in one global registry, then reference their aliases from a panel:

```bash
SSH_SERVERS[0]="APP01|ops@app01"
SSH_SERVERS[1]="APP02|ops@app02"

PANEL_TITLES[3]="Remote Queue"
PANEL_COMMANDS[3]="/opt/checks/check_queue.sh"
PANEL_SSH_ALIASES[3]="APP01 APP02"
PANEL_X[3]=1
PANEL_Y[3]=22
PANEL_WIDTHS[3]=60
PANEL_HEIGHTS[3]=10
PANEL_TABLE_COLUMNS[3]="SERVER APP DEPTH STATUS"
PANEL_TABLE_WIDTHS[3]="8 12 8 12"
PANEL_WARN_RULES[3]="DEPTH:>20"
PANEL_ERROR_RULES[3]="DEPTH:>50 STATUS:==DOWN"
```

Each registry record is `alias|target`:

- An alias may contain only letters, numbers, `.`, `_`, and `-`; it must be unique, contain no whitespace, and must not start with `-`.
- A target must be non-empty and contain no whitespace or `|`, and must not start with `-`. Put complex port, identity, ProxyJump, and similar settings in `~/.ssh/config`, then use the SSH config alias as the target.
- `PANEL_SSH_ALIASES[i]` is a whitespace-separated list of unique registry aliases. Without it, the panel command runs locally.
- SSH uses `ssh -T`, `BatchMode=yes`, `ConnectTimeout=10`, `StrictHostKeyChecking=yes`, and executes `PANEL_COMMANDS[i]` remotely through `bash -s`.
- During one LHC run, polling commands for the same SSH target share one explicit master with bounded `ControlPersist=30`; each command still uses an independent session/channel. Master creation is handled by one per-target background worker with `STARTING`, `READY`, and `FAILED` state, so a slow or unreachable target does not block local panels or keyboard input. LHC checks readiness before polling, recreates a stale/dead master, and retries a transport failure once. Continuous streams use dedicated non-multiplexed connections and do not consume the polling master's session capacity. Connections are explicitly closed when LHC exits and are not reused by a later LHC launch.
- `SSH_CONTROL_PERSIST_SECONDS` may override the persistence bound from 1 to 3600 seconds, `SSH_CONNECT_TIMEOUT_SECONDS` may override the connection timeout from 1 to 300 seconds, `SSH_CONTROL_CHECK_TIMEOUT_SECONDS` may bound each SSH control-socket check from 1 to 60 seconds, and `SSH_MASTER_RETRY_BACKOFF_SECONDS` may override failed-target backoff from 1 to 300 seconds. Defaults are `30`, `10`, `2`, and `5`. The connection timeout limits establishment only; the control-socket check has its own wall-clock bound, while there is no additional timeout after a remote command starts. Prepare keys/agent access and `known_hosts` first, because LHC will not prompt for a password or host-key confirmation.

For an SSH panel, the first configured column is a synthetic server-identity field named `SERVER`; it is not emitted by the remote command. The remote command should output one value for each remaining configured data field. With the example above, each remote line should have three fields:

```text
FPP 2 OK
API 0 OK
```

LHC prepends the alias:

```text
APP01 FPP 2 OK
APP01 API 0 OK
APP02 FPP 1 OK
```

Special results are represented as follows:

| Situation | Table panel | Raw panel |
| --- | --- | --- |
| Successful but empty stdout | `ALIAS No_data - ...` | `ALIAS No data` |
| SSH or command failure | `ALIAS SSH_FAILED - ...`; every cell in the row is ERROR | `ALIAS SSH_FAILED (exit N)`; the panel is failed |
| Another server succeeds | Successful rows remain visible | Successful output remains visible |

SSH stderr is not printed in the full-screen display; only the alias and exit status are shown. If a remote table row has the wrong number of fields, the complete aggregated result falls back to raw output with aliases.

## 5. Display and refresh behavior

- The initial screen draws borders, titles, and `Loading...`; completed panels replace their content progressively.
- Panel titles are centered and clipped to the available title width when necessary.
- Raw panels show text, table panels show a header and data rows, and transpose panels show field-name/value blocks without a separate table-header row.
- Stream raw and table panels update while their command is still running and retain only
  the most recent visible content-height lines. Updates are event-driven;
  `REFRESH_INTERVAL` controls only when an exited command is restarted. A
  stream command that exits is restarted after `REFRESH_INTERVAL` seconds.
- Completed refresh jobs are removed from active scheduler state. This keeps
  long-running dashboards from accumulating historical job PIDs. During
  continuous output, stream notifications are coalesced in per-job queues and
  drained after the event FIFO wakes the main loop; keyboard input is read
  independently, so `q` remains responsive without a fixed idle poll.
- Empty results display `No data`. Content is clipped to panel height and does not scroll automatically.
- Cell widths are fixed. A numeric value that is too wide becomes all `#` characters; an overlong text value keeps a trailing `.` (for example, `abcdefg.` in an eight-character cell).
- Warning cells use black text on yellow; error cells and failed-panel content use white text on red. `NO_COLOR` only disables ANSI colors.
- The footer displays `Refresh: Ns | Press q to exit.`; this value is the
  command restart interval, not the live stream redraw interval.
- If the terminal becomes too small, execution pauses and shows the required size. It resumes and fully redraws after the terminal is enlarged. `q` still exits while paused.

## 6. Complete simple configuration

The following configuration demonstrates raw, table, transpose, and SSH panels. The SSH targets are placeholders; replace them and verify SSH access before use.

```bash
REFRESH_INTERVAL=2
COMMAND_TIMEOUT_SECONDS=10

# Raw local panel
PANEL_TITLES[0]="Local Release"
PANEL_COMMANDS[0]="printf 'release READY\\nowner ops\\n'"
PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=36; PANEL_HEIGHTS[0]=8

# Local table panel
PANEL_TITLES[1]="Queues"
PANEL_COMMANDS[1]="printf 'EAI 12 OK\\nICL 27 WARN\\n'"
PANEL_X[1]=38; PANEL_Y[1]=1; PANEL_WIDTHS[1]=42; PANEL_HEIGHTS[1]=8
PANEL_TABLE_COLUMNS[1]="NAME DEPTH STATUS"
PANEL_TABLE_WIDTHS[1]="10 8 12"
PANEL_WARN_RULES[1]="DEPTH:>20"
PANEL_ERROR_RULES[1]="DEPTH:>50 STATUS:==DOWN"

# Local transpose panel (multiple source rows supported)
PANEL_TITLES[2]="Summary"
PANEL_COMMANDS[2]="printf 'READY 2 BLUE\\nDEGRADED 5 RED\\n'"
PANEL_X[2]=1; PANEL_Y[2]=10; PANEL_WIDTHS[2]=36; PANEL_HEIGHTS[2]=10
PANEL_TABLE_COLUMNS[2]="STATE COUNT COLOR"
PANEL_TABLE_LAYOUT[2]="transpose"
PANEL_TABLE_WIDTHS[2]="12 18"
PANEL_WARN_RULES[2]="COUNT:>3"
PANEL_ERROR_RULES[2]="STATE:==DEGRADED"

# SSH table panel
SSH_SERVERS[0]="APP01|ops@app01"
SSH_SERVERS[1]="APP02|ops@app02"
PANEL_TITLES[3]="Remote Queue"
PANEL_COMMANDS[3]="/opt/checks/check_queue.sh"
PANEL_SSH_ALIASES[3]="APP01 APP02"
PANEL_X[3]=38; PANEL_Y[3]=10; PANEL_WIDTHS[3]=42; PANEL_HEIGHTS[3]=10
PANEL_TABLE_COLUMNS[3]="SERVER APP DEPTH STATUS"
PANEL_TABLE_WIDTHS[3]="8 8 8 12"
PANEL_TIMEOUT_SECONDS[3]=20
PANEL_WARN_RULES[3]="DEPTH:>20"
PANEL_ERROR_RULES[3]="DEPTH:>50 STATUS:==DOWN"
```

## 7. Troubleshooting

| Message or symptom | Resolution |
| --- | --- |
| `config file not found` | Check the path and run `./bin/lhc path/to/config`. |
| `at least one panel must be configured` | Define at least one `PANEL_TITLES[i]` and all required panel fields. |
| `terminal too small` | Enlarge the terminal or reduce `PANEL_X/Y/WIDTHS/HEIGHTS`; a running dashboard pauses when resized too small. |
| A table is displayed as raw output | Check field counts on every non-empty stdout line, whitespace delimiters, and table/transpose rules. |
| `Command failed` | Run the command directly and check permissions, PATH, and exit status; LHC does not put stderr in the display. |
| An SSH row is `SSH_FAILED` | Check registry aliases, `~/.ssh/config`, key/agent access, `known_hosts`, and the target host; strict host-key policy must succeed. |
| No colors appear | Ensure `NO_COLOR` is unset or empty and use an ANSI-capable terminal. |
| A command runs too long | Set `COMMAND_TIMEOUT_SECONDS` or `PANEL_TIMEOUT_SECONDS[i]` for snapshot commands. The panel shows `TIMEOUT after Ns` and retries after `REFRESH_INTERVAL`; stream commands intentionally remain long-running. |

## 8. Testing and compatibility

LHC remains compatible with Bash 3.2 and does not depend on associative arrays or `wait -n`. After changing the script or configuration, run:

```bash
bash -n bin/lhc tests/fixtures/ssh tests/test_v4_ssh.sh tests/test_v5_shutdown.sh tests/test_v6_ssh_lifecycle.sh tests/test_v7_scheduler_timeout.sh tests/test_v8_dirty_snapshot.sh tests/test_v9_ssh_starting_recovery.sh tests/test_v10_output_sanitization.sh
./tests/test_v4_ssh.sh
bash tests/test_v5_stream.sh
bash tests/test_v5_shutdown.sh
bash tests/test_v6_ssh_lifecycle.sh
bash tests/test_v7_scheduler_timeout.sh
bash tests/test_v8_dirty_snapshot.sh
bash tests/test_v9_ssh_starting_recovery.sh
bash tests/test_v10_output_sanitization.sh
bash tests/test_v11_stream_event_loop.sh
LHC_BENCHMARK_COUNT=50 bash tests/benchmark_stream_event_loop.sh
```

The test uses fake SSH. It does not prove that production hosts, credentials, host keys, or remote commands work; verify those with real SSH targets before deployment.
