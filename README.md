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

## 文件結構與引用紀律（維護準則）

文件採 **hub-and-spoke**，避免長鏈與循環引用（最深引用 ≤ 1 層）。改文件時守以下四條：

**兩個 hub（進入點，always-loaded）**
- `skills/screen-mender/SKILL.md`（orchestrator）
- `agents/screen-mender-runner.md`（runner）
- 其餘 `references/*` 皆為 spoke。

**四條連結規則**
1. **hub → spoke（散開只發生在進入點）**：由 hub 負責連到它要用的 reference；spoke 不替 hub 散開。
2. **spoke 只指「另一個元件的進入點」，不指它的 `references/*` 內部**。跨元件＝handoff 到對方的樹根（如指 `add-snapshot/SKILL.md`，不指 `add-snapshot/references/setup.md`），不算加深本樹。
3. **共享規則書 `issue-schemas.md` 是「終點 sink」**：可被多檔指入（扇入是好事、DRY），但**永不往外指**。任何 `…→issue-schemas` 路徑就此終止。
4. **spoke 不回指 hub**：要提 hub 用純文字（如「見 SKILL Phase 1.0」），不掛連結。

**一句話**：扇入到 sink 沒問題；要避免的是 ①sink 外指、②指進別人 internals、③spoke 回指 hub——這三者才會造出鏈與環。純文字麵包屑（如「step 7」）不是導覽邊、不受此限，但仍以指向進入點為準。
