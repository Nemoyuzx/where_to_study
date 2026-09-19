# Where To Study v0.3.0 — Pre-release / 预发布

这是用于体验和反馈的 **0.3.0 预发布版**，不是新的稳定版。稳定下载仍为 0.2.9。安装前建议保留现有配置；所有学校信息请以官方实际记录为准。

## 新增与修复

- 查询页增加“课程作业 DDL”，与班车、重要事件、成绩、考试查询并列；支持查看作业标题、所属课程、截止时间及上游提供的状态。使用已有个人账户和独立教学云密码，不需要浏览器登录状态。
- 纳入之前保留的全平台成绩与考试功能：可查看本人成绩，刷新课表时同步考试安排；考试优先覆盖同一时段的普通课程，不修改学校数据。
- 登录会话与结果缓存分开：重复查询、刷新结果不再无条件重新登录，明确认证过期后最多重登一次；并发请求合并登录，账号／密码变化和清除数据会阻止旧结果回写。
- 令牌仅缓存于当前进程内存，重启进程后会重新登录。优先使用服务提供的有效期；没有期限信息时采用保守的短期上限，不将令牌保存到普通文件。
- 合并 Android 教学云请求受防火墙影响的热修复分支，以及依赖 PR #64、#65。保留 Android／鸿蒙紧凑 32dp／32vp 控件，不恢复此前放大的按钮和间距。
- 更新独立 Rust 锁文件中的 rustls 安全修复，并重新生成第三方许可证清单。

## English

- Added Assignment DDL alongside Shuttle, Important Events, Grades and Exams in Query. It uses the existing saved account and optional separate Teaching Cloud password.
- Integrated the previously retained grades and exam-arrangement features across clients. Timetable refresh includes exams; exams locally take precedence over overlapping course occurrences.
- Reuse credential-scoped, in-memory sessions independently from cached results. Concurrent logins are coalesced; only explicit authentication expiry triggers a single login retry. Account changes and data clearing reject late results. Restarting the process requires a new login.
- Merged the Android Teaching Cloud hotfix and dependency PRs #64/#65, preserving compact mobile control sizing. Updated rustls and generated license notices.

## 构建与验证记录 / Build and verification

版本矩阵：Android **0.3.0 (51)**，Apple **0.3.0 (95)**，HarmonyOS **0.3.0 (1002031)**；Tauri、Core、CLI、TUI **0.3.0**。最终上传回执在完成后补记，不能把本段准备信息理解为已公开。

### 已完成的本地检查

- Android：269 项 Debug／Release JVM 测试、10 项 Android 16 模拟器 UI 测试通过；Release Lint 0 errors／66 warnings／1 hint。签名 APK 为原证书，v2／v3、16 KiB ZIP alignment、版本、HTTPS／许可证校验通过。
- HarmonyOS：222 项 Hypium、正式 HAP／APP 构建、Release 模式与版本检查通过。本机无连接设备，未宣称真机布局验证；未上传 GitHub。
- Apple：完整 macOS 371 项、iOS 395 项单测各仅跳过 1 项既有在线测试，0 失败；另有 2 项 iPhone 中英文查询 UI 流程通过。完整回归发现并修复普通课程时间从节次变成显示文本的兼容性问题，原断言保留。
- 共享逻辑：Core 98 项、Tauri 214 项通过（另有 3 项既有在线测试忽略）；JavaScript 216 项、CLI 24 项、TUI 50 项通过；严格 Clippy、格式检查与许可证检查通过。
- npm audit 未报告漏洞；使用 2026-09-19 更新的 RustSec 库审计全部锁文件，无阻断漏洞／unsound 告警，仍存在第三方未维护提示，不宣称依赖绝对无风险。
- Edge 中英文作业／考试界面、窄桌面布局已检查；Windows／Ubuntu 的最终原生构建和验证以本次 GitHub tag CI 结果为准。

仅公开 Android APK，脚本额外生成的 AAB／校验文件不发布；最终文件摘要在教务认证兼容修复后重新核验。

### Apple 过渡构建记录

iOS **0.3.0 (93)** 已于 **2026-09-19 18:22:33 +0800** 收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`；macOS (93) 未上传。上传在途时交叉审查发现 HTTP 403／423／5xx 中的认证文案不应触发重新登录，以及示例缓存清理的边界，因而修复后最终两端统一使用 **(94)**，不重传已用的 (93)。最终 (94) 回执待补；不检查 App Store Connect processing，不提交正式审核。

上述过渡 **(94)** 已成功上传：iOS **18:30:26.295**、macOS **18:33:03.343 +0800**，均返回 `Upload succeeded` 与 `EXPORT SUCCEEDED`。随后无真实凭据的在线无效令牌探测确认：SJD 教务把明确业务码 401 包装在 HTTP 500 内，因此各平台补充仅限该教务契约的异常分类；一般服务端错误、权限错误及教学云规则不变。最终 Apple 改为 **(95)**，避免对已占用构建号重新上传。实际契约见[教务接入说明](academic-query-contract.md)。

初轮标签构建还修正了 Android SDK 动作默认安装已撤下 `tools` 包的问题，改为显式 `platform-tools`；对应检查覆盖 LF／CRLF，保留所有原测试。仅更新本轮尚未公开的预发布标签，0.2.9 稳定标签及附件不变。

目前验证包括本地 Xcode、Android 模拟器、鸿蒙构建与逻辑测试、共享 Rust／JavaScript 测试和 Edge 中英文桌面预览。所有界面测试使用明确的合成数据；未将私人分数、学号、密码或令牌写入测试产物。当前未连接鸿蒙真机，不能将编译通过称为真机视觉验证。

GitHub 仅计划提供 Windows 安装程序、Linux DEB/AppImage、Linux CLI/TUI、Android APK、原生 macOS Universal DMG；不提供 AAB、HarmonyOS APP/HAP、iOS 包或校验侧文件。Apple 仅上传 TestFlight，不提交 App Store 正式审核；鸿蒙测试上传与其他商店正式审核分别记录。预发布不替换 `releases/latest` 的稳定版。
