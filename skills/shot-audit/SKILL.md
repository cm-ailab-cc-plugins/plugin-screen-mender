---
name: shot-audit
description: 給一張 app 截圖（+ 可選 locale），找出畫面上看得見的跑版/視覺問題（截斷、爆框、重疊、錯位、譯文壞、locale 格式錯、對比不可讀），寫問題描述 + 調整建議。無狀態、雙平台（細節讀 `references/<platform>.md`）。觸發：「看這張截圖 UI 有沒有問題」「這張圖跑版在哪」。逐畫面修走 screen-mender。
---

# shot-audit

給一張截圖，找出畫面上看得見的跑版／視覺問題，寫成「問題 + 描述 + 調整建議」。無狀態、只診斷、雙平台。不做 triage、不附 AC（那是 screen-mender 的事）。

## 輸入

- 一張 PNG path（必填）。
- locale：可選；沒給就從畫面文字推斷。
- code 提示：可選；使用者已知對應 screen／檔案就直接給，可省 Step 1。

## 平台偵測（先做，決定讀哪個細節檔）

本 skill 雙平台，但單次只套一個平台的規則。先偵測：

- 有 `*.kt` / `build.gradle*` → Android，只讀 [`references/android.md`](references/android.md)。
- 有 `*.swift` / `*.xcodeproj` → iOS，只讀 [`references/ios.md`](references/ios.md)。

細節檔提供該平台的「字串系統」與「Step 1 code 反查」。本檔只放平台無關的部分：Step 2 分析、Step 3 輸出、硬規則。

## Step 1：對位 code

- 使用者已給 code 提示 → 跳過。
- 否則照細節檔 §Step 1 反查：列可見字串 → grep 該平台字串資源拿 key → grep 引用點取主檔。
- 對不到 → 標 `low-text`，不硬猜。

## Step 2：靜態 + 視覺合併分析（平台無關）

同時看截圖、Step 1 的 code、該 locale 字串值，找這些功能性問題：

- `truncation` / `wrap-overflow`：文字被截「…」、換行溢出、數字被切。
- `overlap` / 錯位：元素重疊、對齊跑掉、icon 被擠出。
- `contrast`：深色模式／底色對比不足、讀不到。
- `translation-broken`（文字內容完整性）：譯文錯／語意不通／raw key 直出（範例見細節檔）/ `(null)`·`???`；**拼接 artifact**——同詞重複（多段字串串接後重出，如 `Đặt … Đặt …`）、黏字或多餘空格、語法不通、機翻感。即使主訴是跑版，也順掃這類文字內容缺陷，別只盯版面。
- `backend-data-leak`：後台原始資料／預設 placeholder（`default-` 前綴）外露。
- `locale-format`：日期／數字／貨幣格式不符該 locale。
- `a11y`（看得見的）：看得見的可讀性問題。看不見的（缺 `contentDescription` / a11y label）不在範圍。

## Step 3：輸出

每條一個 block。無狀態，只印不存知識庫。

```markdown
## [high] truncation · vi 每日上限數字被截斷
- 觀察：vi `30 từ/ngày` 在 FooScreen.kt:67 的字串引用溢出進右側 icon
- 位置：FooScreen.kt:67（畫面右上「每日上限」列）
- 調整建議：移除外層固定寬約束，改自適應；或縮 vi 翻譯（走字串系統，不 hardcode）
```

- severity：`high`（影響可用／讀不到）/ `med` / `low`。
- 無問題 → 明說「未發現看得見的視覺問題」。

## 硬規則（最重要）

只報功能性 bug，不報「可以更好」的重新設計。以下一律不成立 issue（是設計選擇，不是 bug）：

- 動 layout container 結構（Row→Column、橫→直、卡片拆上下）。
- 新增／刪除 children（補說明文字、加 caption、刪重複 label）。
- 主觀美學（間距／配色／hierarchy 微調）。
- 臆測使用者困惑（「按鈕意圖不明顯」）。

判準：移掉這元件／改 layout container 後，原本能做的事還能做嗎？能 → 設計選擇，不報。

歷史 drift（真實發生過，這三類都不該報）：

- 把橫式三欄卡片報「改直式」→ 排版被毀。
- 報「按鈕缺說明文字」→ 下游疊 Text 文字重複。
- 報「label 與按鈕重複」→ 刪 label 造成雙平台 drift。

其餘硬規則：

- 禁腦補：「可能會」「也許」一律捨棄，看不出來就不報（只診斷單張截圖看得見的東西；臆測的缺陷無法驗證、只會污染下游修復佇列）。
- 無狀態：只輸出本次分析；不寫 `.audit/screens/` 知識庫、不記跨次記憶、不做依名稱查畫面。
- 不改 source code、不開模擬器、不裝 app：只診斷。
- 雙平台不混用：依 §平台偵測 只讀對應細節檔。

唯一「重設計」例外：

- 條件：能舉出對應 Figma node ID + 並排截圖證明「實機 vs 設計稿結構不符」才成立。
- issue body MUST 含 node ID + 並排圖，否則不報。
