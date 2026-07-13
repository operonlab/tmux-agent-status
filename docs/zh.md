# tmux-agent-status（繁體中文說明）

> English: [README.md](../README.md)

一個小巧的 tmux 狀態列膠囊，一眼看出目前有幾個 AI 編碼助手（Claude Code、Codex、
Gemini、Aider 等）正在你的 pane 裡跑，以及哪一個正在等你。

**主要且經過實測的平台是 macOS。** 內容比對邏輯與平台無關，但只在 macOS 上實測過，
詳見[相容性](#相容性)。

## 這是什麼？

當你同時開好幾個 AI CLI —— 一個在啃重構、一個卡在「可以執行這個指令嗎？」的權限
詢問、一個只是停在空提示等你下一步 —— 光看一整牆 pane 很難分辨誰是誰。

這個外掛在狀態列加上一顆小膠囊，把它們分成三種狀態統計：

- **busy（忙碌）** —— 正在工作（燒 token 中）
- **blocked（受阻）** —— 卡在權限詢問或選單，正在*等你*處理
- **idle（閒置）** —— 停在空提示，等待下一個指示

當沒有任何 agent 在跑時，整顆膠囊會消失。它每次重繪只讀取一份快取並立即回傳，
因此永遠不會拖慢你的狀態列（見[如何保持不阻塞](#如何保持不阻塞)）。

## 快速開始

> 第一次用 tmux？`prefix` 指的是 tmux 的前導鍵，預設是 **Ctrl-b**。所以「按 `prefix`
> + `I`」代表先按 Ctrl-b、放開，再按 `I`。

把佔位符 `#{agent_status}` 放進你的 `status-left` 或 `status-right` 任意位置，然後
用下列兩種方式之一載入外掛。

### 方式 A —— 使用 [TPM](https://github.com/tmux-plugins/tpm)（推薦）

在 `~/.tmux.conf` 加入這兩行：

```tmux
set -g status-right ' #{agent_status} %H:%M '
set -g @plugin 'operonlab/tmux-agent-status'
```

接著重新載入設定：

```tmux
tmux source-file ~/.tmux.conf
```

再按 `prefix` + `I`（大寫 i），讓 TPM 下載並載入外掛。

### 方式 B —— 不使用 TPM（純 `run-shell`）

先 clone，再在 `~/.tmux.conf` 指向進入點腳本：

```tmux
set -g status-right ' #{agent_status} %H:%M '
run-shell '~/clones/tmux-agent-status/agent-status.tmux'
```

```sh
git clone https://github.com/operonlab/tmux-agent-status ~/clones/tmux-agent-status
tmux source-file ~/.tmux.conf
```

兩種方式的原理相同：進入點腳本會把你狀態列選項裡的 `#{agent_status}` 字面字串，
改寫成呼叫 `scripts/status.sh` —— 因此膠囊出現的位置由你決定。

## Demo

*Demo GIF coming soon.*

一個忙碌的 Claude pane、一個卡在權限詢問的 Codex pane、一個閒置的 Gemini pane，
用預設 Nerd Font 圖示大致會呈現成：

```
 2   1   1
```

意思是「2 忙碌、1 受阻、1 閒置」。若設 `@agent-status-icons ascii`，同樣狀態會顯示
成 `[B] 2  [W] 1  [I] 1`。

## 選項

在 `~/.tmux.conf` 中、於外掛載入**之前**設定。

| 選項 | 預設 | 說明 |
| --- | --- | --- |
| `@agent-status-provider` | `""`（空） | 回報計數的外部指令。空 = 掃描本機 pane。**見下方警告。** |
| `@agent-status-interval` | `5` | 快取視為過期、觸發背景刷新前的秒數。 |
| `@agent-status-icons` | `nerd` | `nerd` 用 Nerd Font 圖示（play／hand／pause）；`ascii` 用 `[B]`／`[W]`／`[I]`，供沒有 Nerd Font 的終端使用。 |
| `@agent-status-format` | `""`（空） | 進階自訂樣板，見[自訂格式](#自訂格式)。空 = 內建版面。 |

### `@agent-status-provider`（會執行你提供的指令）

> **警告：此選項會執行程式碼，僅在受信任的 `tmux.conf` 中設定。** 這個值會在每次
> 刷新時被當成 shell 指令執行，切勿貼上來路不明的 provider 指令。

預設情況下外掛會掃描本機 tmux pane（各家 CLI 的判定細節見
[docs/detection-matrix.md](detection-matrix.md)）。如果你已經有更權威的 agent 狀態
來源 —— 常駐 daemon、註冊表、跨機聚合器 —— 就把 provider 指向它。**一旦設了
provider 就以 provider 為準；只有當 provider 沒有輸出、逾時或失敗時，才會退回本機
掃描。**

provider 契約是 stdout 上一行 JSON：

```json
{"busy": 2, "wait": 1, "idle": 3}
```

- `busy`、`wait`、`idle` 是整數（缺少的鍵視為 `0`）。
- `wait` 是「受阻／需要人介入」那一桶。
- 當系統有 `timeout`／`gtimeout` 時，指令會被 3 秒逾時包住，因此掛住的 provider
  不會讓背景刷新堆積。

## 自訂格式

`@agent-status-format` 非空時，會取代內建版面。它是一個含下列代換的樣板：

| 代號 | 展開為 |
| --- | --- |
| `%B` / `%W` / `%I` | busy／blocked／idle 的**圖示**（會遵循 `@agent-status-icons`） |
| `%b` / `%w` / `%i` | busy／blocked／idle 的**計數** |

```tmux
set -g @agent-status-format 'A:%b B:%w Z:%i'
```

注意：與內建版面不同，自訂格式會原樣輸出，因此不會自動隱藏為零的狀態 —— 請自行
在樣板中處理。

## 解除安裝

執行 teardown 腳本（還原 `#{agent_status}` 佔位符並清除執行期快取），再移除那兩行
設定：

```sh
tmux run-shell '~/clones/tmux-agent-status/scripts/teardown.sh'
# 接著從 ~/.tmux.conf 移除 @plugin／run-shell 那行，以及 #{agent_status} 佔位符
```

## 疑難排解 / 常見問題

**膠囊一直不出現。**
沒有任何 AI CLI 在跑時，膠囊本來就是空的。啟動一個 agent、等一個刷新週期（預設
5 秒）就會顯示。若仍不出現，確認佔位符有進到選項裡：`tmux show-option -gv
status-right` 應含有 `scripts/status.sh` 而非字面的 `#{agent_status}`；若仍是字面
字串，代表進入點腳本沒跑到，重跑 `tmux source-file ~/.tmux.conf` 或那行 `run-shell`。

**看到方塊或 `?` 而不是圖示。**
你的終端字型不是 Nerd Font。安裝一款 Nerd Font 並設為終端字型，或改用 ASCII 標記：
`set -g @agent-status-icons 'ascii'`。

**某個 pane 顯示的狀態和我預期不同（或什麼都沒有）。**
判定是讀取各家 CLI 的畫面輸出，而上游會隨版本改動 —— 見[偵測對照表](detection-matrix.md)
與其 best-effort 免責聲明。要權威狀態就設 `@agent-status-provider`。若是非 agent 的
`node`／`bun`／`deno` 開發伺服器點亮了膠囊，請注意這幾種只用視窗標題判定、絕不看畫面
文字 —— 檢查該行程是否在 OSC 標題塞了 spinner。

**它會跟我的 agent 對話或讀我的程式碼嗎？**
不會。它只讀 tmux pane 的中繼資料，以及每個 agent pane 畫面最後約 30 行來在本機判定
狀態。除非*你*自己設定了會發網路請求的 provider，否則不會有任何東西離開你的機器。

## 相容性

- **需要 tmux ≥ 2.1。** 依官方 tmux `CHANGES`，本外掛用到的功能都很早就有：
  `@` 前綴使用者選項、`capture-pane -p`、`show-options -q` 在 **1.8**；
  `#{pane_current_command}` 格式在 **1.9**。2.1 這個下限是刻意取的保守、已驗證安全的
  值，落在上述引入版本之上。
- **實測版本：** macOS 上的 tmux `next-3.8`。更舊的 tmux 版本是依 `CHANGES` 的功能
  歷史推斷，未在實際舊版二進位上驗證 —— 若在舊版遇到問題，歡迎開 issue（並考慮升級）。
- **平台：** macOS 是主要且經實測的平台。分類器（`classify.awk`）是純逐位元組的內容
  比對、與平台無關，其單元測試在 CI 的 Linux 上執行；但完整的 pane 掃描整合只在 macOS
  實測過。argv 層的*存在*偵測可攜；只有 busy／blocked／idle 的 TUI 細分是針對各 CLI 的
  macOS 版本調校的。

## 授權

MIT —— 見 [LICENSE](../LICENSE)。
