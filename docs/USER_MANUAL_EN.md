# LHC User Manual

LHC (Local Change Dashboard) is a Bash terminal dashboard for running local or SSH checks on a schedule and displaying their results as raw output, a table, or a transposed key/value view. This manual describes the current behavior of `bin/lhc`.

## 1. Quick start

LHC requires Bash (including Bash 3.2) and an interactive terminal; SSH panels also require a working local OpenSSH `ssh` client. A configuration file is a Bash source file and LHC sources it directly, so only use trusted configuration files.

```bash
# Use the default configuration: example/sample.conf
./bin/lhc

# Use a specific configuration
./bin/lhc example/v3-ux.conf

# Show command help (`-h` or `--help`)
./bin/lhc --help

# Disable ANSI warning/error colors
NO_COLOR=1 ./bin/lhc example/fpp.conf
```

Press `q` to exit the dashboard. `Ctrl+C` also exits. On normal exit, `q`, an interrupt, or a runtime failure, LHC stops running child commands, removes temporary files, and restores the cursor and terminal attributes.

When no file is supplied, LHC uses `example/sample.conf` relative to the project root containing the script.

## 2. Execution model

Each startup or refresh cycle works as follows:

1. Load and validate the Bash configuration.
2. Draw all panel borders and `Loading...` placeholders.
3. Start all local commands concurrently; an SSH panel starts one SSH job per target.
4. As soon as all jobs for one panel finish, parse and redraw that panel while other panels may still be loading.
5. After all panels finish, wait `REFRESH_INTERVAL` seconds and start the next cycle.

SSH jobs run concurrently, but results within one panel are aggregated in the order of `PANEL_SSH_ALIASES`, not completion order. LHC updates only changed frame cells; a terminal resize forces a complete redraw.

## 3. Minimal local configuration

Every panel uses the same zero-based index. The following is a raw-output panel:

```bash
REFRESH_INTERVAL=2

PANEL_TITLES[0]="Queue"
PANEL_COMMANDS[0]="printf 'queue=0\\noldest=0s\\n'"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=32
PANEL_HEIGHTS[0]=8
```

The command's stdout is displayed in the panel. A non-zero exit status displays `Command failed`. Local commands run through `bash -c`; stderr is captured for process handling and is not printed directly into the full-screen dashboard.

Coordinates are one-based, with `(1,1)` at the upper-left terminal cell. Width and height include the panel border. The minimum panel width is `4` and the minimum height is `3`. The terminal must contain the configured rightmost column and bottom row plus the footer; LHC does not automatically prevent panels from overlapping.

## 4. Configuration reference

### 4.1 Global settings

| Variable | Required | Description |
| --- | --- | --- |
| `REFRESH_INTERVAL` | No | Positive integer seconds; default `2`. The delay starts after all commands in a cycle finish. |
| `NO_COLOR` | Environment | Any non-empty value disables ANSI warning/error colors. |

`TMPDIR` is not a panel setting. When set, LHC creates its temporary command-output directory below it and removes that directory on exit; otherwise it uses `/tmp`.

### 4.2 Required fields for every panel

All six fields below must be set at the same index. A missing field, empty title/command, or non-positive integer causes startup validation to fail.

| Variable | Example | Description |
| --- | --- | --- |
| `PANEL_TITLES[i]` | `"Queue"` | Panel title; must not be empty. |
| `PANEL_COMMANDS[i]` | `"check_queue.sh"` | Bash command to run; must not be empty. |
| `PANEL_X[i]` | `1` | Left edge, one-based column. |
| `PANEL_Y[i]` | `1` | Top edge, one-based row. |
| `PANEL_WIDTHS[i]` | `40` | Total panel width, including borders; minimum `4`. |
| `PANEL_HEIGHTS[i]` | `8` | Total panel height, including borders; minimum `3`. |

Panel indexes must be non-negative integers. An extra index (for example, `PANEL_COMMANDS[4]` without `PANEL_TITLES[4]`) is rejected.

### 4.3 Raw panels

A panel without `PANEL_TABLE_COLUMNS[i]` is a raw panel. Command stdout is displayed line by line; empty stdout displays `No data`. Lines do not wrap. Text wider than the panel is clipped, and lines beyond the visible height are not shown.

```bash
PANEL_TITLES[0]="Deployment"
PANEL_COMMANDS[0]="printf 'release=2026.08\\nowner=change-team\\n'"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=40
PANEL_HEIGHTS[0]=7
```

### 4.4 Table panels

Setting `PANEL_TABLE_COLUMNS[i]` enables whitespace-delimited table parsing. Every non-empty stdout line must contain exactly the configured number of fields.

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
- In `table` layout, `PANEL_TABLE_WIDTHS[i]` contains one positive width per source column. If omitted, widths are divided equally across the available content width.
- LHC inserts a fixed one-character gap between columns. Configured widths plus gaps must fit `PANEL_WIDTHS[i] - 2`.
- Numbers are right-aligned; headers and text are left-aligned. A number may have an optional minus sign, integer digits, and fractional digits, such as `-2`, `0`, or `12.50`.

If `PANEL_WARN_RULES`, `PANEL_ERROR_RULES`, `PANEL_TABLE_LAYOUT`, or `PANEL_TABLE_WIDTHS` is set, the same index must also define `PANEL_TABLE_COLUMNS`. The layout must be `table` or `transpose`, and width count and values must match that layout.

### 4.5 Transpose layout

Transpose displays each data row vertically as `column / value`. In this layout, `PANEL_TABLE_WIDTHS[i]` contains exactly two widths: the key width and the value width.

```bash
PANEL_TITLES[2]="Release Summary"
PANEL_COMMANDS[2]="printf 'release READY\\n'"
PANEL_X[2]=1
PANEL_Y[2]=10
PANEL_WIDTHS[2]=38
PANEL_HEIGHTS[2]=10
PANEL_TABLE_COLUMNS[2]="FIELD VALUE"
PANEL_TABLE_LAYOUT[2]="transpose"
PANEL_TABLE_WIDTHS[2]="14 18"
```

A local transpose command may produce at most one data row; multiple rows or a field-count mismatch fall back to raw output. SSH transpose is different: each server may return multiple rows, and every row is rendered as a consecutive key/value block.

### 4.6 Warning and error rules

Rule tokens use `column:condition` and are separated by whitespace:

```bash
PANEL_WARN_RULES[0]="DEPTH:>20 LATENCY:>=200 STATUS:!=OK"
PANEL_ERROR_RULES[0]="DEPTH:>50 STATUS:==DOWN"
```

Supported operators are `>`, `>=`, `<`, `<=`, `==`, and `!=`.

- `>`, `>=`, `<`, and `<=` match only when both the cell value and threshold are numeric.
- `==` and `!=` compare two numeric values numerically; other values are compared as strings.
- Column names must match exactly and must exist in `PANEL_TABLE_COLUMNS`.
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
- `ConnectTimeout=10` limits connection establishment only; there is no additional timeout after the remote command starts. Prepare keys/agent access and `known_hosts` first, because LHC will not prompt for a password or host-key confirmation.

For an SSH table panel, the first configured column is the alias column; the remote command should output the remaining columns. With the example above, each remote line should have three fields:

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
- Raw panels show text, table panels show a header and data rows, and transpose panels show key/value blocks.
- Empty results display `No data`. Content is clipped to panel height and does not scroll automatically.
- Cell widths are fixed. A numeric value that is too wide becomes all `#` characters; an overlong text value keeps a trailing `.` (for example, `abcdefg.` in an eight-character cell).
- Warning cells use black text on yellow; error cells and failed-panel content use white text on red. `NO_COLOR` only disables ANSI colors.
- The footer displays `Refresh: Ns | Press q to exit.`
- If the terminal becomes too small, execution pauses and shows the required size. It resumes and fully redraws after the terminal is enlarged. `q` still exits while paused.

## 6. Complete simple configuration

The following configuration demonstrates raw, table, transpose, and SSH panels. The SSH targets are placeholders; replace them and verify SSH access before use.

```bash
REFRESH_INTERVAL=2

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

# Local transpose panel (one source row)
PANEL_TITLES[2]="Summary"
PANEL_COMMANDS[2]="printf 'state READY\\n'"
PANEL_X[2]=1; PANEL_Y[2]=10; PANEL_WIDTHS[2]=36; PANEL_HEIGHTS[2]=10
PANEL_TABLE_COLUMNS[2]="FIELD VALUE"
PANEL_TABLE_LAYOUT[2]="transpose"
PANEL_TABLE_WIDTHS[2]="12 18"

# SSH table panel
SSH_SERVERS[0]="APP01|ops@app01"
SSH_SERVERS[1]="APP02|ops@app02"
PANEL_TITLES[3]="Remote Queue"
PANEL_COMMANDS[3]="/opt/checks/check_queue.sh"
PANEL_SSH_ALIASES[3]="APP01 APP02"
PANEL_X[3]=38; PANEL_Y[3]=10; PANEL_WIDTHS[3]=42; PANEL_HEIGHTS[3]=10
PANEL_TABLE_COLUMNS[3]="SERVER APP DEPTH STATUS"
PANEL_TABLE_WIDTHS[3]="8 8 8 12"
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
| A remote command runs too long | LHC has only a 10-second SSH connection timeout, not a post-connection command timeout; add a timeout to the remote check itself. |

## 8. Testing and compatibility

LHC remains compatible with Bash 3.2 and does not depend on associative arrays or `wait -n`. After changing the script or configuration, run:

```bash
bash -n bin/lhc tests/fixtures/ssh tests/test_v4_ssh.sh
./tests/test_v4_ssh.sh
```

The test uses fake SSH. It does not prove that production hosts, credentials, host keys, or remote commands work; verify those with real SSH targets before deployment.
