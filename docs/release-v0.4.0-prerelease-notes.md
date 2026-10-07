# Where To Study v0.4.0（预发布）

这是0.4.0预发布测试版，不是正式稳定版。本轮构建为Android68、Apple122、HarmonyOS1002045；0.4.0不提交商店正式审核。需要稳定版时请选择正式发布的0.3.2，各商店状态与GitHub发布相互独立。

本轮替换正在进行：Apple122两端已上传、服务器处理中；Android68与鸿蒙1002045最终签名包已生成，渠道上传和GitHub附件替换尚未全部完成。Windows／Linux／终端新包仍需按最终提交构建。

## 下载哪个文件？

- 安卓：选择 `native-android-universal.apk`。
- Mac：选择 `native-macos-universal.dmg`，适用于Intel和Apple Silicon。Apple测试用户也可使用TestFlight。
- Windows：选择 `windows-x64-setup.exe`，适用于Intel／AMD64位电脑。
- Ubuntu／Debian：普通Intel／AMD电脑选 `linux-x86_64.deb`；ARM64设备选 `linux-aarch64.deb`。在下载目录执行 `sudo apt install ./下载的文件名.deb`。
- 其它Linux：可选择相应架构的AppImage，赋予执行权限后打开。`x86_64`代表Intel／AMD64位，`aarch64`代表ARM64。
- CLI／TUI压缩包是Linux终端工具，不是图形安装程序；解压后先运行相应程序的 `--help`。`Source code`是源码，也不是安装包。

公开附件共11个，不含Android AAB、鸿蒙APP/HAP或iOS IPA。Windows目前没有平台信任的Authenticode签名，公共macOS DMG为ad-hoc签名且未公证；哈希和CI记录不能替代平台签名。遇到系统安全提示请核对来源，不建议关闭系统保护。

## iOS / iPadOS

- 新增“课程”页面，集中查看课程、作业、成绩和考试；课程可展开查看任务，详情保留独立入口。
- QMplus支持独立官方登录、授权自动填写及跨重启会话恢复；只同步当前EBU课程，验证码／MFA仍需本人完成。
- 获取到以前没有的作业时提醒；首次同步不提醒全部旧作业，缓存恢复与重复刷新不重复提醒。课程、作业和日历共用数据，减少重复请求。
- 原全天DDL区域保留，日／周时间轴额外显示主题色截止细条。明确未交的作业有红点，时间统一显示为北京时间，不虚构作业持续时长。
- 提供十三种界面语言、十款预设主题与自定义颜色，新增鼠尾草、陶土、梅子、石墨、夜蓝。
- 增加iPhone Duo开合布局与状态连续性适配，保留iPad导航体验。
- 黄历“宜／忌”标签按翻译后的长度排版，窄卡片可纵向展示，保留接口正文原文。

0.4.0（122）已取得Apple原生上传成功回执；后续处理／测试可用状态另行核对，未提交正式审核。

## macOS

- 同步课程页、QMplus官方登录与会话恢复、新作业提醒和共享缓存。
- 保留原固定日期／全天表头及课程布局，时间轴额外显示主题色截止细条与明确未交红点。
- 同步十三种语言、十款预设主题与自定义颜色；多窗口避免重复弹出同一批新作业提醒。
- 公共DMG使用独立的本机系统钥匙串及QMplus会话、授权和缓存，不迁移商店渠道的登录资料；首次使用公共渠道需要重新保存并授权。商店渠道继续使用原安全存储。
- 改善启动准备阶段的前台恢复；未知或尚未完成布局的登录标题不再被误判为账号变更而清除课程缓存。黄历标签适配长译文。

0.4.0（122）已上传Apple测试渠道，服务器处理中。公共Universal DMG为本地ad-hoc签名包，不等同于Developer ID公证包。

## Android

- 新增课程页及可展开的课程任务，成绩、考试、作业查询集中在课程中。
- QMplus支持可选安全保存与官方页面自动填写、会话恢复；新增作业提醒复用共享查询结果。
- 日／周视图保留全天区域和课程尺寸，增加主题色截止细条与明确未交红点；时间计算继续兼容Android API24。
- 同步十三种语言、十款预设主题与自定义颜色。完整班车时刻表按时段／方向折叠，提供节假日提醒。
- 设置可选择在平台支持时尝试移动网络备用，仅作用于允许的只读数据请求，不重放凭据提交。
- 启动时在后台恢复本机缓存，避免安全存储和缓存读取阻塞主界面；保存账号时保护尚未提交的输入。
- 月视图按实际可用高度和导航条位置布局，去掉82dp行高上限；拖动按两段实测距离计算，保留非今日周的正确折叠位置。
- 黄历英文标签不再挤入固定小方框；窄屏、大字体和语言文字变化后会重新测量。QMplus作业卡片之间留出间隔，历史学期使用开关。

最终签名APK为0.4.0（68）。本轮Debug／Release各450项单元测试、5项隔离原生界面测试通过；包内脚本、法律文件、证书和16KiB对齐核验通过。渠道上传尚待完成；AAB不放GitHub，不覆盖0.3.2。

## HarmonyOS

- 同步课程、任务展开、QMplus独立官方登录和共享缓存、新作业提醒。
- 在原全天和课程布局之外增加主题色截止细条及明确未交红点，修复带小数秒的官方截止时间遗漏。
- 同步十三种语言、十款主题、按时段／方向折叠的完整班车时刻表及可选只读移动网络备用。
- 本机缓存异步读取，保护启动期间的账号输入；月视图按实际导航、标题及内容区域高度排版，折叠详情不再占用隐藏空间。
- 月视图拖动使用实测两段距离；黄历标签按当前语言和字体测量。公开法律声明随软件包一起交付。

最终Release签名包0.4.0（1002045）已生成，405项Hypium规格通过；独立HAP及完整APP验签、当前字节码和包内脚本／法律文件核验通过。新包尚未上传及完成云测。此前1002044的95项云测有1项体验警告，不代表本次新包的结果。上传继续使用“测试和正式上架”用途，但不提交正式审核；鸿蒙安装包不放GitHub。

## Windows

- 新增课程及集中成绩／考试／作业查询、QMplus独立官方会话和共享缓存。
- 新作业提示复用单一同步入口，时间轴额外显示北京时间截止细条、主题色及明确未交红点。
- 十款主题及自定义颜色，非默认主题增加柔和渐变背景；十三种语言保留用户校对。
- 修复跨平台CRLF测试及较新Rust编译告警，保留严格质量检查。

本轮最终源码的新安装包尚待独立构建，并核对安装程序版本、GUI子系统、法律文件和SHA-256；Windows真实登录测试机不在本轮范围内。

## Linux / Ubuntu

- 同步桌面课程、QMplus、共享缓存、新作业提示、截止细条、十三种语言及主题。
- 保留x86_64、aarch64的DEB和AppImage构建及Ubuntu安装门禁。

本轮最终源码的DEB／AppImage仍待独立构建。Ubuntu本地虚拟机中的隔离Debug候选已编译，真实登录／重启验证尚未完成；这不等于公共安装包验收通过。

## CLI / TUI 与工程

- 共享课程数据边界和法律文件同步；TUI新增五套配色。终端不宣称拥有原生日历时间轴功能。
- PR72／73依赖更新已合并，保留现有glib补丁，更新第三方许可清单。
- 原CI的tar管道提前关闭问题已修。本轮四个Linux终端归档待按最终提交重新构建、核对架构、权限、安全路径及许可。
- 修正旧CodeQL结果对应的测试形态，不忽略或直接关闭告警；远端告警状态仍需新扫描确认。

## English — by platform

- **iOS / iPadOS:** Courses centralizes coursework, grades and exams. Authorized QMplus autofill and persistent sessions retain user-controlled MFA. Shared caches and newly discovered coursework notices avoid duplicate queries and first-sync alerts. Theme-colored deadline strips preserve all-day content and course geometry. Thirteen languages, ten themes, custom colors and iPhone Duo layout continuity. Almanac labels adapt to translated text. Build122 upload succeeded; processing/testing availability is checked separately. No formal review submission.
- **macOS:** Courses, official QMplus sessions, shared caches and bounded new-task notices. Fixed headers and course geometry retained. Additional deadline strips, thirteen languages and ten themes. The public DMG has an independent local system Keychain/session/cache namespace, with no Store-data migration; first use needs separate save and authorization. Deferred foreground preparation resumes, and unready login headings no longer falsely invalidate cached courses. Build122 upload succeeded and is processing. The public DMG is ad-hoc signed, not Developer ID notarized.
- **Android:** Courses, expanded tasks, optional secure QMplus autofill and shared data. API24, thirteen languages, ten themes and read-only cellular fallback retained. Startup cache restoration avoids main-thread I/O. Month rows fill the measured viewport with actual navigation avoidance and two-stage physical drag distances. Almanac labels remeasure for English, narrow widths and large fonts; task cards and the historical-term switch are aligned. Signed APK68 passes450Debug/450Release unit tests and5isolated native UI tests plus package gates; channel upload is pending. No public AAB or replacement of0.3.2.
- **HarmonyOS:** Course/task features, independent QMplus sessions, shared caches and notices. Theme deadline strips, thirteen languages, ten themes and timetable disclosures retained. Async cache reads and measured month/header/navigation geometry improve startup and folding. Almanac labels adapt to language/font size, and public legal notices are bundled. Final release-signed1002045 passes405Hypium specifications, signatures, current bytecode and script/legal byte checks; new upload/cloud testing is pending. The prior1002044 cloud report had one UX warning and does not validate this package. Preserve testing-and-formal-release package purpose without submitting formal review; no public Harmony package.
- **Windows:** Shared queries, official QMplus sessions, caches, notices and Beijing-time deadline strips; ten themes and thirteen languages. The new final-source installer still requires independent build and delivery verification. A Windows native login test host is excluded from this round.
- **Linux / Ubuntu:** Equivalent desktop features and x86_64/aarch64 DEB/AppImage targets. New final-source public packages are pending. An isolated local Ubuntu Debug candidate compiled; actual login/restart remains unverified and is not a public-package acceptance result.
- **CLI / TUI:** Shared data boundaries and legal files; five new TUI themes, not native calendar UI. Dependency PRs merged and tar packaging repaired. Four terminal archives still require final-source rebuild and checks; old remote CodeQL closure is excluded from this round.
