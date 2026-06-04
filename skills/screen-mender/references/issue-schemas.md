# screen-mender issue / triage / 安全約束（plugin 自帶，generic）

> screen-mender 自帶的問題檔 schema、triage 規則、修復安全約束，零專案 lore。
> known-intended 清單屬專案專屬，由 host 專案自身 rule 提供（見 §2 triage）；無則跳過該項。

## 1. 範圍：只修「截圖看得見」的視覺缺陷

screen-mender 全程截圖驅動：

- 偵測靠 shot-audit 的視覺分析。
- 驗收靠 verifier 比對 after 截圖。

所以只處理截圖上看得見的視覺缺陷。截圖看不見的問題不在範圍——既偵測不到也驗收不了，route 去專屬 a11y pass（例：缺 `accessibilityLabel` / `contentDescription`）。

### 修的類別

- `truncation-risk` / `wrap-overflow` / `overlap`：文字截斷、換行爆框、元件重疊。
- `hardcoded-string` / `translation-broken`：未走字串系統而顯示錯字，或譯文壞、顯示 raw key。
- `locale-format`：**明顯錯誤**的日期／週幾／數字格式（raw、壞）。不含「該不該加千分位／用哪種分隔符」這類風格選擇——那是設計決策（分隔符還會 sim≠真機），標 `deferred:needs-design`／systemic，不逐畫面硬加（過度修復＝改了非缺陷）。
- `localized-image`：圖片內燒死的文字應隨 locale 切換卻沒切（目標語系變體缺＝真缺陷；變體在＝harness 假象、仍旗標；見 §3.5）。
- `contrast`：對比不可讀（截圖看得見）。修法改文字／底色色值＝可見變更，**不可報「視覺等價」**；換色取自畫面既有色盤，觸品牌色傾向人工確認。

### 不修的類別

- `a11y-missing`（缺 label / contentDescription）：隱形於截圖，測不到也驗不了 → out-of-scope，route 專屬 a11y pass。
- `design-redesign`（「應該改成 Column」「應該加 caption」）：除非帶設計來源 node 證據。

## 2. triage：每條 issue 標三種歸屬之一

audit 階段 agent 對每條 issue 標一種歸屬，寫進 MR description，不落任何檔。

- `kept`：本 run 要修的真視覺缺陷。
- `deferred:<reason>`：真視覺缺陷、但本 run 不修（reason 見〈deferred〉）。
  - 仍是缺陷、after 圖仍可見 → 必須當「殘留可見缺陷」最顯眼回報，並使該畫面狀態降為 `partially-fixed`（見 §4 狀態鐵則 / SKILL Phase 5）。
  - 不可當成已修，不可只藏在「考慮過但不修」段淡化。
- `wont-fix:<reason>`：不是該由本 pass 解的視覺缺陷（誤判／刻意／平台慣例／非視覺…），不計入畫面乾淨度。

### wont-fix：命中即非跑版或不在標的內，標 `wont-fix:<reason>`

- `intended-behavior`：專案 known-intended。
  - 清單來源：host 專案自身 rule 提供；無則跳過此項。
- `design-redesign-not-bug`：容器型別變更／增刪 children／純美學間距層級／推測性 UX。
  - 例外：issue 帶設計來源 node ID + 視覺證據時不算。
- `false-positive`：OCR／視覺誤判，code 實際正確。
- `platform-native`：平台慣例差異（如標題置中 vs 靠左），非 bug。
- `non-visual`：問題真實但截圖上看不見 → 截圖驅動的 screen-mender 既偵測不到也驗收不了，route 去專屬 a11y pass，不在此修。
  - 例：缺 a11y label / contentDescription / 純語意無障礙。
- `out-of-scope`：真實存在、但不是視覺缺陷。不屬 §1 任一修的類別 → screen-mender 不處理。
  - 例：行為／互動 bug（如 onClick 空 TODO）、純 code-quality nit（如未走 design token 但渲染正常）、需功能 PR 或設計決策者。
  - 建議：改由功能 PR / run-spec 帶設計決策。
  - 與這兩者區分（問題都是真的，但超出「視覺缺陷」標的）：
    - `false-positive`：觀察錯誤。
    - `design-redesign-not-bug`：版面重設計。
- `cost-benefit-low`：真缺陷但極輕微（如 1px 級邊緣瑕疵），修復風險／成本顯著高於收益。
- `subsumed-by-other-issue`：與另一條 kept issue 同根因，修那條即連帶解決，避免重複修。
- `user-confirmed`：使用者明確表示此項不修。

reason vocab（必填其一）：`false-positive` / `intended-behavior` / `platform-native` / `non-visual` / `out-of-scope` / `design-redesign-not-bug` / `cost-benefit-low` / `subsumed-by-other-issue` / `user-confirmed`。

### deferred：真視覺缺陷、本 run 不修，標 `deferred:<reason>`

after 圖仍可見 → 列殘留可見、畫面降 `partially-fixed`。

- `needs-design`：修法本身需設計來源／設計決策。
  - 無 Figma node 或設計依據，無法判斷「修成什麼樣才對」。
  - 與 `design-redesign-not-bug` 區分：後者根本不是 bug、是有人想重設計（wont-fix）；needs-design 確實是 bug、但修法需設計拍板（deferred）。
  - 模糊判斷（`…` 是設計還是截斷／某區是否故意留空）：分不出就標 needs-design 並寫出疑問，不准默默判 clean 或默默修。
- `deferred-by-run-config`：缺陷真實、修法已知可行，僅因本 run 設定被關閉而不執行。
  - 例：`string_fix_policy=disabled`，或字串非本地資源檔可改（該類字串如何處理由專案自身 rule 定，plugin 不內建）→ 改／縮字串這條路本 run 不可行（見 SKILL Phase 0 `string_fix_policy`）。
  - 與 `needs-design` 嚴格區分：needs-design 是「不知道怎麼修才對」；deferred-by-run-config 是「知道怎麼修、只是這個 run 不准修」。
  - 鐵則：不可把 config 限制誤標成 needs-design（會淡化「其實已知可修、是我關掉的」這個事實），也不可因此默默改用縮字級硬塞。

developer 修復中途發現 deferred → 用 return 的 `deferred[]` 回報（見 [`screen-mender-developer`](../../../agents/screen-mender-developer.md)），orchestrator 列入 MR 殘留可見段（最顯眼處），不靜默吞。

## 3. 修復安全約束（outcome-based：守「結果」不守「手段」）

核心原則：screen-mender 守的是結果，不是手段。一個修法只要同時滿足三件事就允許，不論它用什麼技巧。

1. 修好目標缺陷：issues.md kept 的那條視覺缺陷消失。
2. 畫面其餘部分視覺等價：除了目標缺陷處，截圖其餘部分對 before 看起來一樣。
   - 由誰證：verifier Step 3 同畫面視覺等價掃描。
3. 不是重設計：沒有改變使用者看到的內容／資訊架構／視覺語言。
   - 由誰判：reviewer。

> 守結果、不禁工具：不要禁特定手段（例：禁 Row↔Column / 禁改容器）——工具自由，由上面三條件 + verifier/reviewer 把關。
>
> 反例警示：
> - 「用 modifier 互搬把 overflow 從右邊搬到左邊」沒讓缺陷真正消失（只是位移），不算修好。
> - 有些畫面用多個 Box offset 堆疊，硬不重構反而更容易跑版。

### 修法分三級（依把關強度）

**T1 自由（綠燈）**

- 手段：modifier 微調（lineLimit／maxLines／autosize／weight／padding／spacing／softWrap／safe-area／contentInset）、調色值、同容器 sibling modifier、字串值改動／縮短字串值（改本地資源檔，見下）。
- 准許條件：直接做；仍須過 verifier 三條件。

**T2 結構改動（需證明）**

- 手段：Row↔Column、reparent、增刪 wrapper/spacer、調整 Box offset 堆疊、改容器型別。
- 准許條件：允許，但 developer 須在 return 標 `tier: T2` + 填 `structural_notes`（為何 T1 解不了／改了什麼結構）；verifier 視覺等價掃描證等價；reviewer 確認非重設計。

**R 始終禁（紅燈）**

- 手段：增刪「使用者看得到的內容元素」（多一個 caption／少一張圖）、改畫面語意或資訊架構、純美學重設計（換配色風格／改圓角視覺語言）。
- 准許條件：需設計來源證據；無證據 → wont-fix `design-redesign-not-bug`。

T2 vs R 的判準（最關鍵）：問「修完截圖除了缺陷處，其餘看起來一樣嗎？」

- 一樣 → 是修復（T2，允許）。
  - 例：只是底層 view tree 換了寫法達到同樣視覺。
- 不一樣／多了或少了使用者看得到的東西 → 是重設計（R，需設計證據）。

### 渲染保真度：改寫自訂繪製原語（render-fidelity）

版面修復（換行／放寬容器／對齊）有時需要改寫「控制視覺紋理的自訂繪製原語」——自訂描邊／外框文字、nativeCanvas／Paint 繪製、`drawStyle = Stroke`、shader、自訂字形渲染。要警覺一件事：**達成同樣的 layout ≠ 產生同樣的像素**。換掉渲染技術（例：絕對座標描邊字 → 路徑 Stroke 疊層）即使位置／換行對了，字形筆畫粗細、外框觀感、(尤其非拉丁) 變音／聲調符號清晰度都可能變樣——這在「視覺等價」判準下其實是 FAIL，卻最容易騙過只看「位置對不對、有沒有截斷」的把關。

- 優先最小改動保留原渲染：能在原元件上加寬度約束／換行而不換渲染技術，就別重寫。
- 若版面修復非重寫渲染不可（原本絕對座標、本就不能換行）→ 視為 **high-fidelity-risk T2**：
  - developer 在 return 標 `render_reimplemented: <改了什麼渲染>`，觸發 reviewer／verifier 加驗。
  - 須用**乾淨參照**證明字形保真（逐字比對筆畫／外框／變音符號），不得拿壞掉的 before（截斷／爆框）當保真基準——它只能證明「不再截斷」、證不了「字沒變樣」。乾淨參照來源：同元件其他短語系（如 zh）的 render、既有乾淨截圖、或設計稿。
  - 拿不到乾淨參照 → verifier 標 `fidelity-unverifiable`、不得逕判視覺等價 PASS。

### 字串值改動（通用，不含任何專案策略）

`hardcoded-string` / `translation` / overflow 走縮字串時：

- 准改：字串值一律改本地資源檔（`values-<locale>/strings.xml`、`Localizable.strings` 等）。
- 禁：永不 hardcode 字串。
- 編輯／縮短／補空白後須確認結果在目標語言**正字法正確**（變音、大小寫、無重複字、`%@`/`%d` placeholder 對得上）。截圖看不到的文字錯靠配套 lint 補（doubled-word／placeholder-parity／拉丁語系誤用 CJK 標點），非視覺 audit 職責。

> screen-mender 對字串只認兩種模式（`string_fix_policy`，見 SKILL Phase 0）：`local-resource`（改本地資源檔）或 `disabled`（不動字串）。保持 self-contained、零專案 lore。
>
> 以下屬專案層、不寫進本 skill、screen-mender 不內建：
> - 某專案的字串若不在本地資源檔（例如由其他來源產生），該如何修——由該專案自身 rule/CLAUDE.md 宣告，並把 `string_fix_policy` 設為 `disabled`、自理修法流程。
> - 何時該縮短譯文／縮到多短／以哪個系統為準。
>
> 此時 screen-mender 只做：偵測出缺陷 → 本地不可改則標 `deferred:deferred-by-run-config`、攤成殘留可見，交專案自身流程接手。

### overflow / truncation 的修法選擇（優先序強制）

對 overflow / truncation / wrap，developer（audit 的修法 hint 可建議）不再被分類綁死只能 modifier，應在真 render 上依下列優先序挑「視覺結果最乾淨」的，且在 return 逐一說明為何跳過更高順位（為何不縮文案、為何不長高／放寬容器）才落到下一順位。

1. 縮短字串值（屬 T1）——改本地資源檔。
   - 本 run 是否允許改字串由 `string_fix_policy`（`local-resource`／`disabled`）決定（見 SKILL Phase 0）；字串非本地可改的專案在自身 rule 處理。
   - 條件：該字串明顯 verbose、縮短不損語意。
   - 被 run-config 關閉時（`disabled`）：不得默默跳過改用縮字級硬塞 → 該缺陷標 `deferred:deferred-by-run-config`（§2），列殘留可見。
2. 長高 / 放寬容器吸收（T1 padding/intrinsic 或 T2 結構，視情況）。
3. T1 modifier（softWrap / lineLimit / weight…）。
4. 字級縮放（autosize / `minimumScaleFactor`）= 末位手段：把字縮小硬塞、以可讀性換不爆框，只有 1–3 都不可行才用。
   - legibility 門檻：縮放比例 < ~0.85（肉眼可辨變小、或明顯小於相鄰同級元素）→ developer 須在 return 標 `legibility-degraded` + 比例；verifier 須量並回報；orchestrator 須在 MR/summary 明示「此為退讓解，最優解（縮文案／長高）因 <原因> 未採」。

判斷準則：

- 若某順位只是把 overflow／折行從一處搬到另一處（沒真消滅，例：weight 互搬），就升級到更高順位，不要交出「換位置」的假修復。
- **省略號／tail-truncate 不是修好的終點**：把爆框改成單行 `…` 只是把「爆框」換成「讀不到」，同屬「換位置」假修復。使用者需讀完的內容（名稱／標題／訊息）一律要完整可見——縮字串（順位 1）或換行（順位 2）。單行 `…` 只在「短尾、無資訊損失、且縮＋換都不可行」才允許，且須標殘留可見。名稱／標題預設**換行**（內容驅動列高），不靠 `…`；「共用 cell」是把列高做成自適應的理由，不是維持單行截斷的藉口。
- 同類缺陷策略要一致：別在 A 畫面「長高保字級」、B 畫面「縮字」只因 B 較難長高——若版面無法乾淨吸收，正解是回到順位 1（縮文案）。

### 放寬換行 / maxLines / 寬度約束 → 必須同時接住多行對齊

「讓元素換行／放寬 maxLines／改寬度約束」這類修法，幾乎一定要同時確認該元素多行時的對齊，否則是把「截斷」換成「跑版」（多出一條對齊缺陷）。

- 典型陷阱（Compose）：靠父 `horizontalAlignment` 置中的 wrap-content `Text`，放寬 maxLines 後第 2 行依 `Text` 自身 `textAlign`（預設 `Start`）靠左 → 須同時加 `textAlign = TextAlign.Center`（通常配 `Modifier.fillMaxWidth()`），對既有單行 consumer 視覺等價、多行才正確。SwiftUI 同理：frame `alignment` ≠ `.multilineTextAlignment`。
- 此類修法的 AC 必含一條「該元素多行後維持原對齊／置中／視覺處理」（見 §4）；audit 偵測到「靠父層 alignment 置中、元素無自身 textAlign」結構時，主動把「一換行就破置中」列為風險寫進 AC。

## 3.5 截圖可信度：snapshot ≠ 真機時，誠實標 unverifiable，不准當 false-positive

screen-mender 全靠截圖偵測＋驗收，但截圖可能不忠於真機。以下三種情形一律當「未驗證」處理，不可一句「真機會對」打發（那是假設不是事實，會關掉真 bug）：

- **非確定性 capture**：內容隨機（`.shuffled()`／無 seed）、async 狀態、自訂字型間歇 fallback → before/after 會因與修復無關的原因不同，視覺等價掃描失效。判定法：同 state 連拍兩張，不一致即非確定 → seed 固定它，或無 seam 就標 `capture-nondeterministic`（類 locked），**不得交出兩張不同畫面的 before/after，也不得在其上判 PASS**。
- **locale 未完整套用**：capture harness 若只換 app 字串、沒換 `Locale.current`／`Calendar.current`（日期／數字／週幾）與 asset `preferredLocalizations`（在地化圖），則目標語系截圖裡這些仍顯示模擬器語系 → `locale-format` 與 `localized-image` 正確性 **unverifiable**，標旗標轉人工／真機抽驗，**不得**標 `wont-fix:false-positive`（缺目標變體的在地化圖就是真缺陷）。
- **非目標語系文字出現**（如 vi run 出現 CJK）必三分：① hardcoded／錯字串＝真缺陷；② `Locale.current` formatter 假象＝unverifiable，旗標；③ 在地化圖顯示錯變體——查 asset catalog 有無目標變體：缺＝真 `deferred:needs-design`、在＝harness 假象但仍旗標。禁一律打 false-positive。

誠實鐵則（跨上述全部）：**after 圖只要還看得到缺陷，畫面就不是 fully-fixed**，不論歸因（字型 fallback／Locale.current／洗牌）——至少 partially-fixed＋殘留可見，或標 capture 不可信。修復正確性無法在 after 圖呈現者（改用 native API 但 sim 仍顯舊值、before/after byte-identical）標 `code-verified／snapshot-unverifiable`，不得報 fully-fixed。

## 4. 紀錄去處：MR 是唯一 SSOT（零本地紀錄檔）

唯一暫存輸入 = `issues.md`，放 ephemeral run 目錄（run 結束即刪，不進 `.audit` 持久區）。

- 由誰產：audit 階段 agent（shot-audit 偵測 + screen-mender 同階段補 triage + 附 AC）。
- 由誰讀：developer 直接讀。

```markdown
## [<severity:high|med|low>] <category> · <title>
- triage：kept | deferred:<needs-design|deferred-by-run-config> | wont-fix:<reason vocab>   # kept 進 developer；deferred=真缺陷本 run 不修→殘留可見段；wont-fix→「考慮過但不修」段
- 觀察 (<date>)：<描述 + code path:line>
- 位置：[<file>](<path:line>)
- 截圖：`shots/<platform>__<state>__<locale>.png`
- 修法 hint：<...>（標 tier T1/T2；縮字串屬 T1；overflow 別只開 T1、依 §3 優先序）
- AC：<一行可驗，verifier 逐條比對，例「vi 下標題完整不截斷」>
  - **換行/放寬 maxLines/改寬度類修法的 AC 必含對齊條款**（如「標題多行後仍與 body/button 同樣置中」，見 §3）。
```

> v3 起無 planner，職責分工：
> - triage（real-visual-defect vs wont-fix）與 AC 由 audit 階段 agent 在偵測時一併產出。
>   - 原因：它已在看截圖 + code，邊際成本低。
> - 「怎麼修 / 反查 file:line / 選 tier」由 developer 在真 render 上迭代決定（見 [`screen-mender-developer`](../../../agents/screen-mender-developer.md)）。

修了什麼／不修什麼／before-after 一律寫進 MR description（不產任何 `.audit` 檔：wont-fix / pending-merge / fixed / ledger）。

### MR 標題固定模板

每個 MR 標題用**同一固定模板**，讓使用者在 MR list 一眼掃描、辨識為 screen-mender 自動產出：

- 全修復：`自動跑版修復：<unified_id> - <原因摘要>`
- 部分修復：`自動跑版修復（部分）：<unified_id> - <原因摘要>`

欄位：

- `<unified_id>`：畫面統一 id（= branch 用的同一個；單平台直接用，monorepo 跨平台才帶平台前綴）。
- `<原因摘要>`：一句話講主要缺陷；多缺陷取最主要者 + 「等 N 處」（例：`暱稱欄位截斷等 3 處`）。
- 「自動」前綴：標示本 MR 為 screen-mender 自動產生，reviewer 一眼可識。

範例：

- `自動跑版修復：use_shield_screen - 連勝盾牌標題截斷`
- `自動跑版修復（部分）：team_rule_view - 規則標題爆框`（1 修 / 1 延後）

標題狀態鐵則（決定用哪個 variant）：畫面狀態由「所有 kept+deferred 缺陷是否都已解決」計（非「我選去修的那幾條過 verify 沒」）。只要有任一 `kept`/`deferred` 缺陷在 after 圖仍可見，**必用「（部分）」variant**，不得用全修復 variant；並把殘留項列在最顯眼處（殘留可見段，不可只藏在「考慮過但不修」段）。summary 標題同此狀態規則。

```markdown
## 狀態：fully-fixed | partially-fixed (n fixed, m deferred-visible) | clean
## 修的視覺缺陷（N 條）
### [<severity>] <category> · <title>
- 修復方式：<...>（file:line）
- AC：<...>
-（若為退讓解）legibility-degraded：縮放比例 <r>，最優解 <縮文案/長高> 因 <原因> 未採

## ⚠️ 殘留可見缺陷（deferred，after 圖仍看得到，m 條）
- [<category>] <title> — `deferred:<needs-design|deferred-by-run-config>` — <為何本 run 不修；deferred-by-run-config 要寫清「已知怎麼修、被哪條 run-config 關掉」>

## 修改前後對照
**修改前** ![](/uploads/.../before.png)
**修改後** ![](/uploads/.../after.png)

## 考慮過但不修（wont-fix，非缺陷或不在標的）
- [<category>] <title> — <wont-fix reason vocab 之一>
```

before/after 截圖經 `POST /projects/:id/uploads` 取得 `/uploads/...` markdown 後內嵌（見 [`orchestration`](orchestration.md) §5）。

- 上傳細節：multipart，`curl -F file=@<png>` + token。
