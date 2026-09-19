# Where To Study v0.3.0 — 预发布 / Pre-release

这是用于体验新功能和反馈问题的测试版本。正式稳定版仍为 **0.2.9**，不会被本次预发布替换。

## 本次更新

- **课程作业 DDL 查询**：在“查询”中与班车、重要事件、成绩、考试并列，查看课程、作业名称、截止时间与提交状态，使用设置中保存的教学云密码。
- **成绩与考试安排**：纳入此前保留的全平台功能；刷新个人课表时同时同步考试，考试与普通课程冲突时优先显示考试，不修改学校端记录。
- **减少重复登录**：课表、教室、成绩、考试及作业查询复用有效的登录会话，处理并发登录和明确过期后的一次重试；更改账号／密码或清除数据时使旧会话失效。
- **Windows 黑框修复**：正式版不再多出黑色命令行窗口。关闭主窗口仍会进入托盘以支持后台提醒；如需完全结束应用，请选择托盘菜单中的“退出”。
- 保留 Android／鸿蒙的紧凑控件布局，合并教学云请求热修复和两个依赖更新 PR，并补充安全更新及回归测试。

登录令牌仅在应用进程内复用；完全退出后重新打开，会使用已保存凭据重新认证。查询结果仅供参考，请以学校实际记录为准。

## 下载与测试

GitHub 附件提供 Windows 安装程序、Linux x86_64／arm64 的 DEB 与 AppImage、对应 CLI／TUI 压缩包、Android APK 和原生 macOS Universal DMG。普通用户请选择自己系统的安装包；CLI／TUI 是终端工具，不是图形窗口版。

- Apple：**0.3.0 (95)** 已上传 TestFlight；可安装时间以 Apple 处理及测试渠道状态为准，未提交正式 App Store 审核。
- Android：**0.3.0 (51)**，下载 Universal APK 即可。
- 鸿蒙：**0.3.0 (1002031)** 已完成本地构建和测试，本轮尚未上传测试渠道，GitHub 不提供鸿蒙安装包。

不附带 Android AAB、iOS 归档或校验侧文件。Windows 尚无公众信任的 Authenticode 签名，GitHub macOS DMG 尚未公证；详见[下载与验证说明](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/code-signing.md)。

## English

- Added Assignment DDL alongside Shuttle, Important Events, Grades and Exams.
- Integrated grades and exam schedules; exams take precedence over overlapping course occurrences locally.
- Reuse valid in-memory login sessions, coalesce concurrent login requests, and retry explicit authentication expiry once. Sessions are invalidated when credentials change or local data is cleared.
- Fixed the extra Windows console window while retaining tray/background behavior. Use the tray's Quit action to fully exit.
- Preserved compact mobile controls and integrated the Teaching Cloud hotfix, dependency updates and regression checks.

This is a pre-release; **0.2.9 remains the stable release**. Token reuse is process-local, and restarting the process requires authentication again. Apple build **95** has been uploaded to TestFlight, not submitted for production review.

[详细构建、测试与上传记录 / Build and verification record](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.0.md)
