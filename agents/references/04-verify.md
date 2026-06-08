# Stage 4 — 審查與驗證（self-review + self-verify）

- **一格兩判**：
  - 先審剛才這次修復的 **diff**（scope + redesign，便宜，先做）。
  - 再驗 after **截圖**（kept 每條 AC 真的達成、且畫面其餘部分沒被波及）。
- 任一不過即回 fix。
- 預設直接判 stage 3 產出的 after 截圖。
  - 原因：snapshot test 確定性 → 同 committed code 重跑必得同圖，故重跑對「修好沒」冗餘。

> 你是修的人，也是審＋驗的人。這一格刻意換上「審查者／驗收者」視角，照下面清單機械地查，**不為自己的修法放水**——範圍安全與視覺正確都靠這關。驗證部分凡判斷必附**可量證據**，不接受「看起來對齊」「應該沒問題」。

> 順序：先做 Step 0（審 diff）。scope 已越界／redesign 就 `NEEDS_CHANGES` 回 fix，不必再燒視覺驗證；Step 0 過了才往下做截圖驗證。

> 此前提僅在 capture 確定性成立時有效：若該畫面標 `capture-nondeterministic`／內容隨機／字型間歇 fallback，before/after 不可比，不得在其上判視覺等價 PASS（[`issue-schemas`](issue-schemas.md) §3.5）。

## Inputs
- diff：`git -C <worktree> diff <base_branch>`（本畫面尚未開 MR——MR 是 run 尾 integrator 統一開——故一律用 git diff）——Step 0 用。
- `issues.md` kept（含每條 AC，ground truth；只該改這些）。
- after 截圖（stage 3）+ before 截圖（stage 1，Step 3 視覺等價掃描必需）。
- `neighborhood_test_cmds`（選用）。

## Step 0 — 審 diff（scope + redesign）
- 先機械審這次修復的 diff，**不審程式美不美／命名／可否更簡潔**。
- 畫面其餘處的像素級等價交 Step 3。

### 判一：scope
- 每個 production 改動都對得上某條 kept issue 嗎？
- 有沒有沒列的「順手改／重構別處／改別畫面」？
- 字串值改動有走字串系統（非 hardcode）嗎？
- 有越界 / hardcode = `NEEDS_CHANGES`。
- 新增的 snapshot test / host 檔屬預期 scaffolding，不算越界。

### 判二：redesign
> 守 outcome，見 [`issue-schemas`](issue-schemas.md) §3

- 核心問句：diff 是讓畫面長一樣、只是結構更穩（T1/T2 修復，OK），還是讓畫面長得不一樣（R 重設計，擋）？
- R 重設計 = 增刪使用者看得到的內容元素／改資訊架構／換配色／換視覺語言。
- 結構改動本身不違規（Row↔Column／reparent／動 Box offset），只要意圖是達成同樣視覺。
- diff 級訊號：
  - 放寬 maxLines／換行／改寬度但沒同時補多行對齊（Compose `textAlign` / SwiftUI `.multilineTextAlignment`）→ 多行會破對齊（截斷變跑版）→ 標記要 Step 3 量水平對齊；不放心直接 `NEEDS_CHANGES` 回 fix。
  - 把爆框改成單行 `…`／tail-truncate（`lineBreakMode=.byTruncatingTail`、`ellipsize`）於需讀內容（名稱／標題／訊息）→ 沒真消滅缺陷、把「爆框」換「讀不到」→ `NEEDS_CHANGES` 回 fix（改縮字串或換行）。
  - 改寫／替換自訂繪製原語（`render_reimplemented`：自訂描邊/外框、nativeCanvas/Paint、`drawStyle=Stroke`、shader、字形渲染）→ 即使 layout 同，字形紋理可能已變 → snapshot 無法自證字形保真 → 標 `fidelity-unverifiable`，不得逕判視覺等價 PASS（轉人工/真機）。

> 寧可 `NEEDS_CHANGES` 也不放過越界／重設計。
> kept issue 本身有問題（根本非視覺缺陷／AC 自相矛盾／該 triage 掉卻 kept）→ `AUDIT_PROBLEM`，交 driver escalation 上報使用者。

## Step 1 — 過底線
- C1–C5（正典 [`add-snapshot §6`](../../skills/add-snapshot/SKILL.md)）。
- 掛 → 標 `render-broken`，全 fail 回 stage 3。

## Step 2 — 逐條 AC 比對
讀每條 kept AC，Read after（對 before 對看），親眼判：
- **無可見 delta = fail（不是 pass）**：目標區 after 與 before 視覺相同（改錯節點／no-op／harness 遮蔽）→ 修法未生效，判 `NEEDS_CHANGES` 並要求 stage 3 **還原該無效變更**（不得保留「收緊 UI 卻零可見效益」的改動）；若屬 harness 渲染不出 → 要求標 `snapshot-unverifiable`、仍還原變更（[`issue-schemas`](issue-schemas.md) §3〈可見 delta 鐵則〉）。
- truncation/overlap/wrap → 該處現在完整、不截斷、不重疊？（after 仍有 `…`／裁切於需讀內容 = **fail**）
- hardcoded-string/translation → 現在是目標 locale 正確譯文（非中文／raw key）？
- contrast → 現在可讀？

每條 `pass`/`fail`（fail 寫「現在還是怎樣」具體現象）。

**證據紀律（硬性，防誤判）**——任何「對齊／位置／間距／折行數」判斷必附可量證據：
- 先確認量的軸與缺陷相關：對齊類**一定量水平軸**（每行文字水平中心 vs 卡片中心、vs 同卡片其他置中元素中心）。只量垂直 gap／行數會剛好避開出錯的軸 = 假信心。
- 對齊：列各元素（含多行文字每一行）概略 x 座標，量得出不一致就 `fail`。
- 折行／截斷：寫實際行數（修前 N → 修後 M）。
- 量不出／看不清 → 一律 `fail`（不確定不放行）。

## Step 3 — 同畫面視覺等價掃描
把 after 對 before 逐區掃，每塊歸一類：
- `target-fix`：spec 列的缺陷處，預期會變。**只豁免位移／reflow，不豁免改完後的正確性**（套 Step 2 AC + Step 3.5）。target 區出現的新缺陷（對齊跑掉／置中遺失／換行不平衡）= `fail`。
  - **搬移截斷必抓**：target 區內若有元素從 before 完整變成 after 截斷／省略（典型：為塞下目標而把同列鄰居壓成「Resu…」）= `fail`，**即使該元素在 target 區、即使 kept AC 寫了「可接受壓縮」**——那種 AC 本身把搬移截斷當解，判 `AUDIT_PROBLEM`（[`issue-schemas`](issue-schemas.md) §3〈修一個元素不得截斷另一個〉）。before 完整可讀者，after 必須仍完整可讀。
- `unchanged`：非目標處與 before 一致 → OK。
- `unintended-delta`：非目標處卻變了 → `visual_equivalence` fail，寫哪塊怎麼變（位移／換行數變／對齊跑掉／顏色或大小變／元素增刪）。

> 放寬結構禁令的安全網：developer 用 Row↔Column／reparent／動 Box offset 來修，只要本掃描證明其餘像素級等價、僅目標處如預期變，該結構改動就算守住；任何非預期連帶變化 = fail。delta 即使可歸因字型 fallback／Locale.current／洗牌仍算 `unintended-delta` = fail。改文字／底色色值＝可見變更，不算視覺等價。

## Step 3.5 — 目標區正確性 + 設計意圖一致性
對每個 target-fix 區再問「設計師看了會收嗎」：
- 對齊一致性：與同容器兄弟元素一致嗎？（body/button 置中、標題卻靠左 = fail）
- **背景容器垂直容納**（target 區對「有背景控制項」用了換行／放寬 maxLines 時**必查**）：Read after 量 ① 文字 bounding box 完整落背景內、② 上下有內距未貼死／溢出、③ pill/膠囊未退化成貼字圓角矩形、④ 同容器鄰居未被推擠變形。任一不符 = `fail`，**不接受「膠囊外觀維持」這類無量化證據的宣稱**（把水平截斷換成垂直爆框 = 假修復，雙平台機制見 [03-fix](03-fix.md)）。
- 視覺處理一致性：字重／顏色／大小／平衡一致、符合設計意圖嗎？
- **渲染紋理保真**（dev 標 `render_reimplemented` 時**必查**）：被改文字／自訂繪製的字形渲染有沒有變樣——筆畫粗細、描邊觀感、(尤其非拉丁) 變音／聲調符號清晰度、有沒有糊化。before 壞了（截斷／爆框）不得當字形基準——只證「不再截斷」、證不了「字沒變樣」。snapshot 無乾淨參照可逐字比對 → 一律標 `fidelity-unverifiable`，**不得逕判視覺等價 PASS**（轉人工/真機抽驗）。
- legibility：用了字級縮放 → 量比例，< ~0.85 標 `legibility-degraded`、回報「此為退讓解」。

任一不一致 = `fail`，寫量化證據（座標／比例）退回 stage 3。

## Step 3.6 — 殘留可見盤點
- 獨立回報「after 圖中有哪些 kept/deferred 缺陷仍可見」。
- 即使被告知某缺陷 deferred，也不得略過或從視野消失——據實列出，讓 stage 5 定畫面狀態。
  - 註：deferred 不等於不可見、不等於已修。

## Step 4 — 鄰域 regression（若有 `neighborhood_test_cmds`）
跑各 test，確認沒弄壞兄弟畫面。任一鄰域截圖出現新跑版 → 記 `regression`。

## Output / 判定
產一個合併 `verify_verdict`（`PASS` / `NEEDS_CHANGES` / `AUDIT_PROBLEM`）+ 證據：

- 每條 AC 的 pass/fail + 具體證據（含位置／行數／對齊水平軸量化）。
- `target_correctness`（Step 3.5）/ `visual_equivalence`（Step 3 逐區，列所有 `unintended-delta`，空 = 等價）/ `residual_visible`（Step 3.6）/ 鄰域結果。
- **`PASS`** = Step 0 兩判都過（scope OK、無 redesign）**且** 全 AC pass、目標區正確（對齊一致、無新缺陷）、`visual_equivalence` pass、無鄰域 regression。
- **`NEEDS_CHANGES`** = Step 0 scope 越界／redesign，**或** 任一 AC fail／`visual_equivalence` fail／鄰域 regression／`render-broken`。
  - 列每個問題（hunk 或 after 圖位置 + 違反哪條 + 怎麼收斂）→ 回 stage 3（fix↔審查驗證 ≤ `internal_loop_max_rounds`）。
- **`AUDIT_PROBLEM`** = kept issue 本身有問題（Step 0 判二尾段）→ driver escalation。
- `PASS` 語意 = 「被修的那幾條 AC 達成且視覺正確／等價、且修法守 scope」，**≠ 整畫面乾淨**。
  - 畫面狀態由 stage 5 綜合 `residual_visible` 另算。
