# add-snapshot — 跨專案接入步驟

> 何時讀本檔：新 App 第一次用本 skill 的一次性 setup。跑通 step 7 後，後續所有畫面只需呼叫者輸入 `(TargetClass, LocaleTag)`，skill 自己跑完 6 階段。

1. **複製 skill**
   - 把 `add-snapshot/` 整包複製到目標專案（或 `~/.claude/skills/` 全域）。
   - 依 [`placeholders.md`](placeholders.md) search-replace。
2. **確認 DI 框架在對照表內**（`references/<platform>.md §DI 偵測`）
   - 不在就加一行 row 並對應寫一份 host 範本（PR 回 skill repo）。
3. **iOS swizzler**
   - 確認 test target 內已有 swizzler / 等價的 locale override 機制；無則先建。
   - 典型：method swizzling `Bundle.localizedString(forKey:value:table:)`，安裝在 `XCTestCase.setUp` class method。
4. **iOS snapshot library** — 確認 `SnapshotTesting` / 等價 swift-snapshot library 已加入 test target（SPM 或 CocoaPods）。
5. **Android debug activity**
   - 確認 `app/src/debug/AndroidManifest.xml` 已宣告 debug-only activity 允許清單。
   - 無則在 `<application>` 內掛預設 `android:exported="false"` activity bucket。
6. **Android instrumentation runner**
   - 確認已設定。
   - 典型：`testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"`。
7. **建首個試跑 test** — 挑一個無 DI 依賴的純 View / 純 Composable 先跑通 skill 一輪，確認 PNG 能取到呼叫者指定的 dest 目錄。
