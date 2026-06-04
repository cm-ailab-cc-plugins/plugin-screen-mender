# plugin-screen-mender

逐畫面修復 App 截圖看得見的視覺跑版缺陷，雙平台 iOS/Android 自動偵測，一畫面一個小 MR 的完整修復閉環。

## 安裝

```
/plugin install screen-mender@cm-ailab-cc-plugins
```

## 內容

**Skills**

對使用者開放：

| Skill | 用途 |
|-------|------|
| `screen-mender:screen-mender` | 逐畫面修復截圖看得見的視覺缺陷，一畫面一個小 MR 的完整閉環 |

內部 skill（`user-invocable: false`，由 runner／orchestrator 呼叫，使用者不可直接觸發）：

| Skill | 用途 |
|-------|------|
| `screen-mender:screen-list` | 純讀 code 盤點「應該建截圖 test」的畫面清單（screen-mender Phase 0 的 work-queue 來源）|
| `screen-mender:add-snapshot` | 給畫面識別子 + locale，產一張該畫面的 PNG（capture 階段用）|
| `screen-mender:shot-audit` | 給一張截圖，找出畫面上看得見的跑版／視覺問題（audit 階段用）|

**Agents**

| Agent | 角色 |
|-------|------|
| `screen-mender-runner` | 內部 agent：每畫面一個，手持 5 格 TODO 獨力跑 capture→audit→fix→審查驗證→MR 完整閉環，回精簡 summary（取代舊 developer/reviewer/verifier 三 agent，由 skill spawn、勿直接呼叫） |

## 平台

iOS / Android 雙平台，由 repo 檔案特徵自動偵測，零設定檔。
