# add-snapshot — iOS 細節規則

> 平台 = iOS 時只讀本檔，不要讀 `android.md`。
> 共用骨架（流程 6 階段、self-verify、SLA、output）回 SKILL.md。
> 註：placeholder 表見 [`placeholders.md`](placeholders.md)、接入見 [`setup.md`](setup.md)、iOS 陷阱見本檔 §常見陷阱（iOS）。

## DI 偵測

- 依下表順序偵測，命中其一即停。
- 未命中 → fail-fast 上報。

| 平台 | DI 系統 | 偵測訊號（檔案 / 字串） | host 載入種子方式 |
|---|---|---|---|
| iOS | Swinject | Podfile / Package.swift 含 `Swinject`；存在 `Container.shared` 或類似 global | test `setUp` 用 `container.register(T.self) { _ in stub }` override 同 type |
| iOS | 手 init 注入（無 DI 容器） | VC / View 直接 `init(dep: Type())` 或 lazy var | host 直接傳 stub 給 init 參數；無 init 參數的舊 VC 用 subclass 改 lazy var 不行（會觸發 production diff）→ 改走「容忍真實 init + seed 真實下游 datasource」 |
| iOS | Storyboard + factory method | VC 有 `static func instantiate(...)` 含 `UIStoryboard(...)` | host 用 `UIStoryboard(name:bundle:).instantiateInitialViewController() as! <VCClass>`，instantiate 後注入 stub property 再 present |

## Host 範本（填 placeholder 規約見 [`placeholders.md`](placeholders.md)）

### 範本 C：iOS SwiftUI page / dialog（直 View，含 closure deps）

`<TestTargetName>/Snapshot/<SnapshotTestName>.swift`：

```swift
@testable import <ModuleName>
import LocalizationKit
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@available(iOS 17.0, *)
final class <SnapshotTestName>: XCTestCase {
    /// 從 env var `SNAPSHOT_LOCALE` 讀；無則 fallback `<DefaultLocaleTag>`。
    /// 注意：xcodebuild test 從 shell 注入 env 必須用 `TEST_RUNNER_` prefix
    /// （例 `TEST_RUNNER_SNAPSHOT_LOCALE=id`），prefix 在 inject 到 test runner process 時自動剝掉。
    /// 裸 `SNAPSHOT_LOCALE=` 與 `SIMCTL_CHILD_SNAPSHOT_LOCALE=` 都無效。
    private static var snapshotLocale: String {
        ProcessInfo.processInfo.environment["SNAPSHOT_LOCALE"] ?? "<DefaultLocaleTag>"
    }

    override class func setUp() {
        super.setUp()
        // BundleLocalizationSwizzler：swizzle Bundle.main.localizedString
        // 讓 NSLocalizedString 永遠回傳 snapshotLocale .lproj 內的字串
        BundleLocalizationSwizzler.install(localeIdentifier: snapshotLocale)
    }

    override class func tearDown() {
        BundleLocalizationSwizzler.uninstall()
        super.tearDown()
    }

    func testSnapshot() {
        let locale = Self.snapshotLocale
        let view = <SwiftUIView>(<ClosureArgs>)
        snapshotScreen(of: view, named: locale)
    }
    // baseline 由 swift-snapshot record 模式同步寫到 test 原始碼旁的
    // `__Snapshots__/<SnapshotTestName>/`（檔名含 `<LocaleTag>`）；模擬器與 host 共用 FS。
    // 取回 + 改名一律由呼叫者在 xcodebuild 跑完後做（見 §跑命令「取回 baseline」），test 碼不碰落點。
}
```

### 範本 D：iOS UIKit storyboard VC

```swift
@testable import <ModuleName>
import LocalizationKit
import SnapshotTesting
import UIKit
import XCTest

@available(iOS 17.0, *)
final class <SnapshotTestName>: XCTestCase {
    /// 從 env var `SNAPSHOT_LOCALE` 讀；shell 注入需用 `TEST_RUNNER_SNAPSHOT_LOCALE=...` prefix（見範本 C 註解）。
    private static var snapshotLocale: String {
        ProcessInfo.processInfo.environment["SNAPSHOT_LOCALE"] ?? "<DefaultLocaleTag>"
    }

    override class func setUp() {
        super.setUp()
        BundleLocalizationSwizzler.install(localeIdentifier: snapshotLocale)
    }

    override class func tearDown() {
        BundleLocalizationSwizzler.uninstall()
        super.tearDown()
    }

    func testSnapshot() {
        let locale = Self.snapshotLocale
        let storyboard = UIStoryboard(name: "<StoryboardName>", bundle: Bundle(for: <VCClass>.self))
        guard let vc = storyboard.instantiateInitialViewController() as? <VCClass> else {
            XCTFail("instantiate failed"); return
        }
        // 注入 stub properties（若 VC 有 lazy var ViewModel，可在此覆寫；
        // 無法覆寫 → 接受真實 VM + 跳過資料區自驗）
        vc.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        vc.beginAppearanceTransition(true, animated: false)
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()
        vc.endAppearanceTransition()

        // 等 Combine binding settle
        let exp = XCTestExpectation(description: "settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        snapshotViewController(of: vc, named: locale)
    }
    // baseline 落 `__Snapshots__/<SnapshotTestName>/`；取回由呼叫者做（見 §跑命令「取回 baseline」），test 碼不碰落點。
}
```

### 範本 E：iOS UIKit cell / `UITableViewHeaderFooterView` / xib view（從 nib 載入，非 storyboard、非 VC）

- 適用：tableview header/footer、cell、或任何從 `.xib` 載入的 `UIView` 子類。
- perfB 實證可跑。

```swift
@testable import <ModuleName>
import LocalizationKit
import SnapshotTesting
import UIKit
import XCTest

@available(iOS 17.0, *)
final class <SnapshotTestName>: XCTestCase {
    private static var snapshotLocale: String {
        ProcessInfo.processInfo.environment["SNAPSHOT_LOCALE"] ?? "<DefaultLocaleTag>"
    }
    override class func setUp() { super.setUp(); BundleLocalizationSwizzler.install(localeIdentifier: snapshotLocale) }
    override class func tearDown() { BundleLocalizationSwizzler.uninstall(); super.tearDown() }

    func testSnapshot() {
        let locale = Self.snapshotLocale

        // 1) 從 nib 載入
        let nib = UINib(nibName: "<NibName>", bundle: Bundle(for: <ViewClass>.self))
        let view = nib.instantiate(withOwner: nil).first as! <ViewClass>

        // 2) 種資料：比照 production 的 bind/configure 入口設 @IBOutlet / model
        <SeedStatements>

        // 3) host 進 sized 容器 —— ⚠️ pin VIEW 本體，**不要** reparent `contentView`
        //    （UITableViewHeaderFooterView/cell 的 contentView 必須保持 direct subview，
        //     抽出來 reparent → runtime crash "contentView must remain a direct subview"）
        let container = UIView()
        container.backgroundColor = .systemBackground
        view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.widthAnchor.constraint(equalToConstant: 393), // production 寬度，讓內部 autolayout 驅動高度
        ])

        // 4)（僅 layout 截斷/爆框類缺陷需要）TEST-ONLY 重建 production 版面約束才重現缺陷。
        //    detached host 預設 free-floating → 並列 label 會給某個全寬、缺陷消失 → 拍到「假乾淨」圖。
        //    例：把並列 StackView 設 .fillEqually + 寬度 pin，重現 production 的 N/N 切分。**不碰 production，只在 test 內套。**
        <ReproduceLayoutConstraints>

        container.setNeedsLayout(); container.layoutIfNeeded()

        // 5) 渲染（record-only）。若專案 SnapshotStrategy 有 UIView helper 就用之；無則 assertSnapshot 直打。
        XCTExpectFailure { assertSnapshot(of: container, as: .image, record: true) }
    }
    // baseline 落 `__Snapshots__/<SnapshotTestName>/`；取回由呼叫者做（見 §跑命令「取回 baseline」），test 碼不碰落點。
}
```

pbxproj：同範本 C/D。
- test 檔須加進 `<TestTargetName>` 的 PBXSourcesBuildPhase（4 anchors），否則 `Executed 0 tests`。
- 詳見下方 §常見陷阱（iOS）。

## 跑特定 locale 的命令

**iOS**：

```shell
TEST_RUNNER_SNAPSHOT_LOCALE=<LocaleTag> xcodebuild test \
  -workspace <WorkspaceName>.xcworkspace \
  -scheme <SchemeName> \
  -only-testing:<TestTargetName>/<SnapshotTestName>/testSnapshot \
  -destination 'generic/platform=iOS Simulator'
```

`TEST_RUNNER_` prefix 必填——Xcode 標準機制，裸 env 無效。

#### 取回 baseline（呼叫者做，test 不碰落點）

- 模擬器與 host 共用檔案系統；swift-snapshot record 模式把 PNG **同步**寫到 test 原始碼旁，xcodebuild 跑完即落地（不需等 teardown、不需 test 端 copy）。
- add-snapshot 剛把 test 建在已知路徑，故 `__Snapshots__` 目錄可直接組出、免全樹搜：

```shell
cp "<test .swift 所在目錄>/__Snapshots__/<SnapshotTestName>/"*<LocaleTag>*.png \
   "<呼叫者給的絕對 dest 目錄>/<SnakeName>__<LocaleTag>.png"
```

> 與 Android 對稱：test 只把圖產到 library 固定位置（iOS `__Snapshots__/` ／ Android on-device `snapshots/`），落點與改名一律呼叫者側（iOS `cp` ／ Android `adb pull`）；test 碼零落點邏輯。

#### 批量跑多 locale（一次跑一個語系）

```shell
for loc in vi ja ko id; do
  TEST_RUNNER_SNAPSHOT_LOCALE=$loc xcodebuild test ...   # 跑完各自 cp 取回（見上「取回 baseline」）
done
```

> 註：執行方式（同步阻塞跑一次、redirect log、禁輪詢）兩平台共通，見 SKILL.md §9.1a 尾段。

## 常見陷阱（iOS）

- 吸收歷次 retro 教訓的防呆清單。
- 平台無關陷阱見 SKILL.md §11。
- `TEST_RUNNER_` env prefix、`HeaderFooterView.contentView` 不可 reparent 已在上方 §跑命令 / §Host 範本 範本 E 註解內。

| 陷阱 | 防呆做法 |
|---|---|
| pbxproj 加 .swift target membership 漏 | 兩個 .swift 檔須加入 `<TestTargetName>` 的 PBXSourcesBuildPhase；用 `xcodeproj` gem ruby script 或手改 pbxproj 4 anchors；不改 GCC_PREPROCESSOR_DEFINITIONS / 不改 OTHER_LDFLAGS |
| Combine binding 沒 settle 就 capture | UIKit VC 範本 D 內 `wait(for: [exp], timeout: 1.0)` 等 settle 再截；SwiftUI 範本 C 由 `snapshotScreen` helper 內部等首幀 |
| storyboard VC `lazy var viewModel`（private）無法覆寫 | 改走 VC 公開 factory（如 `instantiate(dataModel:from:)`）的 stub 入口；無公開 factory → 換畫面 |
| Storyboard `formSheet` / popover modal VC 在 snapshot 渲染時被裁切 | 在 host 端覆寫 `vc.modalPresentationStyle = .fullScreen` 或用 `UINavigationController` 包裝；snapshot helper 內 frame 強設 `393 × 852` 對 modal-style VC 無效 |
