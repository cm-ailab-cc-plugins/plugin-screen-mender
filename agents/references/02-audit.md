# Stage 2 — audit（偵測 + triage + AC）

對應 SKILL Phase 3。對 capture 出的截圖找出所有看得見的視覺缺陷，triage，附 AC，寫 `issues.md`。

shot-audit 只產「問題 + 描述 + 調整建議」、不做 triage／AC（刻意精簡），故 triage + 附 AC 由本階段補上。

## Inputs
- before 截圖路徑（stage 1）+ `capture_locale` + 兄弟畫面參考。
- `string_fix_policy`（triage `deferred-by-run-config` 用）。
- `run_dir`。

## Procedure
1. **偵測** — 用 Skill `shot-audit` 偵測本畫面所有截圖看得見的視覺缺陷（含描述 + 調整建議）。帶 `layout_stress_locale = capture_locale` + 兄弟畫面參考。
   - 多 locale（`extra_audit_locales` 非空）：每個 extra locale 截圖也跑 shot-audit，重點查翻譯正確性／locale 格式（`translation-broken`／`locale-format`）。
2. **triage**（shot-audit 不做、你補）— 依 [`issue-schemas`](../../skills/screen-mender/references/issue-schemas.md) §2 對每條標 `kept` / `deferred:<reason>` / `wont-fix:<reason>`。
   - `wont-fix`：known-intended／無設計證據的 redesign／false-positive／non-visual a11y… → 列 MR「考慮過但不修」段。
   - `deferred`：真缺陷、本 run 不修（`needs-design` 須設計拍板／`deferred-by-run-config` 被 run-config 關閉）→ after 圖仍可見、列殘留可見、畫面降 `partially-fixed`，不得偽裝成已修或與 needs-design 混用。
3. **附 AC** — 每條 `kept` 附一行可驗 AC（verifier 逐條比對）。
   - 換行／放寬 maxLines／改寬度類修法的 AC **必含對齊條款**（如「多行後仍與兄弟元素同樣置中」）。偵測到「靠父層 alignment 置中、元素無自身 textAlign」結構 → 主動把「一換行就破置中」列為風險寫進 AC（[`issue-schemas`](../../skills/screen-mender/references/issue-schemas.md) §3/§4）。
4. **輸出** — 落 `<run_dir>/<unified_id>/issues.md`（schema 見 [`issue-schemas`](../../skills/screen-mender/references/issue-schemas.md) §4）。不寫 `.audit/` 持久檔。

## Output
- `issues.md`（kept[]+AC / deferred[] / wont-fix[]）。
- `kept_count`。

## Exit
- `kept_count == 0`（全乾淨或全 triage 掉）→ status `clean`，不開 MR，結束本畫面。
- 有 kept → 進 stage 3。
- 結構性、需設計決策但無設計來源證據 → `wont-fix:design-redesign-not-bug`（非 bug）或 `deferred:needs-design`（是 bug、修法需設計），記 summary，不靜默吞。
- 「乾淨」的計算對象 = 所有 kept + deferred，不是「我選去修的那幾條」。
