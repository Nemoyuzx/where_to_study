# Where To Study Apple 0.2.9 TestFlight Hotfix

## 0.2.9 (83) — iOS holiday-transition fix and year paging

Built and uploaded with local **Xcode 26.6** on **2026-09-06**, from application-source commit `2b4df61`. The iOS app and Widget archives both report **`0.2.9 (83)`**. Signed archive validation and Apple Distribution export validation, including the no-`get-task-allow` check, succeeded.

Xcode reported **`Upload succeeded` at 10:24:01 +0800** and **`EXPORT SUCCEEDED`**. No App Store Connect processing or test-group checks were performed afterward.

月视图在节假日不可用提示出现时继续完成水平动画；手机年视图支持左右切年、反向返回和保持纵向滚动位置，iPad 宽布局同步支持年份滑动。后台全年投影及可复用月份图层减少切换开销。具体性能结果与限制见[日历性能记录](ios-month-paging-performance-v0.2.9.md)。

The already-validated source has 325 iOS unit tests executed with one expected network skip and no failures; focused iPhone holiday-animation/year-navigation/detail flows and 13-inch iPad year navigation passed. Existing validation was reused for this upload rather than repeated.

Upload route: `scripts/native-apple-app-store.sh upload ios`, with `APPLE_MARKETING_VERSION=0.2.9`, `APPLE_BUILD_NUMBER=83`, and `APPLE_IOS_SIGNING_STYLE=Automatic`. The team was resolved locally from the installed Apple Distribution identity. This single invocation archived, validated, exported and uploaded once. The next upload must increment the build number.

Ignored receipt: `release-artifacts/ios-calendar-paging-029/ios-upload-83.log`. This upload is iOS-only; the GitHub stable Release and other platform packages are unchanged.

## 0.2.9 (82) — iOS month paging follow-up

Built with local Xcode 26.6 and uploaded on **2026-09-05**, from application-source commit `c0de962`. The iOS application and Widget archives both report **`0.2.9 (82)`**. Automatic-signing archive validation and local Apple Distribution export validation passed, including the no-`get-task-allow` check. The shipping executable contains no DEBUG month-frame probe label.

Xcode reported **`Upload succeeded` at 21:41:38 +0800** and **`EXPORT SUCCEEDED`**. No App Store Connect processing or test-group inspection was performed after that receipt. This is an iOS-only TestFlight follow-up: no macOS upload, GitHub Release replacement, or Android/HarmonyOS/Windows/Linux artifact rebuild is included.

### 中文说明

针对左右翻月掉帧，改用三个固定循环页面与可复用原生日期控件，后台准备月份快照，离屏页分行预热；避免翻页开头整页重建及收尾集中排版。等待目标页真正完成布局后才开始动画，保留反向连续翻页、跨月选日和折叠交互。修复零尺寸边框导致的图形错误日志，并加强切换账号、清空数据时的缓存隔离。

### Validation / 验证

- Final iOS unit suite: 292 executed, 1 opt-in live-network skip, 0 failures.
- Seven distinct focused UI flows passed: continuous gesture reversals, unobserved frame replay, out-of-month day selection, month expansion/year jumps, landscape stops/detail scrolling, week-agenda/month-details behavior, and English controls. The final cache-hit recency adjustment received another complete iOS unit run and frame replay.
- Shared-code macOS suite: 276 executed, 1 opt-in live-network skip, 0 failures. Repository contracts: 142/142 passed.
- Local screenshots were visually checked. Timing records, intermediate results and the explicit simulator/real-device limitations are in [the month-paging audit](ios-month-paging-performance-v0.2.9.md). The final replay improved first-callback latency and animation-start intervals; residual completion intervals remain, so this is not a zero-hitch or physical-device FPS guarantee.

### Upload receipt / 发布记录

Used the existing single command `scripts/native-apple-app-store.sh upload ios`, with `APPLE_MARKETING_VERSION=0.2.9`, `APPLE_BUILD_NUMBER=82`, and `APPLE_IOS_SIGNING_STYLE=Automatic`. The team was resolved from the locally installed Apple Distribution identity, not committed. The script performs archive, validation, export and upload; these steps were not separately repeated.

Ignored local evidence: `release-artifacts/ios-month-paging-029/ios-upload-82.log`, final unit/UI/replay logs, and screenshot folders. A later TestFlight upload must use a new build number; do not resend build 82 or check App Store Connect after this successful upload.

## 0.2.9 (81) — iOS and macOS loading follow-up

Both platforms were built with local Xcode 26.6 and uploaded on **2026-09-05**, from application-source commit `1ae10f2`. Main application and Widget versions were verified as `0.2.9 (81)` in both archives.

- iOS: Automatic signing, archive validation, local Apple Distribution export validation (including no `get-task-allow`), and upload completed. Xcode reported **`Upload succeeded` at 17:53:06 +0800** and **`EXPORT SUCCEEDED`**. A developer-services TLS warning occurred earlier in the same upload; that process continued and succeeded without resubmitting the build.
- macOS: Manual App Store profiles and the installed Installer Distribution identity; signed archive validation and upload completed. Xcode reported **`Upload succeeded` at 17:55:43 +0800** and **`EXPORT SUCCEEDED`**.
- No App Store Connect processing or test-group checks were performed after upload. Upload success is not a claim that Apple has finished processing or that every tester can already install the build.
- The GitHub stable Release and repository-wide default version remain `0.2.8`. This Apple-only TestFlight update does not replace other platform artifacts or publish an iOS binary on GitHub.

### 中文说明

将正式启动的课表/空教室缓存读取与解析、节假日缓存读取和刷新落盘移出主线程；避免缓存尚未恢复就重复获取数据。使用代际校验防止清除数据、修改账号或切换模式后旧结果回写。iOS/macOS 导航状态独立于全局业务数据，查询服务持久复用并区分真实/示例模式。重要事件在后台建立并复用搜索索引，翻页不重复解析全量截止时间。日历使用有界会话缓存、合并数据失效通知和预计算课程轨道，分钟刷新缩小到时间相关内容；同时修复首次数据早于缓存订阅到达导致全天区空白的竞态。

### Validation / 验证

- macOS: 254 unit tests executed, 1 opt-in network skip, 0 failures.
- iPhone: 261 unit tests and 28 UI tests executed, 6 combined conditional skips, 0 failures; an additional final four-flow UI run passed 4/4 with an isolated result bundle.
- iPad: English controls, all-day event/header alignment and corner selection, rotation/sidebar retention, primary navigation — 4/4 passed.
- Repository contracts: 142/142 passed. Local live-data visual checks and background-worker stack sampling are documented in [the performance audit](apple-performance-v0.2.9.md), including the limitations of those measurements.

### Repeatable upload path / 后续发布路径

Use `scripts/native-apple-app-store.sh upload ios` with `APPLE_IOS_SIGNING_STYLE=Automatic`, then `upload macos` with `APPLE_MACOS_SIGNING_STYLE=Manual`. For this release set `APPLE_MARKETING_VERSION=0.2.9` and `APPLE_BUILD_NUMBER=81`; a later upload must increment the build number. Resolve `APPLE_DEVELOPMENT_TEAM` from the locally installed Apple Distribution identity rather than committing signing configuration. Each `upload` call already archives, validates and uploads: do not separately repeat `archive → export → upload`. Stop at successful upload, not an App Store Connect browser check.

Ignored local evidence: `release-artifacts/apple-performance-029/ios-upload-81.log`, `macos-upload-81.log`, unit/UI logs and isolated `.xcresult` bundles.

## Earlier iOS-only 0.2.9 (80)

`0.2.9 (80)` is an iOS-only performance hotfix built and uploaded from local Xcode on 2026-09-05. The repository-wide default version and the GitHub stable release remain `0.2.8`; macOS, Android, HarmonyOS, Windows, Linux, CLI, and TUI packages were not rebuilt or replaced.

## 中文说明

- 将 iPhone/iPad 一级栏目选择从全局数据模型中隔离，避免切换底部导航或侧栏时让全部重页面同时重绘。
- 教学日历离开页面后继续保留有界的月/年快照缓存，返回时不再无条件重建当前月或全年数据。
- 月视图完全展开时不再构造不可见的当日日程、课程作业、黄历和活动 DDL 卡片树；收起后仍完整恢复原有详情、滚动和手势逻辑。
- iOS 启动后提前异步获取班车数据，查询页不再把首次请求初始化绑定到切换首帧；真实数据与内置示例数据使用独立缓存，互不覆盖。
- 本机 Xcode 完整测试累计 267 项通过、6 项设备或显式联网门控跳过、0 失败；最终模式隔离补丁另有 15 项针对性测试通过、1 项显式联网门控跳过、0 失败。Debug 模拟器连续切换采样未发现网络或 JSON 解析阻塞主线程。
- 正式归档中的 iOS 主应用与 Widget 均为 `0.2.9 (80)`。签名归档、Apple Distribution 导出校验和上传均成功，并收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`；按发布约定未继续检查 App Store Connect processing。

## English

- Isolated iPhone and iPad primary navigation selection from the global data model so tab and sidebar changes no longer invalidate every heavyweight page at once.
- Preserved the bounded month/year snapshot cache while the calendar tab is hidden, avoiding unconditional reconstruction when users return.
- Replaced the fully hidden month-detail card tree with a lightweight, geometry-stable viewport while the month is expanded. Daily schedule, assignment, almanac, deadline, scrolling, and gesture behavior still return when details are shown.
- Prewarms shuttle data asynchronously at the iOS root and reuses it in Query. Live and built-in sample data use separate stores so stale requests cannot cross runtime modes.
- Local Xcode validation completed with 267 passing tests, 6 device or opt-in live-network skips, and no failures. The final mode-isolation change received another 15 focused passes, one opt-in live-network skip, and no failures. Repeated Debug Simulator switching samples showed no network or JSON parsing work blocking the main thread.
- Both the iOS app and Widget in the signed archive report `0.2.9 (80)`. Automatic-signing archive, Apple Distribution export validation, and upload completed with `Upload succeeded` and `EXPORT SUCCEEDED`. App Store Connect processing was intentionally not inspected afterward.

No iOS binary is attached to GitHub Releases.
