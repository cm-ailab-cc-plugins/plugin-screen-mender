# Stage 5 — verify（自驗）

對應現 verifier 職責。你證明的不是「能跑」，而是「kept 每條缺陷 AC 真的達成、且畫面其餘部分沒被波及」。預設直接判 stage 3 產出的 after 截圖（snapshot test 確定性 → 同 committed code 重跑必得同圖，故重跑對「修好沒」冗餘）。

> 你是修的人也是驗的人。這一格刻意換上「驗收者」視角：凡判斷必附**可量證據**，不接受「看起來對齊」「應該沒問題」。

> 此前提僅在 capture 確定性成立時有效：若該畫面標 `capture-nondeterministic`／內容隨機／字型間歇 fallback，before/after 不可比，不得在其上判視覺等價 PASS（[`issue-schemas`](../../skills/screen-mender/references/issue-schemas.md) §3.5）。

## Inputs
- `issues.md` kept（含每條 AC，ground truth）。
- after 截圖（stage 3）+ before 截圖（stage 1，Step 3 視覺等價掃描必需）。
- `neighborhood_test_cmds`（選用）/ `fidelity_reference`（`render_reimplemented` 時用，乾淨參照）。

## Step 1 — 過底線
C1–C5（正典 [`add-snapshot §6`](../../skills/add-snapshot/SKILL.md)）。掛 → 標 `render-broken`，全 fail 回 stage 3。

## Step 2 — 逐條 AC 比對
讀每條 kept AC，Read after（對 before 對看），親眼判：
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
- `unchanged`：非目標處與 before 一致 → OK。
- `unintended-delta`：非目標處卻變了 → `visual_equivalence` fail，寫哪塊怎麼變（位移／換行數變／對齊跑掉／顏色或大小變／元素增刪）。

> 放寬結構禁令的安全網：developer 用 Row↔Column／reparent／動 Box offset 來修，只要本掃描證明其餘像素級等價、僅目標處如預期變，該結構改動就算守住；任何非預期連帶變化 = fail。delta 即使可歸因字型 fallback／Locale.current／洗牌仍算 `unintended-delta` = fail。改文字／底色色值＝可見變更，不算視覺等價。

## Step 3.5 — 目標區正確性 + 設計意圖一致性
對每個 target-fix 區再問「設計師看了會收嗎」：
- 對齊一致性：與同容器兄弟元素一致嗎？（body/button 置中、標題卻靠左 = fail）
- 視覺處理一致性：字重／顏色／大小／平衡一致、符合設計意圖嗎？
- **渲染紋理保真**（dev 標 `render_reimplemented` 時**必查**）：被改文字／自訂繪製的字形渲染有沒有變樣——筆畫粗細、描邊觀感、(尤其非拉丁) 變音／聲調符號清晰度、有沒有糊化。before 壞了（截斷／爆框）不得當字形基準——只證「不再截斷」、證不了「字沒變樣」；改用 `fidelity_reference` 逐字比對。拿不到 → 標 `fidelity-unverifiable`，**不得逕判視覺等價 PASS**。
- legibility：用了字級縮放 → 量比例，< ~0.85 標 `legibility-degraded`、回報「此為退讓解」。

任一不一致 = `fail`，寫量化證據（座標／比例）退回 stage 3。

## Step 3.6 — 殘留可見盤點
獨立回報「after 圖中有哪些 kept/deferred 缺陷仍可見」。即使被告知某缺陷 deferred，也不得略過或從視野消失——據實列出，讓 stage 6 定畫面狀態（deferred 不等於不可見、不等於已修）。

## Step 4 — 鄰域 regression（若有 `neighborhood_test_cmds`）
跑各 test，確認沒弄壞兄弟畫面。任一鄰域截圖出現新跑版 → 記 `regression`。

## Output / 判定
- 每條 AC 的 pass/fail + 具體證據（含位置／行數／對齊水平軸量化）。
- `target_correctness`（Step 3.5）/ `visual_equivalence`（Step 3 逐區，列所有 `unintended-delta`，空 = 等價）/ `residual_visible`（Step 3.6）/ 鄰域結果。
- **PASS** = 全 AC pass 且目標區正確（對齊一致、無新缺陷）且 `visual_equivalence` pass 且無鄰域 regression。
- PASS 語意 = 「被修的那幾條 AC 達成且視覺正確／等價」，**≠ 整畫面乾淨**（畫面狀態由 stage 6 綜合 `residual_visible` 另算）。
- 任一 AC fail／`visual_equivalence` fail／鄰域 regression／`render-broken` → 回 stage 3（fix↔verify ≤ `internal_loop_max_rounds`）。
