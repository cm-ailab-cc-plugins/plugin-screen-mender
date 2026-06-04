# add-snapshot — Android 細節規則

> 平台 = Android 時只讀本檔，不要讀 `ios.md`。
> 共用骨架（流程 6 階段、self-verify、SLA、output）回 SKILL.md。
> 註：placeholder 表見 [`placeholders.md`](placeholders.md)、接入見 [`setup.md`](setup.md)、Android 陷阱見本檔 §常見陷阱（Android）。

## DI 偵測

- 依下表順序偵測，命中其一即停。
- 未命中 → fail-fast 上報。

| 平台 | DI 系統 | 偵測訊號（檔案 / 字串） | host 載入種子方式 |
|---|---|---|---|
| Android | Koin | `build.gradle*` 含 `io.insert-koin`；Application 子類內有 `startKoin {}` block | host activity 直接 `GlobalContext.get().get<T>()` 拿生產實例；或用 `loadKoinModules(testModule)` override（不需 production code 改 open） |
| Android | Hilt | `build.gradle*` 含 `dagger.hilt.android.plugin` / `hilt-android`；存在 `@HiltAndroidApp` Application | `@HiltAndroidTest` + `@BindValue` 或 custom `@TestInstallIn` module；host activity 用 `@AndroidEntryPoint` 標註 |
| Android | Dagger（純 Dagger，無 Hilt） | `build.gradle*` 含 `com.google.dagger:dagger`；Application 內手刻 `<AppName>Component` | 自建 test component 繼承 production component，override `@Provides`；host 從 test component 取實例 |
| Android | ServiceLocator / 手 wiring | Application 內手動建單例 / `object` 持有實例；無 DI library 訊號 | host activity `onCreate` 前手工覆寫 service locator 內單例參考；用 `@VisibleForTesting` setter |

- host 載入種子方式照表。
- reflection 讀 instrumentation arg 的細節見下方範本 A 註解。

## Host 範本（填 placeholder 規約見 [`placeholders.md`](placeholders.md)）

### 範本 A：Android Compose（Composable function，含 DI ViewModel）

`app/src/debug/java/<PackageNamePath>/<SnakeFolder>/<HostActivityName>.kt`：

```kotlin
package <PackageName>

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.os.LocaleList
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import java.util.Locale

class <HostActivityName> : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) {
        val tag = readSnapshotLocale() ?: "<DefaultLocaleTag>"
        val targetLocale = Locale.forLanguageTag(tag)
        Locale.setDefault(targetLocale)
        val cfg = Configuration(newBase.resources.configuration).apply {
            setLocale(targetLocale)
            setLocales(LocaleList(targetLocale))
        }
        super.attachBaseContext(newBase.createConfigurationContext(cfg))
    }

    /**
     * 讀 instrumentation argument `snapshot_locale`；非 instrumentation context（debug launch、preview）回 null。
     * 用 reflection 而非 import `androidx.test.platform.app.InstrumentationRegistry`，因為 src/debug/ 看不到
     * androidTest classpath；直接 import 會撞 `Unresolved reference 'platform'`。
     */
    private fun readSnapshotLocale(): String? {
        return try {
            Class.forName("androidx.test.platform.app.InstrumentationRegistry")
                .getMethod("getArguments")
                .invoke(null)
                ?.let { it as? android.os.Bundle }
                ?.getString("snapshot_locale")
                ?.takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            <ComposableName>(
                <CallsiteArgs>
            )
        }
    }
}
```

對應 instrumented test `app/src/androidTest/java/<PackageNamePath>/<SnakeFolder>/<SnapshotTestName>.kt`：

```kotlin
package <PackageName>

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
class <SnapshotTestName> {
    @Test
    fun snapshot_<LocaleTag>() {
        val scenario = ActivityScenario.launch(<HostActivityName>::class.java)
        scenario.onActivity { activity ->
            // 等首幀 + 等 LaunchedEffect settle
            activity.window.decorView.postDelayed({}, 300)
        }
        Thread.sleep(400)
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val outDir = File(ctx.getExternalFilesDir(null), "snapshots").apply { mkdirs() }
        val outFile = File(outDir, "<SnakeName>__<LocaleTag>.png")
        scenario.onActivity { activity ->
            val bmp = android.graphics.Bitmap.createBitmap(
                activity.window.decorView.width,
                activity.window.decorView.height,
                android.graphics.Bitmap.Config.ARGB_8888
            )
            android.graphics.Canvas(bmp).also { activity.window.decorView.draw(it) }
            outFile.outputStream().use { bmp.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        }
        scenario.close()
    }
}
```

跑完後 pull PNG（dest 用呼叫者給的絕對路徑，直接指到 `run_dir`）：

```shell
adb pull /sdcard/Android/data/<PackageName>/files/snapshots/<SnakeName>__<LocaleTag>.png \
  <呼叫者給的絕對 dest 目錄>/<SnakeName>__<LocaleTag>.png
```

> 註：
> - on-device 來源檔名固定 `<SnakeName>__<LocaleTag>.png`，是唯一固定契約。
> - host 落點由呼叫者（screen-mender runner）以絕對路徑指定；本 skill 不預設任何持久落點。
> - 詳見 SKILL.md §9.1。

### 範本 B：Android XML DialogFragment / View（無 Compose）

`app/src/debug/java/<PackageNamePath>/<SnakeFolder>/<HostActivityName>.kt`：

```kotlin
package <PackageName>

import android.content.Context
import android.content.res.Configuration
import android.os.Bundle
import android.os.LocaleList
import androidx.appcompat.app.AppCompatActivity
import java.util.Locale

class <HostActivityName> : AppCompatActivity() {
    override fun attachBaseContext(newBase: Context) {
        val tag = readSnapshotLocale() ?: "<DefaultLocaleTag>"
        val targetLocale = Locale.forLanguageTag(tag)
        Locale.setDefault(targetLocale)
        val cfg = Configuration(newBase.resources.configuration).apply {
            setLocale(targetLocale)
            setLocales(LocaleList(targetLocale))
        }
        super.attachBaseContext(newBase.createConfigurationContext(cfg))
    }

    private fun readSnapshotLocale(): String? {
        return try {
            Class.forName("androidx.test.platform.app.InstrumentationRegistry")
                .getMethod("getArguments")
                .invoke(null)
                ?.let { it as? android.os.Bundle }
                ?.getString("snapshot_locale")
                ?.takeIf { it.isNotBlank() }
        } catch (e: Exception) {
            null
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setTheme(android.R.style.Theme_Material_Light_NoActionBar)
        if (savedInstanceState == null) {
            <DialogFragmentClass>().show(supportFragmentManager, "<Tag>")
        }
    }
}
```

instrumented test 與範本 A 同款（換 `<HostActivityName>` / `<SnakeName>`）。

## 跑特定 locale 的命令

**Android**：

```shell
# AGP connectedDebugAndroidTest 不吃 --tests（會 "Unknown command-line option '--tests'"）；
# 改用 runner arg class= 過濾，且 -P 與 configuration cache 不相容 → 必加 --no-configuration-cache。
# ANDROID_SERIAL 指定 emulator（勿用實體機）。
ANDROID_SERIAL=<emulator-serial> ./gradlew :app:connectedDebugAndroidTest \
  --no-configuration-cache \
  -Pandroid.testInstrumentationRunnerArguments.class=<FQClassName> \
  -Pandroid.testInstrumentationRunnerArguments.snapshot_locale=<LocaleTag>
```

或用 `adb -s <emulator-serial> shell am instrument -e class <FQClassName> -e snapshot_locale <LocaleTag> ...`。

> 註：執行方式（同步阻塞跑一次、redirect log、禁輪詢）兩平台共通，見 SKILL.md §9.1a 尾段。

## 常見陷阱（Android）

- 吸收歷次 retro 教訓的防呆清單。
- 平台無關陷阱見 SKILL.md §11。
- `--tests` 不支援、instrumentation arg 走 reflection 已在上方 §跑命令 / §Host 範本 註解內。

| 陷阱 | 防呆做法 |
|---|---|
| 單 method 跑 > 5 min hang | instrumented test SLA 5 min；超時直接 fail-fast pivot，不重試 |
| Compose Preview Screenshot Testing alpha 嘗試 | 明文禁用，不重試（穩定性差） |
| Emulator 多 agent 撞污染 | 僅當多個 test 並行共用同一台 emulator 才需序列化（`flock /tmp/android-emulator-<serial>.lock`）。呼叫端若已保證「一 lane 一 emulator」（如 screen-mender），各 test 各用自己的 `ANDROID_SERIAL`、不需 flock |
| mockk-android jvmti 16K page-size 失敗 | 預設不用 mockk-android；走 seed real data source / DI override 路徑 |
| `Theme.AppCompat` 不夠用 Material theme | 範本 B host activity 預設 `Theme.Material.Light.NoActionBar`；不夠時切 `Theme.MaterialComponents.Light.NoActionBar` |
| LaunchedEffect 內 analytics call 撞 network | host 改傳 noop logger 物件（不靠 DI），避免阻塞渲染或當 |
| `adb pull` 用 cwd 相對路徑 → 從 worktree 跑時落點會跟著 cwd 跑、呼叫者撈不到 | pull destination 一律用呼叫者給的**絕對路徑**（指到 `run_dir`），不要用 cwd 相對路徑 |
| feature module 內的 Composable 畫面：instrumented test 跑時 `TETheme` → `TECompositionLocal` → `getKoin()` 撞 `IllegalStateException("KoinApplication has not been started")`（feature module 的 androidTest 跑在自己的 test package，沒 `MyApplication` bootstrap Koin） | 該 module `src/androidTest` 加一個 module-local `SnapshotTestRunner`（custom `AndroidJUnitRunner`，`newApplication()` 內 `if (GlobalContext.getOrNull()==null) startKoin { androidContext(app); modules(emptyList()) }`）+ module `build.gradle.kts` 設 `testInstrumentationRunner`；直接沿用既有 `SnapshotTestRunner.kt` 範本 |
