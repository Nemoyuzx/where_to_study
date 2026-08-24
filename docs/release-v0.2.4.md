# Where To Study v0.2.4

## 中文

### 教学日历

- 全平台月视图和年视图支持双层同心 DDL 边框：外层、内层按“作业 DDL > 校内竞赛 > 其它 DDL”显示当天优先级最高的两类日程；三类内容仍会完整保留在日期详情和全天日程中。
- 今天与选中日期改用独立、高对比的状态标识，不再占用或覆盖 DDL 分类边框。
- Android 月/年日期格的外框与内框分别收细至 `1.2dp` 和 `0.8dp`，在手机、折叠屏和平板上保持一致。
- 桌面与平板日/周时间轴统一以实线表示整点、虚线表示课程节次，和 iOS 的时间层级一致。

### 桌面月视图

- Tauri 月视图的星期栏、日期、周数、课程/DDL 事件行、字号、文字位置、间距和选中态按原生 macOS 月视图重新对齐。
- 选中日期、今天、课程条和双层 DDL 边框可同时显示，避免一种状态覆盖另一种状态。

### 工程与发布

- 自动生成的效果截图目录改为本地生成物并加入 Git 忽略规则；现有截图从版本控制移除，发布包与商店素材仍按各自流程单独生成和校验。
- Android 发布门禁会解析 APK 的编译后 Manifest 与网络安全资源，确认默认禁用明文流量，并只为竞赛备用接口 `101.201.29.29` 保留单域例外。
- Android 版本为 `0.2.4 (37)`；iOS 与 macOS 版本为 `0.2.4 (65)`。
- GitHub Release 附件范围：Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及固定维护者密钥签名的 Android APK/AAB。`.sha256` 仅用于内部校验，不作为附件。
- TestFlight 分发范围：原生 iOS 与 macOS `0.2.4 (65)`，均已由本地 Xcode 完成签名归档并收到上传成功结果。Apple 制品不进入 GitHub Release；按发布约定未再打开 App Store Connect 检查后续状态。

---

## English

### Teaching calendar

- Month and year views now support two concentric DDL borders on every platform. The outer and inner borders show the two highest-priority categories for the day: assignment DDL, school competition notice, then other DDL. All three categories remain available in date details and all-day schedules.
- Today and the selected date now use independent, high-contrast indicators, so neither state consumes or replaces a DDL border.
- Android uses thinner `1.2dp` outer and `0.8dp` inner borders consistently across phones, foldables, and tablets.
- Desktop and tablet day/week timelines use solid lines for whole hours and dashed lines for class periods, matching the iOS time hierarchy.

### Desktop month view

- The Tauri month view now matches the native macOS geometry more closely, including weekday headers, date and week-number placement, course/DDL rows, font sizes, spacing, and selected states.
- Selection, today, course rows, and two DDL border categories can remain visible at the same time.

### Engineering and distribution

- Generated screenshot directories are now local build artifacts covered by Git ignore rules. Existing screenshots are removed from source control, while release and store artwork continues to be generated and verified separately.
- The Android release gate now parses the compiled APK manifest and network-security resource, enforcing HTTPS by default with a single-domain exception for the contest backup endpoint at `101.201.29.29`.
- Android is version `0.2.4 (37)`; native iOS and macOS are version `0.2.4 (65)`.
- GitHub Release scope: Windows x64 NSIS, Linux arm64/x86_64 Debian/AppImage/CLI/TUI, and maintainer-signed Android APK/AAB. `.sha256` files remain internal verification artifacts and are not attached.
- TestFlight scope: native iOS and macOS `0.2.4 (65)`. Both platforms completed signed local Xcode archives and returned successful upload results. Apple artifacts are not attached to GitHub Release, and App Store Connect was not opened for a follow-up status check.
