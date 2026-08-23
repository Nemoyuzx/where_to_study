# Where To Study v0.2.3

## 中文

### 教学日历

- 作业 DDL 与校内竞赛通知不再只出现在月视图详情卡片：日/周视图加入紧凑全天日程区，内容过多时显示可点击的 `+N`；月格直接显示独立配色的作业与校内竞赛标记；年视图点击日期后也会显示对应详情。
- 日、周、月、年使用按可见范围预取的本地快照。日期选择和翻页动画先完成，网络结果只局部更新当前数据，不再因未缓存请求造成横向抖动、动画截断或整页重建。
- 公开竞赛数据使用短时缓存，移动原生端会把并发范围请求合并为 single-flight；云课堂作业按账户复用一次全量同步，再在本地按日期过滤。
- 公开竞赛与校内通知在应用启动、回前台或相关开关开启时后台预热；完整 feed 每次只解析一次并建立日期索引，日/周/月/年翻页仅查本地缓存。
- iOS、Android 与 HarmonyOS 手机端的日/周课程摘要区均可折叠；Android 补齐与 iOS 一致的日期下方课程信息。

### 多语言与跨平台一致性

- 图形客户端设置新增“跟随系统 / 简体中文 / English”，并持久化界面语言。导航、教学日历、空教室、设置、状态、错误与来源说明均提供英文静态文案；课程、天气、黄历、作业与竞赛 API 返回内容保持原文。
- 各端语言卡片统一移动到设置页底部，并位于隐私与本地数据之前；iOS 修复 English 切回中文后底部导航尺寸和位置未恢复的问题。
- iOS 月视图翻页改为先准备本次方向、再提交目标月份，连续左滑后右滑或右滑后左滑都使用正确的进入/退出动画。
- HarmonyOS 手机端同步近期移动月视图的滚动所有权、折叠状态、遮罩层级、无横向抖动与异步局部更新逻辑，同时保留折叠屏、平板和 PC 自适应布局。
- Windows 与 Linux 延续原生桌面布局，不提供课程小组件；课程小组件只保留在系统能力完整且已实现对应组件的平台。
- Windows 与 Linux 的天气卡片现与空教室主工作区保持一致的左右边距，节次选择中的节次名和时间统一居中。
- Linux AppImage 在重打阶段移除会与新宿主 Mesa/EGL 冲突的旧 Wayland ABI 库，并隔离包内 GIO 模块，避免较新桌面系统出现白屏。

### 数据来源

- 云课堂作业：北京邮电大学云邮教学空间。
- 学科竞赛、夏令营与黑客松：Contest DDL，固定备用源为 `contest-events API`。
- 校内竞赛通知：服务器脚本从学校内部网站公开通知页提取整理，固定来源为 `contest-notices API`。
- 所有显示数据仅供参考，请以实际官方信息为准。

## English

- Assignment deadlines and school competition notices now appear in day/week all-day rows, month cells with distinct colors, and year-date details. Overflow uses a tappable `+N` dialog.
- Calendar paging is decoupled from networking. Visible-range snapshots, account-scoped assignment reuse, short-lived contest caches, and single-flight range loading on native mobile clients prevent incomplete animations and unnecessary repeated requests.
- Public contest and school-notice feeds now prewarm at startup, foreground entry, or when a related switch is enabled. Each full feed is parsed once into a date index, so calendar paging performs local lookups only.
- Day/week course summaries are collapsible on iOS, Android, and HarmonyOS; Android now shows the same date-level course summary as iOS.
- Graphical clients add a persistent System / Simplified Chinese / English interface setting. Static UI is localized while third-party API content remains unchanged.
- Language cards now sit immediately before privacy and local-data settings. iOS also restores tab-bar geometry after an English-to-Chinese round trip and correctly animates month swipes when direction reverses.
- HarmonyOS receives the recent mobile calendar gesture, clipping, rendering, and async-update refinements. Windows and Linux retain their desktop layouts and do not expose course widgets.
- Windows and Linux now align the weather card with the empty-room workspace gutters and center both lines inside every period selector.
- Linux AppImages are repacked without the stale bundled Wayland ABI libraries that conflict with newer host Mesa/EGL stacks, and their GIO module lookup is isolated to the bundle.

## Distribution

- GitHub Release: Windows x64 NSIS, Linux Debian/AppImage and CLI/TUI builds, plus the maintainer-signed Android `0.2.3 (34)` APK/AAB.
- TestFlight: native iOS and macOS `0.2.3 (61)` builds. Apple artifacts are not attached to GitHub Release.
- Checksum sidecars are used for verification but are not attached to the public GitHub Release.
