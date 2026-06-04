# plugin-screen-mender

逐畫面修復 App 截圖看得見的視覺跑版缺陷，雙平台 iOS/Android 自動偵測，一畫面一個小 MR 的完整修復閉環。

## 安裝

```
/plugin install screen-mender@cm-ailab-cc-plugins
```

## 內容

本 plugin 僅有 `screen-mender` 是使用者應該直接使用的 skill ，其餘 skill 為 plugin 內部呼叫用，請勿使用。

`screen-mender` 用法：
```bash
/screen-mender # 掃全部畫面、逐畫面修。
/screen-mender <畫面...> # 只掃指定畫面。
/screen-mender --dry-run [畫面...] # 試跑：照常偵測+修+驗，但不開 MR，產物落 run 目錄供檢視。
/screen-mender [自然語言描述]  #自然語言：「跑 screen-mender」「逐畫面修視覺跑版」「一畫面一個小 MR 修 UI」；試跑：「試跑 screen-mender」「先別開 MR、給我看會怎麼改」。
```

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
