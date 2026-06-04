---
name: screen-mender
description: >-
  逐畫面修復「截圖看得見的視覺缺陷」，雙平台（iOS / Android 由 repo 檔案特徵自動偵測、零設定檔）。以單一畫面為原子單位跑完整閉環：確保截圖 test → 出截圖 → 偵測缺陷 + triage + 附 AC → 自驅 developer/reviewer/verifier 修好 → 發一個小 MR（含 before/after 截圖）→ 下一畫面。一個 MR = 一個畫面被完整修復；多畫面靠 N 條 lane（各獨佔一台裝置）work-stealing 並行。唯一人工點 = PR 把關。

  觸發：「跑 screen-mender」「逐畫面修視覺跑版」「一畫面一個小 MR 修 UI」「把這個 App 的畫面一個個修好」；只在明確要求「逐畫面修復閉環」時觸發。

  不要走本 skill：只列「該建截圖測試的畫面清單」走 screen-list、只找單張截圖問題走 shot-audit。
---

# screen-mender

逐畫面修復「截圖看得見的視覺缺陷」。一個畫面 = 一個原子修復單元 = 一個小 MR；雙平台、零設定、無狀態；唯一人工點是 PR 把關。

## 核心模型

每個畫面獨立跑完整閉環，一個畫面對應一個 MR；多畫面靠 N 條 lane（各佔一台裝置）work-stealing 並行；發 MR 即往下、不追 merge、不被人工 merge 速度鎖死。

```
從共享 queue（全部目標畫面，或使用者指定的子集）原子認領下一個畫面
  → 在本 lane 的常駐 worktree 內，確保有截圖 test（沒有就建）→ 出截圖（C1–C5 渲染標準閘）
  → audit 偵測該畫面「所有」截圖看得見的視覺缺陷 + triage（real vs wont-fix）+ 附 AC
  → 自驅 developer→reviewer→verifier 修好「全部」（developer 在真 render 上有界迭代；worktree 增量編譯、不 clean）
  → 發一個小 MR：修了什麼 + before/after 截圖全寫在 MR 上
  → 通知使用者一句，立刻回去認領下一個畫面（不追 merge）↺
```

## 運作原則

- **只修截圖看得見的缺陷** — 偵測（shot-audit）與驗收（verifier 比 after 圖）都靠截圖，範圍 = 截斷／爆框／重疊／錯位／譯文壞／locale 格式錯／對比不可讀。截圖看不見的（如缺 a11y label / `contentDescription`）不在範圍，route 去專屬 a11y pass。完整類別見 [`issue-schemas`](references/issue-schemas.md)。
- **雙平台、零設定** — 單次 run 鎖定一個平台，由 git repo 檔案特徵自動偵測（Phase 0），無 profile 設定檔；會隨 App 變的值（repo 路徑／build／test／pull／device／git host／base branch／locale／字串落點）起手自動解析。同資料夾並列兩 repo 各自偵測互不干擾。下文「emulator」在 iOS repo 即 simulator。
- **無狀態** — 不留任何本地紀錄檔；「這畫面修過沒」每次 live 查 git host（merged／open MR）。因為 develop 一直在動、視覺缺陷會回歸，每跑必查才正確。
- **MR 是唯一 SSOT** — 修了什麼、before/after 截圖、考慮過但不修的理由，全寫在 MR 。 run 期間暫存放 ephemeral run 目錄（temp／gitignored），run 結束即刪。
- **不重造輪子** — capture 借 add-snapshot、列舉借 screen-list、單圖偵測借 shot-audit；本 skill 只加 per-screen 迴圈、audit 階段併 triage+AC、per-lane worktree 重用、work-stealing 認領、MR 即紀錄，和三個專屬 agent。無 planner——修法推理由 developer 在真 render 上迭代決定。
- **全部委派、不輪詢（無 watchdog）** — orchestrator（main session）只做配 lane／派工／整合／開 MR；改 code／build／test／截圖一律背景 sub-agent（`run_in_background`），完成由 harness 通知驅動，不做 ScheduleWakeup 輪詢、不寫 heartbeat 檔。agent 端只保留 self-abort（連錯 3 次 → return 回報 stuck）；互動觸發、使用者在線即 backstop。細節見 orchestration.md §1–2。
- **lane 並行 + 常駐 worktree** — N 條 lane 各佔一台裝置，從共享 queue work-stealing 認領畫面；每條 worktree 整 run 重用、逐畫面換 branch、絕不 clean／重建 → 第 2+ 畫面走增量編譯（不用 gradle build-cache，對本類 app 無益）。每 lane 獨佔裝置 → 無跨-lane 裝置鎖（lane 內 capture／verify 本就序列，不需互斥鎖）。細節見 orchestration.md §3–4。
- **唯一人工點 = PR 把關** — 偵測→修→發 MR 全自動，不設修前 issue 閘；使用者只在每個 per-screen 小 MR 上審 diff + 前後截圖。
- **production 只在修復階段動** — capture 階段 0-production-diff；真正的修復走 sub-agent 改 production、產 reviewed MR、使用者 gate。

## 使用與自建

使用既有 sibling skill：

- capture: [`../add-snapshot`](../add-snapshot/SKILL.md)
- 畫面列舉: [`../screen-list`](../screen-list/SKILL.md)
- 單圖偵測: [`../shot-audit`](../shot-audit/SKILL.md)
- triage / schema / 安全約束走自帶 [`references/issue-schemas.md`](references/issue-schemas.md)

screen-mender 需要自已負責：
- per-screen 迴圈
- audit 階段在 shot-audit 偵測結果上並且 triage+AC
- per-lane worktree 重用
- work-stealing 認領
- MR 即紀錄
- 驅動三個專屬 agent

### 三個專屬 agent

收窄到「單畫面視覺缺陷修復」：

**[`screen-mender-developer`](../../agents/screen-mender-developer.md)**

- 職責：讀 audit 的 kept issues（含 AC），自己反查 code、選修法，在真 render 上有界迭代（推論→改→render→比 AC→不行升級重修，上限 2）；字串值依 `string_fix_policy`；commit + push。
- 守則：守 outcome（修好缺陷 + 畫面其餘視覺等價 + 不重設計）；修法依 §3 優先序（縮文案 > 長高 > modifier > 字級縮放末位），return 逐一交代為何跳過更高順位；放寬換行／maxLines 必同時接住多行對齊；禁 R 重設計、不交「換位置」假修復。

**[`screen-mender-reviewer`](../../agents/screen-mender-reviewer.md)**

- 職責：審 diff 兩判——(1) scope：只改 kept 缺陷無越界；(2) redesign：是修復（長一樣）還是重設計（長不一樣）。判定 PASS / NEEDS_CHANGES / AUDIT_PROBLEM。
- 守則：NEEDS_CHANGES → 回 developer，最多 3 輪。

**[`screen-mender-verifier`](../../agents/screen-mender-verifier.md)**

- 職責：預設判 developer 的 after-shot（snapshot test 確定性 → 不重跑）——逐條比 AC、目標區正確性（改完是否視覺正確、與兄弟元素對齊一致）、同畫面視覺等價掃描（非目標處有無被波及）、鄰域 regression；帶 `spot_check` 才重跑抽驗。
- 守則：PASS = 被修的那幾條 AC 達成 + 視覺等價（≠ 整畫面乾淨）；對齊類缺陷量相關軸（對齊量水平）；獨立回報殘留可見缺陷；附可量證據；fail → 回 developer。

## 流程

### Phase 0：bootstrap（無狀態）

#### 0. 解析環境（零設定，無 profile）

- 平台偵測：當前 git repo（`git rev-parse --show-toplevel`）有 `gradlew`／`*.gradle*` → Android；有 `*.xcodeproj`／`*.xcworkspace`／`Podfile` → iOS；兩者皆無 → 上報「無法判定平台」並終止。
- repo 路徑 = git toplevel（worktree／鎖目錄皆相對於此）。
- git host／mr_tool：取 remote host → 含 `gitlab`/`github` 字樣直接判；自託管（host 是 IP／公司域名、無字樣）則看 `glab auth status`／`gh auth status` 哪個**涵蓋此 host**（robust 偵測與實例見 [`references/preflight.md`](references/preflight.md)〈git host 偵測〉；勿只比 URL 字樣——自託管 GitLab 的 remote 常不含 `gitlab` 字樣）。
- base_branch：取 `git symbolic-ref refs/remotes/origin/HEAD`（取不到 → 偵測 develop／main／master）。
- 模擬器執行環境：Android `adb`＋`emulator`＋SDK／iOS `xcrun simctl` 可用即可；實際裝置不需事先手動開——由 step 4「配 lane」跑 [`scripts/ensure-devices.sh`](scripts/ensure-devices.sh) 自動準備（查 pool→不足自建→開機），`lanes` 自動降到備妥數。
- 目標 locale：問使用者要測哪個語系（見 step 5 `capture_locale`）。
- build／test／pull 指令不在此解析 → 由 add-snapshot 於 Phase 2 capture 回報後轉傳 developer／verifier。
- **環境快檢（preflight，自動、每次 run、無 `--doctor` 旗標）**：解析完上述後，依 [`references/preflight.md`](references/preflight.md) 一次性 live 探測環境，把缺漏分 ❌硬缺／⚠️軟缺／❓可能缺 三段，列成**單一 checklist**：
  - 有任一 ❌硬缺（平台測不出／無模擬器執行環境或 ensure-devices 備妥 0 台／git host CLI 缺或未登入［`dry_run` 豁免］／相依 skill·agent 缺／Android SDK 位置無法解析）→ 印 checklist + 每條一句「怎麼補」後**終止，不起跑**。
  - 無硬缺 → 印 checklist（⚠️軟缺如裝置數<`lanes` 已自動降級；❓可能缺如 snapshot 測試 harness 靜態探不到、標「需人工確認」）後**續跑**。
  - ❓可能缺一律不擋（靜態無法 100% 確定，擋了會誤殺命名不同的等價設定）；確定性留給首個 capture。零寫檔、維持無狀態。

#### 1. 決定目標畫面集 → 共享 queue

- 使用者指定畫面 → 就這些。
- 未指定 → 全部畫面：跑 bundled [`../screen-list`](../screen-list/SKILL.md) 全量列舉，依平台套對應規則，產 `screen-list.json` = 畫面宇宙（輸出落點覆寫到本 run 的 ephemeral 暫存目錄（step 3 建），不落 `.audit/`，維持無狀態）。
- manifest 即 work-stealing 的共享 queue。每筆的 `id` = 全程使用的 `unified_id`（claim 目錄／branch／截圖路徑都用它；單平台直接相等，monorepo 跨平台才加平台前綴）。

#### 2. 不建／不讀 ledger（無狀態）

已修過的畫面在 Phase 4 開 MR 前靠 live 查 git host 判斷（見 orchestration.md §5.1）。

#### 3. 建 ephemeral run 目錄放暫存

temp／gitignored，run 結束即刪。

#### 4. 配 lane

Reference: orchestration.md §3–4

跑 [`scripts/ensure-devices.sh`](scripts/ensure-devices.sh) `--platform <P> --count <lanes> --prefix <device_prefix> --device-android <device_android> --device-ios <device_ios>`：查自管 `test_phone_NN` pool → 不足自建（指定機型不可用退本機最新；Android 無 avdmanager 走複製現有 AVD）→ 開機 → stdout 回報 ready serial/udid。不需事先手動開模擬器。

起 `lanes` 條 lane（預設 4，自動降到 ensure-devices 備妥的裝置數），每條綁定 1 台回報的裝置 + 1 個常駐 worktree，整 run 重用。

備妥不足 `lanes` → 降到備妥數並 log；備妥 0 台或硬缺 → 終止並印 script 給的「怎麼補」（不靜默縮水）。

#### 5. 參數預設

- `lanes`：`4` — 並行 lane 數；每條獨佔一台 emulator，從共享 queue work-stealing 認領畫面。
- `device_android`：`Pixel 8` — Android 自動建模擬器用的機型；本機無此 profile 或無 avdmanager → 退用本機最新 Pixel／複製現有 AVD。
- `device_ios`：`iPhone 16` — iOS 自動建模擬器用的機型；本機無此機型 → 退用本機最新 iPhone。
- `device_prefix`：`test_phone_` — 自管裝置 pool 命名前綴（`test_phone_01`、`test_phone_02`…）；已存在重用、不夠才補建；run 結束關機保留 profile。
- `capture_locale`：run 起手問使用者要測哪個目標語系（不預設、不寫設定檔）。repo 只支援單一語系 → 直接用、不必問；多語系 → 必問。原因：「哪個 locale 最該測跑版」是當下判斷，交使用者決定。
- `string_fix_policy`：**顯式 run 參數，不可由 orchestrator 默默推斷**。只有兩值，決定本 run 能否用「改字串值（含縮短文案）」這條修法：
  - `local-resource`（預設）：改本地資源檔（`values-<locale>/strings.xml`、`Localizable.strings`）。
  - `disabled`：本 run 不改任何字串。
  - 字串非本地資源檔可改的專案（由專案自身決定）：在自身 rule/CLAUDE.md 設 `disabled` 並自理修法流程——plugin 不內建任何專案專屬的字串機制（零專案 lore）。
  - 鐵則：採 `disabled` 等於關閉 §3 優先序第 1 順位（縮短文案）。起手必須問使用者、或明確預設並告知；因此無法乾淨修的 in-scope 缺陷一律標 `deferred:deferred-by-run-config`（不得偽裝成 needs-design、不得默默改用縮字級）。見 [`issue-schemas`](references/issue-schemas.md) §2/§3。
- `extra_audit_locales`：`[]` — opt-in 多語系翻譯正確性檢查。
- `neighborhood_regression`：`true`。
- `dry_run`：`false` — 試跑模式。照常跑 capture→audit→fix→verify（含 reviewer/verifier），但**不 push production branch、不開 MR**。每畫面把 patch（`git format-patch <base>..HEAD`）＋ before/after 截圖 ＋ 會寫進 MR 的內容（`proposed-mr.md`，schema 同 [`issue-schemas`](references/issue-schemas.md) §4）落本 run 目錄；run 結束**不刪 run 目錄**、回報其路徑（lane worktree 照清）。觸發：`/screen-mender --dry-run [畫面...]`、「試跑 screen-mender」「先別開 MR、給我看會怎麼改」。
- `trace`：`false` — true → final summary 附每畫面逐階段耗時 + build 次數的完整 breakdown（預設只附 compact 一行）。觀測機制見 [`orchestration`](references/orchestration.md) §7。觸發：`/screen-mender --trace ...`、「想看它各階段花多久」。

#### 6. 起跑確認

- `dry_run=true` → 不開任何 MR：一句告知「dry-run：不會開 MR，產物將落 `<run_dir>`」後進 Phase 1。
- `dry_run=false` 且目標畫面數 > 1（掃全部或多個指定畫面）→ 起跑前明確等使用者確認一次：「即將處理 N 個畫面，最多開 N 個小 MR（draft）＋ push N 條 branch 到 `<base_branch>`；繼續？（或加 `--dry-run` 只看不開）」。使用者已明確要求「直接跑」／帶 `--yes` → 跳過。
- 單一明確指定畫面（N==1）→ 視為明確意圖，免閘。

### Phase 1：認領下一個畫面

每條空閒 lane 從共享 queue 原子認領下一個未認領畫面。

- 做法：`mkdir <claim_dir>/<unified_id>/`（見 orchestration.md §3）。
- 挑選：優先挑與本 lane worktree 當前 branch 同 module 者，減少 branch churn。
- 該 lane 認不到任何未認領畫面 → 本 lane 收工。
- 所有 lane 都收工 → 跳 Phase 5。

### Phase 2：確保截圖 test + 出截圖

#### 1. 出截圖（在本 lane worktree 內，已是某 branch）

- 該畫面 snapshot test
  - 已存在：重用並且直接重跑出最新截圖。
  - 不存在：派 subagent 走 `add-snapshot` 在 worktree 內建立 test 並出截圖（`capture_locale`）。test 隨修復一起進 MR。
- 截圖落點與命名（producer→consumer 對接，務必照走）：
  - add-snapshot 的 on-device 截圖檔名固定 `<snake>__<locale>.png`。
  - orchestrator 把它 pull 到 ephemeral run 目錄（pull 方式由 add-snapshot 於 capture 回報），改名成統一命名 `<platform>__<state>__<locale>.png`（落 ephemeral run 目錄，內建路徑）。
  - 不 pull 到 `.audit/`（無狀態）。
  - 單一 state → `state=default`；下游 issues.md／developer／verifier 都引用這個改名後的路徑。
- 條件式 UI 要種對 state（種最壞的真實內容）：
  - 缺陷只在特定 state 現形 → capture 必須種到「缺陷會現形」的 state variant。
  - 種子取最壞的真實內容：最長字串／最極端 state（caller-driven 文案則種真實呼叫點的最長訊息）。否則「乾淨」可能只是種子太短的假陰性。
  - 種錯拍不到、下游誤判已修；同畫面多風險 state → 各拍一張。
- 多 locale（opt-in）：`extra_audit_locales` 非空 → 對每個 extra locale 也各出一張截圖（同 add-snapshot，換 locale runtime arg；檔名以 `{{locale}}` 區分）。預設 `[]` → 只出 `capture_locale` 一張。

**2. C1–C5 渲染標準閘**（[`../add-snapshot`](../add-snapshot/SKILL.md) §6）：檔 >10KB、資料區非空、locale 正確、無 fallback 字串、無 crash／空白。

- capture 保真度旗標（須在報告標明，不可靜默）：
  - 字型保真度降級：自訂字型未註冊、fallback 到系統字型 → 系統字型通常較寬（偏保守），會遮蔽字型專屬的爆框 → 標 `font-fidelity-degraded`。
  - representative／非 live 渲染：以重建的代表性 chrome（非 live 控制器）出圖 → 忠於 SSOT 但屬合成 → 標 `representative-render`，避免被當作 live 行為背書。
  - 非確定性 capture：內容隨機（`.shuffled()`／無 seed）、async 狀態、字型間歇 fallback 會讓 before/after 因與修復無關的原因不同。**同 state 連拍兩張比對**，不一致 → seed 固定它，seed 不了則標 `capture-nondeterministic`（類 locked、不出 before/after）。見 [`issue-schemas`](references/issue-schemas.md) §3.5。
  - locale 未完整套用：harness 只換 app 字串、沒換 `Locale.current`／`Calendar.current`／asset `preferredLocalizations` → 日期/數字/週幾/在地化圖仍顯模擬器語系 → 標 `locale-unverifiable`，相關缺陷轉人工/真機，不得當 false-positive（§3.5）。
- 通過 → 截圖落 ephemeral run 目錄，進 Phase 3。
- 渲染不出（需 production seam）→ 標 locked；一渲染就 crash → 標 defect。兩者都在 final summary 列入 backlog 回報使用者（不寫 .audit 檔）、回 Phase 1 取下一個。
- retry 上限後仍 fail（暫時性）→ 記入 summary、回 Phase 1。

### Phase 3：audit

派 sub-agent 走 bundled [`../shot-audit`](../shot-audit/SKILL.md) 偵測本畫面 shots。shot-audit 只產「問題 + 描述 + 調整建議」、不做 triage／AC（刻意精簡），故 triage + 附 AC 由本階段在同一個 sub-agent prompt 內補上。派工 prompt 必須明確（shot-audit skill 本體不改）：

**1. 偵測** — 走 shot-audit 偵測本畫面所有截圖看得見的視覺缺陷（含描述 + 調整建議）。帶 `layout_stress_locale = capture_locale` + 兄弟畫面參考。

- 多 locale（`extra_audit_locales` 非空）：對每個 extra locale 的截圖也跑 shot-audit，重點查翻譯正確性／locale 格式（`translation-broken`／`locale-format`）。

**2. triage**（screen-mender 加的，非 shot-audit 職責） — 依 [`issue-schemas`](references/issue-schemas.md) §2 對每條標 `kept`／`deferred:<reason>`／`wont-fix:<reason>`。

- `wont-fix`（非該修的視覺缺陷）：known-intended／design-redesign 無證據／false-positive／non-visual a11y… → 列 MR「考慮過但不修」段。
- `deferred`（真缺陷、本 run 不修）：`needs-design`（修法需設計拍板）／`deferred-by-run-config`（修法已知、被 run-config 關閉，如 `string_fix_policy` 不允許改字串）→ after 圖仍可見、列殘留可見、畫面降 partially-fixed，不得偽裝成已修或與 needs-design 混用。

**3. 附 AC** — 對每條 `kept` 附一行可驗 AC（verifier 會逐條比對）。

- 換行／放寬 maxLines／改寬度類修法的 AC 必含對齊條款（如「多行後仍與兄弟元素同樣置中」）。偵測到「靠父層 alignment 置中、元素無自身 textAlign」結構 → 主動把「一換行就破置中」列為風險寫進 AC（見 [`issue-schemas`](references/issue-schemas.md) §3/§4）。

**4. 輸出** — 落 ephemeral run 目錄的 `issues.md`（schema 見 issue-schemas §4）；不要寫 `.audit/screens/` 持久知識庫。原因：shot-audit 本就無狀態；screen-mender 也無狀態。

收尾判斷：

- `kept` 條數 = 0（全乾淨或全 triage 掉）→ 本畫面無 MR → 回 Phase 1。
- 有 `kept` → 進 Phase 4。
- 結構性、需設計決策的缺陷無設計來源證據 → 標 `wont-fix:design-redesign-not-bug`（不是 bug）或 `deferred:needs-design`（是 bug、修法需設計），列入 summary 回報，不靜默吞。
- 「乾淨」的計算對象 = 所有 kept + deferred 缺陷，不是「我選去修的那幾條」（見 Phase 5 畫面狀態）。

### Phase 4：fix

screen-mender 自當此畫面的 mini-orchestrator（沿用 [`orchestration`](references/orchestration.md)，只跑這一畫面）：

1. **lane worktree** — 該畫面已在本 lane 常駐 worktree（branch = `<feature_branch_prefix><unified_id>`）。不新建／不 clean，build 走增量。
2. **MR 冪等** — 先 live 查 `<mr_tool> mr list`，該 branch 已有 open MR → 跳過。`dry_run` → 無 MR 概念，略過本步。
3. **developer（背景）** — `screen-mender-developer` 讀 `issues.md` 的 kept 條（含 AC），自己選修法、在真 render 上有界迭代（≤2）。orchestrator 傳入 `string_fix_policy`（Phase 0）＋ `dry_run`（true → developer 只 commit、不 push）。
   - 迭代：推論→改→build+render→比 AC + 看其餘有無被波及→沒真修好就升級重修；commit + push。
   - 修法依 §3 優先序（縮文案 > 長高 > modifier > 字級縮放末位）；return 逐一交代為何跳過更高順位。字級縮放比例 < ~0.85 → 標 `legibility-degraded`。
   - 回報：return 每條 tier／before→after／AC 達成 + after 圖路徑。
   - developer return 標 `deferred` 的條（`needs-design` 須設計拍板／`deferred-by-run-config` 被 run-config 關閉）→ 不修、列入本 MR 殘留可見段（最顯眼處），畫面降 `partially-fixed`。
   - 該畫面全部 kept 都 `deferred`／`STUCK` → 無乾淨 MR；仍據實標狀態、列 final summary backlog 回報。
4. **MR（或 dry-run 產物）**
   - `dry_run=false`：precheck rebase 後開一個 MR（一畫面一個）。description 含：修了哪些缺陷（file:line + 修法）／考慮過但不修（reason）／內嵌 before/after 截圖（`POST /projects/:id/uploads`，見 orchestration.md §5.3）。
   - `dry_run=true`：不 rebase、不開 MR。orchestrator 從 lane worktree 取 `git format-patch <base_branch>..HEAD --stdout` 落 `<run_dir>/<unified_id>/change.patch`，複製 before/after 截圖，並把同 §5.3／issue-schemas §4 的 MR description 寫成 `<run_dir>/<unified_id>/proposed-mr.md`（截圖改引本地相對路徑，不上傳）。
5. **reviewer（背景）** — 審 diff 兩判（scope／redesign）；NEEDS_CHANGES → 回 developer，最多 3 輪；AUDIT_PROBLEM → 上報使用者。`dry_run` → `diff_cmd` 改用 `git -C <worktree> diff <base_branch>`（無 MR diff）。
6. **verifier（背景）** — 預設判 developer 的 after-shot（不重跑），逐條比 AC + 目標區正確性（含對齊一致性）+ 同畫面視覺等價掃描 + `neighborhood_regression`；可帶 `spot_check` 抽驗重跑；fail → 回 developer。
   - 派工紀律（不可劇透 + 豁免）：verifier prompt 只給 AC + before/after + 哪裡是目標區；不得預先宣告「哪些變化可接受／不要 flag」（如「標題會變 2 行、別管 reflow」）——那等於叫它別看會出錯的地方。最多標示目標區位置，不附「所以不用看」。
   - deferred 缺陷仍須回報可見性：即使某缺陷被標 deferred，verifier 仍須獨立回報「after 圖中哪些 kept／deferred 缺陷仍可見」，不得因 deferred 就從視野消失（orchestrator 據此定畫面狀態）。
   - 鄰域怎麼算（`neighborhood_regression=true` 時）：orchestrator 取與本 `unified_id` 同 module／feature、且 base 已有 snapshot test 的畫面為鄰域，把它們的 snapshot test 指令當 `neighborhood_test_cmds` 傳給 verifier；無鄰域 → 不帶，verifier 略過鄰域檢查。
   - spot_check 時：orchestrator 另傳本 lane `device_serial` + `snapshot_test_cmd`（verifier 用本 lane emulator 重跑，不另取鎖）。
   - 渲染保真（developer return 標 `render_reimplemented`，或 reviewer 提示自訂繪製改動）：orchestrator 另出**乾淨參照** `fidelity_reference` 傳給 verifier——同元件其他短語系（如 base locale zh）的 render，或既有乾淨截圖；供 Step 3.5 逐字比對字形保真（before 壞掉時不能當基準）。拿不到 → verifier 標 `fidelity-unverifiable`、不得逕判 PASS。
7. **判定 + 畫面狀態** — reviewer PASS + verifier（AC + 視覺等價 + 無 regression）PASS → `<mr_tool> mr update <id> --ready`（`dry_run` → 不轉 ready，僅在 `proposed-mr.md` 標 `would-be-ready`）。
   - verifier PASS 的語意 = 「被修的那幾條 AC 達成且視覺正確／等價」，不等於「整個畫面乾淨」。畫面狀態另算（下條）。
   - 畫面狀態 = 由「所有 kept+deferred 缺陷是否都已解決」計，不是「我選去修的那幾條是否過 verify」：`fully-fixed`（全解決）／`partially-fixed (n fixed, m deferred-visible)`（有 deferred 或 after 圖仍見殘留）／`clean`（audit 0 條）。
   - 誠實鐵則：after 圖只要還看得到缺陷，畫面就**不是 fully-fixed**，不論歸因（字型 fallback／Locale.current／洗牌）——降 partially-fixed＋殘留可見，或標 capture 不可信。修復正確性無法在 after 圖呈現者（改 native API 但 sim 仍顯舊值、before/after byte-identical）標 `code-verified／snapshot-unverifiable`，不報 fully-fixed（見 [`issue-schemas`](references/issue-schemas.md) §3.5）。
8. **通知使用者一句**（MR 標題用 [`issue-schemas`](references/issue-schemas.md) §4 固定模板 `自動跑版修復[（部分）]：<unified_id> - <原因摘要>`，下方對話通知遵同段狀態鐵則）：
   - 全解決：「畫面 `<unified_id>` 小 MR 已發（!x），修了 N 條視覺缺陷。」
   - 有殘留：「畫面 `<unified_id>` 部分修復（!x）：N 條已修並驗證；M 條已偵測缺陷 after 圖仍可見、延後（<deferred reason>）。」不得對殘留畫面單用「已修並驗證」。
   - `dry_run`：把上句的「小 MR 已發（!x）」換成「試跑完成，產物 `<run_dir>/<unified_id>/`」；殘留語意照舊。
9. **不追 merge** → 立刻回 Phase 1 認領下一畫面。

### Phase 5：終止 + final summary

所有 lane 收工 → 回報一份 final summary。

- 呈現：口頭／對話呈現 + 寫一份到 ephemeral run 目錄；不留 .audit。
- 內容：各畫面狀態（`fully-fixed`／`partially-fixed (n fixed, m deferred-visible)`／`clean`／locked／defect）+ MR 連結（`dry_run` → 改列 `<run_dir>/<unified_id>/proposed-mr.md` 路徑）。`partially-fixed` 要列殘留可見缺陷與原因（`needs-design`／`deferred-by-run-config`）。
- 觀測（每畫面）：附一行 compact 耗時 `capture <a>s · audit <b>s · fix <c>s/<k> builds (<r> rounds) · verify <d>s`，並點出本 run 最慢階段與 build 次數最高的畫面（=最該優化處）；`trace=true` → 改出完整逐階段 breakdown（見 [`orchestration`](references/orchestration.md) §7）。
- capture 保真度旗標：列出本 run 有 `font-fidelity-degraded`／`representative-render`／`capture-nondeterministic`／`locale-unverifiable` 的畫面（這類「乾淨」或「已修」可能是 capture 不忠於真機造成的假象；`locale-unverifiable` 另列「需真機抽驗」清單）。
- run-config 揭露：明示本 run 的 `string_fix_policy` 與 `dry_run`；若 `string_fix_policy` 關閉了「縮文案」這條修法，列出因此 `deferred-by-run-config` 的缺陷。`dry_run` 時明示「本 run 未開任何 MR，產物在 `<run_dir>`」。
- 收尾：清掉所有 lane worktree + `claim_dir`；跑 [`scripts/ensure-devices.sh`](scripts/ensure-devices.sh) `--teardown --platform <P>` 關機所有自管 `test_phone_NN`（保留 profile 供下次重用、只動 pool 不碰其他裝置）；已 merge 的 branch 清除；ephemeral run 目錄刪除（`dry_run` 例外：run 目錄保留並回報路徑，見 orchestration §5.6）。

## 參考

- **問題 schema／triage／安全約束** → [`references/issue-schemas.md`](references/issue-schemas.md)：§4 issues.md／MR schema、§2 triage（kept／deferred／wont-fix）、§3 修復安全約束（T1 自由／T2 結構改動須證視覺等價／R 重設計禁／overflow 修法優先序／字串值依 `string_fix_policy` 且永不 hardcode）。audit 派工 prompt 與 developer 皆依此。
- **編排紀律** → [`references/orchestration.md`](references/orchestration.md)：§1 delegate、§2 無 watchdog、§3–4 lane／認領／worktree、§5 MR／截圖上傳。

## 操作須知

### 觸發指令

- `/screen-mender` — 掃全部畫面、逐畫面修。
- `/screen-mender <畫面...>` — 只掃指定畫面。
- `/screen-mender --dry-run [畫面...]` — 試跑：照常偵測+修+驗，但不開 MR，產物落 run 目錄供檢視。
- 自然語言：「跑 screen-mender」「逐畫面修視覺跑版」「一畫面一個小 MR 修 UI」；試跑：「試跑 screen-mender」「先別開 MR、給我看會怎麼改」。

### 對話節奏

main session 輸出嚴格限縮在 milestone：

1. 開頭一句：「開始 screen-mender；待檢查畫面 N 個（全部／指定）。」
2. 每畫面發 MR 一句（Phase 4.8）：小 MR 已發 + 修了幾條 + 連結；有殘留可見缺陷時標「部分修復」並點出殘留（不得單用「已修」）。
3. 終止一份 final summary。

只有以下情況才打斷使用者：

- 截圖 build／capture 連續失敗 ≥ 3 次（同畫面）。
- reviewer AUDIT_PROBLEM／dev STUCK／內部 loop ≥ 3 輪未過。
- 字串資源檔修改失敗（找不到對應 key／寫入失敗）。
- agent return 回報 stuck（self-abort）。

### 冪等 / 中斷

- 冪等：開 MR 前 live 查 git host——該畫面 branch 已有 open MR → 跳過；已 merge 過且當前無新缺陷 → audit 0 條自然略過。
- 中斷：無狀態 → 下次 run 重跑；同畫面 sub-pipeline idempotent（worktree 增量 + MR 冪等 live 查）→ 不會重複發 MR。

### 失敗模式

- 相依 skill（add-snapshot／shot-audit／screen-list）或三個 agent 任一缺失 → Phase 0 preflight 即列為 ❌硬缺、印 checklist 後終止（見 [`references/preflight.md`](references/preflight.md)），不留到起動後才反應式爆出。其餘環境硬缺（無裝置／git CLI 未登入／Android SDK 測不到）亦同階段一次攔下。
- manifest 列舉失敗 → 上報「screen-list 未產出 `screen-list.json`」。
- 某畫面卡 locked／defect → 不阻塞整 run，列入 summary backlog、續下一畫面。
- 全部畫面 locked／defect／clean、零可修 → final summary 標 `nothing-to-fix`。
