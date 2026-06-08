# Stage 6 — integrate（run 尾彙整 → 開**單一** MR）

- 由 `screen-mender-integrator` agent 在 Phase 3 spawn 一次（**全部 lane 收工後**），把整 run 所有成功修復的畫面彙整成**一條 integration branch + 一個 MR**。
- 對應 SKILL Phase 3、orchestration §5。本檔自足。
- 為何獨立成階段：彙整天生要碰 diff / 衝突解 / build / 截圖上傳，與「orchestrator 不碰 diff/build/截圖」紀律衝突 → 關進專屬 agent。

## Inputs（orchestrator 傳入）
- `run_dir`、`run_id`、`platform`、`base_branch`、`mr_tool`（glab|gh）、`capture_locale`、`dry_run`。
- `lane_worktrees[]`：各 lane 常駐 worktree 路徑（取一條暖的當 integration worktree，省冷編）。
- `device_serial`：任一台已備妥裝置（衝突畫面重跑 snapshot test 用）。
- `screens[]`：每筆 = 各 runner 交出的 `<run_dir>/<unified_id>/`（含 `meta.json` / `mr-section.md` / before·after PNG）；只含 status ∈ {`fully-fixed`,`partially-fixed`} 的畫面（`clean`/`locked`/`defect`/`stuck`/`harness-missing` 無修復產物、不彙整）。
- `feature_branch_prefix`：per-screen branch 命名前綴（cherry-pick 來源）。
- `integration_refix_max_rounds`（預設 2）、`refix_round`（本次 resume 的整合層輪次，初次為 0）。

無任何成功畫面（`screens` 空）→ 不開 MR，回 `no-changes`。

## Procedure

### 1. 建 integration branch（重用暖 worktree）
- 取 `lane_worktrees[0]`（已暖）當 integration worktree。
- `git -C <wt> fetch origin`
- 直接從 `origin/<base_branch>` 切 integration branch（**不 `checkout <base_branch>` 本身**——它可能已 checked out 在 canonical／別的 worktree，git 不允許同名 branch 兩處 checkout）：
  - `git -C <wt> checkout -B screen-mender-run-<run_id> origin/<base_branch>`（`-B` = 存在則重置）。
  - 名含 `run_id` → run 級冪等（同 run 重跑同名 branch；不同 run 各自 branch/MR）。
- **resume（`refix_round>0`）**：本階段每次 invocation 都從 `origin/<base_branch>` **整條重建** integration branch、重 cherry-pick 全部 `screens[]`（重修畫面的 commit 已 amend 在其 branch）→ 確定性、冪等，warm worktree 走增量編譯，重建成本低。

### 2. 依序 cherry-pick 每個成功畫面（保留一畫面一 commit）
對 `screens[]` 逐一（順序穩定，例 unified_id 字典序）：

```
git -C <wt> cherry-pick <feature_branch_prefix><unified_id>   # per-screen branch 的單一 commit
```

- per-screen branch 在共用 .git，**不需 push/fetch** 即可取用。
- runner 已把每畫面壓成**一個** commit（05-finalize）→ cherry-pick 後 integration branch 上**一畫面一 commit**，reviewer 可逐 commit 審。

#### 衝突處理
- 衝突面**幾乎只有共享字串資源檔**（`values-<locale>/strings.xml`、`Localizable.strings`）：不同 key 多由 3-way 自動合掉；**同 key 被兩畫面都改**才需手解。
  - 手解原則：兩畫面都是「縮短同一字串」→ 取**更短且兩畫面 after 圖都不爆框**的值（必要時回看兩畫面 after 截圖判定）；無法兼顧 → 該字串保留、把**較難容納**的那個畫面對應缺陷降 `partially-fixed` 並在其 section 註記「字串合併衝突、與 `<另一畫面>` 共用 key」。
  - snapshot test 檔 / production 檔多為各畫面獨立、不衝突；若衝突（同檔同區）→ 視為兩畫面動到同元件，手解後**該兩畫面都列入步驟 3 重跑**。
- 記 `conflict_screens[]` = 任何發生過衝突解的畫面 unified_id。

### 3. build 驗證
- **一律 build 一次** integration branch（抓 cherry-pick/衝突解造成的編譯破壞）：
  - `<build_cmd> > <run_dir>/integrate-build.log 2>&1`，`grep -E 'error|FAILED|Exception|FAIL' <...> | head -50`。
  - build 失敗 → 修最小編譯破壞（通常衝突解殘漏）；連 3 次同錯 → return `escalation`（含 log 摘要），不無限試。

### 3.5 Tier-2 整合層 review（**只審 merge 動到的 delta，不重審全部**）

> 為何窄：沒被 merge 碰到的畫面在 integration branch 上跟它**已通過 tier-1（per-screen 審查與驗證）的 per-screen branch 逐字相同**，重審零收益。Tier-2 只補「合併才出現」的風險：衝突解品質 + 跨畫面共用檔/元件的互相打架。

1. **算 `affected_screens`** = `conflict_screens[]`（有 git 衝突解過的）∪「touched 檔與另一畫面重疊的畫面」（無衝突但動到同一共享檔/元件——個別 branch 看不出、合併才暴露）。其餘畫面不審。
2. **重跑 + 視覺比對**：在 `device_serial` 跑各 `affected_screens` 的 `snapshot_test_cmd`，比對新 after 圖 vs 該畫面 runner 交出的 after：
   - 視覺等價 → 通過。
   - 不等價 → 該畫面在合併後被改壞（典型：共享字串/元件被另一畫面動到）。
3. **focused diff 審**：對「衝突解的 hunk」+「被 >1 畫面碰過的檔」做 scope/redesign/語意審（同 [`04-verify`](04-verify.md) Step 0 視角，但只看這些 hunk）。
4. **歸因 + 處置**：
   - **衝突解本身的問題**（無特定畫面、是 integrator 自己解錯）→ integrator **自己重解**（Edit）→ 回步驟 3 重 build/比對。
   - **可歸因到某畫面的修復缺陷**（該畫面 tier-1 漏掉、或與他人共用檔互踩）→ **退回該畫面 runner 重修**（見下〈退回重修〉）。
5. `affected_screens` 為空（無衝突、無共用檔重疊）→ 整段跳過（最省、最常見）。

#### 退回重修（Tier-2 → developer，orchestrator 中介）

> integrator **無 `Agent` 工具、不能自己 spawn runner**；退回一律經 orchestrator。

- 把需重修的畫面組成 `needs_refix: [{ unified_id, branch, findings[] }]`（findings 一行一條：問題 + 期望，等同 AC）後 **return 給 orchestrator**（先不 push、不開 MR）。
- orchestrator 對每個 `needs_refix` 畫面重派其 runner（帶 `refix={findings, round}`，在既有 branch 上重修、amend 單一 commit），再**重新 spawn integrator**（resume：重 cherry-pick 更新後的畫面、重跑 3→3.5）。
- 有界：整合層重修輪數受 orchestrator 的 `integration_refix_max_rounds`（預設 2）；達上限仍未過 → **把該畫面踢出本 MR**（不 cherry-pick）、在 return `dropped: [unified_id → reason]` 標記，其餘畫面照常成 MR。被踢畫面下次 run 由 audit 自然重撿。

### 4. 組單一 MR description（aggregate schema 見 [`issue-schemas`](issue-schemas.md) §4）
- 總覽段：`涵蓋 N 畫面（X 全修 / Y 部分）` + run 資訊（platform / locale / run_id / string_fix_policy）。
- 每畫面一段 `<details>`（收合、可逐畫面展開）：直接取該畫面 `mr-section.md` 內容，截圖引用換成上傳後的 `/uploads/...`。
- 截圖上傳：對每張 before/after `POST /projects/:id/uploads`（multipart，`glab api -F` 不支援，用 `curl -F file=@<png>` + token）取 `/uploads/...` markdown。
- 殘留可見彙總：把所有 `partially-fixed` 畫面的殘留可見缺陷彙整到總覽段最顯眼處（不只藏在各畫面收合段）。

### 5. push + 開 MR + 轉 ready
- `git -C <wt> push -u origin screen-mender-run-<run_id>`（已 push 用 `--force-with-lease`）。
- 冪等：先 live 查 `<mr_tool> mr list`，該 integration branch 已有 open MR → 不重開、改 update description。
- 開**一個** MR：標題固定模板 `自動跑版修復：N 畫面（X 全修 / Y 部分）`（見 [`issue-schemas`](issue-schemas.md) §4）。
- 全部畫面皆 `fully-fixed` 且無任何殘留可見 → 直接 `<mr_tool> mr update <id> --ready`；否則留 draft（有部分修復需人工掃殘留）。

## dry_run=true（不開 MR）
- 不 push、不開 MR；步驟 1–4 照跑（cherry-pick 到本地 integration branch、build 驗證），產物落 `<run_dir>/`：
  - `change.patch` = `git -C <wt> format-patch <base_branch>..HEAD --stdout`（整 run 合併 diff，一份）。
  - `proposed-mr.md` = 步驟 4 的 aggregate description，但截圖引 `<run_dir>/<unified_id>/` 內相對路徑（不 `POST /uploads`），轉 ready 改標 `would-be-ready`。
  - 各畫面 before/after PNG 已在 `<run_dir>/<unified_id>/`，不另複製。
- integration branch 與 lane worktree 仍照 teardown 清（dry_run 只保留 `run_dir` 產物）。

## Output（integrator return）
```
status: done | needs-refix | no-changes
# needs-refix：Tier-2 退回，等 orchestrator 重派 runner 後 resume；尚未 push/開 MR
mr_url:            # status=done 才有；dry_run → <run_dir>/proposed-mr.md 路徑；no-changes/needs-refix → none
integrated: [unified_id…]            # 成功併入的畫面
needs_refix: [{ unified_id, branch, findings[] }]   # Tier-2 退回重修的畫面（status=needs-refix 時）
dropped: [unified_id → reason]       # 達 integration_refix_max_rounds 仍未過、踢出本 MR 的畫面
demoted: [unified_id → reason]       # 因衝突解/合併被降 partially-fixed 的畫面
conflict_screens: [unified_id…]      # 發生過衝突解、已重驗
timing: { integrate_s, cherrypick_n, conflict_n, build_runs, refix_rounds }
escalation: <build 連敗 3 次 / 無法解的衝突 / push 失敗，否則空>
```
