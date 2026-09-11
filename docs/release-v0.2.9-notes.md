# Where To Study 0.2.9

本次更新带来本地课程管理、独立教学云密码、颜色主题、自定义提醒时间，以及 Android 界面和 Apple 日历性能改进。

## 中文

- **管理本地课程**：课程详情可选择「仅删除本次」或「删除本学期整门课程」，刷新课表后仍保留，可在设置中逐条恢复。课表、空闲节次、支持的小组件和课程提醒同步采用编辑后的结果。操作只保存在本机，不会向学校退课、删除学校作业或自动改动已导出的系统日历事件。
- **独立教学云密码**：同一学号可单独设置用于作业 DDL 的教学云平台密码；未设置时继续使用教务密码。同账号留空保留已存密码，显式选择「改用教务密码」并保存可恢复默认方式。
- **颜色主题与背景**：新增五套预设和自定义配色，背景、卡片、控件随主题协调变化，兼顾浅色、深色及文字对比度。默认主题保留原配色，日程类别颜色保持原有含义，设置仅保存在本机。
- **提醒与小组件**：图形客户端可自选每日课程提醒时间，默认北京时间 07:30，提醒默认关闭。支持的小组件优先显示今日课程，有空间时追加明日课程；同时改善大字号布局、提醒撤销与任务恢复。提醒到达仍受系统权限和后台调度影响。
- **Android 界面**：调整手机导航、查询卡片和设置分组，统一圆角、间距与层级，改善平板、英文和大字号布局。
- **班车查询布局**：Android 与鸿蒙按 iOS 的结构展示状态及通知卡、方向和有效日期、自动分列的班次方块、浅色下一班标记与来源说明。整页统一滚动，候车地点和乘车提醒仍保留；修复短列表空位撑高和底部内容遮挡。
- **Apple 日历与加载**：减少导航切换、缓存加载和日历计算对界面的影响；复用月份页面，改善连续翻月、左右切年、节假日提示期间的翻页，以及首次打开年视图日期详情的动画。
- **鸿蒙与平台适配**：改善日历刷新、月视图交互、导航安全区和 PC 字号；修复服务卡片缓存目录与刷新处理，并完善隐私清单、账号切换和清除数据后的状态隔离。
- **安全与稳定性**：作业缓存改用凭据版本隔离，移除密码指纹与终端登录成功信息中的学号；更新兼容依赖，并为 Linux GTK3 所需的 glib 0.18.5 回补上游内存安全修复。安全扫描中的误报按具体证据逐项审查；仍有未维护依赖提示，不代表所有风险归零。

## English

- **Local course management:** remove one occurrence or every meeting of a course in the semester, retain edits after refresh, and restore them in Settings. Timetables, free periods and supported widgets/reminders use the edited result. Changes stay on the device and do not drop university courses, delete assignments or modify previously exported calendar events.
- **Separate teaching cloud password:** use an optional UCloud password with the same student ID for assignment deadlines. With no override, the academic password remains the fallback. Blank same-account edits retain the saved password; an explicit saved reset restores the fallback.
- **Themes and backgrounds:** choose from five presets or custom colors, with coordinated backgrounds, cards and controls across light and dark appearances. Default and deadline-category colors retain their existing meaning; preferences stay local.
- **Reminders and widgets:** choose a daily reminder time, defaulting to 07:30 Beijing time with reminders initially off. Supported widgets prioritize today's courses and add tomorrow's when space allows. Large-text layouts, cancellation and task recovery are improved; delivery remains subject to system permissions and scheduling.
- **Android interface:** refine phone navigation, query cards and Settings groups, with more consistent spacing and hierarchy across tablet, English and large-text layouts.
- **Shuttle layout:** align Android and HarmonyOS with the iOS status/notice card, route and validity headers, adaptive departure tiles, subtle next-departure marker and source notice. Use one scrolling page while preserving pickup locations and rider guidance; fix short-grid sizing and bottom-content overlap.
- **Apple calendar and loading:** reduce work during navigation and cache loading, reuse month pages, and improve repeated month/year paging, holiday-message transitions and the first year-date detail animation.
- **HarmonyOS and platform integration:** improve calendar refresh, month interactions, navigation insets and PC text sizes; repair service-card cache paths and refresh handling, privacy manifests and state isolation after account changes or data clearing.
- **Security and robustness:** isolate assignment caches by credential revision, remove password fingerprints and student IDs from terminal login-success output, update compatible dependencies, and backport the upstream memory-safety fix to glib 0.18.5 required by Linux GTK3. Scanner false positives are reviewed individually with evidence. Unmaintained-dependency notices remain; this is not a claim of zero remaining risk.

## 下载与渠道 / Downloads and channels

从 [GitHub 最新版本页面](https://github.com/Nemoyuzx/where_to_study/releases/latest)的 Assets 选择安装包。不会选择时，参照 [README 下载指南](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/README.md#下载)。GitHub 公开文件共 11 个：

| 用途 / Use | 文件 / Files |
| --- | --- |
| Windows x64 | 1 × `.exe` 安装包 / installer |
| Mac，Apple 芯片和 Intel / Apple silicon and Intel | 1 × 原生 Universal `.dmg` / native Universal DMG |
| Android | 1 × Universal `.apk` |
| Linux，x86_64 和 ARM64 / x86_64 and ARM64 | 4 × 图形版 / desktop `.deb`、`.AppImage`；4 × 终端 CLI/TUI / terminal CLI/TUI `.tar.gz` |

Apple 本轮通过 TestFlight 提供测试，公开测试版本需等待 Apple 审核。Android 商店版通过 vivo 应用商店或华为应用市场，HarmonyOS 通过 AppGallery 渠道；可安装版本以各渠道页面为准。GitHub 不提供 Android AAB、HarmonyOS APP/HAP、iOS 安装包、macOS ZIP 或独立 `.sha256` 附件；`Source code` 为源码，不是安装包。

Apple updates in this round use TestFlight; public testing availability depends on Apple review. Android store distribution uses vivo and Huawei channels, and HarmonyOS uses AppGallery. Availability and versions follow each channel's listing. GitHub provides the 11 files above; source archives are for developers.

Windows 安装包尚无公众信任签名，GitHub macOS DMG 尚未经过 Apple 公证。详见[签名说明 / Signing information](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/docs/code-signing.md)。隐私与开源条款见 [Privacy Policy](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/PRIVACY.md)、[GPL-3.0-only](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/LICENSE)和[第三方声明 / Third-party notices](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/THIRD_PARTY_NOTICES.md)。

各项测试范围、设备限制和安全审查依据见[持续更新的工程发布记录 / Engineering record](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.2.9.md)、[班车布局验证](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/docs/shuttle-layout-v0.2.9.md)、[课程管理验证](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/docs/course-management-v0.2.9.md)、[平台验证](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/docs/platform-standards-fixes-v0.2.9.md)和[安全修复记录](https://github.com/Nemoyuzx/where_to_study/blob/v0.2.9/docs/security-quality-2026-09-11.md)。本地或模拟器测试不能代替所有真机检查，上传成功也不表示商店审核通过。
