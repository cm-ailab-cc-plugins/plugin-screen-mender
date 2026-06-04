# Stage 1 — capture（產圖）

在 lane worktree 內確保該畫面有 snapshot test，跑出一張過渲染閘的截圖當修復基準。

## Inputs
- `worktree` / `branch` / `device_serial` / `unified_id` / `capture_locale` / `extra_audit_locales`
- `run_dir`（截圖落 `<run_dir>/<unified_id>/`）

## Procedure
1. 該畫面 snapshot test 是否存在？
   - 是 → 重用，直接重跑出最新截圖。
   - 否 → 用 Skill `add-snapshot` 在 worktree 內建 test 並出截圖（`capture_locale`）。test 隨修復一起進 MR。
2. 在 `device_serial` 上跑、pull 截圖到 `<run_dir>/<unified_id>/before__<state>__<locale>.png`。
   - add-snapshot 的 on-device 檔名固定 `<snake>__<locale>.png`；pull 後改名成上面統一命名。
   - 單一 state → `state=default`。
3. 條件式 UI 種對 state——種**最壞的真實內容**（最長字串／最極端 state；caller-driven 文案種真實呼叫點的最長訊息）。種錯 → 拍不到、下游誤判已修。
4. 多 locale（`extra_audit_locales` 非空）→ 每個 extra locale 各出一張（換 locale runtime arg，檔名以 locale 區分）。預設只出 `capture_locale` 一張。
5. **C1–C5 渲染標準閘**（正典 [`add-snapshot §6`](../../skills/add-snapshot/SKILL.md)）：C1 檔 >10KB / C2 資料區非空 / C3 locale 對 / C4 無 fallback 字串 / C5 無 crash·空白。
6. capture 保真度旗標（**須回報、不可靜默**，見 [`issue-schemas`](../../skills/screen-mender/references/issue-schemas.md) §3.5）：
   - `font-fidelity-degraded`：自訂字型未註冊、fallback 到系統字型（系統字型通常較寬、會遮蔽字型專屬爆框）。
   - `representative-render`：以重建 chrome（非 live 控制器）出圖。
   - `capture-nondeterministic`：內容隨機／async／字型間歇 fallback。**同 state 連拍兩張比對**，不一致 → 固定 seed；seed 不了則標此旗標（before/after 不可比，下游不得在其上判視覺等價 PASS）。
   - `locale-unverifiable`：harness 只換 app 字串、沒換 `Locale.current`／`Calendar.current`／asset `preferredLocalizations` → 日期·數字·週幾·在地化圖仍顯模擬器語系；相關缺陷轉人工/真機。

## Output（runner 記下，供後續階段）
- before 截圖路徑（每 state/locale 一張）。
- `build_cmd` / `snapshot_test_cmd`：add-snapshot 回報的實際指令——**後面 fix / verify 階段重用**（test 已存在則同樣回報其重跑指令）。
- `capture_report`：C1–C5 是否過 + `fidelity_flags[]`。

## Exit
- 渲染不出（需 production seam）→ status `locked`；一渲染就 crash → status `defect`。兩者列 backlog、結束本畫面（其餘 TODO 標掉、不開 MR）。
- retry 上限仍 fail（暫時性）→ 同上，記 summary。
