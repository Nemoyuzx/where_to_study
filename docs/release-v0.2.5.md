# Where To Study v0.2.5

## 中文

### 教学日历与动画

- Android 日/周课程摘要改用真实展开图标，收起与展开拥有一致的空状态高度、更紧凑的字号与行距，并加入平滑高度和箭头旋转动画；月视图同时减少了底部导航预留空间。
- iOS 月视图减少重复聚合和大范围隐式动画，修正跨月日期、反向连续翻页、切换日期及折叠状态的动画时序和性能。
- iOS/macOS 模式切换改为先稳定方向、下一渲染事务再替换页面，修复月/日与年视图反向切换时旧页面沿错误方向退出；Picker、年视图跳转和键盘共用同一入口。
- 全平台点击月视图中的非本月日期时，会按正确方向过渡到目标月份并选中对应日期。
- 桌面端统一日/周/月/年的按钮、键盘和手势过渡方向；周视图全天日程按日期列对齐并显示截止时间，日期标题、全天区和对应时间列均可选中，带链接的事件可整卡访问。
- 月视图和周视图只显示由个人课表学期起始日与真实课程周次计算出的教学周，不再混入公历周数；超出实际课表范围不再伪造周次。
- 桌面月视图把课程与全天日程分层显示且不再弹出月日程窗口；年视图日期详情改为独立可滚动正文。
- macOS、Windows/Linux Tauri 与 HarmonyOS PC 增加合理键盘操作：栏目切换、日/周/月/年切换、前后翻页、回到今天和关闭弹层。

### 收藏与自定义日程

- 所有可开关活动日程的详情右侧新增独立星标按钮，原文链接与收藏操作互不干扰。
- 收藏会在本机保存最多 500 条完整事件快照；即使关闭来源、请求失败或上游移除条目，收藏仍会保留在原日期并进入日、周、月、年视图。
- 设置中的“日期详情与生活信息”新增独立收藏管理页，可返回设置并逐条取消收藏；清除本地数据会同时删除收藏。
- 新增用户自定义 HTTPS JSON 日程源，接口格式见 [`custom-schedule-api.md`](custom-schedule-api.md)。客户端执行无凭据、无 Cookie GET，拒绝重定向、本机和私有/保留 IP 字面量，限制 2 MiB、5000 条、每天 100 条和 370 天范围，并缓存成功响应 5 分钟。
- 内置 DDL、云课堂作业和自定义日程在设置加载后按自然年独立预热；普通日期选择、同年翻页和视图切换只读内存缓存，不再把网络请求放进动画路径。
- 支持系统日历的平台可在课程导入按钮下方单独导入本地已收藏日程，保留截止时间、来源详情与官方链接。

### 一致性、设置与隐私

- 全平台统一选中日期、作业 DDL、校内竞赛和其它 DDL 的浅色/深色颜色；月/年日期框继续用最多两层边框显示优先级最高的两类日程。
- Android 移除设置页 `Spinner`，非二元选择改为动画分段控件；所有二元设置继续使用原生 `Switch`。其它平台的二元项同样使用开关控件。
- HarmonyOS 手机、折叠屏、平板与 PC 同步收藏、自定义源、动画、颜色、教学周和英文布局语义。
- 更新中英双语隐私说明：自定义源不接收教务凭据或个人数据；收藏只存本机，不上传、不跨设备同步，并随清除本地数据删除。
- Windows/Linux 浏览器壳与原生 Apple、Android、HarmonyOS 均补充英文长文案回归；第三方 API 内容仍保持原文。

### 版本与分发

- Android：`0.2.5 (40)`。
- iOS 与原生 macOS：`0.2.5 (68)`，通过本地 Xcode 归档并上传 TestFlight；Apple 制品不进入 GitHub Release。
- HarmonyOS：`0.2.5 (1002007)`，构建与本地单元测试通过；AGC 发布仍需要维护者账号签名配置。
- GitHub Release：Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及维护者签名的 Android APK/AAB；`.sha256` 仅供发布校验，不作为附件。

## English

### Teaching calendar and motion

- Android now uses a real disclosure icon for the day/week course summary, keeps empty expanded and collapsed heights consistent, tightens typography and spacing, animates both height and chevron rotation, and reduces excess month-view bottom-navigation reserve.
- iOS month rendering performs less repeated aggregation and avoids broad implicit animations, improving cross-month selection, reverse paging, date changes, and sheet-state transitions.
- iOS/macOS mode changes now prepare direction before replacing page identity in the next render transaction, fixing stale exit edges when reversing between year and day/month views; pickers, year jumps, and keyboard commands share the same path.
- Selecting an out-of-month date now animates in the correct direction and lands on that date on every graphical platform.
- Desktop button, keyboard, and gesture navigation now share the same directional transition. Week all-day events align with their date columns, show deadline times, and open linked cards directly; the date header, all-day cell, and matching timeline lane are selectable.
- Month and week views display only teaching weeks derived from the personal timetable's authoritative term start and actual course weeks; Gregorian week numbers are no longer mixed into this label.
- Desktop month cells separate courses from all-day events without a month-agenda modal, while year-day details use a dedicated scrollable body.
- macOS, Windows/Linux Tauri, and HarmonyOS PC now provide keyboard actions for sections, calendar modes, paging, Today, and dismissing overlays.

### Favorites and custom feeds

- Toggleable event details now have an independent star button, separate from the source link.
- Up to 500 complete favorite snapshots are stored locally. Favorites remain on their original dates and in every calendar view when a source is disabled, unavailable, or removes an item.
- Settings now includes an independent Favorite Management page. Local-data reset removes favorites as well.
- Users can add a custom HTTPS JSON schedule feed documented in [`custom-schedule-api.md`](custom-schedule-api.md). Clients send credential-free, cookie-free GET requests; reject redirects and local/private/reserved literal addresses; enforce 2 MiB, 5000-item, 100-per-day, and 370-day limits; and cache successful responses for five minutes.
- Built-in deadlines, UCloud assignments, and custom events are prewarmed independently for the calendar year after settings load. Normal selection, same-year paging, and view changes read memory state instead of starting network work from an animation path.
- Platforms with system-calendar support can separately import locally saved favorite events, including their deadline time, source details, and official link.

### Consistency, settings, and privacy

- Selected-date, assignment, school-notice, and other-deadline colors now match in light and dark appearances on every platform; month/year cells retain up to two concentric priority borders.
- Android removes Settings `Spinner` controls: multi-choice values use animated segmented controls, while every binary value uses a native `Switch`. Other platforms likewise use switch controls for binary settings.
- HarmonyOS phone, foldable, tablet, and PC layouts receive the matching favorites, custom-feed, animation, color, teaching-week, and English semantics.
- The bilingual privacy policy now explains that custom feeds receive no academic credentials or personal data and that favorites stay on-device, do not sync, and are removed by local-data reset.

### Versions and distribution

- Android: `0.2.5 (40)`.
- Native iOS and macOS: `0.2.5 (68)`, archived and uploaded to TestFlight with local Xcode. Apple artifacts are excluded from GitHub Release.
- HarmonyOS: `0.2.5 (1002007)`, locally built and unit-tested; AGC distribution still requires maintainer signing configuration.
- GitHub Release scope: Windows x64 NSIS; Linux arm64/x86_64 Debian, AppImage, CLI, and TUI; and maintainer-signed Android APK/AAB. `.sha256` files remain verification-only and are not attached.
