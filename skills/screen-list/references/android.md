# screen-list — Android 細節規則

> 平台 = Android 時**只讀本檔**，不要讀 `ios.md`。回 SKILL.md 看共用骨架（四類定義、信心分層、輸出、硬規則）。

## 1. 找 registry（依序，最強命中為主）

1. **自刻 router enum / sealed**（最強）：把導航目標列成 case 的 enum/sealed + `when(target)` dispatch。
   - 每個 case ≈ 一畫面。
2. **Jetpack NavHost**：`composable(...)` / `dialog(...)` / `bottomSheet(...)` 目的地。
3. **AndroidManifest `<activity>`**：補 router 沒涵蓋、Intent 直開的 Activity。
4. **nav_graph xml `<fragment>`**：tab 級 Fragment。
5. **Compose 入口**：`setContent { XxxScreen() }`、top-level `*Screen/*Page/*Route` composable。

## 2. 四類捕捉目標的 Android marker

**screen**

- §1 registry 上每個 standalone 頁（含次要 / 答題 / 結果 / 過場 / 設定 / 編輯頁，全收）。

**overlay**（含系統 chrome）

- `Dialog` / `AlertDialog` / `ModalBottomSheet` / `Popup` / `DropdownMenu` / `Snackbar` / `Toast`
- `DialogFragment` / `BottomSheetDialogFragment`
- `MaterialAlertDialogBuilder`

**shell**

- `MainActivity`
- 帶 `bottomBar` / `topBar` / `drawer` / `FAB` 的 `Scaffold`
- 持久 navigation bar

**不收**

- 容器 / 抽象 base「作為頁」
- `Debug*` / legacy
- `*Item/*Row/*Card/*Cell/*Section/*Bar` 等非浮動子元件

## 3. 判「頁 vs 子元件」的 Android 訊號

- call-graph root：
  - 只被導航邊界呼叫 = 畫面。
  - 被別 composable body include = 子元件。
- 名字：
  - `*Screen/*Page/*Route` 加分。
  - `*Item/*Row/*Cell/*Bar` 扣分。
- 是否持 ViewModel。
- 是否 `Scaffold` / `fillMaxSize`。

## 4. census 對帳 marker（grep ground-truth）

**screen** → in-scope / excluded

- router enum case
- `composable(` · `dialog(` · `bottomSheet(`
- `<activity>`
- `*Screen` · `*Page` · `*Route`

**overlay** → in-scope

- `DialogFragment` · `BottomSheetDialogFragment`
- `Dialog` · `ModalBottomSheet` · `Popup`
- `MaterialAlertDialogBuilder` · `Toast` · `Snackbar`

**shell** → in-scope / excluded

- `Scaffold` 帶持久 bar
- `MainActivity`

## 5. id 命名

class name 去 `Activity` / `Fragment` 後綴轉 snake_case：`NoteCenterActivity` → `note_center`。
