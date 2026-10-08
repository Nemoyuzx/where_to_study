# Where To Study v0.4.0（预发布）

0.4.0保持预发布状态，更新集中在[同一预发布页面](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.4.0-prerelease)，不替换[0.3.2正式版](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.3.2)。本说明记录分平台功能与已验证限制；附件批次、构建来源、最终CI结果和可下载文件以预发布页面为准，不据此宣称新批次已上传。

本轮原生构建为Android69、Apple122、HarmonyOS1002046。各商店、TestFlight与GitHub相互独立；0.4.0不提交商店正式审核或新的外部Beta审核，审核锁定的平台本轮跳过。

## 下载哪个文件？

- 安卓：选择 `native-android-universal.apk`。
- Mac：选择 `native-macos-universal.dmg`，适用于Intel和Apple Silicon。Apple测试用户也可使用TestFlight。
- Windows：选择 `windows-x64-setup.exe`，适用于Intel／AMD64位电脑。
- Ubuntu／Debian：普通Intel／AMD电脑选 `linux-x86_64.deb`；ARM64设备选 `linux-aarch64.deb`。在下载目录执行 `sudo apt install ./下载的文件名.deb`。
- 其它Linux：可选择相应架构的AppImage，赋予执行权限后打开。`x86_64`代表Intel／AMD64位，`aarch64`代表ARM64。
- CLI／TUI压缩包是Linux终端工具，不是图形安装程序；解压后先运行相应程序的 `--help`。`Source code`是源码，也不是安装包。

公开附件范围为11个文件：Android APK、macOS Universal DMG、Windows x64安装程序、两种架构各一份Linux DEB和AppImage，以及两种架构各一份CLI和TUI归档。不含Android AAB、鸿蒙APP/HAP、iOS IPA或校验旁文件；文件选择说明不表示新批次已公开。Windows目前没有平台信任的Authenticode签名，公共macOS DMG为ad-hoc签名且未公证；哈希和CI记录不能替代平台签名。遇到系统安全提示请阅读[下载文件验证说明](./code-signing.md)。

## iOS / iPadOS

- 新增“课程”页面，集中查看课程、作业、成绩和考试；课程可展开查看任务，详情保留独立入口。
- QMplus支持独立官方登录、授权自动填写及跨重启会话恢复；只同步当前EBU课程，验证码／MFA仍需本人完成。
- 获取到以前没有的作业时提醒；首次同步不提醒全部旧作业，缓存恢复与重复刷新不重复提醒。课程、作业和日历共用数据，减少重复请求。
- 原全天DDL区域保留，日／周时间轴额外显示主题色截止细条。明确未交的作业有红点，时间统一显示为北京时间，不虚构作业持续时长。
- 提供十三种界面语言、十款预设主题与自定义颜色，新增鼠尾草、陶土、梅子、石墨、夜蓝。
- 增加iPhone Duo开合布局与状态连续性适配，保留iPad导航体验。
- 黄历“宜／忌”标签按翻译后的长度排版，窄卡片可纵向展示，保留接口正文原文。

0.4.0（122）上传成功，已关联既有内部测试组，0.4.0草稿已关联122并保存。未提交正式审核或新的外部Beta审核，外部可安装版本以TestFlight页面为准；iPhone、iPad及Duo更新截图的验收尚未完成。

## macOS

- 同步课程页、QMplus官方登录与会话恢复、新作业提醒和共享缓存。
- 保留原固定日期／全天表头及课程布局，时间轴额外显示主题色截止细条与明确未交红点。
- 同步十三种语言、十款预设主题与自定义颜色；多窗口避免重复弹出同一批新作业提醒。
- 公共DMG使用独立的本机系统钥匙串及QMplus会话、授权和缓存，不迁移商店渠道的登录资料；首次使用公共渠道需要重新保存并授权。商店渠道继续使用原安全存储。
- 改善启动准备阶段的前台恢复；未知或尚未完成布局的登录标题不再被误判为账号变更而清除课程缓存。黄历标签适配长译文。

macOS正式0.3.2已可分发；0.4.0（122）上传成功并关联既有内部测试组。独立0.4.0草稿关联122，已保存平台更新内容、中英审核说明及4张新的真实运行截图，并刷新确认。未提交正式审核或新的外部Beta审核；外部可安装版本以TestFlight页面为准。公共Universal DMG为本地ad-hoc签名包，未经过Apple公证。

## Android

- 新增课程页及可展开的课程任务，成绩、考试、作业查询集中在课程中。
- QMplus支持可选安全保存与官方页面自动填写、会话恢复；新增作业提醒复用共享查询结果。
- 日／周视图保留全天区域和课程尺寸，增加主题色截止细条与明确未交红点；时间计算继续兼容Android API24。
- 同步十三种语言、十款预设主题与自定义颜色。完整班车时刻表按时段／方向折叠，提供节假日提醒。
- 语言选择改为跟随当前主题的自定义面板，保留“跟随系统”和全部语言；修复全屏模糊强度及完成勾整层淡出，等待本地任务与布局就绪后才显示完成。
- 设置可选择在平台支持时尝试移动网络备用，仅作用于允许的只读数据请求，不重放凭据提交。
- 启动时在后台恢复本机缓存，避免安全存储和缓存读取阻塞主界面；保存账号时保护尚未提交的输入。
- 月视图按实际可用高度和导航条位置布局，去掉82dp行高上限；拖动按两段实测距离计算，保留非今日周的正确折叠位置。
- 黄历英文标签不再挤入固定小方框；窄屏、大字体和语言文字变化后会重新测量。QMplus作业卡片之间留出间隔，历史学期使用开关。

签名APK为0.4.0（69），Release单元测试450/450、语言展示原生测试5/5通过；包内脚本、法律文件、证书和16KiB对齐核验通过。Lint无错误，既有警告未宣称清零。保留真实账号有效会话的隔离模拟器冷启动后，无需点击连接或重新输入凭据，官方会话自动恢复并产生更新的课程快照；本次未清Cookie、未触发MFA，不能代替过期会话或首次MFA验证。华为新包草稿已保存，未提交审核；vivo的0.3.2审核锁定，本轮跳过。AAB不公开。

## HarmonyOS

- 同步课程、任务展开、QMplus独立官方登录和共享缓存、新作业提醒。
- 在原全天和课程布局之外增加主题色截止细条及明确未交红点，修复带小数秒的官方截止时间遗漏。
- 同步十三种语言、十款主题、按时段／方向折叠的完整班车时刻表及可选只读移动网络备用。
- 本机缓存异步读取，保护启动期间的账号输入；月视图按实际导航、标题及内容区域高度排版，折叠详情不再占用隐藏空间。
- 月视图拖动使用实测两段距离；黄历标签按当前语言和字体测量。公开法律声明随软件包一起交付。
- 1002046将手机日／周时间轴的边界反馈改为弹性回弹；宽屏日历、日期选择器、控件尺寸、课程几何及月视图拖动保持原状。

0.4.0（1002046/build1）的完整Release HAP／APP、405项测试、签名及包体门禁通过，构建前后217项源码输入一致。模拟器升级安装确认日／周时间轴回弹和释放后的布局恢复；SDK验证包与实际上传包的217项源码输入一致，但不是同一包哈希。该验证未登录或输入凭据，不能代替QMplus真实MFA／重启验收。

1002046已通过DevEco上传，保留“测试和正式上架”用途，合法性达标；正式及测试草稿已保存，测试草稿已回读确认。未提交审核、发布测试或通知／邀请测试者。新包自检最终结果尚未复核，旧1002045的云测报告不能作为新包通过的证据。鸿蒙安装包不放GitHub。

## Windows

- 新增课程及集中成绩／考试／作业查询、QMplus独立官方会话和共享缓存。
- 新作业提示复用单一同步入口，时间轴额外显示北京时间截止细条、主题色及明确未交红点。
- 十款主题及自定义颜色，非默认主题增加柔和渐变背景；十三种语言保留用户校对。
- QMplus设置移至Account下方，密码说明及数据类别间距更清晰；切换语言增加全屏模糊、切换中提示及完成勾过渡，结束后释放滤镜，保留页面位置和草稿。
- QMplus设置及课程页的账号、刷新、更多和私有详情按钮统一跟随当前主题。
- 后台刷新只复用已有QMplus会话，不在首次保存前建立空会话；清理屏障显示明确提示。
- 修复跨平台CRLF测试及较新Rust编译告警，保留严格质量检查。

Windows本轮验收范围为构建、安装及包体检查，包括安装程序版本、安装后主程序GUI子系统、HTTPS数据源、法律文件和SHA-256。最终安装包的构建来源及CI结果记录在预发布页面；真实账号登录／MFA测试机不在本轮范围内，安装门禁不代替运行登录验收。

## Linux / Ubuntu

- 同步桌面课程、QMplus、共享缓存、新作业提示、截止细条、十三种语言及主题。
- 同步QMplus设置顺序与间距、语言切换模糊和完成过渡，以及后台空会话和明确错误提示修复。
- 同步QMplus设置及课程页账号、刷新、更多和私有详情按钮的主题样式修复。
- 提供x86_64、aarch64的DEB和AppImage构建，安装验证限定为Ubuntu 24.04 x86_64 DEB，不扩写为aarch64安装验收。

此前版本完成过真实MFA并取得新业务快照，后续候选曾因网页与原生端的IPC消息被拒绝而静默同步超时。本轮修复Linux QMplus消息桥接，保留既有命令权限与消息校验。在关闭诊断功能、使用隔离凭据命名空间的同一ARM64 Debug候选中，两次正常退出后的普通冷启动均自动取得更新快照，获取时间分别前进；两次均未显示登录窗口，也未执行连接、手动继续、保存凭据或MFA操作。验证保留已有凭据和有效官方会话，不把恢复旧缓存当作刷新成功。这是本地Debug候选验收，不代表最终Release安装包、Linux x86_64运行或首次／过期会话MFA已通过；最终包的构建来源及CI结果记录在预发布页面。

## CLI / TUI 与工程

- 共享课程数据边界和法律文件同步；TUI新增五套配色。终端不宣称拥有原生日历时间轴功能。
- PR72／73依赖更新已合并，保留现有glib补丁，更新第三方许可清单。
- 原CI的tar管道提前关闭问题已修。四个Linux终端归档的架构、权限、安全路径、版本和法律文件验证通过，保留原Actions字节及提交`da7a166`来源，不宣称按本轮桌面提交重建；最终输入一致性检查记录在预发布页面。

## 已知限制

- Linux两次冷启动验证限定为关闭诊断功能、隔离凭据命名空间的ARM64 Debug候选及已有有效官方会话；最终Release包、x86_64运行和首次／过期会话MFA仍需单独验收。恢复缓存不能当作本次刷新成功的证据。
- Android69仅验证已有有效官方会话的冷启动自动更新，首次登录及会话过期后的MFA不在该次验证范围。
- HarmonyOS1002046新包自检最终结果尚未复核，QMplus真实重启验收未通过，个人运行截图尚未补齐；旧云测结果不可替代。iPhone、iPad及Duo更新截图仍需完成验收。
- Windows本轮仅覆盖构建及安装验收。公共DMG未公证，Windows安装程序未获Authenticode签名。

每个公开附件的源码提交、CI或本地原生构建来源及SHA-256在发布正文中记录。发布核对使用本地文件与远端附件元数据，不从Release回下载；这些记录不能替代真实账号运行验收。

## English — by platform

- **iOS / iPadOS:** Courses centralizes coursework, grades and exams, with independent official QMplus login, authorized autofill and persistent sessions. Shared caches and new-task notices avoid duplicate queries and first-sync alerts. Deadline strips retain all-day content and course geometry. Thirteen languages, ten themes, adaptive Almanac labels and iPhone Duo layout continuity. Build 122 uploaded and linked to existing internal groups and the saved 0.4.0 draft. Updated iPhone/iPad/Duo screenshot validation remains incomplete.
- **macOS:** Shared Courses/QMplus features, multi-window notice deduplication, fixed calendar headers, deadline strips, thirteen languages and ten themes. The public DMG has separate system Keychain, session and cache storage and requires separate initial authorization. Build 122 uploaded and linked to existing internal groups; the saved 0.4.0 draft includes updated platform notes and four real screenshots. The public DMG is ad-hoc signed and unnotarized.
- **Android:** Courses, optional secure QMplus autofill, shared data, API 24 support and read-only cellular fallback. Async startup restoration, measured month geometry, adaptive Almanac labels and themed language transitions. APK 69 passes 450 Release unit tests, five native language tests and package gates; lint retains existing warnings. A real-account cold launch with an existing valid session produced a newer snapshot automatically. No cookie clearing or MFA occurred, so this does not validate first-time or expired-session MFA. Huawei draft saved without submission; review-locked vivo 0.3.2 skipped. No public AAB.
- **HarmonyOS:** Shared course/task features, notices, deadline strips, thirteen languages and ten themes, async caches and measured calendar geometry. Build 1002046 adds spring feedback to mobile day/week timelines. Release HAP/APP, 405 tests, signatures and package gates passed; 217 source inputs match between SDK-tested and uploaded packages, whose hashes differ. DevEco upload and package legality passed; formal and test drafts saved without review submission or test release. Final self-check results are unverified; old 1002045 cloud results do not validate this build. Real QMplus restart acceptance and personal screenshots remain incomplete. No public Harmony package.
- **Windows:** Shared course queries, official QMplus sessions, caches, notices and deadline strips; themed controls, revised settings and language transitions. This round covers build and installation gates, excluding real-account login/MFA validation. No Authenticode signature.
- **Linux / Ubuntu:** Shared desktop features and UI fixes, with x86_64/aarch64 DEB/AppImage targets; installation validation is limited to Ubuntu 24.04 x86_64 DEB. The QMplus IPC bridge fix preserves existing command permissions and message checks. The same ARM64 Debug candidate, with diagnostics disabled and an isolated credential namespace, automatically fetched newer snapshots after two normal quits and cold launches. Existing credentials and a valid official session were retained; no login window, Connect, manual continuation, credential save or MFA action occurred. This does not validate final packaged Release binaries, Linux x86_64 runtime or first-time/expired-session MFA.
- **CLI / TUI:** Shared data boundaries, legal files, five new TUI themes and repaired tar packaging. Four verified original Actions archives retain source commit `da7a166`; they are not relabeled as new desktop-commit builds.

Version 0.4.0 remains prerelease only; stable 0.3.2 is unchanged. No formal or new external Beta review is submitted. The same prerelease page records the actual 11 public files, source commits, CI/local build provenance and hashes. It excludes AAB, Harmony packages, IPA and checksum sidecars; verification uses local files and remote metadata without Release re-download.
