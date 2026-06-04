---
name: screen-mender
description: >-
  逐畫面修復「截圖看得見的視覺缺陷」，雙平台（iOS / Android 由 repo 檔案特徵自動偵測、零設定檔）。以單一畫面為原子單位跑完整閉環：每畫面派一個 runner agent，獨力跑「確保截圖 test → 出截圖 → 偵測缺陷 + triage + 附 AC → 修復→審查驗證 → 發一個小 MR（含 before/after 截圖）」，回一段精簡 summary → 下一畫面。一個 MR = 一個畫面被完整修復；多畫面靠 N 條 lane（各獨佔一台裝置）work-stealing 並行。唯一人工點 = PR 把關。

  觸發：「跑 screen-mender」「逐畫面修視覺跑版」「一畫面一個小 MR 修 UI」「把這個 App 的畫面一個個修好」；只在明確要求「逐畫面修復閉環」時觸發。
---

# screen-mender

逐畫面修復「截圖看得見的視覺缺陷」。一個畫面 = 一個原子修復單元 = 一個小 MR；雙平台、零設定、無狀態；唯一人工點是 PR 把關。

## 核心模型

每個畫面派一個 runner 獨立跑完整閉環，一個畫面對應一個 MR；多畫面靠 N 條 lane（各佔一台裝置）work-stealing 並行；發 MR 即往下、不追 merge、不被人工 merge 速度鎖死。

```
從共享 queue（全部目標畫面，或使用者指定的子集）原子認領下一個畫面
  → 在本 lane 常駐 worktree checkout 新 branch，同一輪 spawn 一個 screen-mender-runner（背景）
  → runner 獨力跑完整閉環：產圖（C1–C5 閘）→ 偵測 + triage + 附 AC → 修復→審查驗證（真 render 上有界迭代）→ 發一個小 MR（修了什麼 + before/after 全寫 MR）
  → runner 回一段精簡 summary；orchestrator 通知使用者一句、釋放 lane，立刻認領下一個畫面（不追 merge）↺
```

## 運作原則

### 只修截圖看得見的缺陷
- 偵測與驗收都靠截圖
- 範圍: 截斷／爆框／重疊／錯位／譯文壞／locale 格式錯／對比不可讀
- 截圖看不見的不在範圍，route 去專屬 a11y pass
- 完整類別: [`issue-schemas`](references/issue-schemas.md)

### 雙平台、零設定
- 單次 run 鎖定一個平台，由 git repo 檔案特徵自動偵測（Phase 0），無 profile 設定檔
- 會隨 App 變的值起手自動解析
  - repo 路徑／build／test／pull／device／git host／base branch／locale／字串落點
- 同資料夾並列兩 repo 各自偵測互不干擾
- 下文 "emulator" 在 iOS repo 即 "simulator"

### 無狀態
- 不留任何本地紀錄檔
- 「這畫面修過沒」每次 live 查 git host（merged／open MR）

### MR 是唯一 SSOT
- 修了什麼、before/after 截圖、考慮過但不修的理由，全寫在 MR。
- run 期間暫存放 ephemeral run 目錄（temp／gitignored），run 結束即刪。

### 不重造輪子
- capture 用 add-snapshot
- 列舉借 screen-list
- 單圖偵測借 shot-audit
- 本 skill 只加 per-screen 認領迴圈、work-stealing、per-lane worktree 重用，和**一個專屬 runner agent**（capture / audit / fix / 審查驗證 / MR 串成它的 5 個內部階段）

### 全部委派、不輪詢

- 只做配 lane／認領／**每畫面派一個 runner**／收 summary／發通知；
- capture／改 code／build／test／截圖／開 MR 全在背景 runner（`run_in_background`）內，orchestrator **不碰截圖·issues·diff·build log**
- 完成由 harness 通知驅動，不做 ScheduleWakeup 輪詢、不寫 heartbeat 檔
- runner 端只保留 self-abort（達迭代上限／build 連錯 3 次 → return stuck）
- 互動觸發、使用者在線即 backstop。細節見 orchestration.md §1–2。

### lane 並行 + 常駐 worktree

- N 條 lane 各佔一台裝置，從共享 queue work-stealing 認領畫面
- 每條 worktree 整 run 重用、逐畫面換 branch、絕不 clean／重建 → 第 2+ 畫面走增量編譯
- 每 lane 獨佔裝置 → 無跨-lane 裝置鎖（lane 內 runner 的 capture／verify 本就序列，不需互斥鎖）
- 細節見 orchestration.md §3–4。

### 合併 PR 是唯一人工點

- 偵測→修→發 MR 全自動，不設修前 issue 閘
- 使用者只在每個 per-screen 小 MR 上審 diff + 前後截圖。

### production 只在修復階段動

- capture 階段 0-production-diff
- 真正的修復走 runner 改 production、產 reviewed MR、使用者 gate。

## 使用與自建

使用既有 sibling skill ：

- capture: [`../add-snapshot`](../add-snapshot/SKILL.md)
- 畫面列舉: [`../screen-list`](../screen-list/SKILL.md)
- 單圖偵測: [`../shot-audit`](../shot-audit/SKILL.md)
- triage / schema / 安全約束走自帶 [`references/issue-schemas.md`](references/issue-schemas.md)

screen-mender 自己負責：
- 畫面認領迴圈 + work-stealing
- 每個 lane worktree 重用
- 每個畫面驅動一個 runner agent 進行修復

### 專屬 agent

**[`screen-mender-runner`](../../agents/screen-mender-runner.md)**

- 職責：**每畫面一個**，獨力跑 capture→audit→fix→審查驗證→MR 共 5 階段，回一段精簡 summary。手持 5 格 TODO，逐格 Read `agents/references/0X-*.md` 階段 prompt 當該階段指令（早退畫面不讀後面幾格、省 context）。
- 5 個內部階段（詳細規則在各階段檔；orchestrator 不需懂細節）：
  - **capture**：確保 snapshot test（缺就用 add-snapshot 建）、出截圖、C1–C5 渲染閘、capture 保真旗標。
  - **audit**：shot-audit 偵測 + triage（`kept`/`deferred`/`wont-fix`）+ 每條附 AC → `issues.md`。
  - **fix**：讀 kept、依 §3 優先序在真 render 上有界迭代（≤`iterate_max`）、守 outcome（T1/T2/R）、字串依 `string_fix_policy`、commit + push。
  - **審查與驗證（self-review + self-verify）**：先審 diff（scope：只改 kept、無越界；redesign：修復 vs 重設計），再驗 after 截圖（逐條比 AC、證據紀律量水平軸 + 同畫面視覺等價掃描 + 殘留盤點 + 鄰域 regression）；產合併 `verify_verdict`，NEEDS_CHANGES 回 fix、AUDIT_PROBLEM 升級。
  - **mr**：冪等 live 查 + rebase + 開一個 MR（before/after 內嵌）+ 轉 ready。
- 內部迴圈：`fix↔審查驗證` ≤ `internal_loop_max_rounds`；超界 / STUCK / AUDIT_PROBLEM → return `escalation`，由 orchestrator 上報使用者。
- context 紀律：build log 導檔只 grep 錯誤行、截圖讀一次、逐畫面歸零——這是它即使難畫面也不爆 context 的關鍵。

## 流程

### Phase 0：bootstrap（無狀態）

#### 0. 解析環境（零設定，無 profile）

- 平台偵測
  - Android: 當前 git repo 有 `gradlew`／`*.gradle*`
  - iOS: repo root 有 `*.xcodeproj`／`*.xcworkspace`／`Podfile`
  - 兩者皆無: 上報「無法判定平台」並終止。
- repo 路徑 = git toplevel
- git host／mr_tool：取 remote host → 含 `gitlab`/`github` 字樣直接判；自託管（host 是 IP／公司域名、無字樣）則看 `glab auth status`／`gh auth status` 哪個**涵蓋此 host**（robust 偵測與實例見 [`references/preflight.md`](references/preflight.md)〈git host 偵測〉；勿只比 URL 字樣——自託管 GitLab 的 remote 常不含 `gitlab` 字樣）。
- base_branch：取 `git symbolic-ref refs/remotes/origin/HEAD`（取不到 → 偵測 develop／main／master）。
- 模擬器執行環境
  - Android `adb`＋`emulator`＋SDK
  - iOS `xcrun simctl` 可用即可
  - 實際裝置不需事先手動開——由 step 4「配 lane」跑 [`scripts/ensure-devices.sh`](scripts/ensure-devices.sh) 自動準備（查 pool→不足自建→開機），`lanes` 自動降到備妥數。
- 目標 locale：問使用者要測哪個語系（見 step 5 `capture_locale`）。
- build／test／pull 指令不在此解析 → 由 runner 於 capture 階段經 add-snapshot 取得後內部重用（fix/verify 階段共用）。
- **環境快檢（preflight，自動、每次 run、無 `--doctor` 旗標）**：解析完上述後，依 [`references/preflight.md`](references/preflight.md) 一次性 live 探測環境，把缺漏分 ❌硬缺／⚠️軟缺／❓可能缺 三段，列成**單一 checklist**：
  - 有任一 ❌硬缺 → 印 checklist + 每條一句「怎麼補」後**終止，不起跑**。
    - 平台測不出
    - 無模擬器執行環境或 ensure-devices 備妥 0 台
    - git host CLI 缺或未登入［`dry_run` 豁免］
    - 相依 skill·agent 缺
    - Android SDK 位置無法解析
  - 無硬缺 → 印 checklist（⚠️軟缺如裝置數<`lanes` 已自動降級；❓可能缺如 snapshot 測試 harness 靜態探不到、標「需人工確認」）後**續跑**。
  - ❓可能缺一律不擋
    - 靜態無法 100% 確定，擋了會誤殺命名不同的等價設定
    - 確定性留給首個 capture。零寫檔、維持無狀態。

#### 1. 決定目標畫面集 → 共享 queue

- 使用者指定畫面 → 就這些。
- 未指定 → 全部畫面：跑 bundled [`../screen-list`](../screen-list/SKILL.md) 全量列舉，依平台套對應規則，產 `screen-list.json` = 畫面宇宙（輸出落點覆寫到本 run 的 ephemeral 暫存目錄（step 3 建），不落 `.audit/`，維持無狀態）。
- manifest 即 work-stealing 的共享 queue。每筆的 `id` = 全程使用的 `unified_id`（claim 目錄／branch／截圖路徑都用它；單平台直接相等，monorepo 跨平台才加平台前綴）。

#### 2. 不建／不讀 ledger（無狀態）

已修過的畫面在 Phase 2 開 MR 前由 runner live 查 git host 判斷（見 orchestration.md §5.1）。

#### 3. 建 ephemeral run 目錄放暫存

temp／gitignored，run 結束即刪。

#### 4. 配 lane

Reference: orchestration.md §3–4

跑 [`scripts/ensure-devices.sh`](scripts/ensure-devices.sh) `--platform <P> --count <lanes> --prefix <device_prefix> --device-android <device_android> --device-ios <device_ios>`：查自管 `test_phone_NN` pool → 不足自建（指定機型不可用退本機最新；Android 無 avdmanager 走複製現有 AVD）→ 開機 → stdout 回報 ready serial/udid。不需事先手動開模擬器。

起 `lanes` 條 lane，每條綁定 1 台回報的裝置 + 1 個常駐 worktree，整 run 重用。

備妥不足 `lanes` → 降到備妥數並 log；備妥 0 台或硬缺 → 終止並印 script 給的「怎麼補」（不靜默縮水）。

#### 5. 參數預設

- `lanes`：`4` — 並行 lane 數；每條獨佔一台 emulator，從共享 queue work-stealing 認領畫面。
- `device_android`：`Pixel 8`
  - Android 自動建模擬器用的機型
  - 本機無此 profile 或無 avdmanager → 退用本機最新 Pixel／複製現有 AVD。
- `device_ios`：`iPhone 16`
  - iOS 自動建模擬器用的機型
  - 本機無此機型 → 退用本機最新 iPhone。
- `device_prefix`：`test_phone_`
  - 自管裝置 pool 命名前綴（`test_phone_01`、`test_phone_02`…）
  - 已存在重用、不夠才補建
  - run 結束關機保留 profile
- `capture_locale`：run 起手問使用者要測哪個目標語系
  - repo 只支援單一語系 → 直接用、不必問
  - 多語系 → 必問
  - 原因：「哪個 locale 最該測跑版」是當下判斷，交使用者決定。
- `string_fix_policy`：顯式 run 參數，不可由 orchestrator 默默推斷
  - 只有兩值，決定本 run 能否用「改字串值（含縮短文案）」這條修法：
    - `local-resource`（預設）：改本地資源檔（`values-<locale>/strings.xml`、`Localizable.strings`）。
    - `disabled`：本 run 不改任何字串。
  - 鐵則：採 `disabled` 等於關閉 §3 優先序第 1 順位（縮短文案）
    - 起手必須問使用者、或明確預設並告知
    - 因此無法乾淨修的 in-scope 缺陷一律標 `deferred:deferred-by-run-config`
    - 詳情見 [`issue-schemas`](references/issue-schemas.md) §2/§3。
- `extra_audit_locales`：`[]` — opt-in 多語系翻譯正確性檢查。
- `neighborhood_regression`：`true`。
- `dry_run`：`false`
  - 此為試跑模式
  - 照常跑 capture→audit→fix→review→verify
  - **不 push production branch、不開 MR**
  - 每畫面把 patch落本 run 目錄，包含以下內容
    - `git format-patch <base>..HEAD`
    - before/after 截圖
    - `proposed-mr.md`，schema 同 [`issue-schemas`](references/issue-schemas.md) §4
  - run 結束**不刪** run 目錄、回報其路徑（lane worktree 照清）。觸發：`/screen-mender --dry-run [畫面...]`、「試跑 screen-mender」「先別開 MR、給我看會怎麼改」。
- `trace`：`false`
  - 是否要記錄 skill 分析數據
  - 設為 true 時， final summary 附上以下資訊
    - 每畫面逐階段耗時
    - build 次數的完整 breakdown
  - 觀測機制見 [`orchestration`](references/orchestration.md) §7
  - 觸發：`/screen-mender --trace ...`、「想看它各階段花多久」。

#### 6. 起跑確認

起跑時，當以下條件滿足時，需要向使用者告知後續行為：
- `dry_run=true`
  - 一句告知「dry-run：不會開 MR，產物將落 `<run_dir>`」後進 Phase 1。
- `dry_run=false` 且目標畫面數 > 1
  - 起跑前明確等使用者確認一次：「即將處理 N 個畫面，最多開 N 個小 MR（draft）＋ push N 條 branch 到 `<base_branch>`；繼續？（或加 `--dry-run` 只看不開）」
  - 使用者已明確要求「直接跑」／帶 `--yes` → 跳過。

### Phase 1：認領下一個畫面 + 派 runner（原子）

每條空閒 lane 從共享 queue 原子認領下一個未認領畫面，並**在同一輪**就把 runner spawn 出去（原子認領鐵則，見 orchestration.md §3）。

1. **認領**：`mkdir <claim_dir>/<unified_id>/`（atomic 搶占）。
   - 挑選：優先挑與本 lane worktree 當前 branch 同 module 者，減少 branch churn。
   - 認不到任何未認領畫面 → 本 lane 收工；所有 lane 都收工 → 跳 Phase 3。
2. **切 branch**：在本 lane 常駐 worktree `checkout -b <feature_branch_prefix><unified_id>`（不新建／不 clean worktree → 增量編譯；做法見 orchestration.md §4）。
3. **spawn runner（背景）**：**同一輪**立刻 spawn 一個 [`screen-mender-runner`](../../agents/screen-mender-runner.md)（`run_in_background`），傳入 Phase 2 列的 prompt 欄位。
   - 鐵則：認領與 spawn 必須同一輪 tool-call 完成，不可只 `mkdir`／敘述「已認領、待會派」卻漏掉 spawn。

### Phase 2：runner 跑完整畫面閉環（背景）

runner 獨力執行單一畫面的修復，完成後會回一段精簡 summary。
orchestrator 對本畫面只做三件事：
- 傳對 prompt 欄位
- 收 summary
- 發通知 + 釋放 lane

全程不碰截圖／issues／diff／build log

#### 傳給 runner 的 prompt 欄位

orchestrator 已知值轉傳，runner 不讀設定檔
- `run_dir`、`unified_id`、`platform`
- `worktree`、`branch`、`feature_branch_prefix`、`repo_canonical_path`
- `device_serial`（本 lane 獨佔）
- `base_branch`、`mr_tool`
- `capture_locale`、`extra_audit_locales`
- `string_fix_policy`、`dry_run`
- `ui_framework_pref`（自動偵測 compose|swiftui）、`iterate_max`（2）、`internal_loop_max_rounds`（3）
- `snapshot_test_cmd` / `build_cmd`（已知則預填，否則 runner 於 capture 經 add-snapshot 取得）
- `neighborhood_test_cmds`（`neighborhood_regression=true` 時帶：與本 `unified_id` 同 module／feature、且 base 已有 snapshot test 的鄰域畫面測試指令；無鄰域 → 不帶）
- `fidelity_reference`（選用：同元件乾淨語系 render／既有乾淨截圖，供 verify 字形保真比對）

**收到 runner summary 後**（依 `status`，遵 [`issue-schemas`](references/issue-schemas.md) §4 狀態鐵則）：

- 發 milestone 通知一句（見〈對話節奏〉）：
  - `fully-fixed`：「畫面 `<unified_id>` 小 MR 已發（!x），修了 N 條視覺缺陷。」
  - `partially-fixed`：「畫面 `<unified_id>` 部分修復（!x）：N 條已修並驗證；M 條缺陷 after 圖仍可見、延後（<reason>）。」不得對殘留畫面單用「已修並驗證」。
  - `clean`：audit 0 條 → 無 MR，summary 列入。
  - `locked`／`defect`／`stuck`：列入 final summary backlog；`stuck` 且 `escalation` 非空 → 立刻打斷使用者。
  - `dry_run`：把「小 MR 已發（!x）」換成「試跑完成，產物 `<run_dir>/<unified_id>/`」；殘留語意照舊。
- `escalation` 非空（STUCK／AUDIT_PROBLEM／build 連敗 3 次／字串資源檔修改失敗）→ 打斷使用者、附 runner 給的卡點與建議。
- 釋放本 lane（claim 留著供對賬，worktree 留著續服務下一畫面）。
- **不追 merge** → 立刻回 Phase 1 認領下一畫面。

> 畫面狀態（`fully-fixed`／`partially-fixed`／`clean`）由 runner 在 stage 5 依「所有 kept+deferred 是否都解決」算定並寫進 MR；orchestrator 照 runner 的 status 轉述，不另判。verify PASS ≠ 整畫面乾淨。

### Phase 3：終止 + final summary

所有 lane 收工 → 回報一份 final summary。

- 呈現：口頭／對話呈現 + 寫一份到 ephemeral run 目錄；不留 .audit。
- 內容：各畫面狀態（`fully-fixed`／`partially-fixed (n fixed, m deferred-visible)`／`clean`／locked／defect／stuck）+ MR 連結（`dry_run` → 改列 `<run_dir>/<unified_id>/proposed-mr.md` 路徑）。`partially-fixed` 要列殘留可見缺陷與原因（`needs-design`／`deferred-by-run-config`）。
- 觀測（每畫面）：附一行 compact 耗時 `capture <a>s · audit <b>s · fix <c>s/<k> builds (<r> rounds) · verify <d>s`（資料來自各 runner summary 的 `timing`），並點出本 run 最慢階段與 build 次數最高的畫面（=最該優化處）；`trace=true` → 改出完整逐階段 breakdown（見 [`orchestration`](references/orchestration.md) §7）。
- capture 保真度旗標：列出本 run 有 `font-fidelity-degraded`／`representative-render`／`capture-nondeterministic`／`locale-unverifiable` 的畫面（這類「乾淨」或「已修」可能是 capture 不忠於真機造成的假象；`locale-unverifiable` 另列「需真機抽驗」清單）。
- run-config 揭露：明示本 run 的 `string_fix_policy` 與 `dry_run`；若 `string_fix_policy` 關閉了「縮文案」這條修法，列出因此 `deferred-by-run-config` 的缺陷。`dry_run` 時明示「本 run 未開任何 MR，產物在 `<run_dir>`」。
- 收尾：清掉所有 lane worktree + `claim_dir`；跑 [`scripts/ensure-devices.sh`](scripts/ensure-devices.sh) `--teardown --platform <P>` 關機所有自管 `test_phone_NN`（保留 profile 供下次重用、只動 pool 不碰其他裝置）；已 merge 的 branch 清除；ephemeral run 目錄刪除（`dry_run` 例外：run 目錄保留並回報路徑，見 orchestration §5.6）。

## 參考

- **問題 schema／triage／安全約束** → [`references/issue-schemas.md`](references/issue-schemas.md)：§4 issues.md／MR schema、§2 triage（kept／deferred／wont-fix）、§3 修復安全約束（T1 自由／T2 結構改動須證視覺等價／R 重設計禁／overflow 修法優先序／字串值依 `string_fix_policy` 且永不 hardcode）。runner 的 audit／fix／review／verify 階段皆依此。
- **編排紀律** → [`references/orchestration.md`](references/orchestration.md)：§1 delegate、§2 無 watchdog、§3–4 lane／認領／worktree、§5 MR／截圖上傳、§6 內部 loop 上限、§7 觀測。
- **runner agent** → [`../../agents/screen-mender-runner.md`](../../agents/screen-mender-runner.md) 與 [`../../agents/references/`](../../agents/references/) 的 6 個階段 prompt。

## 操作須知

### 觸發指令

- `/screen-mender` — 掃全部畫面、逐畫面修。
- `/screen-mender <畫面...>` — 只掃指定畫面。
- `/screen-mender --dry-run [畫面...]` — 試跑：照常偵測+修+驗，但不開 MR，產物落 run 目錄供檢視。
- 自然語言：「跑 screen-mender」「逐畫面修視覺跑版」「一畫面一個小 MR 修 UI」；試跑：「試跑 screen-mender」「先別開 MR、給我看會怎麼改」。

### 對話節奏

main session 輸出嚴格限縮在 milestone：

1. 開頭一句：「開始 screen-mender；待檢查畫面 N 個（全部／指定）。」
2. 每畫面 runner 回 summary 後一句（Phase 2）：小 MR 已發 + 修了幾條 + 連結；有殘留可見缺陷時標「部分修復」並點出殘留（不得單用「已修」）。
3. 終止一份 final summary。

只有以下情況才打斷使用者（一律由 runner return 的 `escalation` 帶上來）：

- 截圖 build／capture 連續失敗 ≥ 3 次（同畫面）。
- reviewer AUDIT_PROBLEM／fix STUCK／內部 loop 超 `internal_loop_max_rounds` 未過。
- 字串資源檔修改失敗（找不到對應 key／寫入失敗）。

### 冪等 / 中斷

- 冪等：runner 在 stage 5 開 MR 前 live 查 git host——該畫面 branch 已有 open MR → 跳過；已 merge 過且當前無新缺陷 → audit 0 條自然略過。
- 中斷：無狀態 → 下次 run 重跑；同畫面 runner idempotent（worktree 增量 + MR 冪等 live 查）→ 不會重複發 MR。
- claim↔live-runner 對賬：orchestrator 被完成通知喚醒、或讓 lane 收工前，對照 `claim_dir` 與 live runner；有 claim 卻無對應 live runner = 漏派，立即補 spawn（事件驅動，非 watchdog；見 orchestration.md §3）。

### 失敗模式

- 相依 skill（add-snapshot／shot-audit／screen-list）或 runner agent 缺失 → Phase 0 preflight 即列為 ❌硬缺、印 checklist 後終止（見 [`references/preflight.md`](references/preflight.md)），不留到起動後才反應式爆出。其餘環境硬缺（無裝置／git CLI 未登入／Android SDK 測不到）亦同階段一次攔下。
- manifest 列舉失敗 → 上報「screen-list 未產出 `screen-list.json`」。
- 某畫面卡 locked／defect／stuck → 不阻塞整 run，列入 summary backlog、續下一畫面。
- 全部畫面 locked／defect／clean、零可修 → final summary 標 `nothing-to-fix`。
