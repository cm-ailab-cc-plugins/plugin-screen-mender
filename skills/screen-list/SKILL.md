---
name: screen-list
description: 掃 codebase，純讀 code 列出「應該建截圖 test」的目標——畫面 + 浮動元件（dialog / bottom-sheet / snackbar / toast / 系統 alert）+ 容器 chrome，輸出畫面的類別/函式清單。雙平台（細節讀 `references/<platform>.md`）。零外部清單、不產 test、不跑 emulator/sim、不改任何檔。觸發：「跑 screen-list」「列出該建截圖測試的畫面」「盤點畫面清單」。要實際產 test 走 add-snapshot；要逐畫面修跑版走 screen-mender。
---

# screen-list

掃 codebase，純讀 code 列出「應該建截圖 test」的目標，輸出分類好的清單供下游消耗。

## 定位

**輸入**

- 無（掃整個 codebase），或使用者指定的 module / 子目錄。

**輸出**

- 一份分類好的目標清單，類別為 screen / overlay / shell。
- 供 add-snapshot 逐個產 test、供 screen-mender 當 work queue。

**邊界** — 本 skill 到「清單」為止。

- 要產 test → `add-snapshot`。
- 要量產截圖矩陣 → 既有 run pipeline。
- 要逐畫面修跑版 → `screen-mender`。

## 平台偵測（第一步，決定讀哪個細節檔）

本 skill 雙平台，但單次只套一個平台的規則，**不混用**。先偵測：

- 有 `*.kt` / `build.gradle*` / `AndroidManifest.xml` → 平台 = Android，只讀 [`references/android.md`](references/android.md)。
- 有 `*.swift` / `*.xcodeproj` / `*.xcworkspace` → 平台 = iOS，只讀 [`references/ios.md`](references/ios.md)。
- 兩者皆有（monorepo）→ 依使用者指定平台跑。
  - 未指定平台時：兩平台各跑一輪，各讀各自細節檔。
  - 各出一份清單 `screen-list-<platform>.json`。
  - 兩邊規則不交叉。

細節檔提供該平台的：

- §1 registry 訊號 checklist
- §2 四類 marker
- §3 判「頁 vs 子元件」訊號
- §4 census marker
- §5 id 命名後綴

本檔（SKILL.md）只放平台無關的骨架。

## 原則

「畫面」由**站在導航邊界上**定義，不由 UI 長相定義。

- 接在導航入口 = 畫面。
- 被別的畫面 include = 子元件，不收。

每個 App 的 code 內建一份 screen registry——框架一定有地方列「我在哪些東西之間導航」。找到它，掛上面的就是畫面。純 code 推導，零外部 curated 清單。

## 偵測流程（平台無關骨架）

1. **找 registry**：依該平台細節檔 §1 的訊號 checklist，最強命中為主 registry。
2. **四類分類**：對列舉到的每個單位，歸成 screen / overlay / shell / 不收（定義見下），marker 查細節檔 §2。
3. **信心分層**（見下）排序與驗證。
4. **census 對帳**（見下），marker 查細節檔 §4。
5. **輸出**（見下）。

## 四類捕捉目標

定義平台無關；對應 marker 見細節檔 §2。

| 類別 | 定義 |
|---|---|
| screen | registry 上每個 standalone 頁，含次要 / 答題 / 結果 / 過場 / 設定 / 編輯頁——全收，不分 Tier、不延後 |
| overlay | 浮動元件（dialog / sheet / popup / snackbar / toast / 系統 alert）——全收，含系統 chrome（下游要查 locale 截斷 / 字串缺漏） |
| shell | 容器自有 chrome：「容器畫、子畫面孤立時看不到」的那塊。判準：這塊 chrome 在某子畫面 snapshot 裡會出現嗎？不會 → shell（升格成獨立目標） |
| 不收 | 容器 / 抽象 base「作為頁」、`Debug*` / legacy 模組（非當前維護標的、修跑版無收益）、非浮動子元件（隨宿主頁一起入鏡） |

## 信心分層

只決定順序與驗證，**不決定收不收**。

- **Tier A**：registry 確認的頁。
  - 直接列。
- **Tier B**：可列舉但 registry 未確認。
  - 先驗證再列——逐個確認真是 standalone 頁再列。
  - 只有確認「其實是子元件 / 容器」才落不收。

判「頁 vs 子元件」的具體訊號見細節檔 §3。

## census 對帳（no-silent-gap）

列舉後，對每個 marker（清單見細節檔 §4）跑一道機械式 grep census 取 ground-truth 數量，再把清單逐筆對帳回 census。差額每筆都要歸類，不准默默消失。

每個 census 命中必落入下列三類之一：

- `in-scope`：該建 test。
- `excluded`：真正非頁 + 理由。
- `ambiguous`：拿不準 + 理由。

**差額歸零才算掃乾淨**。漏判只會變「清單裡待確認」，不靜默消失。

## 輸出

寫兩份檔到輸出目錄 `<out_dir>`，並印分群摘要。

- `<out_dir>` standalone 預設 = repo 根的 `.audit/`。
- 呼叫者可覆寫落點，如 screen-mender 指向 ephemeral run 目錄以維持無狀態。

**`<out_dir>/screen-list.json`** — 機器可讀，給下游。

- monorepo 雙跑時檔名為 `screen-list-<platform>.json`。
  ```json
  [{ "id": "note_center", "kind": "screen", "platform": "android",
     "class_name": "NoteCenterActivity", "source_file": "feature/note/.../NoteCenterActivity.kt",
     "module": "feature:note", "status": "in-scope", "note": null }]
  ```
- `kind` ∈ `screen | overlay | shell`。
- `status` ∈ `in-scope | excluded | ambiguous`。
- `id` 命名規則見細節檔 §5。

**`<out_dir>/screen-list.md`** — 人類可讀。

- 按 module / feature 分群，每群列 screen / overlay / shell 各幾個 + 逐項。

**結尾 census 對帳段** — 各類總數 + 差額 = 0，證明真的全列到。

## 硬規則

- 純讀 code：**不產 test、不跑 emulator/sim、不改任何檔**。
- 零外部 curated 清單。
  - 不依賴 `INDEX.md` / navigate。
  - 畫面全從 code 推導。
- 全覆蓋、不預先過濾「值不值得拍」——那由下游 problem-finder 在圖上判斷。
- partial：拿不準的標 `ambiguous` + 理由，不靜默丟。
- 雙平台**不混用**：依 §平台偵測 只讀對應細節檔。
  - 不要把 Android marker 套到 iOS 專案、反之亦然。
