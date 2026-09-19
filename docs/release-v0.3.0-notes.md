# Where To Study v0.3.0 — 预发布 / Pre-release

这是用于体验新功能和反馈问题的测试版本。正式稳定版仍为 **0.2.9**，不会被本次预发布替换。

## 本次更新

- **课前提醒**：与每日摘要独立开关，默认提前 10 分钟；可设置 1–5 次、每次 1–1440 分钟，例如 10 分钟和 5 分钟各提醒一次。默认关闭，在“设置 → 课程提醒”中开启。安卓支持可选“闹钟和提醒”授权；未授权可能延迟，过期通知不会补发。只使用本地有效课表，不新增网络登录。Apple／鸿蒙需适时打开应用补排未来通知。[功能与限制](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/pre-class-reminders.md)。
- **桌面日历固定表头**：本轮 macOS 和鸿蒙电脑版中，日／周视图的日期、课程数量和全天日程不再随时间轴滚走；月视图星期栏固定。手机布局不变。Windows／Linux 共享前端源码已同步，此次其 GitHub 安装包暂未替换。
- **课程作业 DDL 查询**：在“查询”中与班车、重要事件、成绩、考试并列，查看课程、作业名称、截止时间与提交状态，使用设置中保存的教学云密码。
- **成绩与考试安排**：纳入此前保留的全平台功能；刷新个人课表时同时同步考试，考试与普通课程冲突时优先显示考试，不修改学校端记录。
- **减少重复登录**：课表、教室、成绩、考试及作业查询复用有效的登录会话，处理并发登录和明确过期后的一次重试；更改账号／密码或清除数据时使旧会话失效。
- **Windows 黑框修复**：正式版不再多出黑色命令行窗口。关闭主窗口仍会进入托盘以支持后台提醒；如需完全结束应用，请选择托盘菜单中的“退出”。
- 保留 Android／鸿蒙的紧凑控件布局，合并教学云请求热修复和两个依赖更新 PR，并补充安全更新及回归测试。

登录令牌仅在应用进程内复用；完全退出后重新打开，会使用已保存凭据重新认证。查询结果仅供参考，请以学校实际记录为准。

## 下载与测试

GitHub 附件提供 Windows 安装程序、Linux x86_64／arm64 的 DEB 与 AppImage、对应 CLI／TUI 压缩包、Android APK 和原生 macOS Universal DMG。普通用户请选择自己系统的安装包；CLI／TUI 是终端工具，不是图形窗口版。

- Apple：**0.3.0 (97)** 已上传 TestFlight；可安装时间以 Apple 处理及测试渠道状态为准，未提交正式 App Store 审核。
- Android：**0.3.0 (53)**，下载 Universal APK 即可。
- 鸿蒙：新构建 **0.3.0 (1002033)** 已完成本地构建和测试，待完成测试渠道上传；上一构建 **(1002032)** 已完成仅测试上传。GitHub 不提供鸿蒙安装包。

本轮新 APK／DMG 的[准确源码提交](https://github.com/Nemoyuzx/where_to_study/tree/87363e620b1efc58b0ea597db7b86929fe0be585)已公开，原 `v0.3.0` 标签保持不变。Windows/Linux 源码和云端构建检查已同步，但本轮未替换它们的安装附件；其附件暂不包含新增课前提醒。

不附带 Android AAB、iOS 归档或校验侧文件。Windows 尚无公众信任的 Authenticode 签名，GitHub macOS DMG 尚未公证；详见[下载与验证说明](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/code-signing.md)。

## English

- Added independent, opt-in pre-class reminders: one at 10 minutes by default, configurable as 1–5 distinct offsets from 1 to 1440 minutes. Android offers optional Alarms & reminders access with approximate fallback. Expired notifications are not replayed; schedules stay local. Apple/HarmonyOS need occasional foreground replenishment because pending notification capacity is limited.
- Pinned desktop calendar headings in the refreshed macOS and HarmonyOS PC builds. Mobile layouts are unchanged. Windows/Linux source has the same fix; their existing public installers are unchanged in this native-only rebuild.
- Added Assignment DDL alongside Shuttle, Important Events, Grades and Exams.
- Integrated grades and exam schedules; exams take precedence over overlapping course occurrences locally.
- Reuse valid in-memory login sessions, coalesce concurrent login requests, and retry explicit authentication expiry once. Sessions are invalidated when credentials change or local data is cleared.
- Fixed the extra Windows console window while retaining tray/background behavior. Use the tray's Quit action to fully exit.
- Preserved compact mobile controls and integrated the Teaching Cloud hotfix, dependency updates and regression checks.

This is a pre-release; **0.2.9 remains the stable release**. Token reuse is process-local, and restarting the process requires authentication again. Apple build **97** has been uploaded to TestFlight, not submitted for production review. Android APK is build **53**. HarmonyOS build **1002033** is locally verified but its test-channel upload is still pending. Windows/Linux source is updated, but their existing public installers are unchanged in this native-only rebuild.

[详细构建、测试与上传记录 / Build and verification record](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.0.md)
