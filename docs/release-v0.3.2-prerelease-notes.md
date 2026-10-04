# Where To Study v0.3.2-prerelease

这是 0.3.2 预发布版，用于测试竞赛备份、完整班车时刻表，以及最新的动画、隐私弹窗和语言切换修复。GitHub 最新正式版仍为 0.3.1。

当前 GitHub 预发布仍为草稿：Windows／Linux 等构建因账户账单锁定尚未运行，完整安装包未公开。请不要把旧构建当作包含全部修复的新版本。

## 本次更新

- 增加 `https://where-to-study.cn/contest-ddl/data/competitions.json` 作为公开竞赛镜像。客户端验证 Schema 1.4、时区和生成时间后，与 GitHub 主源比较；镜像更新时自动采用镜像，同时间优先 GitHub。两者都不可用时才使用原 `contest-events` API。教学日历、重要事件以及 CLI/TUI 的公开查询使用同一规则。
- 竞赛整表响应上限提高到有界的 4 MiB，保留五分钟缓存；自定义日程上限仍为 2 MiB。卡片与隐私说明同步列出镜像来源。
- 个人账户明确区分移动教务密码与教学云密码：前者可能与统一身份认证密码不同；教学云密码通常填写统一身份认证密码，选填，未设置时沿用教务密码。补充部分账号初始密码可能为 YYYYMMDD 的提示，以本人实际设置为准。
- “改用教务密码”“前往个人账户”“打开教学云平台”采用带图标的按钮样式，补齐中英文与无障碍名称。
- 班车内容使用公交、线路等专属图标；节假日、缓存和时段提示跟随主题次要文字色，避免与错误提示混淆。教学云平台入口在各端统一显示完整名称，英文为 “Open Teaching Cloud Platform”。
- 班车查询在当日班次下增加完整时刻表，按运行时段、方向、周一至周日展示已解析班次。历史、未来和当前时段分别标注；最新通知未解析时明确显示上一份时刻表仅供对照。
- 法定节假日显示班车提醒，普通节日名称和调休上班日不会误触发；假日当天不再强调计划表中的“下一班”。实际运行请以学校通知与放假安排为准。
- 合入并修复依赖 PR #66、#70、#71；同步第三方许可证，避免引入已撤回的 `yoke-derive` 版本。
- 修复日／周课程摘要、月／年视图及跨平台切换的动画与迟到回调；减少 Apple 隐私页出现前的准备工作，保留原生呈现动画。
- 设置弹窗、收藏长列表与未保存草稿使用稳定的页面所有者；收藏按批次展示，离页后取消旧任务。
- 切换中英界面时保留当前位置、输入草稿、查询筛选和已加载数据；修复导航条测量及鸿蒙局部文字刷新，原始 API 内容不自动翻译。
- 修复 iPhone/iPad 切换语言过程中整个页面短暂跳动；鸿蒙语言及导航动画限于独立背景与图标，不让文本重排触发整页动画。保持安卓原控件尺寸不变。
- iPhone 英文底栏使用简洁名称并保持四项等距，横屏也保留图标在文字上方；完整页面及无障碍名称不变。iPhone/iPad 切换语言增加短暂全屏系统模糊过渡，保留当前位置和草稿；尊重减少动态效果，并处理快速反向与离页清理。
- 语言变化不触发额外登录或课表获取；公开班车快照复用有界缓存，过期或手动刷新仍会正常获取。

## 安装与渠道

包内版本为 **0.3.2**：Android build **61**、Apple build **103**、HarmonyOS versionCode **1002038**。构建、测试与上传状态见[工程记录](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.2-prerelease.md)。

公开前计划补齐 Windows 安装程序、Linux x86_64/arm64 的 DEB 与 AppImage、CLI/TUI、Android Universal APK 与原生 macOS Universal DMG。当前草稿附件和未完成项以工程记录为准。Apple 与鸿蒙测试上传不等于已经对所有测试者可安装；本轮不提交正式商店审核。

## English

- Added a fixed Contest DDL mirror. Valid generation timestamps determine whether the mirror is newer than GitHub; ties prefer GitHub, and the existing API remains the final fallback.
- Bounded public contest payloads at 4 MiB while preserving the 2 MiB custom-feed limit and five-minute cache.
- Clarified Mobile Academic Services versus Teaching Cloud passwords and added accessible icon buttons for account and cloud actions.
- Added full shuttle timetables by operating period, direction, and weekday, with statutory-holiday notices and clear historical/fallback labels.
- Updated reviewed dependencies and their bundled license notices.
- Preserved scroll anchors, unsaved drafts, query filters and cached data across language changes, without extra authentication or schedule requests.
- Prevented transient whole-page geometry jumps during iPhone/iPad language changes; HarmonyOS animates only isolated backgrounds and icons. Android control sizes remain unchanged.
- Kept the four iPhone tabs evenly spaced with concise labels and full accessibility names, including landscape. Added a brief full-window native blur transition on iPhone/iPad, preserving position and drafts, respecting Reduce Motion, and canceling stale callbacks.
- Fixed animation lifecycles, privacy-sheet preparation, native tab geometry and incremental favorites rendering.

**The GitHub pre-release is still a draft while Windows/Linux builds are blocked by an account billing lock. 0.3.1 remains the stable version.** See the [build and upload record](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.2-prerelease.md) for the actual channel and asset status.
