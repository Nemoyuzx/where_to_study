# Where To Study v0.2.6

## 中文

### 教学日历与日程

- 所有图形客户端、CLI/TUI 统一使用 ISO 8601 公历周，并与真实教学周同时显示；跨年边界使用同一算法。
- 全平台移除基于第 17、18 个周次的考试周推断，以及 UI、通知、系统日历、菜单栏和小组件中的考试标记。v1 兼容字段继续保留，但运行时与新缓存始终为空。
- macOS/Tauri/HarmonyOS 桌面月格直接显示课程、作业、校内通知和其它活动 DDL；下方课程摘要只显示课程，作业、黄历和活动卡各保留一次。
- macOS 年视图日期弹卡改为独立可滚动区域；Tauri 年弹卡也验证了真实滚轮滚动。
- 收藏管理改为真正的顶层或设置子页面，不再通过移除/隐藏主导航伪装跳转。

### 自适应布局与性能

- Android 平板与折叠屏复用手机教学日历顶部和统一分页状态机，修复反向切换跳帧、日期锚点丢失和年视图横滑。
- Android 折叠侧栏使用 foreground 层严格横纵居中；UI 坐标验证中心误差不超过 1 dp。
- iPad、macOS、Android 宽屏、HarmonyOS 宽屏和 Tauri 宽屏的空教室结果均支持两栏。
- Apple 月/年视图按日期一次索引课程、节假日和 DDL，缓存月/年快照并复用单个年份网格，减少拖拽和翻页时的重复 CPU 计算；未声称未经 Instruments 验证的 GPU 加速。
- Tauri 完成宽/窄屏、深/浅色、中/英文的日/周/月/年、设置、收藏和空教室视觉矩阵，并修复窄屏操作栏与收藏空页布局。

### 版本与分发

- Android：`0.2.6 (42)`，固定维护者证书签名的 Universal APK/AAB。
- iOS 与原生 macOS：`0.2.6 (70)`，本地 Xcode 归档并上传 TestFlight；两端均收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`，按约定未继续检查 App Store Connect processing。
- HarmonyOS：`0.2.6 (1002009)`，签名 HAP/App 构建与 112 项单元测试通过；DevEco 上传向导显示当前 AGC 账户没有已注册应用，确定按钮被禁用，因此无法创建内测。GitHub Release 改为提供已验证的签名 APP/HAP 构建。
- GitHub Release 恢复原生 macOS Universal DMG，同时继续提供 Windows、Linux、CLI/TUI、Android 和 HarmonyOS 制品。DMG 包含 `arm64 + x86_64`、标准 Applications 快捷方式并通过签名和镜像校验，但未使用 Developer ID 公证；优先推荐 TestFlight 版本。

### 验证

- Node 契约与主题测试：114/114。
- Tauri Rust：146 通过，1 个需要真实账号和在线服务的测试按设计忽略。
- Apple：macOS 204 项、iOS 210 项单元测试通过；iPhone 核心 UI、iPad Pro 13 英寸横屏与 macOS 视觉/滚动回归通过。
- Android：186/186 Release JVM 测试、Lint、签名 APK/AAB、Phone/Fold UI smoke 与平板/折叠屏视觉检查通过。
- HarmonyOS：112/112 ArkTS 单元测试与签名构建通过。
- CLI/TUI：各 14 项测试通过。

## English

### Teaching calendar and schedules

- Every graphical client plus the CLI/TUI now uses the same ISO 8601 calendar-week rule and shows it alongside the authoritative teaching week.
- Positional exam-week inference and all exam badges were removed from UI, notifications, calendar export, menu-bar, and widget presentation. The v1 compatibility field remains but is always empty at runtime and in new caches.
- Desktop month cells on native macOS, Tauri, and HarmonyOS now include courses, assignments, school notices, and other activity deadlines. The selected-day course summary contains courses only, while assignment, almanac, and deadline cards each appear once.
- Native macOS year-day popovers now have an independently scrollable body. Tauri year popovers were also verified with real wheel input.
- Favorite management is now a real top-level or Settings subpage instead of hiding the primary navigation as a routing workaround.

### Adaptive layout and performance

- Android tablets and foldables share the phone calendar header and pager state machine, fixing reverse-transition jumps, preferred-day loss, and year-view swiping.
- Collapsed Android rail icons use a centered foreground layer; UI-bound checks keep both-axis center error within 1 dp.
- Empty-classroom results use two columns when width permits on iPad/macOS, Android, HarmonyOS, and Tauri.
- Apple month/year views index date data once, cache snapshots, and reuse a single year grid to reduce repeated CPU work during drag and paging. This release does not claim unmeasured GPU acceleration.
- Tauri received a wide/narrow, light/dark, Chinese/English visual matrix across planner, day/week/month/year, Settings, and Favorites.

### Versions and distribution

- Android: `0.2.6 (42)`, pinned-maintainer-certificate Universal APK/AAB.
- Native iOS and macOS: `0.2.6 (70)`, archived and uploaded with local Xcode. Both uploads returned `Upload succeeded` and `EXPORT SUCCEEDED`; App Store Connect processing was intentionally not inspected afterward.
- HarmonyOS: `0.2.6 (1002009)`, signed HAP/App build plus 112 unit tests passed. DevEco's upload wizard found no registered app in the current AGC account and disabled submission, so verified signed APP/HAP artifacts are published on GitHub instead.
- GitHub Release restores a native universal macOS DMG alongside Windows, Linux, CLI/TUI, Android, and HarmonyOS artifacts. The DMG contains `arm64 + x86_64`, an Applications shortcut, and passed signature/image validation, but is not Developer-ID notarized; TestFlight remains the recommended macOS channel.

### Validation

- Node contracts/theme: 114/114.
- Tauri Rust: 146 passed, 1 live-account test intentionally ignored.
- Apple: 204 macOS and 210 iOS unit tests, core iPhone UI, 13-inch iPad landscape, and macOS visual/scroll regressions passed.
- Android: 186/186 Release JVM tests, Lint, signed APK/AAB validation, Phone/Fold UI smoke, and tablet/foldable visual QA passed.
- HarmonyOS: 112/112 ArkTS tests and signed build passed.
- CLI/TUI: 14 tests each passed.
