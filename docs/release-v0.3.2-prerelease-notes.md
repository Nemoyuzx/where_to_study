# Where To Study v0.3.2-prerelease

0.3.2 为测试版本，最新正式版仍为 0.3.1。以下按平台列出改动和实际分发状态，未完成的安装包不会用旧包替代。

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
