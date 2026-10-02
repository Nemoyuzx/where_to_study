# Where To Study v0.3.2-prerelease

这是 0.3.2 预发布版，用于测试竞赛数据备份、账户说明与班车完整时刻表。GitHub 最新正式版仍为 0.3.1。

## 本次更新

- 增加 `https://where-to-study.cn/contest-ddl/data/competitions.json` 作为公开竞赛镜像。客户端验证 Schema 1.4、时区和生成时间后，与 GitHub 主源比较；镜像更新时自动采用镜像，同时间优先 GitHub。两者都不可用时才使用原 `contest-events` API。教学日历、重要事件以及 CLI/TUI 的公开查询使用同一规则。
- 竞赛整表响应上限提高到有界的 4 MiB，保留五分钟缓存；自定义日程上限仍为 2 MiB。卡片与隐私说明同步列出镜像来源。
- 个人账户明确区分移动教务密码与教学云密码：前者可能与统一身份认证密码不同；教学云密码通常填写统一身份认证密码，选填，未设置时沿用教务密码。补充部分账号初始密码可能为 YYYYMMDD 的提示，以本人实际设置为准。
- “改用教务密码”“前往个人账户”“打开教学云”采用带图标的按钮样式，补齐中英文与无障碍名称。
- 班车查询在当日班次下增加完整时刻表，按运行时段、方向、周一至周日展示已解析班次。历史、未来和当前时段分别标注；最新通知未解析时明确显示上一份时刻表仅供对照。
- 法定节假日显示班车提醒，普通节日名称和调休上班日不会误触发；假日当天不再强调计划表中的“下一班”。实际运行请以学校通知与放假安排为准。
- 合入并修复依赖 PR #66、#70、#71；同步第三方许可证，避免引入已撤回的 `yoke-derive` 版本。

## 安装与渠道

包内版本为 **0.3.2**：Android build **59**、Apple build **100**、HarmonyOS versionCode **1002036**。构建、测试与上传状态见[工程记录](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.2-prerelease.md)。

GitHub 预发布提供 Windows 安装程序、Linux x86_64/arm64 的 DEB 与 AppImage、CLI/TUI、Android Universal APK 与原生 macOS Universal DMG。Apple 和鸿蒙测试渠道的可安装状态以实际上传回执及渠道页面为准。

## English

- Added a fixed Contest DDL mirror. Valid generation timestamps determine whether the mirror is newer than GitHub; ties prefer GitHub, and the existing API remains the final fallback.
- Bounded public contest payloads at 4 MiB while preserving the 2 MiB custom-feed limit and five-minute cache.
- Clarified Mobile Academic Services versus Teaching Cloud passwords and added accessible icon buttons for account and cloud actions.
- Added full shuttle timetables by operating period, direction, and weekday, with statutory-holiday notices and clear historical/fallback labels.
- Updated reviewed dependencies and their bundled license notices.

**This is a pre-release. 0.3.1 remains the stable GitHub version.** See the [build and upload record](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.2-prerelease.md) for channel completion.
