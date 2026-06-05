# Stage 3 — fix（修復）

- 對應現 developer 職責。
- 把 `issues.md` 的 kept 條**全部修好、且只修這些**。
- 怎麼修、改哪一行、用哪一級手段，由你在真 render 上迭代決定——UI 的真相在截圖裡，不在紙上。

## Inputs
- `<run_dir>/<unified_id>/issues.md`（kept + 每條 AC）。
- before 截圖（基準）。
- `worktree` / `branch` / `build_cmd` / `snapshot_test_cmd` / `device_serial`（stage 1 establish）。
- `string_fix_policy` / `ui_framework_pref`（compose|swiftui）/ `iterate_max`（預設 2）。

## 守 outcome 不守手段
> [`issue-schemas`](issue-schemas.md) §3

任何修法只要同時滿足下列，就允許：
1. 目標缺陷消失
2. 截圖其餘對 before 視覺等價
3. 非重設計

分三級：

- **T1** 直接做：modifier 微調、調色、字串值。
- **T2** 結構改動可做但須證明：Row↔Column／reparent／增刪 wrapper-spacer／調 Box offset／改容器型別。
  - 回報寫明為何 T1 不夠 + 改了什麼結構。
  - **改寫自訂繪製原語**（描邊/外框文字、nativeCanvas/Paint、`drawStyle=Stroke`、shader、字形渲染）= high-fidelity-risk T2：layout 對 ≠ 像素對。
    - 回報標 `render_reimplemented`；字形保真無法在 snapshot 上自證，交審查與驗證階段標 `fidelity-unverifiable`。
- **R** 永遠禁：增刪使用者看得到的內容元素／改資訊架構／純美學重設計。
  - 判準「改完截圖除缺陷處其餘一樣嗎」。
  - 不確定就當 R，不做，列 `deferred[]`（reason `needs-design`）。

## 字串值改動（依 `string_fix_policy`）
- `local-resource`：改本地資源檔（`values-<locale>/strings.xml`、`Localizable.strings` 等）的該 locale 值。
- `disabled`：本 run 不准改字串。
  - 凡「乾淨修法須改／縮字串」的缺陷，不得默默改用縮字級硬塞。
  - 一律列 `deferred[]`（reason `deferred-by-run-config`，**非** `needs-design`）。
- 鐵則：永不 hardcode。
  - 註：hardcode 必在非預設語系重現為錯字——正是本 skill 要修的缺陷。

## 有界迭代 loop（核心）
逐 kept 條跑，每條 ≤ `iterate_max`：

```
推論修法（依 §3 優先序：1 縮字串 > 2 長高/放寬容器 > 3 T1 modifier > 4 字級縮放[末位]；
          在真 render 上選視覺最乾淨的，並記下「為何跳過更高順位」）
  → 改（守紅線，見 driver：只動本 worktree、只動 kept 相關檔）
  → 跑 build_cmd + snapshot_test_cmd 出 after 截圖（落 <run_dir>/<unified_id>/after__<state>__<locale>.png）
  → Read after 截圖：逐條比 AC + 看「畫面其餘有沒被波及」
    ├─ 全 AC 達成且其餘等價 → 完成
    └─ 沒真修好（overflow 只搬位 / 波及鄰處）→ 升級修法重來
```

### loop 自檢規則
- render 自檢底線 = **過 C1–C5** 才算有效 render。
- **無可見 delta = 還原**：Read after 後若目標區與 before **視覺相同**（改錯節點／no-op／harness 遮蔽）→ 此修法無效，**還原該變更**（不得把「收緊 UI 卻零可見效益」的改動如 `maxLines=1`／改 `padding` 語義留在 diff），升級修法重試；若確認是 harness 渲染不出（如 `navigationBarsPadding` 在非 edge-to-edge host no-op／`Locale.current` 未套）→ 標 `snapshot-unverifiable` 交 stage 4／escalate，**仍還原無效變更**（[`issue-schemas`](issue-schemas.md) §3〈可見 delta 鐵則〉）。修法依據是可見差異、非 code 推敲。
- **借鄰居空間不得截斷鄰居**：用 weight／maxLines／ellipsis 壓縮同列鄰居來騰位給目標時，Read after 必確認該鄰居沒從 before 完整變成 after 新截斷（`…`／裁切）；有 → 搬移截斷、不算修好，改走整列換行／縮字串或 `deferred:needs-design`（[`issue-schemas`](issue-schemas.md) §3）。
- **不要交「換位置」假修復**：modifier 只把 overflow／折行搬到別處 = 沒修好，必須升級。
- **省略號／tail-truncate 不是修好**：
  - 需讀內容（名稱／標題／訊息）要完整可見（縮字串或換行）。
  - 名稱／標題預設換行（內容驅動列高），「共用 cell」是把列高做自適應的理由、不是維持單行截斷的藉口。
- 字級縮放比例 **< ~0.85** → 標 `legibility-degraded` + 比例（以可讀性換不爆框的退讓解）。
- **放寬換行／maxLines／寬度 → 必同時接住多行對齊**（不然是把截斷換成跑版）：
  - Compose：放寬 maxLines 後加 `textAlign = TextAlign.Center`（通常配 `Modifier.fillMaxWidth()`）。
  - SwiftUI：frame `alignment` ≠ `.multilineTextAlignment`；多行置中要設 `.multilineTextAlignment(.center)`。
  - 自檢必問「改完多行時還置中／對齊、跟兄弟元素一致嗎」，不只問「文字出現了嗎」。
- **固定外觀控制項換行 → 必同時接住「背景容器垂直容納」**（不然是把水平截斷換成垂直爆框，等同搬移截斷）：
  - 對象：有背景／邊框／固定外觀者——按鈕、膠囊 pill、卡片、固定高 cell。
  - 強預設順位 1 縮字串（固定狀態短訊息如「人數已滿」尤其）；採換行須讓背景隨內容長高，否則文字擠爆／溢出背景。
  - iOS UIKit：`titleLabel.numberOfLines=0` 不會自動長高——移除固定高約束改 `>=` minHeight + `contentEdgeInsets`／`configuration.contentInsets` 垂直內距；膠囊 cornerRadius 若 = 高/2，長高後須在 `layoutSubviews` 重算，否則 pill 退化成圓角矩形。
  - iOS SwiftUI：`.lineLimit(nil)` + `.fixedSize(horizontal:false, vertical:true)`；容器勿 `.frame(height:)`（會裁切）改 `.frame(minHeight:)` + 垂直 `.padding`；`Capsule()` 背景自隨內容長高。
  - Android XML：`MaterialButton`／`TextView` 放寬 `maxLines` 時 `layout_height` 勿固定 dp，改 `wrap_content` + `minHeight` + 垂直 padding；`app:cornerRadius` 設半高做 pill 者長高後變矩形，改 `shapeAppearance` `cornerSize=50%` 或接受矩形。
  - Android Compose：放寬 `maxLines` 時容器勿 `Modifier.height()`（會裁切）改 `Modifier.heightIn(min=…)` + `contentPadding`；`RoundedCornerShape(percent=50)` 自適應。
  - 自檢必 Read after 確認背景完整包住多行文字、上下未貼死／溢出、pill 未退化、鄰居未被推擠。
  - **跨兄弟畫面共用同一字串 key 必採同一修法**（同一 `maxPeopleReached` 在 A/B 縮字串、C 卻換行 = 不一致，違 §3 一致性）。

## commit
- commit（連同本畫面 snapshot test）；message「修 `<unified_id>` 視覺缺陷：<逐條>」。
- push 到 `branch`；已 push 過用 `--force-with-lease`。
- `dry_run=true` → **只 commit、不 push**（含被退回重修輪）。
- 被審查／驗證退回重修：只針對退回意見修，commit + `--force-with-lease` 重 push。
- 你不自己 rebase——rebase 一律由 stage 5 在開 MR 前統一做。

## Output / Exit
- `fix_record[]`：每條 `{title, tier(T1|T2), fix_choice, skipped_higher(為何跳過縮文案/長高), before→after 一句, AC 達成?, legibility_degraded(比例,若有)}`。
- `render_reimplemented`（若改寫自訂繪製：改了什麼、原本怎麼畫）/ `string_changes`（字串 id 異動，若有）/ `commit_hash` / after 圖路徑 / `build_runs`（build+test 實際次數）。
- `deferred[]`：`{title, reason(needs-design|deferred-by-run-config), 為何本 run 不修}`。
  - config 限制要寫清「已知怎麼修、被哪條關掉」。
- **STUCK**：跑滿 `iterate_max` 仍未達成、或 build 同錯連 3 次 → 記 STUCK（platform / 卡點 / 試過什麼 / 建議），交 driver 升級 escalation。
- capture 不忠於真機（非確定／locale 未套／字型 fallback）時別硬判已修：
  - 依 [`issue-schemas`](issue-schemas.md) §3.5 標 `code-verified／snapshot-unverifiable` 或殘留。
  - after 圖仍見缺陷一律不報 OK。
