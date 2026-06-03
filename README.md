# plugin-screen-mender

逐畫面修復 App 截圖看得見的視覺跑版缺陷，雙平台 iOS/Android 自動偵測，一畫面一個小 MR 的完整修復閉環。

## 安裝

```
/plugin install screen-mender@cm-ailab-cc-plugins
```

## 內容

**Skills**

| Skill | 用途 |
|-------|------|
| `screen-mender:screen-mender` | 逐畫面修復截圖看得見的視覺缺陷，一畫面一個小 MR 的完整閉環 |
| `screen-mender:screen-list` | 純讀 code 盤點「應該建截圖 test」的畫面清單 |
| `screen-mender:add-snapshot` | 給畫面識別子 + locale，產一張該畫面的 PNG（自動偵測 DI、寫 host + snapshot test） |
| `screen-mender:shot-audit` | 給一張截圖，找出畫面上看得見的跑版／視覺問題 |

**Agents**

| Agent | 角色 |
|-------|------|
| `screen-mender-developer` | 在 lane worktree 內依 AC 修復缺陷並 commit/push |
| `screen-mender-reviewer` | 審單一畫面修復的 diff（scope / redesign 把關） |
| `screen-mender-verifier` | 逐條比對 AC + 同畫面視覺等價掃描 |

## 平台

iOS / Android 雙平台，由 repo 檔案特徵自動偵測，零設定檔。
