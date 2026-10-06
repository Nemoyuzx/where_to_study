# Where To Study v0.4.0（预发布）

本页为待发布更新说明。安装包交付状态以[同步记录](store-sync-v032-v040-2026-10-06.md)为准；0.4.0尚未提交商店正式审核，0.3.2仍保持独立的审核与GitHub草稿。

## iOS / iPadOS

- 新增“课程”页面，集中查看课程、作业、成绩和考试；课程可展开查看任务，详情保留独立入口。
- QMplus支持独立官方登录、授权自动填写及跨重启会话恢复；只同步当前EBU课程，验证码／MFA仍需本人完成。
- 获取到以前没有的作业时提醒；首次同步不提醒全部旧作业，缓存恢复与重复刷新不重复提醒。课程、作业和日历共用数据，减少重复请求。
- 原全天DDL区域保留，日／周时间轴额外显示主题色截止细条。明确未交的作业有红点，时间统一显示为北京时间，不虚构作业持续时长。
- 提供十三种界面语言、十款预设主题与自定义颜色，新增鼠尾草、陶土、梅子、石墨、夜蓝。
- 增加iPhone Duo开合布局与状态连续性适配，保留iPad导航体验。

0.4.0（121）已上传Apple测试渠道；未提交正式审核。

## macOS

- 同步课程页、QMplus官方登录与会话恢复、新作业提醒和共享缓存。
- 保留原固定日期／全天表头及课程布局，时间轴额外显示主题色截止细条与明确未交红点。
- 同步十三种语言、十款预设主题与自定义颜色；多窗口避免重复弹出同一批新作业提醒。

0.4.0（121）已上传Apple测试渠道。公共Universal DMG为本地ad-hoc签名包，不等同于Developer ID公证包。

## Android

- 新增课程页及可展开的课程任务，成绩、考试、作业查询集中在课程中。
- QMplus支持可选安全保存与官方页面自动填写、会话恢复；新增作业提醒复用共享查询结果。
- 日／周视图保留全天区域和课程尺寸，增加主题色截止细条与明确未交红点；时间计算继续兼容Android API24。
- 同步十三种语言、十款预设主题与自定义颜色。完整班车时刻表按时段／方向折叠，提供节假日提醒。
- 设置可选择在平台支持时尝试移动网络备用，仅作用于允许的只读数据请求，不重放凭据提交。

签名测试APK为0.4.0（67）；AAB不放GitHub，不覆盖审核中的0.3.2。

## HarmonyOS

- 同步课程、任务展开、QMplus独立官方登录和共享缓存、新作业提醒。
- 在原全天和课程布局之外增加主题色截止细条及明确未交红点，修复带小数秒的官方截止时间遗漏。
- 同步十三种语言、十款主题、按时段／方向折叠的完整班车时刻表及可选只读移动网络备用。

签名测试包为0.4.0（1002044），通过DevEco仅测试渠道上传；实际上传回执仍待确认。鸿蒙安装包不放GitHub，未提交正式审核。

## Windows

- 新增课程及集中成绩／考试／作业查询、QMplus独立官方会话和共享缓存。
- 新作业提示复用单一同步入口，时间轴额外显示北京时间截止细条、主题色及明确未交红点。
- 十款主题及自定义颜色，非默认主题增加柔和渐变背景；十三种语言保留用户校对。
- 修复跨平台CRLF测试及较新Rust编译告警，保留严格质量检查。

独立构建成功；安装包下载与本地完整性校验未完成，当前不能作为已发布文件。

## Linux / Ubuntu

- 同步桌面课程、QMplus、共享缓存、新作业提示、截止细条、十三种语言及主题。
- 保留x86_64、aarch64的DEB和AppImage构建及Ubuntu安装门禁。

独立构建成功；安装包下载与本地完整性校验未完成，不使用旧版本包替代。

## CLI / TUI 与工程

- 共享课程数据边界和法律文件同步；TUI新增五套配色。终端不宣称拥有原生日历时间轴功能。
- PR72／73依赖更新已合并，保留现有glib补丁，更新第三方许可清单。
- 原CI的tar管道提前关闭问题已修。四个Linux终端归档保留原Actions字节并通过架构、权限、安全路径及许可校验。
- 修正旧CodeQL结果对应的测试形态，不忽略或直接关闭告警；远端告警状态仍需新扫描确认。

## English — by platform

- **iOS / iPadOS:** Courses centralizes coursework, grades and exams. Authorized QMplus autofill and persistent sessions retain user-controlled MFA. Shared caches and newly discovered coursework notices avoid duplicate queries and first-sync alerts. Theme-colored deadline strips preserve all-day content and course geometry. Thirteen languages, ten themes and custom colors; iPhone Duo layout continuity. Build121 uploaded for testing only.
- **macOS:** Courses, official QMplus sessions, shared caches and bounded new-task notices. Fixed headers and course geometry retained. Additional deadline strips, thirteen languages and ten themes. Build121 uploaded for testing only; the public DMG is ad-hoc signed, not Developer ID notarized.
- **Android:** Courses and expanded tasks, secure optional QMplus autofill, shared data and new-task notices. Additional deadline strips and explicit pending dots preserve course sizes. API24 retained. Thirteen languages, ten themes, timetable disclosures and optional read-only cellular fallback. Signed APK67, no public AAB or replacement of the0.3.2 review.
- **HarmonyOS:** Equivalent course/task features, official QMplus sessions, shared caches and notices. Theme deadline strips also accept fractional official timestamps. Thirteen languages, ten themes, timetable disclosures and optional read-only cellular fallback. Build1002044 is testing-only; upload confirmation is pending, with no GitHub Harmony package.
- **Windows:** Shared course queries, official QMplus sessions, persistent caches, notices and Beijing-time deadline strips. Ten themes with ambient gradients and thirteen languages. Build succeeded; local installer delivery verification is pending.
- **Linux / Ubuntu:** Equivalent desktop features and x86_64/aarch64 DEB/AppImage builds. Build succeeded; local package delivery verification is pending.
- **CLI / TUI:** Shared data boundaries and legal files; five new TUI themes, not native calendar UI. Dependency PRs merged and tar packaging repaired. Four Linux terminal archives verified; remote CodeQL closure is not yet confirmed.
