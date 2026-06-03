# shot-audit — Android 細節規則

> 平台 = Android 時只讀本檔，不要讀 `ios.md`。共用骨架（Step 2 類別、Step 3 輸出、硬規則）回 SKILL.md 看。

## 字串系統

- 字串資源：`res/values*/strings.xml`（或專案的 string_mapping）。
- 引用點：`R.string.<key>` / `stringResource(R.string.<key>)`。
- raw key 直出（= translation-broken 訊號）範例：`text_button_foo`。

## Step 1 反查 code

找問題要先知道改哪。

1. Read PNG，列出畫面內可見字串，順便從字元範圍推斷 locale（例：標題／按鈕／說明／tab）。
2. 反查 key：對每個字串 grep `res/values*/strings.xml` 拿 resource key。
3. 取候選 code：對命中的 key 一次 ripgrep 帶所有 key alternation grep `R.string.<key>` 引用點，取交集 ≥ 2 個 key 的 source file 為主檔。
4. 對不到（純圖／數字畫面）→ 標 `low-text`，請使用者指認對應 `.kt` 檔，不硬猜。
