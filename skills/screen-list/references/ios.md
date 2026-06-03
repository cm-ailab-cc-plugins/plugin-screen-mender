# screen-list — iOS 細節規則

> 平台 = iOS 時**只讀本檔**，不要讀 `android.md`。回 SKILL.md 看共用骨架（四類定義、信心分層、輸出、硬規則）。

## 1. 找 registry（依序，最強命中為主）

1. **`UIViewController` 子類**（最強）：`class Xxx(VC|ViewController): UIViewController` —— 畫面的基本單位。
   - 含泛型 `<Strategy>` VC。
   - 含 `UIHostingController` 子類。
2. **Coordinator / router**：`pushViewController(...)` / `present(...)` callsite 確認哪些 VC 是真 destination。
3. **Storyboard scene**：每個 `.storyboard` 的 `<viewController>`。
4. **`UIHostingController(rootView:)` root**：被 host 的 SwiftUI View = 畫面。
5. **被 push / present 的 SwiftUI View**：`NavigationLink(destination:)` / `.sheet` / `.fullScreenCover`。

## 2. 四類捕捉目標的 iOS marker

**screen**

- §1 registry 上每個非容器 VC / 被 host 的 SwiftUI View（含次要 / 答題 / 結果 / 過場 / 設定 / 編輯頁，全收）。

**overlay**（含系統 chrome）

- `UIAlertController`
- `.alert` / `.sheet` / `.fullScreenCover` / `.popover` / `.confirmationDialog`
- `presentationDetents`
- `modalPresentationStyle = .overFullScreen/.overCurrentContext/.custom` 的 modal VC

**shell**

- `UITabBarController` / `MainTabBarController` 子類的 tab bar chrome

**不收**

- `UITabBarController` / `UINavigationController` / `UIPageViewController` 子類「作為頁」
- 空 base VC
- `UIView` 子元件
- `Debug*` / legacy

## 3. 判「頁 vs 子元件」的 iOS 訊號

- call-graph root：
  - 只被導航邊界 push·present = 畫面。
- 名字：
  - `*ViewController` / 被 host 的 `*View` 加分。
  - `*Cell/*Row` 扣分。
- 是否持 ViewModel。
- 是否全螢幕 layout。

## 4. census 對帳 marker（grep ground-truth）

**screen** → in-scope / excluded

- `: UIViewController` 子類宣告（含泛型 / `UIHostingController` 子類）
- `.storyboard` scene

**overlay** → in-scope

- `UIAlertController(`
- `.sheet` · `.fullScreenCover` · `.popover` · `.confirmationDialog`
- `presentationDetents`

**shell** → in-scope / excluded

- `UITabBarController` · `MainTabBarController` 子類

## 5. id 命名

class name 去 `ViewController` 後綴轉 snake_case：`NoteCenterViewController` → `note_center`。
