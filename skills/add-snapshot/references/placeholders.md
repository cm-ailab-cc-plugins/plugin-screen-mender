# add-snapshot — Placeholder 規約（單一來源）

> 何時讀本檔：填 host / test 範本、或要知道 placeholder 如何被 runtime 代入時。所有「逐畫面會被換成具體值」的 token 一律走大駝峰角括號形式；skill 本體不寫死任何專案字面。

## 共用 / 識別

| Placeholder | 用途 | 範例 |
|---|---|---|
| `<TargetClass>` | 呼叫者輸入的目標畫面類名（識別階段用） | `UseShieldScreen` |
| `<SnakeName>` | 畫面識別子（snake_case，用於 PNG 檔名） | `use_shield_screen` |
| `<SnakeFolder>` | host / test 檔的子資料夾（snake_case） | `shield` |
| `<SnapshotTestName>` | test class 名 | `UseShieldScreenInstrumentedTest` |
| `<FrameworkCell>` | 偵測到的 framework 類別 | `Android Compose + Koin` / `iOS SwiftUI` |
| `<DIContainer>` | DI container 識別名（Koin / Hilt / Dagger / Swinject / ServiceLocator / Manual）；決定 host 取依賴形式（`inject()` / `hiltViewModel()` / `container.resolve(...)`）與 seed 策略（Koin → `loadKoinModules` / Hilt → `@TestInstallIn` / 手 wiring → setter）。偵測表見 `references/<platform>.md §DI 偵測`。 | `Koin` |
| `<ResourcePrefix>` | 字串資源 ID prefix（C4 判斷 raw key 用） | `team_rule` |

## Locale

| Placeholder | 用途 | 範例 |
|---|---|---|
| `<LocaleTag>` | runtime locale tag，跑 test 時透過 argument / env var 傳；不寫進 host file | `vi` / `id` / `ja` |
| `<DefaultLocaleTag>` | host fallback BCP-47 locale tag（無 runtime arg 時使用） | `vi` / `ja` / `zh-Hant` |

## Android

| Placeholder | 用途 | 範例 |
|---|---|---|
| `<PackageName>` | Android package（dot form），用於 `package` 宣告與 import | `com.foo.bar.feature.shield` |
| `<PackageNamePath>` | Android package（slash form），用於檔案路徑 | `com/foo/bar/feature/shield` |
| `<HostActivityName>` | Android host activity 類名 | `UseShieldScreenHostActivity` |
| `<ComposableName>` | Android Compose function 名 | `UseShieldScreen` |
| `<DialogFragmentClass>` | Android XML DialogFragment 類名 | `EditNameDialogFragment` |
| `<Tag>` | `DialogFragment.show()` 用的 fragment tag | `edit_name_dialog` |
| `<CallsiteArgs>` | host body 內呼叫 target 傳的參數列 | `appUserLogger = noopLogger, onLater = {}, onConfirm = {}` |
| `<AppName>` | Application 子類名（純 Dagger 手刻 `<AppName>Component` 用） | `MyApp` |
| `<FQClassName>` | 跑命令過濾用的 test class 全限定名 | `com.foo.bar.feature.shield.UseShieldScreenInstrumentedTest` |
| `<emulator-serial>` | `ANDROID_SERIAL` 指定的 emulator serial | `emulator-5554` |

## iOS

| Placeholder | 用途 | 範例 |
|---|---|---|
| `<ModuleName>` | iOS module 名，用於 `@testable import` | `MyAppCore` |
| `<TargetName>` | iOS app target 名 | `MyApp` |
| `<TestTargetName>` | iOS test target 名（snapshot test 加入 PBXSourcesBuildPhase 用） | `MyAppTests` |
| `<WorkspaceName>` | `xcodebuild -workspace` 用（無 `.xcworkspace` 副檔名） | `MyApp` |
| `<SchemeName>` | `xcodebuild -scheme` 用 | `MyApp` |
| `<SwiftUIView>` | iOS SwiftUI View struct 名 | `TeamRuleView` |
| `<ClosureArgs>` | SwiftUI View init closure 參數 | `onAllStylesTapped: {}, onDismissed: {}` |
| `<VCClass>` | iOS UIViewController 類名 | `JoinTeamViewController` |
| `<StoryboardName>` | iOS Storyboard 檔名（無 `.storyboard` 副檔名） | `JoinTeamViewController` |
| `<NibName>` | 從 nib 載入的 view 的 nib 檔名（範本 E） | `TeamHeaderView` |
| `<ViewClass>` | 從 nib 載入的 `UIView` 子類（範本 E） | `TeamHeaderView` |
| `<SeedStatements>` | 範本 E 內比照 production 設 `@IBOutlet` / model 的種資料敘述 | `view.titleLabel.text = ...` |
| `<ReproduceLayoutConstraints>` | 範本 E 內 TEST-ONLY 重建 production 版面約束的敘述（讓 layout 缺陷現形，不碰 production） | `stack.distribution = .fillEqually` |

## placeholder 怎麼被代入

placeholder 不是「一次性 search-replace 進 skill 檔」的東西——skill 本體永遠保持泛用、角括號原樣不動。

- 代入時機：skill 在 §5 產 host / test 範本時，逐畫面用該畫面的實際值取代範本內的 `<CamelCase>`。
- 代入者：執行 skill 的 agent（runtime），依上表把每個 token 換成當前 `(TargetClass, LocaleTag, …)` 對應值，只寫進**產出的** host/test 檔。
- 因此同一份 skill 跨專案、跨畫面通用——不需複製資料夾、不需改 skill 任何檔。
