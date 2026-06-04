# Stage 4 — review（自審）

對應現 reviewer 職責。審剛才這次修復的 diff，只判兩件事：**scope**（只改 kept、無越界）、**redesign**（修復 vs 重設計）。不審程式美不美、命名、可否更簡潔——畫面其餘處的像素級等價交 stage 5。

> 你是修的人也是審的人。這一格刻意換上「審查者」視角，照下面清單機械地查，**不為自己的修法放水**——範圍安全靠這關。

## Inputs
- diff：`git -C <worktree> diff <base_branch>`（`dry_run` 也用這個；非 dry-run 已開 MR 後可改 `<mr_tool> mr diff <id>`）。
- `issues.md` kept（你的 ground truth：只該改這些）。

## 判一：scope
- 每個 production 改動都對得上某條 kept issue 嗎？
- 有沒有沒列的「順手改／重構別處／改別畫面」？
- 字串值改動有走字串系統（非 hardcode）嗎？
- 有越界 / hardcode = NEEDS_CHANGES。
- 新增的 snapshot test / host 檔屬預期 scaffolding，不算越界。

## 判二：redesign（守 outcome，見 [`issue-schemas`](../../skills/screen-mender/references/issue-schemas.md) §3）
diff 是讓畫面長一樣、只是結構更穩（T1/T2 修復，OK），還是讓畫面長得不一樣（R 重設計，擋）？

- R 重設計 = 增刪使用者看得到的內容元素／改資訊架構／換配色／換視覺語言。
- 結構改動本身不違規（Row↔Column／reparent／動 Box offset），只要意圖是達成同樣視覺。
- diff 級訊號：
  - 放寬 maxLines／換行／改寬度但沒同時補多行對齊（Compose `textAlign` / SwiftUI `.multilineTextAlignment`）→ 多行會破對齊（截斷變跑版）→ 標記要 stage 5 量水平對齊；不放心直接 NEEDS_CHANGES 回 fix。
  - 把爆框改成單行 `…`／tail-truncate（`lineBreakMode=.byTruncatingTail`、`ellipsize`）於需讀內容（名稱／標題／訊息）→ 沒真消滅缺陷、把「爆框」換「讀不到」→ NEEDS_CHANGES 回 fix（改縮字串或換行）。
  - diff 改寫／替換自訂繪製原語（`render_reimplemented`：自訂描邊/外框、nativeCanvas/Paint、`drawStyle=Stroke`、shader、字形渲染）→ 即使 layout 同，字形紋理可能已變 → 要求 stage 5 用乾淨參照做字形保真；拿不到乾淨參照、無法確保等價 → NEEDS_CHANGES。

## 判定
- **PASS**：兩判都過 → 進 stage 5。
- **NEEDS_CHANGES**：列每個問題（hunk + 違反 scope 還 redesign + 怎麼收斂）→ 回 stage 3 重修（fix↔review ≤ `internal_loop_max_rounds`）。
- **AUDIT_PROBLEM**：kept issue 本身有問題（根本非視覺缺陷／AC 自相矛盾／該 triage 掉卻 kept）→ 交 driver escalation 上報使用者。

> 寧可 NEEDS_CHANGES 也不放過越界／重設計。
