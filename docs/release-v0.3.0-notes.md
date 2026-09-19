# Where To Study v0.3.0

**0.3.0 正式版已发布。** GitHub 提供同步后的 Windows、Linux、Android 和 macOS 安装包；手机应用商店的版本可用性取决于各自审核，不等同于 GitHub 发布状态。

## 本次更新

- **课前提醒**：与每日摘要独立开关，默认提前 10 分钟；可设置 1–5 次、每次 1–1440 分钟，例如 10 分钟和 5 分钟各提醒一次。默认关闭，在“设置 → 课程提醒”中开启。安卓支持可选“闹钟和提醒”授权；未授权可能延迟，过期通知不会补发。只使用本地有效课表，不新增网络登录。Apple／鸿蒙需适时打开应用补排未来通知。[功能与限制](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/pre-class-reminders.md)。
- **桌面日历固定表头**：日／周视图的日期、课程数量和全天日程不再随时间轴滚走；月视图星期栏固定。macOS、Windows、Linux 安装包及鸿蒙电脑版源码已同步，手机布局不变。
- **课程作业 DDL 查询**：在“查询”中与班车、重要事件、成绩、考试并列，查看课程、作业名称、截止时间与提交状态，使用设置中保存的教学云密码。
- **成绩与考试安排**：纳入此前保留的全平台功能；刷新个人课表时同时同步考试，考试与普通课程冲突时优先显示考试，不修改学校端记录。
- **减少重复登录**：课表、教室、成绩、考试及作业查询复用有效的登录会话，处理并发登录和明确过期后的一次重试；更改账号／密码或清除数据时使旧会话失效。
- **Windows 黑框修复**：正式版不再多出黑色命令行窗口。关闭主窗口仍会进入托盘以支持后台提醒；如需完全结束应用，请选择托盘菜单中的“退出”。
- 保留 Android／鸿蒙的紧凑控件布局，合并教学云请求热修复和两个依赖更新 PR，并补充安全更新及回归测试。

登录令牌仅在应用进程内复用；完全退出后重新打开，会使用已保存凭据重新认证。查询结果仅供参考，请以学校实际记录为准。

## 下载与商店状态

GitHub 附件提供 Windows 安装程序、Linux x86_64／arm64 的 DEB 与 AppImage、对应 CLI／TUI 压缩包、Android APK 和原生 macOS Universal DMG。普通用户请选择自己系统的安装包；CLI／TUI 是终端工具，不是图形窗口版。

- Apple：**0.3.0 (97)** 已上传 TestFlight，App Store 新版本草稿已准备；正式审核提交状态见工程记录，可安装时间以 Apple 页面为准。
- Android：**0.3.0 (53)**，下载 Universal APK 即可。
- 鸿蒙：**0.3.0 (1002033)** 已通过 DevEco“测试和发布”上传并通过云测试，正式上架草稿已准备。GitHub 不提供鸿蒙安装包。
- vivo：**0.3.0 (53)** 已于 2026-09-19 提交，状态为审核中。华为 Android 同一 APK 已上传至新版本草稿。

本轮安装包的[准确应用源码提交](https://github.com/Nemoyuzx/where_to_study/tree/87363e620b1efc58b0ea597db7b86929fe0be585)已公开；Windows 构建额外包含不改变应用输入的 [CRLF 测试修正](https://github.com/Nemoyuzx/where_to_study/commit/a420142183847638f5d1c16c2d5e210fd93d543e)。原 `v0.3.0` 标签保持不变，因此 GitHub 自动生成的标签源码并非本轮完整应用源码，请开发者使用上述准确提交。

不附带 Android AAB、iOS 归档或校验侧文件。Windows 尚无公众信任的 Authenticode 签名，GitHub macOS DMG 尚未公证；详见[下载与验证说明](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/code-signing.md)。

## English

- Added independent, opt-in pre-class reminders: one at 10 minutes by default, configurable as 1–5 distinct offsets from 1 to 1440 minutes. Android offers optional Alarms & reminders access with approximate fallback. Expired notifications are not replayed; schedules stay local. Apple/HarmonyOS need occasional foreground replenishment because pending notification capacity is limited.
- Pinned desktop calendar headings across macOS, Windows, Linux and HarmonyOS PC. Mobile layouts are unchanged; all GitHub graphical installers include the latest application changes.
- Added Assignment DDL alongside Shuttle, Important Events, Grades and Exams.
- Integrated grades and exam schedules; exams take precedence over overlapping course occurrences locally.
- Reuse valid in-memory login sessions, coalesce concurrent login requests, and retry explicit authentication expiry once. Sessions are invalidated when credentials change or local data is cleared.
- Fixed the extra Windows console window while retaining tray/background behavior. Use the tray's Quit action to fully exit.
- Preserved compact mobile controls and integrated the Teaching Cloud hotfix, dependency updates and regression checks.

**0.3.0 is now the stable GitHub release.** Token reuse is process-local, and restarting the process requires authentication again. Apple build **97** is uploaded to TestFlight, Android APK is build **53**, and HarmonyOS **1002033** has passed DevEco upload and cloud testing. Vivo review has been submitted; Apple and Huawei production drafts are prepared. Store availability depends on each store's review; see the engineering record for submission receipts.

[详细构建、测试与上传记录 / Build and verification record](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.0.md)
