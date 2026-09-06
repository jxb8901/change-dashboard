# LHC 使用手冊（繁體中文）

LHC（Local Change Dashboard）是一個以 Bash 編寫的終端機儀表板，用來週期性執行本機或 SSH 檢查命令，並以 raw、表格或字段/值 transpose 方式顯示結果。本文以目前 `bin/lhc` 的實際行為為準。

## 1. 快速開始

需要 Bash（支援 Bash 3.2）及可用的互動式終端機；使用 SSH 面板時亦需要本機可用的 OpenSSH `ssh` client。配置檔是 Bash source file，會被 LHC 直接 `source`，所以只應執行可信任的配置檔。

```bash
# 使用預設配置：example/sample.conf
./bin/lhc

# 使用指定配置
./bin/lhc example/v3-ux.conf

# 查看命令說明（`-h`、`--help` 或 `--usage`）
./bin/lhc --help

# 關閉警告/錯誤的 ANSI 顏色
NO_COLOR=1 ./bin/lhc example/fpp.conf
```

在儀表板中按 `q` 離開；按 `Ctrl+C` 也會離開。正常離開、`q`、中斷或執行失敗時，LHC 會停止仍在執行的子命令、清理暫存檔、恢復游標及終端機顏色。

不指定檔案時，預設使用 `example/sample.conf`（相對於腳本所在的專案根目錄）。

`-h`、`--help` 及 `--usage` 是等效選項；每個選項都會顯示使用方法並退出，不會啟動儀表板。沒有指定選項或配置檔路徑時，LHC 會使用預設配置並啟動儀表板。

## 2. 執行模型

每次啟動或刷新時，流程如下：

1. 讀取並驗證 Bash 配置。
2. 先畫出所有面板及 `Loading...` 狀態。
3. 啟動每個已到期 panel 的本機命令或 SSH jobs。
4. snapshot panel 在所有 jobs 完成後立即解析並重畫；stream panel
   在命令仍然運行時，每收到新的完整輸出行便重畫。stream collector
   每次更新快照後會通知主終端機循環，因此不需要等待原本的一秒排程
   timeout。
5. 該 panel 的命令結束後等待 `REFRESH_INTERVAL` 秒再執行下一輪；其他
   panel 使用獨立計時器，不會被它阻塞。

SSH job 會並行執行，但同一面板的結果按 `PANEL_SSH_ALIASES` 配置順序聚合，而不是按完成先後排序。LHC 使用局部 frame diff 更新改變的內容；調整終端機大小後會強制完整重畫。

## 3. 最小本機配置

每個面板都使用同一個 zero-based index。下例是一個 raw 面板：

```bash
REFRESH_INTERVAL=2

PANEL_TITLES[0]="Queue"
PANEL_COMMANDS[0]="printf 'queue=0\\noldest=0s\\n'"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=32
PANEL_HEIGHTS[0]=8
```

`PANEL_COMMANDS` 的 stdout 會顯示在面板內；非零 exit status 會顯示 `Command failed`。本機命令由 `bash -c` 執行，stderr 只會被捕獲作為執行資料，不會直接印入全屏儀表板。

座標以終端機左上角為 `(1,1)`；寬度及高度包含邊框。每個面板的最小值是寬 `4`、高 `3`。配置的最右欄及最底行再加上底部 footer，必須容納在終端機內；LHC 不會自動防止面板互相重疊。

最後一個 panel 可以省略 `PANEL_HEIGHTS[i]`；LHC 會由 `PANEL_Y[i]` 計算至 footer 上一列的最大可用高度。其他 panel 必須定義 height；終端機 resize 時會重新計算自動高度。

`PANEL_X`、`PANEL_Y`、`PANEL_WIDTHS` 及 `PANEL_HEIGHTS` 亦接受例如 `50%` 的百分比。X 及 width 百分比按終端機欄數計算；Y 及 height 百分比按扣除 footer 的可用行數計算。位置使用 `0%` 代表最左或最上邊界。百分比會向下取整，並在每次 resize 後根據原始配置重新計算。單一 panel 內可以混用整數及百分比；換算後仍須符合原有最小尺寸及邊界檢查。

## 4. 配置參考

### 4.1 全域設定

| 變數 | 必需 | 說明 |
| --- | --- | --- |
| `REFRESH_INTERVAL` | 否 | 正整數秒數；預設 `2`。每個 panel 在自己的命令完成後等待這段時間再刷新。 |
| `NO_COLOR` | 環境變數 | 任何非空值都會關閉 warning/error 的 ANSI 顏色。 |

`TMPDIR` 不是面板配置欄位；若已設定，LHC 會在其下建立短暫的命令輸出目錄，離開時清理。未設定時使用 `/tmp`。

### 4.2 每個面板的必需欄位

同一 index 必須同時設定以下六個欄位；缺少欄位、空標題/命令或無效的整數/百分比幾何值會令啟動驗證失敗。

| 變數 | 例子 | 說明 |
| --- | --- | --- |
| `PANEL_TITLES[i]` | `"Queue"` | 面板標題，不能為空。 |
| `PANEL_COMMANDS[i]` | `"check_queue.sh"` | 要執行的 Bash 命令，不能為空。 |
| `PANEL_X[i]` | `1` 或 `"0%"` | 左邊界；整數是一-based 欄位，百分比按終端機寬度計算。 |
| `PANEL_Y[i]` | `1` 或 `"0%"` | 上邊界；整數是一-based 行數，百分比按可用終端機高度計算。 |
| `PANEL_WIDTHS[i]` | `40` 或 `"50%"` | 面板總寬，包括左右邊框；換算後最小 `4`。 |
| `PANEL_HEIGHTS[i]` | `8` 或 `"50%"` | 面板總高，包括上下邊框；換算後最小 `3`。 |

面板 index 必須是非負整數。額外設定的 index（例如有 `PANEL_COMMANDS[4]` 卻沒有 `PANEL_TITLES[4]`）會被拒絕。

例如以下配置會把終端機左右分成兩個 panel，並在 resize 後自動適應：

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

footer 行仍會保留。百分比換算後低於最小尺寸或超出終端機時，啟動驗證會失敗；運行中 resize 至不合適大小時，dashboard 會暫停，直至終端機足夠大。

### 4.2.1 可選的 stream 設定

| 變數 | 例子 | 說明 |
| --- | --- | --- |
| `PANEL_STREAM[i]` | `1` | 啟用 panel `i` 的持續 raw 或 `table` 輸出；有效值是 `0` 或 `1`，預設是 snapshot 模式。滾動 buffer 按 panel 有效高度計算。 |

### 4.3 Raw 面板

不設定 `PANEL_TABLE_COLUMNS[i]` 就是 raw 面板。命令 stdout 按原本的行顯示；空 stdout 顯示 `No data`。內容不會換行，超過面板寬度的文字會被截斷，超過可見高度的行會被裁掉。Raw panel 可使用保留字段 `MESSAGE` 的 `~` 或 `!~` rule；使用 `~` 時只高亮每一個命中的 keyword，其餘 message 保持普通樣式。

設定 `PANEL_STREAM[i]=1` 可把 raw panel 變成持續輸出模式。LHC 會在命令
仍然運行時讀取完整 newline 行，並只保留最近
`PANEL_EFFECTIVE_HEIGHTS[i] - 2` 行，因此不需要另外設定 stream 行數。
本設定同時適用於本機及 raw SSH panel。Table stream 的規則見下文；
transpose stream panel 仍不支援。命令退出後保留最後 buffer，並在
`REFRESH_INTERVAL` 秒後重啟。
如果輸出程序本身有 stdout buffering，可能需要使用 `stdbuf -oL` 等
line-buffering 設定。

```bash
PANEL_TITLES[0]="Deployment"
PANEL_COMMANDS[0]="printf 'release=2026.08\\nowner=change-team\\n'"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=40
PANEL_HEIGHTS[0]=7
```

持續 raw panel 例子：

```bash
PANEL_TITLES[0]="Application log"
PANEL_COMMANDS[0]="tail -f /var/log/app.log"
PANEL_STREAM[0]=1
PANEL_X[0]=1; PANEL_Y[0]=1; PANEL_WIDTHS[0]=60; PANEL_HEIGHTS[0]=12
```

### 4.4 表格面板

設定 `PANEL_TABLE_COLUMNS[i]` 後，LHC 會按空白分隔 stdout。其空白分隔的 token 是實際來源數據字段名稱，不是固定的 `key`、`value` 字樣；每個非空行必須剛好包含相同數目的欄位。

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

規則如下：

- 欄名以空白分隔，必須非空、互不重複，且不能包含 `:`。
- 空行會跳過；欄位值本身不能包含空白。若輸出行的欄位數不符，整個面板回退為 raw，且不套用 threshold 顏色。
- `PANEL_TABLE_LAYOUT[i]` 可省略（預設 `table`），或設為 `table` / `transpose`。
- `PANEL_TABLE_WIDTHS[i]` 在 `table` layout 可省略最右欄的 width；該欄會取得扣除其他寬度及間隔後的全部剩餘寬度。整個設定省略時則按可用寬度平均分配。
- 表格欄位之間固定有一個字元間距。指定寬度的總和加間距不能超過面板內寬，即 `PANEL_WIDTHS[i] - 2`。
- 數字靠右，文字及標題靠左。數字格式是可選負號、整數或小數，例如 `-2`、`0`、`12.50`。

`table` panel 也可以設定 `PANEL_STREAM[i]=1`。每個完整 newline 行會被
追加為一筆新 row，只保留 header 以下可容納的最新 rows，因此不需要另設
stream row 數量。現有 table parser、width 及 cell rules 會在每次更新時套用。
如果可見 buffer 中有欄位數不符的 row，panel 會暫時回退為 raw；該 row
滾出 buffer 後會恢復 table。SSH table stream 要把 alias prefix 納入來源
欄位，例如 `SERVER`；alias 仍按配置順序排列，SSH failure 使用現有
synthetic failure row。

```bash
PANEL_TITLES[0]="Live Services"
PANEL_COMMANDS[0]="tail -f /tmp/services.tsv"
PANEL_STREAM[0]=1
PANEL_TABLE_COLUMNS[0]="SERVICE COUNT STATUS"
PANEL_TABLE_LAYOUT[0]="table"
PANEL_X[0]=1
PANEL_Y[0]=1
PANEL_WIDTHS[0]=48
PANEL_HEIGHTS[0]=8
```

Raw panel 若設定 `PANEL_WARN_RULES`、`PANEL_ERROR_RULES` 或 `PANEL_INFO_RULES`，rule 必須使用 `MESSAGE:~keyword` 或 `MESSAGE:!~keyword`。Table/transpose rule 仍必須先有 `PANEL_TABLE_COLUMNS`；layout 必須是 `table` 或 `transpose`，width 必須符合該 layout，但可只省略最右字段的 width。

### 4.5 Transpose layout

Transpose 把每個資料 row 直向顯示為一個「字段名稱 / 字段值」block。`PANEL_TABLE_COLUMNS[i]` 必須按來源字段順序填寫實際數據字段名稱。`PANEL_TABLE_WIDTHS[i]` 是字段名稱及字段值的顯示寬度；最右的字段值 width 可以省略，由 LHC 取得全部剩餘內容寬度。

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

本機及 SSH transpose 都可處理零個或多個資料 row。以上例子會顯示 `STATE READY`、`COUNT 2`、`COLOR BLUE`，再顯示 `STATE DEGRADED`、`COUNT 5`、`COLOR RED`。Transpose 不會增加獨立的表格列頭；配置的字段名稱只會在每個資料 block 內作為標籤重複顯示。任何 row 的欄位數不符時，LHC 會回退為 raw。SSH 面板會先在每個 row 前加上 server alias，因此 SSH block 會以 `SERVER <alias>` 開始，之後才是配置的數據字段。

### 4.6 Warning / error 規則

規則 token 格式是 `來源字段:條件`，同一設定以空白分隔。`field:~keyword` 匹配包含 keyword 的字段；`field:!~keyword` 匹配不包含 keyword 的字段。`PANEL_INFO_RULES` 使用相同語法，命中的 cell 或 raw keyword 會以綠色顯示。`table` 及 `transpose` 都必須引用 `PANEL_TABLE_COLUMNS[i]` 中的實際字段名稱；`字段名稱` 和 `字段值` 只是顯示概念，不是 rules 名稱：

```bash
PANEL_WARN_RULES[0]="DEPTH:>20 LATENCY:>=200 STATUS:!=OK"
PANEL_ERROR_RULES[0]="DEPTH:>50 STATUS:==DOWN"
PANEL_INFO_RULES[0]="STATUS:==READY"
```

支援運算子：`>`、`>=`、`<`、`<=`、`==`、`!=`、`~`、`!~`。優先順序是 `ERROR > WARN > INFO > OK`。

- `>`、`>=`、`<`、`<=` 只有在值及門檻都是數字時才會匹配。
- `==` / `!=` 對兩個數字作數值比較；其他值作字串比較。
- 字段名稱必須完全匹配，且必須存在於 `PANEL_TABLE_COLUMNS`。
- error 優先於 warning；面板狀態取所有 cell 中最嚴重者：`ERROR > WARN > OK`。
- 匹配的 cell 以 warning 黃底或 error 紅底顯示；設置 `NO_COLOR` 後保留判定但不顯示顏色。

### 4.7 SSH 多伺服器面板

先在全域 registry 宣告目標，再在面板引用 alias：

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

Registry record 必須是 `alias|target`：

- alias 只可包含英文字母、數字、`.`、`_`、`-`，不可重複、不可含空白，且不能以 `-` 開頭。
- target 不可為空、不可含空白或 `|`，亦不能以 `-` 開頭。複雜的 port、identity、ProxyJump 等設定應放在 `~/.ssh/config`，再以 SSH config alias 作為 target。
- `PANEL_SSH_ALIASES[i]` 是空白分隔且不可重複的 registry alias。面板未設定此欄位時，命令在本機執行。
- SSH 使用 `ssh -T`、`BatchMode=yes`、`ConnectTimeout=10`、`StrictHostKeyChecking=yes`，並以 `bash -s` 在遠端執行 `PANEL_COMMANDS[i]`。
- 同一次 LHC 執行期間，相同 SSH target 會透過 `ControlMaster`/`ControlPersist` 重用一條底層 OpenSSH 連線；每個命令仍使用獨立的 session/channel。LHC 結束時會關閉連線，下一次啟動不會重用。
- `ConnectTimeout=10` 只限制建立 SSH 連線的時間；成功連線後的遠端命令沒有額外 timeout。請預先準備 key/agent 及 `known_hosts`，否則不會互動式要求密碼或確認 host key。

SSH 面板的第一個配置欄位是名為 `SERVER` 的合成伺服器識別字段，不由遠端命令輸出；遠端命令只應為其餘配置的數據字段各輸出一個值。例如上述設定中，每行應輸出三個欄位：

```text
FPP 2 OK
API 0 OK
```

LHC 會加上 alias，成為：

```text
APP01 FPP 2 OK
APP01 API 0 OK
APP02 FPP 1 OK
```

SSH raw 面板則在每一個實體行前加 alias。各種特殊結果如下：

| 情況 | table 面板 | raw 面板 |
| --- | --- | --- |
| 成功但無 stdout | `ALIAS No_data - ...` | `ALIAS No data` |
| SSH 或命令失敗 | `ALIAS SSH_FAILED - ...`，該 row 全部 ERROR | `ALIAS SSH_FAILED (exit N)`，面板顯示 failed |
| 另一台成功 | 保留成功 rows | 保留成功輸出 |

SSH 失敗的 stderr 不會直接顯示在全屏畫面，只顯示 alias 及 exit status。table 的遠端輸出若欄位數不符，整個聚合結果回退為帶 alias 的 raw 輸出。

## 5. 顯示及刷新行為

- 初始畫面先顯示邊框、標題及 `Loading...`；完成的面板會逐一替換內容。
- 面板標題置中顯示；標題過長時會按面板可用寬度截斷。
- raw 面板顯示文字；table 顯示標題列及資料列；transpose 顯示字段名稱/字段值 block，且不增加獨立表格列頭。
- stream raw 及 table panel 會在命令仍然運行時以事件驅動方式更新，只保留最近的可見內容高度行數；命令退出後按 `REFRESH_INTERVAL` 秒重啟。
- 空結果顯示 `No data`。資料按面板高度裁剪，不會自動滾動。
- cell 寬度是固定的。超寬數字全部顯示為 `#`；超寬文字在最後保留 `.`，例如寬度 8 的文字可能顯示 `abcdefg.`。
- warning cell 是黑字黃底；error cell 及失敗面板內容是白字紅底。`NO_COLOR` 只關閉 ANSI 顏色。
- footer 顯示 `Refresh: Ns | Press q to exit.`；這個數值是命令重啟間隔，不是 stream 的即時重畫間隔。
- 若終端機被縮小至不足以容納配置，畫面會暫停並顯示所需尺寸；恢復尺寸後會繼續並完整重畫。暫停期間按 `q` 仍可離開。

## 6. 完整的簡單配置

下面的配置同時示範 raw、table、transpose 及 SSH。SSH target 是佔位值，使用前必須替換並先驗證 SSH 登入。

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

# Local transpose panel（可有多個來源 row）
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
PANEL_WARN_RULES[3]="DEPTH:>20"
PANEL_ERROR_RULES[3]="DEPTH:>50 STATUS:==DOWN"
```

## 7. 問題排查

| 訊息/現象 | 處理方式 |
| --- | --- |
| `config file not found` | 確認路徑；使用 `./bin/lhc path/to/config`。 |
| `at least one panel must be configured` | 至少設定一組 `PANEL_TITLES[i]` 及全部必需面板欄位。 |
| `terminal too small` | 擴大終端機，或調低 `PANEL_X/Y/WIDTHS/HEIGHTS`；運行中縮小會暫停。 |
| 表格變成 raw 顯示 | 檢查每個非空 stdout 行的欄位數、空白分隔及 table/transpose 規則。 |
| 出現 `Command failed` | 直接在 shell 測試命令、權限、PATH 及 exit status；LHC 不把 stderr 放進畫面。 |
| SSH row 是 `SSH_FAILED` | 檢查 registry alias、`~/.ssh/config`、key/agent、`known_hosts` 及目標主機；必須接受 strict host-key policy。 |
| 沒有顏色 | 確認沒有設定非空 `NO_COLOR`，並使用支援 ANSI 的終端機。 |
| 遠端命令執行太久 | LHC 只有 10 秒 SSH 連線建立 timeout，沒有成功連線後的命令 timeout；應在遠端檢查命令本身設定 timeout。 |

## 8. 測試及相容性

LHC 保持 Bash 3.2 相容性，不依賴 associative arrays 或 `wait -n`。修改腳本或配置後可執行：

```bash
bash -n bin/lhc tests/fixtures/ssh tests/test_v4_ssh.sh
./tests/test_v4_ssh.sh
```

測試使用 fake SSH，不代表實際部署主機、憑證、host key 或遠端命令已驗證；正式使用前仍須以實際 SSH 目標測試。
