# add-snapshot — 跨專案接入步驟

> 何時讀本檔：新 App 第一次用本 skill 的一次性 setup。跑通 step 6 後，後續所有畫面只需呼叫者輸入 `(TargetClass, LocaleTag)`，skill 自己跑完 6 階段。
>
> 本 skill 是 plugin 內建（`user-invocable: false`，由 screen-mender runner 呼叫）——**不需複製到專案、也不需在 skill 檔內 search-replace 任何值**。placeholder 是 runtime 產 host/test 檔時逐畫面代入的點（見 [`placeholders.md`](placeholders.md)），skill 自身保持泛用。下列步驟只是確認該專案具備 snapshot 出圖的前置條件。

1. **確認 DI 框架在對照表內**（`references/<platform>.md §DI 偵測`）
   - 不在就加一行 row 並對應寫一份 host 範本（PR 回 skill repo）。
2. **iOS swizzler + `Locale.current` 啟動 locale**
   - 確認 test target 內已有 swizzler / 等價的 locale override 機制；無則先建。
   - 典型：method swizzling `Bundle.localizedString(forKey:value:table:)`，安裝在 `XCTestCase.setUp` class method。
   - swizzler 只管 app 字串；另須在 test plan/scheme 設 App Language/Region（或命令帶 `-testLanguage`/`-testRegion`）讓 `Locale.current` 忠真，否則日期/星期/數字 formatter 顯模擬器 locale（見 [`ios.md` §`Locale.current` 忠真](ios.md)）。Android host `attachBaseContext` 已內建對等機制。
3. **iOS snapshot library** — 確認 `SnapshotTesting` / 等價 swift-snapshot library 已加入 test target（SPM 或 CocoaPods）。
4. **Android debug activity**
   - 確認 `app/src/debug/AndroidManifest.xml` 已宣告 debug-only activity 允許清單。
   - 無則在 `<application>` 內掛預設 `android:exported="false"` activity bucket。
5. **Android instrumentation runner**
   - 確認已設定。
   - 典型：`testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"`。
6. **建首個試跑 test** — 挑一個無 DI 依賴的純 View / 純 Composable 先跑通 skill 一輪，確認 PNG 能取到呼叫者指定的 dest 目錄。
