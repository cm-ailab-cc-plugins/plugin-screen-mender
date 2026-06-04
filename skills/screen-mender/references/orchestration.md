# screen-mender 編排紀律（plugin 自帶，generic）

> 本檔是 screen-mender 自帶的通用編排規則，零專案 lore。
>
> 無 profile 設定檔——所有專案專屬值在 run 起手自動解析：平台偵測、repo = git toplevel、device 由 [`scripts/ensure-devices.sh`](../scripts/ensure-devices.sh) 自動準備（查 pool→不足自建→開機）、build/test/pull 由 add-snapshot 回報、git host/base 由 `git remote` 推、目標 locale 問使用者（見 SKILL Phase 0.0）。
>
> orchestrator(SKILL) 讀本檔；agent 不讀本檔（需要的紀律已 inline 進各 agent）。單平台（當前 repo 自動偵測）。

## 1. Delegate everything

orchestrator(main session) 只做：配 lane、認領畫面、**每畫面 spawn 一個 runner**、收 runner summary、發通知（不維護 ledger、不輪詢 merge、**不自己開 MR**——MR 由 runner 在其 mr 階段開，見 §5）。

整個 per-screen pipeline（capture / codebase 修改 / build / test / 截圖 / 自審 / 自驗 / rebase / push / 開 MR）一律在背景 runner（`run_in_background`）內完成；orchestrator **不碰截圖·issues·diff·build log**。

- 原因：main session 不自己跑會 block > 5 min 的工作；把 per-screen 細節關進 runner，main 的 context 每畫面只留一段精簡 summary（這是 runner 模型省 context 的核心）。

## 2. 背景 agent 生命週期（無 watchdog）

orchestrator 不做 heartbeat 輪詢 / ScheduleWakeup watchdog。每畫面一個背景 runner，完成時 harness 通知。

- happy path：背景 runner 完成時 harness 自動通知 orchestrator（完成通知驅動），不需輪詢。一個 runner = 一次通知（不再是每畫面 3–6 次階段通知）。
- backstop：極端「卡死不回報」靠本 skill 互動觸發、使用者在線，無進度即打斷。

runner 端只保留 self-abort：fix 達 `iterate_max`／build 同錯連 3 次／內部迴圈超 `internal_loop_max_rounds`／reviewer AUDIT_PROBLEM → 停止，用 return 的 `escalation` 回報；orchestrator 收到即上報使用者。

- `escalation` 四項：原因(stuck/audit-problem/...)、卡點、試過什麼、建議。
- 不寫 `stuck.md` / heartbeat 檔。

## 3. 並行模型：N 條 lane（work-stealing）

並行單位 = lane，共 `lanes` 條（預設 4，自動降到 ensure-devices 備妥的裝置數）。每條 lane 整 run 獨佔一組資源、從共享 queue 搶畫面、序列消化。

每 lane 獨佔（run 起手一次性綁定，整 run 不換）：

- 1 台 emulator（起手 `ensure-devices.sh` 回報的 ready serial/udid[i]，來自自管 `test_phone_NN` pool）。
- 1 個 worktree（§4）。

共享 queue（work-stealing）：所有待修畫面（Phase 0 manifest）放一個共享 queue；lane 跑完一個就原子認領下一個未認領畫面，認不到即收工。負載自動均衡、無拖尾。

原子認領 = `mkdir` + 立刻 spawn runner，同一個 action：

- `mkdir` atomic 當搶占宣告，在內建 claim 目錄（`<repo>/.screen-mender/claims`）；鎖目錄則用內建預設 `<repo>/.screen-mender/locks`。
- 鐵則：認領與「spawn 該畫面的 runner」必須在同一輪 tool-call 內完成——不可只 `mkdir`/敘述「已認領、待會 launch」卻把 spawn 的 tool call 漏掉（曾因此讓一條 lane 閒置數十分鐘才被發現補發）。

```
for unified_id in manifest（優先挑與本 lane worktree 當前 branch 同 module 者，減少 branch churn）:
    mkdir <claim_dir>/<unified_id>/   成功 → 這個歸我，checkout 新 branch 後**同一輪立刻 spawn 它的 runner**（Phase 1→2）
                                      失敗（已被別 lane 搶）→ 試下一個
全 manifest 都認領不到 → 本 lane 收工
```

claim↔live-runner 對賬（事件驅動，非輪詢）：orchestrator 每次被完成通知喚醒、或準備讓某 lane 收工前，對照 `claim_dir` 既有 claim 與目前 live runner；有 claim 卻無對應 live runner = 漏派，立即補 spawn。這不是 watchdog（不定時主動喚醒、不寫 heartbeat），是事件驅動下的一致性對賬。

無跨-lane 裝置鎖：每 lane 各有一台 emulator，lane 內 runner 的 capture 與 verify 本就序列（同一畫面先 capture 後 verify），故不需單裝置 singleton / capture-verify 互斥鎖。

無 tester slot：新版 capture 走 component snapshot test 直接 instantiate 畫面、繞過登入導航（見 add-snapshot），不需登入帳號池。

> 起手跑 `scripts/ensure-devices.sh --platform <P> --count <lanes>`：查自管 `test_phone_NN` pool→不足自建（指定機型不可用退本機最新；Android 無 avdmanager 走複製現有 AVD）→開機→回報 ready serial/udid。
>
> 備妥 M 台：`M≥1` 即以 M 條 lane 續跑（`M<lanes` 標降級、不靜默縮水）；`M=0` 或硬缺 → 終止並印 script 給的「怎麼補」。run 結束跑 `--teardown` 關機保留 profile（見 §4 收尾）。

## 4. lane worktree（per-lane 常駐重用 — 效能關鍵）

紅線：絕不在 canonical repo 路徑（git toplevel）改 code 或切分支，唯一允許 `git pull {base_branch}`。

per-lane 常駐 worktree：每條 lane 維持 1 個常駐 worktree。三條紀律：

- 整 run 重用。
- 逐畫面換 branch。
- 絕不 clean / 重建 / 砍 build 產物。

原因：同 worktree 路徑重用讓第 2+ 畫面 build 走增量；新建/重建 worktree = 冷編，務必避免。

```
# run 起手：每 lane 建一次（從 base 切第一個認領畫面的 branch）
git -C <repo_path> fetch origin && git -C <repo_path> pull origin <base_branch>
git -C <repo_path> worktree add <worktree_root>/screen-mender-lane<i> -b <feature_branch_prefix><unified_id>
# lane 建立後：把 canonical 內「gitignored 的本地 build 設定」複製進 worktree（worktree 不帶 untracked 檔）。
#   Android：cp <repo_path>/local.properties <lane_worktree>/（缺它第一次 build 必 "SDK location not found" 白跑一次冷編）
#   一般化：任何 build 必需但未進版控的本地檔（local.properties / 簽章設定 / .env 類）都比照複製。
# 下一個認領畫面：同一 lane worktree 內換 branch（不刪 worktree、不 clean）
git -C <lane_worktree> checkout <base_branch> && git -C <lane_worktree> pull --ff-only && git -C <lane_worktree> checkout -b <feature_branch_prefix><下一 unified_id>
```

run 結束才回收 lane 資源：`git worktree remove` 所有 lane，並跑 `scripts/ensure-devices.sh --teardown --platform <P>` 關機所有自管 `test_phone_NN`（保留 profile 供下次重用；只動 pool、不碰使用者其他裝置）。已 merge 的 branch 確認後 `branch -D` + `push origin --delete`（worktree 留著續服務下一畫面）。不用 gradle build-cache（對本類 app 無益）；加速全靠 per-lane 增量。

## 5. MR 生命週期

`mr_tool` 由 git remote 推得：gitlab→glab / github→gh。MR = 唯一 SSOT，零紀錄檔。

> 新模型下本節由 **runner 的 mr 階段**執行（見 [`screen-mender-runner`](../../../agents/screen-mender-runner.md) 與 `agents/references/06-mr.md`），orchestrator 不直接碰 MR。下文「orchestrator／developer／reviewer／verifier」讀作 runner 的對應內部階段（mr／fix／review／verify）。

### §5.0 dry-run（試跑，不開 MR）

`dry_run=true` 時整個 §5 改走「只產出、不動遠端」：

- fix 階段只 local commit、**不 push**（orchestrator 傳 `dry_run` 給 runner）。
- mr 階段 **不 rebase、不 push、不開 MR**；改從 lane worktree 取產物落 `<run_dir>/<unified_id>/`：
  - `change.patch` = `git -C <worktree> format-patch <base_branch>..HEAD --stdout`。
  - `before.png` / `after.png`（複製 fix 階段的 before/after 截圖）。
  - `proposed-mr.md` = §5.3／[`issue-schemas`](issue-schemas.md) §4 的 MR description，但截圖引本地相對路徑（不 `POST /uploads`），轉 ready 與否改標 `would-be-ready`。
- review 階段照跑，`diff_cmd` = `git -C <worktree> diff <base_branch>`；verify 階段照判 after-shot；內部 loop 照常。
- 冪等（§5.1）略過（無 MR 可查）；轉 ready（§5.4）略過。

### §5.1 冪等

開 MR 前 live 查 `<mr_tool> mr list`，若該畫面 branch（`<feature_branch_prefix><unified_id>`）已有 open MR → 跳過不重開。done-ness 不靠本地紀錄、靠 live 查。

### §5.2 開 MR + rebase 歸屬

fix 階段 push 後，mr 階段 rebase 到 `base_branch`（已 push 用 `--force-with-lease`），開一個 MR（一畫面一個）。

- rebase 一律由 mr 階段做；fix 階段（含被退回重修那輪）只 commit + push，不自己 rebase——避免同一 branch 在不同階段互踩 force-push。

### §5.3 MR description = 唯一紀錄

列 + 內嵌截圖（schema 見 [`issue-schemas`](issue-schemas.md) §4）：

- 標題：固定模板 `自動跑版修復[（部分）]：<unified_id> - <原因摘要>`（見 [`issue-schemas`](issue-schemas.md) §4〈MR 標題固定模板〉；有任一殘留可見 → 必用「（部分）」variant）。
- 畫面狀態：`fully-fixed` / `partially-fixed (n fixed, m deferred-visible)` / `clean`——由「所有 kept+deferred 缺陷是否都解決」計，非「我選修的那幾條過 verify 沒」。
- 修了哪些視覺缺陷（file:line + 修法；退讓解註記 `legibility-degraded`）。
- ⚠️ 殘留可見缺陷（`deferred:needs-design` / `deferred:deferred-by-run-config`，after 圖仍可見）列最顯眼處。
  - 標題鐵則：有任一殘留可見 → MR 標題必用「（部分）」variant（`自動跑版修復（部分）：…`，見 [`issue-schemas`](issue-schemas.md) §4），不得用全修復 variant。
- 考慮過但不修（wont-fix reason）。
- 內嵌 before/after 截圖。
  - 上傳：`POST /projects/:id/uploads` 取得 `/uploads/...` markdown 嵌進 description。
  - 注意：multipart；`glab api -F` 不支援，用 `curl -F file=@<png>` + token。
- 不產任何 `.audit` 紀錄檔（一律不寫：issues / fixed / wont-fix / pending-merge）。

### §5.4 轉 ready

review PASS + verify PASS（被修的那幾條 AC + 目標區正確 + 視覺等價 + 無 regression）→ `<mr_tool> mr update <id> --ready`。

- verify PASS ≠ 畫面乾淨；畫面狀態由 mr 階段綜合 verify 的 `residual_visible` 另算（§5.3）。
- self-verify 紀律：verify 階段雖與 fix 是同一 runner，仍須換「驗收者」視角獨立比 AC + 視覺等價 + 殘留盤點，**不得因自己是修的人就放水或略過會出錯處**（見 `agents/references/05-verify.md`）。這是合併 agent 後最需守住的一關。

### §5.5 無 polling、無 watchdog

發出即往下一畫面；run 內不追 merge 狀態（merge 與否、何時不阻塞 run）。下次 run 靠 §5.1 冪等 live 查避免重做。

### §5.6 run 期間暫存

= ephemeral run 目錄（temp / gitignored）。以下皆放此，run 結束即刪，repo / `.audit` 不留檔：

- issues.md
- 截圖
- audit/dev/verify 的 working 輸出
- run 結束清所有 lane worktree + `claim_dir`，並跑 `ensure-devices.sh --teardown` 關機自管裝置（保留 profile，見 §4）。

**dry-run 例外**：`dry_run=true` 時 run 目錄是交付物（`change.patch` / 截圖 / `proposed-mr.md`），run 結束**不刪**、於 final summary 回報路徑；lane worktree + `claim_dir` 仍照清。此產出不被未來 run 讀回（idempotency 仍純靠 live 查 MR），不違反無狀態。

## 6. internal loop 上限

`fix ↔ review` / `fix ↔ verify` 各自最多 `internal_loop_max_rounds`（內建預設 3）輪。超過 → runner return `escalation`（含 round 紀錄）+ orchestrator 上報使用者（不寫檔），不無限迴圈。

上限 `internal_loop_max_rounds`（內建預設 3）適用對象（runner 內部、各自獨立計）：

- `fix ↔ review`
- `fix ↔ verify`

## 7. 觀測：每階段耗時 + build 次數（`trace`）

目的：讓「慢在哪」現形——本類 app 時間幾乎全在「build + 模擬器 render」，故核心觀測量 = 每畫面各階段 wall-clock + build 次數。

runner 對每畫面自報各階段耗時（合併 agent 後 orchestrator 看不到內部 stage 的 spawn／完成事件，故改 runner 自報）：

- runner 進出每個內部階段（capture / audit / fix / review / verify / mr）時順手取 `date +%s`，差值 = 該階段 wall-clock，彙整進 return 的 `timing`。
- build 次數：runner 加總 fix 階段 + verify 階段（spot-check 重跑）+ capture 階段本身一次 build 的實際次數。
- 迴圈輪數：`fix↔review`、`fix↔verify` 實際輪數（runner 本就掌握）。
- orchestrator 另記「spawn runner → 收到完成通知」整段 wall-clock 當交叉檢核（涵蓋 spawn 延遲），不新增喚醒、不輪詢。

每畫面 runner 回一筆 `{capture_s, audit_s, fix_s, review_s, verify_s, build_runs, dev_rounds}` → 供 Phase 3 final summary 呈現（compact 一行；`trace=true` 出完整逐階段 breakdown）。觀測資料只進 final summary（對話呈現），不寫 `.audit`。
