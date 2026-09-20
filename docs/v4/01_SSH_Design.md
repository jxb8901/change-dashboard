# V4 SSH Multi-Server Execution Design

## 1. Summary

LHC will support running a panel command on zero or more SSH servers.

- A panel without SSH aliases keeps the existing local execution behavior.
- A panel with SSH aliases runs the same command on every referenced server.
- Servers within one panel run concurrently.
- LHC waits for every server assigned to the panel before displaying that
  panel's aggregated result.
- Aggregated rows follow the alias order in the panel configuration, regardless
  of the order in which the SSH commands finish.
- Every result includes the server alias in its first column.
- Other panels retain the existing concurrent and progressive rendering
  behavior.
- During one LHC process, the same SSH target reuses one explicit OpenSSH
  polling master; each polling command still uses an independent SSH
  session/channel. Continuous stream commands use dedicated non-multiplexed
  connections and never consume the polling master's session capacity.
- The implementation must remain compatible with Bash 3.2 and must not depend
  on associative arrays or `wait -n`.

## 2. Configuration

### 2.1 Global SSH Server Registry

SSH servers are declared once near the top of the Bash configuration file.
Each entry uses the following record format:

```text
alias|ssh-target
```

Example:

```bash
SSH_SERVERS[0]="APP01|ops@app01"
SSH_SERVERS[1]="APP02|ops@app02"
SSH_SERVERS[2]="DB01|production-db"
```

- `alias` is both the stable name referenced by panels and the value displayed
  in the first output column.
- `ssh-target` is an OpenSSH destination such as `user@host` or an alias from
  `~/.ssh/config`.
- Port, identity file, proxy jump, and other server-specific connection
  settings should be configured in `~/.ssh/config`.

### 2.2 Per-Panel SSH Configuration

A panel enables remote execution by listing one or more global aliases:

```bash
PANEL_COMMANDS[0]="/opt/checks/check_queue.sh"
PANEL_SSH_ALIASES[0]="APP01 APP02"
```

The alias order determines the final result order. A panel with no
`PANEL_SSH_ALIASES[index]` entry continues to run `PANEL_COMMANDS[index]`
locally.

### 2.3 Table Column Configuration

For an SSH table panel, the first configured table field is the synthetic SSH
server-identity field. It is normally named `SERVER`; it is not emitted by the
remote command. The remaining configured fields are the actual remote data
fields. No SSH-specific display-column or display-width setting is used.

```bash
PANEL_TABLE_COLUMNS[0]="SERVER APP EAIQ ICLQ"
PANEL_TABLE_WIDTHS[0]="8 4 5 4"
```

- The first `PANEL_TABLE_COLUMNS[index]` token supplies the displayed server
  identity label, normally `SERVER`.
- The remote command emits values only for the remaining configured data
  fields; LHC prepends the alias to each logical row.
- If `PANEL_TABLE_WIDTHS[index]` is configured for normal table layout, its
  first width is the server-column width and its remaining widths map to the
  command-output columns.
- Automatic equal-width calculation includes the server column like every
  other configured table column.
- The full column and gap total must fit inside the panel content width.

### 2.4 Transpose Configuration

Transpose layout uses the same multi-row rendering for local and SSH panels.
For an SSH panel, configure it as follows:

```bash
PANEL_TABLE_COLUMNS[1]="SERVER APP EAIQ ICLQ"
PANEL_TABLE_LAYOUT[1]="transpose"
PANEL_TABLE_WIDTHS[1]="8 10"
PANEL_SSH_ALIASES[1]="APP01 APP02"
```

Transpose widths describe the rendered field-name and field-value cells, not the
number or names of source fields. `PANEL_TABLE_COLUMNS[index]` still contains
the actual source-field names in source order. For SSH, the first configured
name is the synthetic server-identity label and every non-empty remote output
row must contain values for every configured data field after that first label.

For SSH, LHC prepends the alias to every output row, then renders each
resulting logical row as one consecutive field-name/value block. The `SERVER <alias>`
row is first in every block. Blocks follow panel alias order and remote output
order, with no blank separator row or separate table-header row. Local rows use
the same renderer without the server-alias prefix; their configured field names
are all actual source-field names.

### 2.5 Validation Rules

Configuration loading must reject:

- malformed `SSH_SERVERS` records;
- empty or duplicate aliases;
- aliases or targets containing whitespace or `|`;
- aliases containing characters other than letters, numbers, dot, underscore,
  and dash;
- a panel referencing an unknown or duplicate alias;
- an SSH table with fewer than two configured source columns;
- a total configured table width that does not fit the panel.

Remote row field counts are checked at runtime. A mismatch uses the existing
raw-output fallback described below rather than failing configuration loading.

Unused, valid global SSH server entries are allowed.

## 3. Execution Model

### 3.1 Job Scheduling

The command scheduler uses flat jobs with independent panel timers:

- a local panel creates one local job;
- an SSH panel creates one job for every configured alias; and
- every job tracks its panel index, alias, PID, stdout file, status file, and
  collection state.

Each panel starts when its own timer is due. This preserves panel-level
concurrency while also allowing the servers within a panel to run in parallel.
Using flat jobs also allows the main process to track and clean up every SSH
process directly. A slow panel remains active until its jobs finish, but does
not prevent another panel whose timer is due from starting or rendering.

A local panel is ready when its single job finishes. An SSH panel is ready only
when every job belonging to that panel has finished. The dashboard renders the
panel once at that point, starts its next timer, and does not expose partially
aggregated server data.

### 3.2 SSH Invocation

The remote job executes the configured `PANEL_COMMANDS[index]` string using
Bash on the destination host. The command is quoted as data before being passed
to the remote Bash process so local shell expansion cannot alter it.

Before a polling command starts, LHC checks the target's control socket with
`ssh -O check`. If no ready master exists, it creates one explicitly and waits
for it to become ready. The master uses non-interactive settings equivalent to:

```text
BatchMode=yes
ConnectTimeout=10
StrictHostKeyChecking=yes
ControlMaster=yes
ControlPersist=30
ControlPath=<process-temporary-directory>/control.<target-index>
```

Polling channels use the same target-specific path with
`ControlMaster=no` and `ControlPersist=no`. The control path is allocated once
for each distinct `ssh-target` and is reused by all polling panels and
refreshes in the same LHC process. Different target strings use different
control paths, even if they may ultimately resolve to the same host.

Stream commands use a separate connection with `ControlMaster=no`,
`ControlPersist=no`, and `ControlPath=none`. If a polling command reports a
transport failure and the readiness check confirms that its master is dead,
LHC recreates the master and retries that command once. A healthy master does
not cause a failed remote command to be retried.

The temporary control sockets and master connections are closed when LHC exits;
they are not shared across LHC launches. The bounded persistence value is
configurable through `SSH_CONTROL_PERSIST_SECONDS` from 1 to 3600 seconds;
the default is 30 seconds. `SSH_CONNECT_TIMEOUT_SECONDS` is configurable from
1 to 300 seconds and defaults to 10.

The dashboard therefore never prompts for a password, key passphrase, or host
key confirmation. Authentication, SSH agent access, and `known_hosts` entries
must be prepared before LHC starts.

The connection-timeout value limits connection establishment only. LHC does
not add a runtime limit for a successfully started remote command.

### 3.3 Cleanup

Normal exit, `q`, Ctrl+C, and startup/runtime failure must:

- terminate every still-running local or SSH job;
- wait for terminated child processes;
- remove all stdout and completion-marker files;
- remove the command temporary directory; and
- send `ssh -O exit` for every known control socket so persistent SSH masters
  do not remain after LHC exits; and
- restore the cursor and terminal attributes as before.

No SSH child process or temporary result file may remain after LHC exits.

## 4. Result Aggregation and Rendering

### 4.1 Table Panels

For successful remote output, LHC prepends the server alias to every parsed
row. The first configured table field is the synthetic server-identity field,
so LHC does not add a separate table-header row.

Example command output from both servers:

```text
FPP 2 10
API 0 4
```

Aggregated table input:

```text
APP01 FPP 2 10
APP01 API 0 4
APP02 FPP 2 10
APP02 API 0 4
```

Warning and error rules continue to reference the actual names in
`PANEL_TABLE_COLUMNS` normally. In an SSH panel, a rule may target the synthetic
`SERVER` identity field, but remote data rules should use the configured names
after `SERVER`.

If a successful server returns no data, LHC adds an informational row in the
shape:

```text
APP01 No_data - ...
```

The row is padded with `-` values to match the configured command-output column
count and retains `OK` severity.

If a server fails, LHC adds an error row in the shape:

```text
APP02 SSH_FAILED - ...
```

The row is padded to the configured field count. Every cell in that synthetic
row is marked `ERROR`, and the panel status becomes `ERROR`. Successful rows
from other servers remain visible.

If any successful output row has the wrong field count, the combined panel
uses the existing raw-output fallback rather than silently discarding data.

### 4.2 Transpose Panels

Transpose operates on every logical row for both local and SSH panels without
treating one-row and multi-row output differently. For example, with an SSH
panel:

```bash
PANEL_TABLE_COLUMNS[0]="SERVER APP EAIQ ICLQ"
PANEL_TABLE_LAYOUT[0]="transpose"
```

APP01 returning `FPP 2 10` and `API 0 4`, and APP02 returning `FPP 2 10`, LHC
renders:

```text
SERVER  APP01
APP     FPP
EAIQ    2
ICLQ    10
SERVER  APP01
APP     API
EAIQ    0
ICLQ    4
SERVER  APP02
APP     FPP
EAIQ    2
ICLQ    10
```

The server-identity row starts every block; it is not a separate table header.
Blocks are rendered consecutively in alias and source-row order without a blank
separator. Empty and failed servers
use the same synthetic logical rows as normal table mode, so their transposed
block remains identifiable by alias. A row with the wrong field count makes the
whole panel use prefixed raw-output fallback.

### 4.3 Raw Panels

Raw output receives the server alias at the start of every physical line:

```text
APP01 queue=0
APP01 oldest_age=0s
APP02 queue=2
APP02 oldest_age=15s
```

A successful empty result displays:

```text
APP01 No data
```

A failed server displays:

```text
APP02 SSH_FAILED (exit 255)
```

Any failed server marks the raw panel as failed while preserving successful
output from the other servers.

### 4.4 Error Output

Remote stderr is captured for process management and testing but is not printed
inside the dashboard. This avoids corrupting the full-screen display and
reduces the risk of exposing sensitive diagnostic content. The displayed error
contains only the server alias and SSH/command exit status.

## 5. Compatibility

- Existing configuration files require no changes.
- Local-only panels preserve their current command, output parsing, threshold,
  refresh, loading, and failure behavior.
- Panel completion remains progressive: a completed local or SSH panel may be
  rendered while unrelated panels are still loading.
- Cell overflow and table alignment continue to use the existing rendering
  policies.
- The implementation must work with the Bash version shipped with older macOS
  systems and with Bash 3.2 on supported deployment hosts.

## 6. Test and Acceptance Plan

### 6.1 Configuration Validation

- Accept a valid global registry referenced by multiple panels.
- Accept unused global entries.
- Reject malformed records, duplicates, invalid tokens, and unknown aliases.
- Reject duplicate aliases within a panel.
- Reject an SSH table without both a server column and at least one
  command-output column.
- Reject normal and transpose layouts whose configured widths do not fit the
  panel.

### 6.2 Scheduler and SSH Tests

Use a fake `ssh` executable earlier in `PATH` so tests require no real server.
Verify that:

- the expected SSH options and destination are passed;
- special characters in the panel command reach remote Bash unchanged;
- all servers in a panel start concurrently;
- results are ordered by panel alias configuration rather than completion time;
- a panel is rendered only after all of its server jobs complete;
- unrelated panels continue to update progressively; and
- cleanup terminates every fake SSH process and removes temporary files.

### 6.3 Aggregation Tests

- Table mode with one server, multiple servers, and multiple rows per server.
- Transpose mode locally and with one or multiple SSH servers.
- Verify each transpose block begins with `SERVER <alias>` and follows alias
  and source-row order without separator rows.
- Verify one-row and multi-row local and remote results use the same transpose
  path.
- Raw mode with one server, multiple servers, and multiline output.
- Successful empty output in both modes.
- One failed server mixed with successful servers.
- All servers failing with different exit codes.
- Malformed table output falling back to prefixed raw output.
- Threshold evaluation remaining mapped to original columns.
- Synthetic failure rows overriding threshold state and marking the panel red.
- The first configured table column and width mapping to the server alias.

### 6.4 Regression Tests

- Run `bash -n bin/lhc`.
- Run the existing V1, V2, V3, and FPP configurations.
- Verify loading placeholders and per-panel progressive updates.
- Verify fixed-width formatting, overflow markers, and raw fallback.
- Verify terminal resize pause and recovery.
- Verify both `q` and Ctrl+C restore the terminal.
- Run the established macOS PTY test pattern with a fixed terminal size.

## 7. Review Decisions Captured

- SSH servers are configured globally; panels reference aliases only.
- Registry records use `alias|target`, and alias is also the displayed server
  key.
- Remote commands refer to commands or scripts already present on the server;
  local scripts are not streamed to the destination.
- Servers within one panel execute concurrently and aggregate in configured
  order.
- Table and raw panels both receive alias prefixes.
- An SSH table's first normal `PANEL_TABLE_COLUMNS` field is the server field;
  there are no `PANEL_SSH_DISPLAY_COLUMN` or `PANEL_SSH_DISPLAY_WIDTH`
  settings.
- Local and SSH transpose render one field-name/value block per source row,
  without special handling or limits based on the row count.
- Successful results remain visible when one server fails.
- SSH is non-interactive with a 10-second connection timeout.
- Command runtime timeout is outside this change.
