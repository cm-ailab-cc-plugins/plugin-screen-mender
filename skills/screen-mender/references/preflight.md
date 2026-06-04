# screen-mender 環境快檢（preflight，plugin 自帶，generic）

> 何時跑：每次 run 起手（[`SKILL`](../SKILL.md) Phase 0.0），自動、無條件、無 `--doctor` 旗標。
> 怎麼跑：零設定、無狀態——全部 live 探測當前環境（指令存在？模擬器可自動備妥？CLI 已登入？檔案在？），不讀任何 profile。
> 為什麼：在冷編／長 run 之前，一次把「環境缺什麼」列清楚，而不是跑到一半才在某個 sub-agent 深處反應式爆掉（最貴的失敗＝ snapshot harness 沒設好，冷編後才炸）。

## 判級（每條探測歸一級）

- ❌ **硬缺**（確定且致命）→ 印完整 checklist + 每條「怎麼補」後**終止，不進 Phase 1**。
- ⚠️ **軟缺**（確定、可降級）→ 列出、降級後**續跑**。
- ❓ **可能缺**（靜態探測無法 100% 確定）→ 列出「需人工確認」、**不擋**；首個 capture 會真正驗證。
  - 為何不擋：
    - 專案可能用命名不同的等價機制（例：自訂 swizzler、別名 lib）。
    - 靜態 grep 探不到不代表真的缺；擋了會誤殺。
    - 把確定性留給「實際 capture 出不出得了圖」。

## 探測項

- 平台先測（項 1）。
- harness／DI 類的「該長怎樣」一律以 [`../../add-snapshot/references/setup.md`](../../add-snapshot/references/setup.md) 與 [`../../add-snapshot/references/<platform>.md`](../../add-snapshot/references/) 為準。
- 本檔只列「探什麼訊號、缺了去哪補」，不複製專案 lore。

> grep 探測在 zsh 下記得用引號包住 glob（`--include='*.gradle'`），否則被當檔名展開、報 `no matches found`。

### 共通

| # | 級 | 探測 | 訊號 | 缺了 |
|---|---|---|---|---|
| 1 | ❌ | 平台 | git toplevel 有 `gradlew`/`*.gradle*`→Android；`*.xcodeproj`/`*.xcworkspace`/`Podfile`→iOS | 皆無→硬缺終止（無法判定平台） |
| 2 | ❌ | 模擬器執行環境 | Android：`adb`＋`emulator`＋SDK 路徑可解析／iOS：`xcrun simctl` 可用 | 缺→硬缺（本機無法跑模擬器）；提示裝 Xcode／Android SDK |
| 3 | ⚠️/❌ | 裝置自動準備 | 跑 [`scripts/ensure-devices.sh`](../scripts/ensure-devices.sh) `--platform <P> --count <lanes>`：查自管 `test_phone_NN` pool→不足自建（指定機型不可用退本機最新；Android 無 avdmanager 走複製現有 AVD）→開機→stdout 回報 ready serial/udid | 回報 M 台：`M≥1`→以 M 條 lane 續跑（`M<lanes` 標降級、不靜默縮水）；`M=0` 或 script 印硬缺→終止（附 script 給的「怎麼補」） |
| 4 | ❌* | git host CLI 可用 | 取 remote host（見下〈git host 偵測〉）→ 對應 CLI（gitlab→`glab`／github→`gh`）已安裝且 `auth status` **涵蓋此 host** | host 判不出／對應 CLI 缺／該 host 未登入 → 硬缺。*`dry_run=true` 豁免（不開 MR）* |
| 5 | ❌ | 相依 skill·agent | sibling skill `add-snapshot`/`screen-list`/`shot-audit` ＋ agent `screen-mender-runner`（及其 `agents/references/01..05-*.md` 階段檔）皆在 | 任一缺→硬缺終止（依賴缺失無法起動） |

> **git host 偵測（self-hosted 也要對，勿只比 URL 字樣）**：
> 1. 取 host：`git remote get-url origin` → 去 scheme/user，留 host（`ssh://git@H:port/…`／`git@H:path` → `H`）。
> 2. fast-path：host 含 `gitlab`→`glab`；含 `github`→`gh`。
> 3. 自託管 fallback（host 是 IP／公司域名、無 gitlab/github 字樣）：`glab auth status` 的 host 清單含此 host → GitLab(`glab`)；`gh auth status` 含此 host → GitHub(`gh`)。
> 4. 皆未涵蓋（或兩者衝突）→ 判不出 mr_tool → 硬缺：提示 `glab auth login --hostname <host>` 或確認 host。
>
> 實例：自託管 remote `ssh://git@<host>:<port>/…`（host 為 IP 或內網域名）不含 gitlab/github 字樣 → 只比字串會判不出；須靠 `glab auth status` 列出該 host 才正確判為 GitLab。

### Android 專屬

| # | 級 | 探測 | 訊號 | 缺了 |
|---|---|---|---|---|
| A1 | ❌ | SDK 位置可解析 | canonical repo `local.properties` 含 `sdk.dir`，或環境有 `ANDROID_HOME`/`ANDROID_SDK_ROOT` | 皆無→硬缺（worktree 第一次 build 必 `SDK location not found` 白跑冷編）。orchestration §4 會把 `local.properties` 複製進 worktree，故 canonical 必須有它或有 env |
| A2 | ❓ | instrumentation runner | grep `app/build.gradle*` 有 `testInstrumentationRunner` | 無跡象→可能缺，見 setup.md step 7 |
| A3 | ❓ | debug activity | `app/src/debug/AndroidManifest.xml` 存在且宣告 activity | 無→可能缺，見 setup.md step 6 |
| A4 | ❓ | DI 框架在表內 | grep 依賴有 Koin/Hilt/Dagger 跡象 | 無→可能缺（capture 時 add-snapshot DI 偵測會 escalate），見 [`../../add-snapshot/references/android.md`](../../add-snapshot/references/android.md) §DI 偵測 |

### iOS 專屬

| # | 級 | 探測 | 訊號 | 缺了 |
|---|---|---|---|---|
| I1 | ❓ | snapshot library | `Podfile`/`Package.swift`/`*.xcodeproj` 有 `SnapshotTesting`（或等價 swift-snapshot lib） | 無跡象→可能缺，見 setup.md step 5 |
| I2 | ❓ | locale swizzler | test target grep 有 `localizedString(forKey` 的 swizzle（或等價 locale override 機制） | 無跡象→可能缺，見 setup.md step 4 |
| I3 | ❓ | DI 框架在表內 | grep 有 Swinject／手 init／Storyboard factory 跡象 | 無→可能缺，見 [`../../add-snapshot/references/ios.md`](../../add-snapshot/references/ios.md) §DI 偵測 |

## 報告格式（一次列完，分三段；範例 Android）

```
screen-mender 環境快檢 · 平台 Android · 目標裝置 4 台
✅ 模擬器執行環境（adb＋emulator＋SDK）   ✅ git host gitlab（glab 已登入）
✅ 相依 skill/agent 齊                      ✅ Android SDK（local.properties sdk.dir）
⚠️ 軟缺（降級後續跑）
   · 裝置自動準備備妥 2/4 台（無 avdmanager＋僅 1 個可複製模板）→ 本 run 降為 2 條 lane
   · 找不到指定機型 Pixel 8 → 已退用本機最新機型 pixel_10
❓ 可能缺（需人工確認，首個 capture 會驗證）
   · 找不到 instrumentation runner 設定（build.gradle 無 testInstrumentationRunner）→ add-snapshot/setup.md step 7
判定：無硬缺 → 續跑（2 lane）
```

```
screen-mender 環境快檢 · 平台 iOS · 目標裝置 4 台
✅ 模擬器執行環境（xcrun simctl）
✅ 裝置自動準備：test_phone_01..04 已建/重用並開機（4/4）
❌ 硬缺（無法起跑，請先補齊）
   · glab 未登入 → `glab auth login`
判定：有硬缺 → 終止，未起跑
```

## 判定

- 任一 ❌ 硬缺 → 印 checklist（每條附一句「怎麼補」或 setup.md 指引）+ **終止**，不進 Phase 1。
- 無硬缺 → 印 checklist（含 ⚠️ 已降級與 ❓ 待確認）後**續跑**。
- ❓ 可能缺一律不擋（理由見〈判級〉）。
- 探測本身只 live 查、零寫檔（不落 `.audit`、不寫 profile），維持無狀態。
