---
name: add-snapshot
user-invocable: false
description: >-
  給一個畫面識別子（class name / 截圖 / 自然語言描述）+ locale，產一張該畫面在指定 locale 的 PNG：自動偵測 DI、種子依賴、寫 host + snapshot test、跑測試、Read PNG 自驗（C1–C5）。雙平台（iOS / Android），平台細節分檔於 `references/<platform>.md`。

  觸發：要某元件 / 畫面 / dialog 的單張 locale 截圖。
---

# add-snapshot

## 1. Overview

把「為某個畫面 / 元件產一張固定 locale 的 PNG」從手刻變成可重複呼叫的食譜。

### 為什麼需要

- condition-gated UI 用一般 navigation 配方走不到：硬走會在中途 race condition。
- 走 component snapshot test 直接從 code 端 instantiate 該畫面，繞過所有導航。

condition-gated UI 例：

- 要剛好登入失敗才會跳的 dialog
- 要剛好斷網才會出現的 banner
- 要剛好某個 deeplink 才會打開的 sheet

**本 skill 不做的事**：

- 不修 production code——嚴格 0 diff；遇到鎖死的畫面就換畫面，不放寬規則。
- 不跑全 app build——snapshot test 是 module-local。

---

## 2. Input（三擇一）

呼叫者給以下任一種輸入：

1. **Class name / file path** — skill 直接 grep 找定義。
   - 例：`<TargetClass>` 或 `path/to/<TargetClass>.kt`
2. **截圖** — 使用者貼一張現有 PNG，skill 用 vision + OCR-by-LLM 反查對應的 composable / view / VC。
3. **自然語言** — skill 走「字串 → cid → 引用點」三角定位。
   - 例：「保護你連勝的盾牌頁」或「編輯暱稱的 dialog」

三種輸入最後都正規化成 `(TargetClassName, FilePath, LocaleTag)`。

LocaleTag 必填；無則向呼叫者要。

> 例：`vi` / `ja` / `ko` / `zh-Hant`。

---

## 3. Flow（6 階段）

- 骨架不可省，但每階段內 agent 有自由度。
- 本 SKILL.md 是平台無關骨架。

**先做：平台偵測**

- Android：有 `*.kt` / `build.gradle*`。
- iOS：有 `*.swift` / `*.xcodeproj`。

偵測後，§4 DI 表、§5 host 範本、§9.1a 跑命令都**只讀本次平台**的 [`references/<platform>.md`](references/)，不要讀另一平台那一檔。

```
[1] 識別 target            → 拿到 (ClassName, FilePath, FrameworkCell)
[2] 偵測 DI                → 查 § 4 → references/<platform>.md §DI，命中其一或上報 escalate
[3] 反查依賴鏈              → 列出 target 需要的 dep 種子（ViewModel / UseCase / Closure）
[4] 寫 host + snapshot test → 套 references/<platform>.md §Host 範本，填 placeholder
[5] 跑 test                 → references/<platform>.md §跑命令（gradle / xcodebuild）
[6] Self-verify PNG         → § 6 5 項檢查，過關 → 落地 / 不過關 → 重試 ≤ 3
```

每階段 fail-fast（見 §7）：

- 任一階段超時就上報呼叫者，不悶頭重試到天荒地老。

---

## 4. DI 偵測表

- agent 依下表順序偵測，命中其一即停。
- 雙平台共 6 種框架，至少要支援 Android 3 + iOS 3。

對照表（偵測訊號 + host 載入種子方式）依平台讀，**只讀本次平台那一檔**：

- Android（Koin / Hilt / Dagger / ServiceLocator）→ [`references/android.md`](references/android.md) §DI 偵測
- iOS（Swinject / 手 init / Storyboard factory）→ [`references/ios.md`](references/ios.md) §DI 偵測

未命中 → fail-fast，上報「請告訴我這個專案的 DI 系統」（見 §7）。

---

## 5. Host 範本（5 種 framework cell）

placeholder 一律 `<CamelCase>` 角括號形式，用途見 §8 → [`references/placeholders.md`](references/placeholders.md)。

host + snapshot test 範本依平台讀，**只讀本次平台那一檔**，別把另一平台的範本套進來：

- Android → [`references/android.md`](references/android.md) §Host 範本：範本 A（Compose）/ 範本 B（XML DialogFragment·View）
- iOS → [`references/ios.md`](references/ios.md) §Host 範本：範本 C（SwiftUI）/ 範本 D（Storyboard VC）/ 範本 E（nib cell·HeaderFooter）

---

## 6. Self-verify 5 項檢查

跑完 test、拿到 PNG 後，MUST 用 Read tool 讀 PNG 做 LLM 視覺判讀（本平台無 OCR runtime），逐項打勾：

| # | 檢查項 | 判準 | 不過關時動作 |
|---|---|---|---|
| C1 | 檔案大小 | PNG > 10 KB（小於此通常代表純空白 / 純單色） | 重跑；連 3 次小檔 → fail-fast 報錯 |
| C2 | 資料區非空 | 主視覺區至少 1 個可辨識文字 block（非僅 system bar / placeholder ring） | 改種子策略：fake stub → real DI seed；或 real DI seed → 在 host 多塞一層 fixture |
| C3 | locale 對 | 主視覺區無與 `<LocaleTag>` 不符的語言殘留（如 target 是 `vi` 卻見中文 / 英文 raw key `text_button_foo`） | 查 host `attachBaseContext` / swizzler 是否生效；補 fallback locale config（Android：emulator default locale；iOS：launch argument） |
| C4 | 無 fallback string | 截圖無 `(null)` / `???` / locale key 字面（如 `<ResourcePrefix>_title_foo` 直出） | string id 對不上 → 確認資源檔有該 key 對應 `<LocaleTag>` 翻譯；無翻譯則非 skill 能修，報給呼叫者 |
| C5 | 無 crash / blank dialog | 畫面 > 80% 面積不是純單色背景（用 vision 抓「是不是看起來就是空的」） | DI 漏注入 → 補節點種子；或 host 沒等到首幀 → 加 `Thread.sleep` / `wait(for: [exp])` |

重試上限 3 次（經驗預設值，可調）。

- 第 4 次仍 fail → 把 PNG + 自驗報告附給呼叫者，不丟一張壞圖蓋章說過了。

**確定性 + locale-faithful capture**（給拿 before/after 比對的消費者，如 screen-mender；做不到的項要在自驗報告標明，不可靜默）：

- 自訂字型須**同步註冊成功**再拍——間歇 fallback 會讓兩次 render 字型不同，製造假的截斷/爆框 delta。
- 忠實呈現目標語系需 harness 一併覆寫 `Locale.current`／`Calendar.current`（日期/數字/週幾）與 asset `preferredLocalizations`（在地化圖），不只換 app 字串 bundle；蓋不到 → 標這些項 `locale-unverifiable`。
- 內容隨機（`.shuffled()`／無 seed）須 seed 固定，否則同畫面兩次 render 不同、無法當 before/after 基準。

**Read PNG 視覺判讀的具體做法**：

1. 用 Read tool 讀 PNG（multimodal 直接解析圖像）。
2. 在 stdout 寫一段判讀：「我看到 X 個文字 block / Y 顏色 / Z 圖示 / 沒看到 ABC」。
3. 比對判準逐項勾選 C1-C5。
4. 任一項 fail → 寫進「自驗報告」段。
5. 5 項全過 → 寫「self-verify pass」到 stdout，PNG 算交付。

進階替代：

- 呼叫專案內已有 OCR binary（如 tesseract / VisionKit CLI），可優先用 OCR 抽 text block 再做精準比對。
- 無則純 LLM vision 即可。

---

## 7. Fail-fast SLA

每階段卡住的上限與超時動作：

| 階段 | 上限 | 超時動作 |
|---|---|---|
| [1] 識別 target | 2 分鐘 | grep 找不到 class → 上報「找不到 `<TargetClass>` 定義，請確認檔名」 |
| [2] DI 偵測 | 2 分鐘 | 6 種已知 framework 全不命中 → escalate「請告訴我這個專案的 DI 系統」 |
| [3] 依賴鏈反查 | 5 分鐘 | 超過 5 層 nested injection → 切到「不追鏈，直接 seed real DataSource」；仍卡死 → fail-fast |
| [4] Host + test 寫檔 | 3 分鐘 | 範本選錯 → 退回 step [1] 重判 framework cell |
| [5] 單次 build + test 跑 | 8 分鐘（Android instrumented test）/ 5 分鐘（iOS swift-snapshot） | 標 fail，不繼續重試；改用：換目標畫面，或上報呼叫者該畫面無法以 snapshot test 出圖 |
| [6] Self-verify 重試 | 3 次 | 第 4 次直接 fail 上報；不蓋章交差 |
| 整體 skill 跑 | 25 分鐘 | 用 return 值 / stdout 上報「skill 在 framework `<FrameworkCell>` 上撞壁」+ 試過什麼 + 建議；不寫 stuck.md / 任何紀錄檔 |

> 上表各階段分鐘數與重試次數均為經驗預設值，可依專案調整，非硬性不變量。

---

## 8. Placeholder 規約

所有「跨專案會被換成具體值」的 token 一律走大駝峰角括號形式（`<CamelCase>`）。

完整對照表（用途 / 範例 / 跨專案搬移）見 [`references/placeholders.md`](references/placeholders.md)——填 host / test 範本或搬移專案時讀。

---

## 9. Output 規格

skill 跑完後輸出三件事：

### 9.1 PNG 落地路徑

- on-device 截圖檔名固定 `<SnakeName>__<LocaleTag>.png`（test code 寫死）。
- pull 到 host 的落點 / 改名可由呼叫者覆寫。

**standalone 預設**（呼叫者未指定 dest）：

```
.audit/inbox/<platform>/previews/<SnakeName>__<LocaleTag>.png
```

**呼叫者覆寫**：

- orchestrator（如 screen-mender）可把 PNG pull 到自己的目錄並改名。
- 本 skill 只保證 on-device 來源檔名固定，dest 由呼叫端決定。
- 例：screen-mender 會 pull 到 ephemeral run 目錄、改名 `<platform>__<state>__<locale>.png`。

命名規則：

- `<platform>` ∈ `{android, ios}`。
- 預設路徑相對於 repo root（呼叫端 cwd）。
- 檔名以 `<SnakeName>` 起手、`__<LocaleTag>` 接尾（雙底線分隔以利後續 parser）。
- 例：`.audit/inbox/android/previews/use_shield_screen__vi.png` / `.audit/inbox/ios/previews/team_rule_view__id.png`。

`<LocaleTag>` 由 runtime arg 決定；無 arg 則用 host file 內的 `<DefaultLocaleTag>`：

- Android：`snapshot_locale` instrumentation arg。
- iOS：`SNAPSHOT_LOCALE` env var。

### 9.1a 跑特定 locale 的命令

指令依平台讀：

- Android（gradle `connectedDebugAndroidTest` / `adb am instrument`）→ [`references/android.md`](references/android.md) §跑命令
- iOS（`TEST_RUNNER_SNAPSHOT_LOCALE` + xcodebuild）→ [`references/ios.md`](references/ios.md) §跑命令

**執行方式（兩平台共通，必守）**：

- test 指令一律同步阻塞跑一次，stdout/stderr redirect 到 log 檔，跑完再讀 log 判結果。
- 禁 `run_in_background` + 反覆 tail/grep log 輪詢——那會吃掉大量 turn/token，且對 orchestrator 洗版狀態通知。
- cold build 慢是正常，耐心等一次即可，不是卡住。
  - 例：iOS ~130–150s 全編；warm 增量會快很多。

### 9.2 自驗報告（stdout）

agent 在最後一輪結束時 stdout 印一段：

```
SELF-VERIFY <SnakeName>__<LocaleTag>
  C1 size:        PASS / FAIL (XXX KB)
  C2 data-area:   PASS / FAIL (<comment>)
  C3 locale:      PASS / FAIL (<comment>)
  C4 fallback:    PASS / FAIL (<comment>)
  C5 visible-ui:  PASS / FAIL (<comment>)
DI: <DIContainer>
SEED STRATEGY: <real-koin-with-noop-logger | swinject-stub | storyboard-factory | ...>
ATTEMPTS: 1 / 2 / 3
```

### 9.3 Host 檔開檔註解

host / test 檔頭部 MUST 加 3 行註解，給下次重跑 / debug 時看：

```
// add-snapshot generated
// DI: <DIContainer>
// SEED: <strategy>
// SELF-VERIFY: pass at attempt <N>
```

---

## 10. 跨專案接入步驟

新 App 第一次用本 skill 的一次性 setup 見 [`references/setup.md`](references/setup.md)：

- 複製 skill
- 建 `.audit/inbox/` 目錄
- 確認 DI 框架在表內
- iOS swizzler + SnapshotTesting
- Android debug activity + instrumentation runner
- 跑通首個試跑 test

跑通後，後續畫面只需呼叫者輸入 `(TargetClass, LocaleTag)`，skill 自己跑完 6 階段。

---

## 11. 常見陷阱

平台專屬陷阱隨範本放在平台細節檔：

- Android → [`references/android.md`](references/android.md) §常見陷阱（Android）
- iOS → [`references/ios.md`](references/ios.md) §常見陷阱（iOS）

下面只列平台無關的：

| 陷阱 | 防呆做法 |
|---|---|
| macOS native `timeout` 不存在 | 一律 `gtimeout`（brew install coreutils）或 `perl -e 'alarm SECS; exec @ARGV'` |
| Spotless / SwiftFormat 漏跑 | 收尾 checklist 加 `./gradlew spotlessCheck` / `swiftformat --lint`；fail 跑 apply 後 re-commit |
| Production 0 diff 隱式下放 | 嚴格解釋；遇 final class / private lazy var 鎖死 → 換畫面，不加 `open` / 不加新 interface |
| sub-view（header / cell / 並列 label）的截斷 / 爆框在 detached host 不重現（free-floating 給該 label 全寬，缺陷消失）→ 拍到「假乾淨」圖、下游誤判已修 | host 內重建 production 版面約束才能讓 layout 缺陷現形；此為 TEST-ONLY 約束，不碰 production（iOS 範本 E 的 `<ReproduceLayoutConstraints>` 即此用途） |
