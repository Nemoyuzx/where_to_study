# Where To Study v0.3.2-prerelease

0.3.2 为测试版本，最新正式版仍为 0.3.1。以下按平台列出改动和实际分发状态，未完成的安装包不会用旧包替代。

## 本轮更新（2026-10-05）

GitHub 继续保留 **draft + pre-release**，只更新现有测试包，不公开、不转正式版。本轮包由 `codex/v032-language-hotfix` 的 `fced615e` 构建，完整回执见[本轮记录](https://github.com/Nemoyuzx/where_to_study/blob/codex/v032-language-hotfix/docs/release-v0.3.2-prerelease.md)。下面的 103／61／1002038 为历史记录，不代表本次新包。

### iOS / iPadOS — 0.3.2（108）

全窗口系统模糊层保留原页面与草稿，目标语言布局就绪才淡出；超时仅清理，不把超时当作布局完成。本机已有语言切换界面回归通过；用户随后要求停止本机自动化测试，已停止，不再启动新的自动化测试。2026-10-05 10:47 +0800 已取得 TestFlight 上传成功回执；不提交正式审核，成功后不检查处理状态。

### macOS — 0.3.2（108）

新增独立全窗口原生材质，覆盖侧栏和当前内容，尊重 Reduce Motion。单元回归通过，界面 runner 曾遇本机签名／窗口命中问题，未宣称该界面回归通过；按用户要求不再进行本机自动化测试。2026-10-05 10:44 +0800 已取得 TestFlight 上传成功回执，GitHub 草稿的原生 Universal DMG 已更新；公共 DMG 仍为 ad-hoc、未公证。

### Android — 0.3.2（65）

全应用区域语言模糊过渡使用系统 RenderEffect，较旧系统采用有界的应用内回退，回收位图与工作线程；不采集系统桌面，保留查询、草稿和滚动位置。签名 Universal APK 编译与既有发布门禁通过，已更新同一 GitHub 草稿的 APK，不上传 AAB。

### HarmonyOS — 0.3.2（1002042）

独立系统材质层比较语言卡片和目标控件的 x、y、宽、高，连续三个有效帧稳定后才揭开；节点缺失重置采样，后台／离页／超时撤销旧回调。原生编译通过。2026-10-05 11:22 +0800 已通过 DevEco 仅测试上传，结果页显示云测试通过；不提交正式审核、不上传 GitHub 鸿蒙包。

### Windows / Linux / Ubuntu

Tauri 源码增加全屏 WebView 材质过渡、布局稳定和有界清理，不重新挂载整页或发起查询。新安装包仍等待用户确认 GitHub 构建恢复；不触发受限 CI、不修改服务器或创建定时任务。

### English — this update

Keep the existing GitHub release both **draft and pre-release**. iOS/iPadOS and macOS build 108 uploaded successfully; Android APK 65 and macOS DMG 108 replaced in the draft. HarmonyOS 1002042 uploaded for testing through DevEco, with its quick cloud test passed. Add platform-native/app-only full-window language material while preserving views, drafts, scroll and cache. Layout readiness—not timeout—controls the reveal; stale/background work is canceled. macOS GUI regression is not claimed as passed. Local automated testing stopped at the user's request. No AAB or HarmonyOS package on GitHub, no formal store review submission. Windows/Linux await build availability, without scheduled retries.

## 历史记录（此前 103／61／1002038）

## iOS / iPadOS

- 修复中英切换时整体界面跳动，保留滚动位置、未保存草稿、查询筛选和已加载数据，不重新登录或重复获取课表。
- iPhone 英文底栏使用简洁标签，四项等距；横屏保持图标在文字上方，旋转返回后布局正常。页面及无障碍名称仍完整。
- 切换语言增加全屏系统模糊过渡，等待目标布局就绪后淡出；支持减少动态效果，处理快速反向、离页和后台清理。
- 修复手机日／周课程摘要、月／年翻页及视图切换的动画和迟到回调；减少隐私说明出现前的准备工作，保留原生弹窗动画。
- 班车新增完整时刻表和法定节假日提醒，交通图标与主题提示色统一；明确教务／教学云平台密码用途，操作入口采用图标按钮。公开竞赛源增加镜像并自动择新。

**分发：** 0.3.2（103）已上传 TestFlight。上传成功后未检查 App Store Connect 处理状态，未提交正式审核。

## macOS

- 保持设置弹窗与编辑状态的稳定所有者；隐私／帮助及收藏使用惰性列表排版，不将它描述成移动端的全屏收藏页面或分批加载。
- 切换中英界面保留当前位置、输入草稿及查询／日历状态；减少隐私页准备工作，修复动画生命周期和迟到回调。
- 班车显示完整时刻表、历史／未来时段及法定节假日提醒，图标和文字跟随主题；补齐账号密码说明、图标按钮及公开竞赛镜像。
- 本轮全屏语言模糊过渡仅用于 iPhone/iPad，macOS 不冒称已增加该效果。

**分发：** 0.3.2（103）已上传 TestFlight；GitHub 草稿中的原生 Universal DMG 已更新。公共 DMG 为 ad-hoc 签名、未公证，与 TestFlight 包不同。

## Android

- 日／周顶部课程摘要加入连续展开、折叠动画，支持快速反向、空日期和切页取消，不改变原控件高度、字号或间距。
- 切换中英界面保留设置草稿、滚动位置、日历／查询状态及缓存，避免恢复页面时重复获取数据。
- 班车新增完整时刻表与法定节假日提醒；内容使用交通专属图标，缓存、时段与假日说明跟随主题文字色。
- 明确教务／教学云平台密码的区别，补齐图标操作按钮；公开竞赛镜像更新时自动使用镜像数据。

**分发：** 0.3.2（61）签名 Universal APK 已放入 GitHub 草稿。AAB 不上传 GitHub；未提交本轮正式商店审核。

## HarmonyOS

- 语言及导航动画限于独立背景／图标，翻译引起的文字重排不再触发整页动画；保留可见位置、草稿和当前页面状态。
- 修复月视图分页、日程开合、视图切换和离页后的迟到回调，保留原 32vp 控件及既有布局尺寸。
- 班车补齐完整时刻表、法定假日提醒和主题交通图标；窄屏教学云平台操作按钮可换行，保留完整名称。
- 明确两种账号密码用途，增加公开竞赛镜像择新，卡片和隐私说明标明来源。

**分发：** 0.3.2（1002038）已通过 DevEco 上传 AppGallery Connect，仅用于测试，快速云测试通过。未提交正式审核，鸿蒙包不上传 GitHub。

## Windows

- Tauri 源码同步公开竞赛镜像择新、有界响应和缓存策略；镜像比 GitHub 主源更新时自动使用镜像。
- 班车源码增加完整时刻表、法定假日提醒、历史／回退说明及主题交通图标。
- 同步账号密码说明、图标按钮和“打开教学云平台”完整名称；语言切换保留页面、筛选、草稿及缓存，修复日历和设置／收藏的生命周期。

**分发：源码已同步，新的 Windows 安装包尚未生成。** GitHub Actions 仍受账户构建限制，不用旧包充当更新。

## Linux / Ubuntu

- Tauri 源码同步竞赛镜像择新、完整班车表及法定假日提醒；提示和图标跟随主题。
- 同步账号说明、图标操作按钮、语言状态及缓存保持，以及日历／设置／收藏的动画与迟到回调修复。

**分发：源码已同步，新的 x86_64/arm64 DEB、AppImage 尚未生成。** 等待 GitHub 构建恢复，不用旧包替代。

## CLI / TUI

- 公开竞赛查询比较主源与镜像的实际生成时间，同时间优先 GitHub，两者失败才使用原备用 API。
- 公开竞赛响应上限 4 MiB，保留有界缓存、严格数据验证和失败降级。

**分发：** 新 CLI/TUI 文件尚未生成，等待 GitHub 构建恢复。

## 工程与发布状态

依赖 PR #66、#70、#71 已合入并修复，第三方许可证同步，避免引入被撤回的 `yoke-derive` 版本。

**GitHub 预发布仍为草稿，尚未完整公开。** 当前只有上述 APK 与 DMG；Windows/Linux/CLI/TUI 及最终标签门禁待完成。测试上传不代表全部测试者已经可安装。详细回执见[构建与上传记录](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.2-prerelease.md)。

## English — changes by platform

### iOS / iPadOS

- Preserved position, drafts, filters and cached data across language changes without reauthentication or timetable reloads.
- Kept four iPhone tabs evenly spaced with concise labels and full accessibility names, including landscape and rotation back.
- Added a brief full-window native blur transition, respecting Reduce Motion and canceling stale work. Improved calendar motion and privacy-sheet preparation.
- Added full shuttle timetables, holiday notices, themed transport icons, clearer password guidance and a freshness-checked contest mirror.

**Delivery:** 0.3.2 (103) uploaded to TestFlight; no post-upload processing check or formal review submission.

### macOS

- Preserved settings/editing owners, drafts, scroll and query/calendar state; improved lazy privacy/help/favorites layout and animation lifecycles.
- Added shuttle timetables, holiday notices, themed icons, account guidance and the contest mirror. Mobile full-window blur and full-screen favorites are not macOS features.

**Delivery:** 0.3.2 (103) uploaded to TestFlight; native Universal DMG replaced in the GitHub draft. Public DMG is ad-hoc signed and not notarized.

### Android

- Animated course-summary expansion with reversible motion and cancellation, keeping existing control sizes.
- Preserved drafts, scroll, calendar/query state and cache; added themed shuttle timetables/notices, account action buttons and the contest mirror.

**Delivery:** signed Universal APK 0.3.2 (61) in the GitHub draft; no public AAB or new formal store submission.

### HarmonyOS

- Limited language/navigation animation to backgrounds and icons, preserving position without whole-page text-layout animation.
- Fixed calendar transition lifecycles; added themed shuttle timetables/notices, wrapping action buttons, account guidance and the contest mirror without changing control sizes.

**Delivery:** 0.3.2 (1002038) uploaded through DevEco for testing; quick cloud test passed. No formal review submission or GitHub HarmonyOS package.

### Windows

- Source includes the contest mirror, full shuttle timetable/notices, themed icons, account guidance and language/lifecycle state preservation.

**Delivery:** new Windows installer has not been built due to the GitHub account build restriction. Older files are not presented as the updated version.

### Linux / Ubuntu

- Source includes the contest mirror, full shuttle timetable/notices, themed icons, account guidance and state-preserving language and view transitions.

**Delivery:** new x86_64/arm64 DEB and AppImage files await GitHub builds.

### CLI / TUI

- Public contest queries use freshness-checked mirrors, bounded payloads, caching and validated fallback behavior.

**Delivery:** new binaries await GitHub builds. **The complete pre-release remains a draft; 0.3.1 remains stable.**
