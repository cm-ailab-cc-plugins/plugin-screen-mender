# screen-mender 編排紀律（plugin 自帶，generic）

> 本檔是 screen-mender 自帶的通用編排規則，零專案 lore。
>
> 無 profile 設定檔——所有專案專屬值在 run 起手自動解析：平台偵測、repo = git toplevel、device 由 [`scripts/ensure-devices.sh`](../scripts/ensure-devices.sh) 自動準備（查 pool→不足自建→開機）、build/test/pull 由 add-snapshot 回報、git host/base 由 `git remote` 推、目標 locale 問使用者（見 SKILL Phase 0.0）。
>
> orchestrator(SKILL) 讀本檔；agent 不讀本檔（需要的紀律已 inline 進各 agent）。單平台（當前 repo 自動偵測）。

## 1. Delegate everything

### orchestrator(main session) 只做

- 配 lane
- 認領畫面
- **每畫面 spawn 一個 runner**
- 收 runner summary
- 發通知

> 註：不維護 ledger、不輪詢 merge、**不自己碰 diff/開 MR**——run 尾 spawn 一個 `screen-mender-integrator` 把所有畫面彙整成**單一** MR，見 §5。

### per-screen pipeline 一律在背景 runner 內完成

整個 per-screen pipeline（capture / codebase 修改 / build / test / 截圖 / 審查驗證 / commit）一律在背景 runner（`run_in_background`）內完成；run 尾的彙整（cherry-pick / 解衝突 / build 驗證 / 截圖上傳 / 開單一 MR）在背景 `screen-mender-integrator` 內完成；orchestrator **不碰截圖·issues·diff·build log**。

- 原因：main session 不自己跑會 block > 5 min 的工作。
- 把 per-screen 細節關進 runner，main 的 context 每畫面只留一段精簡 summary。
  - 這是 runner 模型省 context 的核心。

## 2. 背景 agent 生命週期（無 watchdog）

orchestrator 不做 heartbeat 輪詢 / ScheduleWakeup watchdog。每畫面一個背景 runner，完成時 harness 通知。

- happy path：背景 runner 完成時 harness 自動通知 orchestrator（完成通知驅動），不需輪詢。
  - 一個 runner = 一次通知（不再是每畫面 3–6 次階段通知）。
- backstop：極端「卡死不回報」靠本 skill 互動觸發、使用者在線，無進度即打斷。

### runner 端只保留 self-abort

以下任一發生 → 停止，用 return 的 `escalation` 回報；orchestrator 收到即上報使用者：

- fix 達 `iterate_max`
- build 同錯連 3 次
- 內部迴圈超 `internal_loop_max_rounds`
- 審查驗證階段 AUDIT_PROBLEM

紀律：

- `escalation` 四項：原因(stuck/audit-problem/...)、卡點、試過什麼、建議。

## 3. 並行模型：N 條 lane（work-stealing）

並行單位 = lane，共 `lanes` 條（預設 4，自動降到 ensure-devices 備妥的裝置數）。每條 lane 整 run 獨佔一組資源、從共享 queue 搶畫面、序列消化。

> 起跑序：fan-out **前**先過 SKILL Phase 1.0 **canary 閘**（只用一條 lane 帶 `canary=true` 認領第一個畫面、真 build 一次確認 snapshot harness 能出圖）。canary 回 `harness-missing` → 停整 run；回 `canary-ok` 才放開下列 work-stealing 全量 fan-out。canary 把「缺 harness」的成本從 N 次冷編壓到 1 次。

### 每 lane 獨佔的資源

> run 起手一次性綁定，整 run 不換。

- 1 台 emulator（起手 `ensure-devices.sh` 回報的 ready serial/udid[i]，來自自管 `test_phone_NN` pool）。
- 1 個 worktree（§4）。

### 共享 queue（work-stealing）

- 所有待修畫面（Phase 0 manifest）放一個共享 queue。
- lane 跑完一個就原子認領下一個未認領畫面，認不到即收工。
- 負載自動均衡、無拖尾。

### 原子認領 = `mkdir` + 立刻 spawn runner，同一個 action

- `mkdir` atomic 當搶占宣告，在內建 claim 目錄（`<repo>/.screen-mender/claims`）。
  - 鎖目錄則用內建預設 `<repo>/.screen-mender/locks`。
- 鐵則：認領與「spawn 該畫面的 runner」必須在同一輪 tool-call 內完成。
  - 不可只 `mkdir`／敘述「已認領、待會 launch」卻把 spawn 的 tool call 漏掉。
  - > 註：曾因此讓一條 lane 閒置數十分鐘才被發現補發。
- spawn 時以 Agent 的 `model` 參數帶 run 參數 `runner_model`（預設 `sonnet`；省用量主槓桿，覆寫 runner agent frontmatter，per-call 優先）。canary runner 同此 model。

```
for unified_id in manifest（優先挑與本 lane worktree 當前 branch 同 module 者，減少 branch churn）:
    mkdir <claim_dir>/<unified_id>/   成功 → 這個歸我，checkout 新 branch 後**同一輪立刻 spawn 它的 runner**（Phase 1→2）
                                      失敗（已被別 lane 搶）→ 試下一個
全 manifest 都認領不到 → 本 lane 收工
```

### claim↔live-runner 對賬（事件驅動，非輪詢）

- 觸發點：orchestrator 每次被完成通知喚醒、或準備讓某 lane 收工前。
- 動作：對照 `claim_dir` 既有 claim 與目前 live runner；有 claim 卻無對應 live runner = 漏派，立即補 spawn。
- 這不是 watchdog（不定時主動喚醒），是事件驅動下的一致性對賬。

### 無跨-lane 裝置鎖

- 每 lane 各有一台 emulator。
- lane 內 runner 的 capture 與 verify 本就序列（同一畫面先 capture 後 verify）。
- 故不需單裝置 singleton / capture-verify 互斥鎖。

### 無 tester slot

- 新版 capture 走 component snapshot test 直接 instantiate 畫面、繞過登入導航（見 add-snapshot）。
- 不需登入帳號池。

> 起手跑 `scripts/ensure-devices.sh --platform <P> --count <lanes>`：查自管 `test_phone_NN` pool→不足自建（指定機型不可用退本機最新；Android 無 avdmanager 走複製現有 AVD）→開機→回報 ready serial/udid。
>
> 備妥 M 台：`M≥1` 即以 M 條 lane 續跑（`M<lanes` 標降級、不靜默縮水）；`M=0` 或硬缺 → 終止並印 script 給的「怎麼補」。run 結束跑 `--teardown` 關機保留 profile（見 §4 收尾）。

## 4. lane worktree（per-lane 常駐重用 — 效能關鍵）

紅線：絕不在 canonical repo 路徑（git toplevel）改 code 或切分支，唯一允許 `git pull {base_branch}`。

### per-lane 常駐 worktree：每條 lane 維持 1 個常駐 worktree

三條紀律：

- 整 run 重用。
- 逐畫面換 branch。
- 絕不 clean / 重建 / 砍 build 產物。

原因：

- 同 worktree 路徑重用讓第 2+ 畫面 build 走增量。
- 新建／重建 worktree = 冷編，務必避免。

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

### integration worktree（run 尾彙整重用，不新建）

- integrator 不新建 worktree（會冷編）→ 重用一條暖的 lane worktree（`lane_worktrees[0]`）切 integration branch、cherry-pick 全部畫面。
- 故 lane worktree 在 integrator 跑完前**不可先回收**；Phase 3 順序固定：全 lane 收工 → spawn integrator → integrator 回 `mr_url` → 才回收 worktree。

### run 結束才回收 lane 資源（在 integrator 跑完之後）

- `git worktree remove` 所有 lane。
- 跑 `scripts/ensure-devices.sh --teardown --platform <P>` 關機所有自管 `test_phone_NN`。
  - 保留 profile 供下次重用；只動 pool、不碰使用者其他裝置。
- per-screen branch 純本地（整 run 不 push）→ 隨 worktree remove 一併清（`branch -D <feature_branch_prefix>*`）；**只有 integration branch `screen-mender-run-<run_id>` push 到遠端**（承載唯一 MR），不刪。
- 不用 gradle build-cache（對本類 app 無益）；加速全靠 per-lane 增量。

## 5. MR 生命週期：一個 run 一個 MR

`mr_tool` 由 git remote 推得：gitlab→glab / github→gh。單一 MR = 唯一 SSOT，零紀錄檔。

> 新模型：per-screen runner **不開 MR**（stage 5 只 local commit + 交出 `mr-section.md` 到 run_dir，見 05-finalize）；run 尾 orchestrator spawn 一個 `screen-mender-integrator`，把所有成功畫面的 per-screen branch 彙整成**一條 integration branch + 一個 MR**（見 [`06-integrate`](../../../agents/references/06-integrate.md)）。orchestrator 仍不直接碰 diff/MR。
>
> 為何收斂成單一 MR：一次 run 修數十畫面、各開一個 MR → 數十個 review/合併單位，管理成本爆炸。改成一個 MR、MR 內**一畫面一 commit**：reviewer 仍可逐 commit／逐收合段審（每塊 diff 一樣小），但只批准／合併**一次**。

### §5.0 per-screen branch 不 push（共用 .git）

- lane worktree 都是 canonical repo 的 `git worktree`，**共用 .git / refs** → per-screen branch 整 run 留本地，integrator 直接 cherry-pick，無需 push。
- 只有 run 尾的 integration branch `screen-mender-run-<run_id>` push 到遠端（承載唯一 MR）。
- 連帶消掉舊模型「數十條 branch push 到遠端」。

### §5.1 彙整（integrator，全 lane 收工後 spawn 一次）

orchestrator 傳給 integrator 的 prompt 欄位（已知值轉傳，見 [`06-integrate`](../../../agents/references/06-integrate.md)）：

- `run_dir`、`run_id`、`platform`、`base_branch`、`mr_tool`、`capture_locale`、`string_fix_policy`、`dry_run`
- `lane_worktrees[]`（取一條暖的當 integration worktree）、`device_serial`、`feature_branch_prefix`
- `screens[]` = 各 runner 交出 status ∈ {fully-fixed, partially-fixed} 的 `<run_dir>/<unified_id>/`（含 `meta.json`/`mr-section.md`/before·after）

integrator 程序（細節在 06-integrate）：暖 worktree 切 integration branch → 依序 cherry-pick（一畫面一 commit）→ 解共享字串衝突 → build 一次 + 只對衝突畫面重跑 snapshot test → 串 aggregate description（每畫面一收合段 + 內嵌 before/after）→ push 開單一 MR。

`screens` 空（無任何成功畫面）→ integrator 回 `no-changes`、不開 MR。

### §5.2 冪等（run 級）

- integration branch 名含 `run_id` → 同一 run 重跑同名 branch、integrator 先 live 查 `<mr_tool> mr list`，該 branch 已有 open MR → 不重開、改 update description。
- 不同 run 各自 branch/MR。
- 已修畫面的冪等在 **audit 級**達成：已 merge 過且無新缺陷的畫面 audit 回 `clean` → 不產 section、不被 cherry-pick（不再 per-branch 查 open MR）。

### §5.3 description = 唯一紀錄（aggregate schema 見 [`issue-schemas`](../../../agents/references/issue-schemas.md) §4）

- 標題：固定模板 `自動跑版修復：<N> 畫面（<X> 全修 / <Y> 部分）`。
- 總覽段：涵蓋畫面清單 + 全 run 殘留可見彙總（所有 partially-fixed 畫面的殘留集中列最顯眼處）。
- 每畫面一 `<details>` 收合段（= 該畫面 `mr-section.md`：狀態 / 修了什麼 file:line / 殘留 / wont-fix / before·after）。
- before/after 上傳：`POST /projects/:id/uploads` 取 `/uploads/...` 嵌入（multipart；`glab api -F` 不支援，用 `curl -F file=@<png>` + token）。
- 不產任何 `.audit` 紀錄檔。

### §5.4 轉 ready

- 全部畫面 fully-fixed 且無任何殘留可見 → integrator `<mr_tool> mr update <id> --ready`。
- 任一畫面 partially-fixed／有殘留可見 → 留 draft（需人工掃殘留）。
- 畫面狀態由「所有 kept+deferred 是否都解決」計，非「過 verify 的那幾條」。
- self-review/verify 紀律（per-screen 階段）：審查與驗證階段雖與 fix 同一 runner，仍須換「審查者／驗收者」視角獨立審 scope/redesign + 比 AC + 視覺等價 + 殘留盤點。
  - **不得因自己是修的人就放水**（見 `agents/references/04-verify.md`）。

### §5.5 無 polling、無 watchdog

- integrator 開出 MR 即收工；run 內不追 merge 狀態。
- 下次 run 靠 audit 級冪等（已修畫面回 clean）避免重做。

### §5.6 run 期間暫存

= ephemeral run 目錄 `<repo>/.screen-mender/runs/<run_id>/`（gitignored、不進版控，`.audit` 一律不寫）。以下皆放此，run 結束即刪：

- issues.md / 截圖 / 各畫面 `mr-section.md`·`meta.json` / audit/dev/verify 的 working 輸出 / `integrate-build.log`
- run 結束清所有 lane worktree + `claim_dir`，並跑 `ensure-devices.sh --teardown` 關機自管裝置（保留 profile，見 §4）。**順序：integrator 跑完才回收 worktree**（它要重用暖 worktree）。

**dry-run 例外**：`dry_run=true` 時

- integrator 不 push/不開 MR；步驟照跑後產**一份**合併產物落 run_dir：`change.patch`（整 run 合併 diff）、`proposed-mr.md`（aggregate description，截圖引本地相對路徑、轉 ready 改標 `would-be-ready`）；各畫面 before/after 已在 `<run_dir>/<unified_id>/`。
- run 目錄是交付物，run 結束**不刪**、於 final summary 回報路徑；lane worktree + `claim_dir` 仍照清。
- 此產出不被未來 run 讀回（idempotency 仍純靠 audit 級 + live 查 MR），不違反無狀態。

## 6. internal loop 上限

- `fix ↔ 審查驗證`（review + verify 已併為一格）最多 `internal_loop_max_rounds`（內建預設 3）輪。
- 超過 → runner return `escalation`（含 round 紀錄）+ orchestrator 上報使用者（不寫檔），不無限迴圈。

## 7. 觀測：每階段耗時 + build 次數（`trace`）

目的：讓「慢在哪」現形。

- 本類 app 時間幾乎全在「build + 模擬器 render」。
- 故核心觀測量 = 每畫面各階段 wall-clock + build 次數。

### runner 對每畫面自報各階段耗時

> 合併 agent 後 orchestrator 看不到內部 stage 的 spawn／完成事件，故改 runner 自報。

- runner 進出每個內部階段（capture / audit / fix / 審查驗證 / mr）時順手取 `date +%s`，差值 = 該階段 wall-clock，彙整進 return 的 `timing`。
- build 次數：runner 加總 fix 階段 + 審查驗證階段（spot-check 重跑）+ capture 階段本身一次 build 的實際次數。
- 迴圈輪數：`fix↔審查驗證` 實際輪數（runner 本就掌握）。
- orchestrator 另記「spawn runner → 收到完成通知」整段 wall-clock 當交叉檢核（涵蓋 spawn 延遲），不新增喚醒、不輪詢。

### 彙整去處

- 每畫面 runner 回一筆 `{capture_s, audit_s, fix_s, verify_s, build_runs, dev_rounds}`（`verify_s` 涵蓋審查＋驗證；fix/verify 不再含 push）。
- integrator 另回一筆 `{integrate_s, cherrypick_n, conflict_n, build_runs}`（彙整 wall-clock + cherry-pick/衝突/build 次數）；orchestrator 以「spawn integrator → 收到完成通知」整段 wall-clock 交叉檢核。
- 供 Phase 3 final summary 呈現（compact 一行 + 一行 integrate；`trace=true` 出完整逐階段 breakdown）。
- 觀測資料只進 final summary（對話呈現），不寫 `.audit`。
