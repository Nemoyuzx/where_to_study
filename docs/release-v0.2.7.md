# Where To Study v0.2.7

## 中文

### HTTPS 域名迁移

- Windows、Linux 与 Tauri 兼容构建、iOS、macOS、Android 和 HarmonyOS 的竞赛备用源统一迁移到 `https://where-to-study.cn/api/contest-events`。
- 校内竞赛通知统一迁移到 `https://where-to-study.cn/api/contest-notices`。数据仍由服务器脚本从学校公开通知页提取整理，条目链接回 HTTPS 原文。
- 所有固定源仍校验 HTTPS scheme 与主机、拒绝重定向、限制响应大小，且不发送账号、密码、Cookie、token、课表、教室或作业数据。
- Android 删除竞赛 API 的明文网络安全例外，iOS/macOS 删除对应 ATS 例外；发布脚本会检查安装包中不含旧主机，并确认包含新 HTTPS 域名。
- README、隐私政策、安全说明和第三方声明已同步。

### 版本与分发

- Web/Tauri、共享 Rust Core、CLI 和 TUI：`0.2.7`；Tauri Android `versionCode=2010`，legacy Tauri iOS build 46。
- Android：`0.2.7 (43)`，固定维护者证书签名的 Universal APK/AAB。
- iOS 与原生 macOS：`0.2.7 (73)`，由本机 Xcode 分平台重新归档并上传；两端均收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`，按发布约定未继续检查 App Store Connect processing。
- HarmonyOS：`0.2.7 (1002012)`，DevEco `Upload Product` 已上传用于测试和发布的 APP，云测试结果为“通过”。[打开 HarmonyOS 测试邀请（已含邀请码）](https://appgallery.huawei.com/link/invite-test-wap?taskId=dfc32d0293987b9d09911717759ac063&invitationCode=A0IsJpKIcn3)。
- GitHub Release 保持 14 项公开制品：Windows x64 NSIS；Linux arm64/x86_64 Debian 包、AppImage、CLI 与 TUI；Android APK/AAB；HarmonyOS APP/HAP；以及原生 macOS Universal DMG。不上传 iOS 或 `.sha256` 文件。macOS DMG 是未公证的开源预览包。

### 验证

- 新 HTTPS 接口均直接返回 `200 application/json`、不重定向；实际数据契约与全平台解析器兼容。
- Node 契约/主题/发布门禁：116/116；Vite 生产构建与许可证新鲜度检查通过。
- Tauri Rust：146 通过，1 项真实账号测试按设计忽略；共享 Core 55/55，CLI 14/14，TUI 14/14。
- Apple：macOS 212/212；iOS 219/219 单元测试；23 项 iOS UI 中 19 通过、4 项仅 iPad 条件跳过、0 失败。严格 Swift 6、警告即错误、正式归档与本地 App Store export 检查通过；iOS 导出包主应用与 Widget 均为 Apple Distribution 签名且不含 `get-task-allow`。
- Android：186/186 Release JVM 测试、Lint、证书指纹、ZIP 对齐、APK/AAB 签名、版本、许可证与 HTTPS-only 网络策略校验通过。
- HarmonyOS：113/113 ArkTS 单元测试、assembleHap/assembleApp、独立 HAP 签名验证、APP ZIP 结构和 DevEco 云测试通过。

## English

### HTTPS domain migration

- Windows, Linux, Tauri-compatible builds, iOS, macOS, Android, and HarmonyOS now use `https://where-to-study.cn/api/contest-events` as the fixed contest backup endpoint.
- School competition notices now use `https://where-to-study.cn/api/contest-notices`. The server-side script still extracts deadlines from public university notices, and item links point back to their HTTPS originals.
- Every fixed source still pins the HTTPS scheme and host, rejects redirects, limits the response body, and sends no account, password, cookie, token, schedule, classroom, or assignment data.
- Android no longer carries a cleartext network-security exception, and iOS/macOS no longer carry the corresponding ATS exception. Packaging gates reject the retired host and require the new HTTPS domain in final artifacts.
- README, privacy, security, and third-party notices were updated together.

### Versions and distribution

- Web/Tauri, shared Rust Core, CLI, and TUI: `0.2.7`; Tauri Android `versionCode=2010`; legacy Tauri iOS build 46.
- Android: `0.2.7 (43)`, Universal APK/AAB signed with the pinned maintainer certificate.
- Native iOS and macOS: `0.2.7 (73)`, freshly archived and uploaded separately with local Xcode. Both returned `Upload succeeded` and `EXPORT SUCCEEDED`; App Store Connect processing was intentionally not inspected afterward.
- HarmonyOS: `0.2.7 (1002012)`. DevEco `Upload Product` uploaded the APP for testing and release, and the cloud-test result passed. [Open the HarmonyOS test invitation (code included)](https://appgallery.huawei.com/link/invite-test-wap?taskId=dfc32d0293987b9d09911717759ac063&invitationCode=A0IsJpKIcn3).
- The GitHub Release keeps 14 public artifacts: Windows x64 NSIS; Linux arm64/x86_64 Debian, AppImage, CLI, and TUI builds; Android APK/AAB; HarmonyOS APP/HAP; and the native macOS Universal DMG. iOS and `.sha256` files are not attached. The macOS DMG is an unnotarized open-source preview.

### Validation

- Both HTTPS APIs returned direct `200 application/json` responses without redirects, and their live envelopes matched the existing cross-platform parsers.
- Node contracts/theme/release gates: 116/116; Vite production build and license freshness passed.
- Tauri Rust: 146 passed, 1 live-account test intentionally ignored; shared Core 55/55; CLI 14/14; TUI 14/14.
- Apple: macOS 212/212; iOS 219/219 unit tests; 19 of 23 iOS UI tests passed with 4 iPad-only conditional skips and no failures. Strict Swift 6, warnings-as-errors, signed archives, and a local App Store export passed; the exported iOS app and widget are Apple Distribution signed without `get-task-allow`.
- Android: 186/186 Release JVM tests, Lint, signer fingerprint, ZIP alignment, APK/AAB signing, version, license, and HTTPS-only packaged policy checks passed.
- HarmonyOS: 113/113 ArkTS tests, assembleHap/assembleApp, standalone HAP signature verification, APP ZIP structure, and DevEco cloud testing passed.
