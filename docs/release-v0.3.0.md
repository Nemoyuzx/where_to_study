# Where To Study v0.3.0 — Pre-release / 预发布

## 2026-09-19 桌面表头修复构建 / Pinned-header rebuild

本轮构建源码为 `1833f57e10b08b92273001f9042550bf72cea137`（包含 `a1106d0` 的桌面日／周日期、课程数量与全天日程固定，以及月视图星期栏固定）。版本仍为 **0.3.0 预发布**，现有标签和稳定版 0.2.9 未移动；仅替换下述原生 APK／DMG，Windows／Linux／终端工具附件保持此前内容。

- Android **(52)**：Release JVM 271 项通过，Lint 0 errors／66 warnings／1 hint，固定证书、v2／v3、16 KiB ZIP alignment、HTTPS 与许可证检查通过。Android 此次是当前源码重建，未更改手机布局。
- Apple **(96)**：本地 Xcode 完整 macOS 376 项（跳过 1）、iOS 单测 398 项（跳过 1）、iOS UI 44 项（跳过 7），全部 0 失败。iOS 于 **21:40:09.274**、macOS 于 **21:43:35.288 +0800** 收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`；未继续检查 App Store Connect，未提交正式审核。149 项 Apple 源码／构建输入前后摘要一致。Universal DMG 的 App／Widget 均为 (96)、arm64+x86_64；公开 DMG 仍为 ad-hoc 签名、未公证。
- HarmonyOS **(1002032)**：224 项 Hypium、release 模式、独立签名／profile／ZIP／版本校验通过。DevEco 使用主工程，重新加载磁盘并同步后确认 0.3.0，选择第二项“生成 .app 包并上传至 AppGallery Connect 进行测试”；本轮 **仅测试上传成功，云测试通过**，没有提交上架审核。最终 APP 修改时间 21:24:23，21:26:44 完成上传后字节核验。界面显示的附加 build=1 不替代真实 versionCode。无鸿蒙设备，未宣称真机通知／视觉验证。

| 最终产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| GitHub Android APK (52) | 1,148,838 | `030fd3e611385ce8d855ac3f0de868ff30273b4cbd954a1710d998cb094d55bb` |
| GitHub macOS Universal DMG (96) | 7,831,878 | `7e21ee218c0eb7c441fb1ca4381f0af780a726fcb998df358ec8f1a2052a6ff0` |
| DevEco 最终 HAP (1002032)，不公开 | 2,068,947 | `ac3042ccc1862d9bbb5384ce3bea84f793b35c54b720319b70971257e3e99989` |
| DevEco 最终 APP (1002032)，不公开 | 1,354,584 | `634eaaf4fca37af64660d7dbafa8c6883be15f3a8e6276d9047fd37c4eca314c` |

GitHub 两个替换附件的 API 大小与 SHA-256 均与本地一致，未回下载。无公开 AAB／HarmonyOS／iOS 包。原生安装包路径：`release-artifacts/v0.3.0-pinned-build{52,96,1002032}/`；鸿蒙最终 DevEco 字节另存于 `devecoupload/`，不覆盖 CLI 副本。Apple (96) 的归档和 xcresult 已独立保留，下一轮构建不覆盖该证据。

## 已公开 / Published

[Where To Study v0.3.0](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.3.0) 于 **2026-09-19 20:24:19 +0800** 公开为预发布版（Release ID `392028491`，`draft=false`，`prerelease=true`）。标题符合既有命名，恰有 **11 个**安装／终端工具附件；稳定版 `releases/latest` 仍为 **v0.2.9**，旧版附件未修改。

最终标签提交 **`b317917e17d63f1d2786894d0b60f6d60c7e994a`** 的七条工作流全部通过：

| 工作流 | Run | 结果 |
| --- | --- | --- |
| Windows | [35440712204](https://github.com/Nemoyuzx/where_to_study/actions/runs/35440712204) | success |
| Linux | [35440712186](https://github.com/Nemoyuzx/where_to_study/actions/runs/35440712186) | success |
| macOS | [35440712176](https://github.com/Nemoyuzx/where_to_study/actions/runs/35440712176) | success |
| Native Clients | [35440712207](https://github.com/Nemoyuzx/where_to_study/actions/runs/35440712207) | success |
| CLI | [35440712214](https://github.com/Nemoyuzx/where_to_study/actions/runs/35440712214) | success |
| TUI | [35440712206](https://github.com/Nemoyuzx/where_to_study/actions/runs/35440712206) | success |
| Security Checks | [35440712199](https://github.com/Nemoyuzx/where_to_study/actions/runs/35440712199) | success |

Windows 修复包（4,279,736 bytes）的 SHA-256 为 `dafe106d1ee78848293173d57892d25555429c7c704eb54fe1a541f65b42fc1c`。实际构建的 Windows 工作流 `35439539986` 在静默安装 NSIS 后验证真正的 `where_to_study.exe`，GUI 子系统检查 **8 项通过、0 跳过**；不是只检查安装器。

公开前已通过 GitHub API 逐项核对 11 个资产的名称、大小和 SHA-256。九个 CI 产物的结构／架构、现有摘要侧文件和固定工作流来源证明通过，并固定到其实际构建源 `5c99ef6`；源码差异说明见下文。遵照用户最新要求，**不继续回下载核验**，也不把 API 摘要比对称为下载后的逐字节验证。

热修复分支 `codex/android-029-layout-hotfix` 的最新提交 `bd20973` 已通过 [6a2df48](https://github.com/Nemoyuzx/where_to_study/commit/6a2df48bb8fbdf0c3d61540ec3834eb1f6a8e6e6) 合入 `main`；PR #64、#65 均已合并。热修复分支没有独有的未合并提交，仅保留分支名称，没有擅自删除。原工作区的 138 个功能文件核对后保留了本地备份，`source-picture/` 未提交。

Apple 最终 (95) 两端已上传 TestFlight，未再检查 App Store Connect 或提交正式审核。HarmonyOS (1002031) 已签名构建／测试，但尚未获得本轮测试渠道上传确认，因此未上传 AppGallery；vivo／华为 Android 正式商店状态未改。

这是用于体验和反馈的 **0.3.0 预发布版**，不是新的稳定版。稳定下载仍为 0.2.9。安装前建议保留现有配置；所有学校信息请以官方实际记录为准。

## 新增与修复

- 查询页增加“课程作业 DDL”，与班车、重要事件、成绩、考试查询并列；支持查看作业标题、所属课程、截止时间及上游提供的状态。使用已有个人账户和独立教学云密码，不需要浏览器登录状态。
- 纳入之前保留的全平台成绩与考试功能：可查看本人成绩，刷新课表时同步考试安排；考试优先覆盖同一时段的普通课程，不修改学校数据。
- 登录会话与结果缓存分开：重复查询、刷新结果不再无条件重新登录，明确认证过期后最多重登一次；并发请求合并登录，账号／密码变化和清除数据会阻止旧结果回写。
- 令牌仅缓存于当前进程内存，重启进程后会重新登录。优先使用服务提供的有效期；没有期限信息时采用保守的短期上限，不将令牌保存到普通文件。
- 合并 Android 教学云请求受防火墙影响的热修复分支，以及依赖 PR #64、#65。保留 Android／鸿蒙紧凑 32dp／32vp 控件，不恢复此前放大的按钮和间距。
- 更新独立 Rust 锁文件中的 rustls 安全修复，并重新生成第三方许可证清单。
- 修复 Windows 正式版启动时出现黑色控制台、关闭主窗口后黑框仍残留的问题。正式版改为 GUI 子系统；托盘常驻／后台提醒保持原样，“退出”仍会结束应用。CI 安装最终 NSIS 后会检查真正的主程序 PE Subsystem=2，避免只检查安装器造成误判。

## English

- Added Assignment DDL alongside Shuttle, Important Events, Grades and Exams in Query. It uses the existing saved account and optional separate Teaching Cloud password.
- Integrated the previously retained grades and exam-arrangement features across clients. Timetable refresh includes exams; exams locally take precedence over overlapping course occurrences.
- Reuse credential-scoped, in-memory sessions independently from cached results. Concurrent logins are coalesced; only explicit authentication expiry triggers a single login retry. Account changes and data clearing reject late results. Restarting the process requires a new login.
- Merged the Android Teaching Cloud hotfix and dependency PRs #64/#65, preserving compact mobile control sizing. Updated rustls and generated license notices.
- Windows release builds no longer create a console window. Existing tray/background behavior is preserved; the installed application is checked for the Windows GUI subsystem in CI.

## 构建与验证记录 / Build and verification

版本矩阵：Android **0.3.0 (51)**，Apple **0.3.0 (95)**，HarmonyOS **0.3.0 (1002031)**；Tauri、Core、CLI、TUI **0.3.0**。

### 最终 Apple 上传与本地产物

本次最终标签源码为 **`b317917e17d63f1d2786894d0b60f6d60c7e994a`**。Windows／Linux／CLI／TUI 九个附件的实际构建源是 **`5c99ef60aa472e58ce4236ed33b8d14cd55dce47`**；最终标签相对该提交只修改 `native/apple/UITests/ColorThemeUITests.swift` 的滚动方向，已逐项确认其余生产源码、资源和构建配置完全相同，不将测试修正后标签冒称为附件的实际构建提交。

`5c99ef6` 相对 **`0e1989fc523369aa7f302993bf3cd6cd063ba74f`** 只追加 Windows GUI 子系统及其 CI／测试检查；Apple、Android、HarmonyOS 应用源码／打包输入未变，不重复上传已经成功的原生客户端。

通过本地 Xcode 单次 `native-apple-app-store.sh upload all` 完成最终 Apple **0.3.0 (95)**：iOS／iPadOS 于 **2026-09-19 18:45:48.297 +0800**，macOS 于 **18:48:25.557 +0800** 收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`。四个主应用／Widget 的版本一致，99 项源码／打包输入在前后完全一致。未检查 App Store Connect processing，未提交 App Store 正式审核；上传成功不等于已完成 Apple 处理或外部测试审核。

| 最终本地产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| Android Universal APK (51) | 1,148,838 | `d69762465c8e4e0fd91e414c1bb0589edd8b5f2b70e8a40ec6473d580bb21b91` |
| macOS Universal DMG (95) | 7,788,233 | `9e960cef85260e9db858f0a388aed5919e399e25bc2e4087a2c27701dca77c34` |

这两个文件先上传至 GitHub 预发布草稿，用户后续调整验收方式之前已完成逐字节比对；最终公开状态见文首回执。

**发布验收方式更新（用户要求）**：不再执行 GitHub Release 附件回下载核验。采用上传前本地文件 SHA-256、GitHub API 返回的资产名称／大小／摘要，以及已有 CI、签名／构建来源证明结果。后续九个附件的回下载验证阶段已按用户要求停止，不把已发生的传输或服务端摘要比对称为“全部回下载逐字节通过”；现有文件不删除。此前九个资产的 API 元数据均已匹配，附件总数仍为 11。

### 已完成的本地检查

- Android：最终 Release JVM 271 项通过，SJD 会话定向 13 项通过；之前 10 项 Android 16 模拟器 UI 流程通过。Release Lint 0 errors／66 warnings／1 hint。签名 APK 为原证书，v2／v3、16 KiB ZIP alignment、版本、HTTPS／许可证校验通过。
- HarmonyOS：224 项 Hypium、正式 HAP／APP 构建、Release 模式与版本检查通过。本机无连接设备，未宣称真机布局验证；未上传 GitHub，未提交正式商店审核。
- Apple：最终完整 macOS 374 项、iOS 398 项单测各仅跳过 1 项既有在线测试，0 失败；另有 2 项 iPhone 中英文查询 UI 流程通过。完整回归发现并修复普通课程时间从节次变成显示文本的兼容性问题，原断言保留。
- 共享逻辑：Core 100 项、Tauri 216 项通过（另有 3 项既有在线测试忽略）；JavaScript 225 项（224 通过，实际 Windows 安装包检查在 macOS 上跳过、在 Windows CI 安装后执行）、CLI 24 项、TUI 50 项通过；严格 Clippy、格式检查与许可证检查通过。
- npm audit 未报告漏洞；使用 2026-09-19 更新的 RustSec 库审计全部锁文件，无阻断漏洞／unsound 告警，仍存在第三方未维护提示，不宣称依赖绝对无风险。
- Edge 中英文作业／考试界面、窄桌面布局已检查；Windows／Ubuntu 的最终原生构建和验证以本次 GitHub tag CI 结果为准。

仅公开 Android APK，脚本额外生成的 AAB／校验文件不发布；最终文件摘要在教务认证兼容修复后重新核验。

### Apple 过渡构建记录

iOS **0.3.0 (93)** 已于 **2026-09-19 18:22:33 +0800** 收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`；macOS (93) 未上传。上传在途时交叉审查发现 HTTP 403／423／5xx 中的认证文案不应触发重新登录，以及示例缓存清理的边界，因而修复后最终两端统一使用 **(94)**，不重传已用的 (93)。最终 (94) 回执待补；不检查 App Store Connect processing，不提交正式审核。

上述过渡 **(94)** 已成功上传：iOS **18:30:26.295**、macOS **18:33:03.343 +0800**，均返回 `Upload succeeded` 与 `EXPORT SUCCEEDED`。随后无真实凭据的在线无效令牌探测确认：SJD 教务把明确业务码 401 包装在 HTTP 500 内，因此各平台补充仅限该教务契约的异常分类；一般服务端错误、权限错误及教学云规则不变。最终 Apple 改为 **(95)**，避免对已占用构建号重新上传。实际契约见[教务接入说明](academic-query-contract.md)。

初轮标签构建还修正了 Android SDK 动作默认安装已撤下 `tools` 包的问题，改为显式 `platform-tools`；对应检查覆盖 LF／CRLF，保留所有原测试。仅更新本轮尚未公开的预发布标签，0.2.9 稳定标签及附件不变。

云端完整 UI 回归识别出主题测试脚本方向错误：遍历到 `rose` 后返回上方 `default`，原脚本仍向下滚动，无法让 LazyVGrid 离屏按钮重新出现。仅对返回默认项指定向上滚动，全部断言及 18 次滚动预算保持不变；本地同一用例连续两次通过（57.441／48.951 秒）。生产输入摘要不变，未因此重新打包或上传 Apple (95)。

目前验证包括本地 Xcode、Android 模拟器、鸿蒙构建与逻辑测试、共享 Rust／JavaScript 测试和 Edge 中英文桌面预览。所有界面测试使用明确的合成数据；未将私人分数、学号、密码或令牌写入测试产物。当前未连接鸿蒙真机，不能将编译通过称为真机视觉验证。

GitHub 仅计划提供 Windows 安装程序、Linux DEB/AppImage、Linux CLI/TUI、Android APK、原生 macOS Universal DMG；不提供 AAB、HarmonyOS APP/HAP、iOS 包或校验侧文件。Apple 仅上传 TestFlight，不提交 App Store 正式审核；鸿蒙测试上传与其他商店正式审核分别记录。预发布不替换 `releases/latest` 的稳定版。
