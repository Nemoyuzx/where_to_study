## 主要更新

- 在月视图日期详情中原生同步北邮云课堂作业 DDL，复用应用已保存的账号凭据和统一认证流程，不依赖浏览器会话。
- 联动查询上方加入默认折叠的今日、明日校区天气；日期详情加入带“宜/忌”的黄历卡片。
- 统一活动 DDL 卡片同时读取 Contest DDL 与北邮校内竞赛通知，汇总学科竞赛、夏令营和黑客松截止日期，并在卡片底部标明第三方来源。
- 设置页增加天气、黄历、竞赛、夏令营和黑客松开关；任一公开 DDL 来源暂时不可用时仍会保留其他可用来源。
- 统一 Windows 与 macOS 的教学日历、空教室和设置布局，修复 macOS 教学日历内容宽度被固定在中间的问题。
- 修复 iOS 将普通节日误标为休息日的问题；Windows 与 Linux 继续不包含课程小组件。

## 下载说明

- Windows：x64 NSIS 安装程序。
- Linux：x86_64 与 aarch64 的 Debian 包、AppImage、CLI 和 TUI。
- Android：维护者固定 release key 签名的 Universal APK 与 AAB。
- iOS 与 macOS：正式签名的 `0.2.1 (50)` 已上传 TestFlight，不作为 GitHub Release 附件。

本 Release 不附带 `.sha256` 文件。发布前已完成 Web、Rust、Android、Apple 与 HarmonyOS 全量测试，并以实时校内竞赛通知 API 验证解析契约。
