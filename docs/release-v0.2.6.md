# Where To Study v0.2.6

## 中文

### 教学日历与日程

- 所有图形客户端、CLI/TUI 统一使用 ISO 8601 公历周，并与真实教学周同时显示；跨年边界使用同一算法。
- 全平台移除基于第 17、18 个周次的考试周推断，以及 UI、通知、系统日历、菜单栏和小组件中的考试标记。v1 兼容字段继续保留，但运行时与新缓存始终为空。
- macOS/Tauri/HarmonyOS 桌面月格直接显示课程、作业、校内通知和其它活动 DDL；下方课程摘要只显示课程，作业、黄历和活动卡各保留一次。
- macOS 年视图日期弹卡改为独立可滚动区域，并直接锚定被点击的日期格；窗口边缘自动换向，连续点击另一个日期时弹卡会直接移动。HarmonyOS 宽屏/二合一同步使用点击坐标定位；Tauri 年弹卡也验证了真实滚轮滚动。
- 收藏管理改为真正的顶层或设置子页面，不再通过移除/隐藏主导航伪装跳转。

### 自适应布局与性能

- Android 平板与折叠屏复用手机教学日历顶部和统一分页状态机，修复反向切换跳帧、日期锚点丢失和年视图横滑。
- Android 折叠侧栏使用 foreground 层严格横纵居中；UI 坐标验证中心误差不超过 1 dp。
- iPad、macOS、Android 宽屏、HarmonyOS 宽屏和 Tauri 宽屏的空教室结果均支持两栏。
- Apple 月/年视图按日期一次索引课程、节假日和 DDL，缓存月/年快照并复用单个年份网格，减少拖拽和翻页时的重复 CPU 计算；未声称未经 Instruments 验证的 GPU 加速。
- Apple build 72 将 iPhone 月、年快照拆分为独立缓存并按可见月份构建，移除详情整树交叉淡入、重复视图内数据加载、冗余折叠尾任务和逐帧滚动容器查找；黄历、作业和 DDL 状态只刷新各自卡片。macOS 年视图弹卡恢复日期格锚点并保留滚动。
- Tauri 完成宽/窄屏、深/浅色、中/英文的日/周/月/年、设置、收藏和空教室视觉矩阵，并修复窄屏操作栏与收藏空页布局。

### 版本与分发

- Android：`0.2.6 (42)`，固定维护者证书签名的 Universal APK/AAB。
- iOS 与原生 macOS：`0.2.6 (72)`，由本机 Xcode 分平台归档并上传 TestFlight；iOS 使用 Xcode 自动管理签名，macOS 使用手动 App Store profile 与 Installer Distribution 证书。两端均收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`，按约定未继续检查 App Store Connect processing。
- HarmonyOS：`0.2.6 (1002010)`，Release 签名 HAP/App 构建、签名摘要验证与 113 项单元测试通过；DevEco 已上传 AppGallery Connect、云测试通过并绑定至 `0.2.6` 发布草稿。GitHub 同时保留已验证签名资产；[打开 HarmonyOS 测试邀请](https://appgallery.huawei.com/link/invite-test-wap?taskId=dfc32d0293987b9d09911717759ac063)，邀请码为 `A0IsJpKIcn3`。
- GitHub Release 的原生 macOS Universal DMG 已刷新为 `0.2.6 (72)`，HarmonyOS APP/HAP 刷新为 `0.2.6 (1002010)`；Windows、Linux、CLI/TUI 和 Android 资产因产品源码未变化而保持不变。DMG 包含 `arm64 + x86_64`、标准 Applications 快捷方式并通过签名和镜像校验；该预览包未使用 Developer ID 公证。`v0.2.6` 标签不强制移动，刷新资产来自标签后的 `main` 修复。

### 验证

- Node 契约与主题测试：114/114。
- Tauri Rust：146 通过，1 个需要真实账号和在线服务的测试按设计忽略。
- Apple：macOS 211 项、iOS 218 项单元测试和 4 项关键 iPhone UI 回归通过；本机严格 Release 归档、双平台签名/隐私/App Group/许可证校验通过。
- Android：186/186 Release JVM 测试、Lint、签名 APK/AAB、Phone/Fold UI smoke 与平板/折叠屏视觉检查通过。
- HarmonyOS：113/113 ArkTS 单元测试、Release APP/HAP 构建与签名摘要验证通过。
- CLI/TUI：各 14 项测试通过。

## English

### Teaching calendar and schedules

- Every graphical client plus the CLI/TUI now uses the same ISO 8601 calendar-week rule and shows it alongside the authoritative teaching week.
- Positional exam-week inference and all exam badges were removed from UI, notifications, calendar export, menu-bar, and widget presentation. The v1 compatibility field remains but is always empty at runtime and in new caches.
- Desktop month cells on native macOS, Tauri, and HarmonyOS now include courses, assignments, school notices, and other activity deadlines. The selected-day course summary contains courses only, while assignment, almanac, and deadline cards each appear once.
- Native macOS year-day popovers now have an independently scrollable body anchored to the clicked day cell, flip at window edges, and move directly when another day is selected. HarmonyOS wide/two-in-one layouts now use the same click-anchor behavior. Tauri year popovers were also verified with real wheel input.
- Favorite management is now a real top-level or Settings subpage instead of hiding the primary navigation as a routing workaround.

### Adaptive layout and performance

- Android tablets and foldables share the phone calendar header and pager state machine, fixing reverse-transition jumps, preferred-day loss, and year-view swiping.
- Collapsed Android rail icons use a centered foreground layer; UI-bound checks keep both-axis center error within 1 dp.
- Empty-classroom results use two columns when width permits on iPad/macOS, Android, HarmonyOS, and Tauri.
- Apple month/year views index date data once, cache snapshots, and reuse a single year grid to reduce repeated CPU work during drag and paging. This release does not claim unmeasured GPU acceleration.
- Apple build 72 separates iPhone month/year caches and builds year data by visible month, removes full-detail crossfades, duplicate view-owned loading, redundant detent tail tasks, and per-frame scroll-container searches. Almanac, assignment, and deadline updates now invalidate only their own cards. The macOS year popover keeps scrolling while regaining a real day-cell anchor.
- Tauri received a wide/narrow, light/dark, Chinese/English visual matrix across planner, day/week/month/year, Settings, and Favorites.

### Versions and distribution

- Android: `0.2.6 (42)`, pinned-maintainer-certificate Universal APK/AAB.
- Native iOS and macOS: `0.2.6 (72)`, archived and uploaded separately with local Xcode. iOS used Xcode-managed automatic signing; macOS used manual App Store profiles plus the Installer Distribution identity. Both uploads returned `Upload succeeded` and `EXPORT SUCCEEDED`; App Store Connect processing was intentionally not inspected afterward.
- HarmonyOS: `0.2.6 (1002010)`, Release-signed HAP/App builds, signature-digest verification, and 113 unit tests passed. DevEco uploaded the build to AppGallery Connect, its cloud test passed, and the package is bound to the `0.2.6` release draft. [Open the HarmonyOS test invitation](https://appgallery.huawei.com/link/invite-test-wap?taskId=dfc32d0293987b9d09911717759ac063); the invitation code is `A0IsJpKIcn3`.
- The GitHub Release native macOS universal DMG was refreshed to `0.2.6 (72)` and HarmonyOS APP/HAP to `0.2.6 (1002010)`. Windows, Linux, CLI/TUI, and Android assets remain unchanged because their product sources did not change. The v0.2.6 tag was not force-moved; refreshed assets come from post-tag `main` fixes.

### Validation

- Node contracts/theme: 114/114.
- Tauri Rust: 146 passed, 1 live-account test intentionally ignored.
- Apple: 211 macOS tests, 218 iOS unit tests, and 4 key iPhone UI regressions passed; strict Release archives and signing/privacy/App Group/license validation passed on both platforms.
- Android: 186/186 Release JVM tests, Lint, signed APK/AAB validation, Phone/Fold UI smoke, and tablet/foldable visual QA passed.
- HarmonyOS: 113/113 ArkTS tests, Release APP/HAP builds, and signature-digest verification passed.
- CLI/TUI: 14 tests each passed.
