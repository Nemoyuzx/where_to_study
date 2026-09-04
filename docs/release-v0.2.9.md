# Where To Study iOS 0.2.9 TestFlight Hotfix

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
