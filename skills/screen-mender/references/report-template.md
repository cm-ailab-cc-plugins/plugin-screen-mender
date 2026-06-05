# screen-mender 修復報告 template

> Phase 3 終止時，orchestrator 依本 template 產一份**持久**報告，落 `<repo>/.screen-mender/reports/run-<run_id>.md`。
> 資料一律取自各 runner return（`unified_id` / `status` / `mr_url` / `fixed[]` / `residual_visible[]` / `escalation`），orchestrator 不另開截圖·diff。

## 填寫規則

- 依「修復程度」分三段：完全修復 / 部分修復 / 未能修復。**clean（audit 0 條、無缺陷）不列。**
- `<unified_id>` = 畫面 id（= screen-list 產出、branch 用的同一個 id）。
- **修復元件（類別/函式）**：取自 runner `fixed[]` 的 file:line 反推——真正被改的 composable/類別函式名 + 檔名（如 `LoginScreen（LoginScreen.kt）`）；一畫面動到多個元件就並列。未能修復段無此欄。
- **修復項目**：每條 `fixed` 壓成一句話，只講「修了什麼缺陷」；file:line / tier / 退讓解細節留 MR，不進報告。
- **MR**：正式 run 填 `mr_url`；`dry_run` 改填該畫面 `<run_dir>/<unified_id>/proposed-mr.md` 的路徑。
- 部分修復**必列殘留可見缺陷段**（沿用殘留可見鐵則，不可省、不可淡化）。
- 未能修復段涵蓋 `locked` / `defect` / `stuck` / `harness-missing`，原因取 `escalation` 一句摘要。
- 不寫任何 `.audit`；本報告是唯一持久產物，run 結束 teardown 不刪 `reports/`。

---

# screen-mender 修復報告

- run id：<run_id>
- 平台：<platform> · 語系：<capture_locale> · 模式：<正式|dry-run>
- string_fix_policy：<local-resource|disabled>
- 產出時間：<YYYY-MM-DD HH:MM>
- 涵蓋：完全修復 <a> · 部分修復 <b> · 未能修復 <c>（clean <d> 略過不列）

---

## ✅ 完全修復（<a>）

### <unified_id>
- 修復元件（類別/函式）：<ComposableFn>（<file>）
- 修復項目：
  - <一句話描述這條修了什麼>
  - <一句話描述下一條>
- MR：<mr_url>

---

## 🟡 部分修復（<b>）

### <unified_id>
- 修復元件（類別/函式）：<ComposableFn>（<file>）
- 修復項目：
  - <一句話>
- 殘留可見缺陷：
  - <一句話> — <needs-design|deferred-by-run-config>
- MR：<mr_url>（標題含「（部分）」）

---

## ⛔ 未能修復（<c>）

### <unified_id>
- 狀態：<locked|defect|stuck|harness-missing>
- 原因：<escalation 一句摘要>
- MR：無
