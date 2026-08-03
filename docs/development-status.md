# 开发检查点（2026-08-03）

## 检查点范围

- 分支：`codex/native-platform-foundation`
- 起始基线：`v0.1.1-alpha.5`（`1e6dd28`）
- 数据源：继续使用现有移动教务 SJD 接口，没有切换数据源
- 发布状态：源码检查点，尚不是可发布版本
- 本地发布暂存：`release-artifacts/`（被 `.gitignore` 排除，不提交二进制）

## 已完成

### 共享契约与业务规则

- 固化 `contracts/v1` 课表、空教室和节假日结构及脱敏夹具。
- Rust、Swift、Kotlin 统一教室名称解析：教学楼与教室号分开，普通教室保留三位号，`202-203`、`217-218` 等双门号码保持为同一间教室。
- 空教室只查询当天，使用原有教学楼集合；已移除“推荐同一教室”。
- 个人课表持久化到本地；课表实际存在第 17、18 周时将对应课程标记为“试”。
- 保留原有浅色、绿色品牌样式，日/周/月/年仅复用系统日历的交互能力。

### Apple 原生端

- SwiftUI macOS/iOS 三个一级页面：空教室、教学日历、设置。
- 接入个人课表、当天空教室、法定节假日、本地缓存和 Keychain。
- 日/周/月/年日历、课程节次与整点刻度、今日/选中日期状态、年视图课程热度、日期日程浮层和当前时间线。
- EventKit 课程导入、考试标题、提醒能力。
- macOS 菜单栏图标与今日/明日课程内容；关闭主窗口后保持菜单栏运行。
- 启动时按需刷新当天空教室；macOS 每日 07:00 低频刷新任务。
- 原生图标、隐私清单、通用 macOS 构建和无签名 iOS Archive 脚本。

### Android 原生端

- Kotlin + Android Views 手机/平板布局及三个一级页面。
- 接入个人课表、当天空教室、法定节假日、Keystore 凭据和 `AtomicFile` 缓存。
- 日/周/月/年日历、节次与整点刻度、课程热度、日期浮层、法定节假日和当前时间线。
- Android Calendar Provider 课程导入。
- 启动刷新与 `JobScheduler` 每日 07:00 刷新基础实现。
- APK/AAB 本地签名与打包脚本。

### Tauri / Windows 基线

- 保留 Tauri + React 作为 Windows 客户端，并保持现有 macOS 迁移期构建可用。
- 只使用当前 SJD 请求路径，移除旧接口/XLS 回退和旧 macOS User-Agent 分支。
- 密码不再返回 WebView；系统安全存储、旧明文设置迁移及敏感结构内存清理已接入。
- 托盘、今日/明日课程、通知、日历导入、节假日和本地数据清除命令已接入。
- 启动/每日定时任务已扩展为跨日调度基础实现。

### 工程与安全

- GitHub Actions 第三方 Action 固定到提交 SHA，并增加 Dependabot 配置。
- 增加隐私、安全、贡献、行为准则、Issue 与 PR 模板。
- 忽略环境文件、证书、签名密钥、构建目录和发布二进制。
- 当前源码检查点的高风险密钥、GitHub token、私钥和 Gmail 地址模式扫描无命中。

## 最近验证结果

| 范围 | 结果 | 说明 |
| --- | --- | --- |
| Android 全量 Debug 构建 | 通过 | 2026-08-03；编译、44 个 JVM 测试、Lint、APK 组装全部通过，Lint 为 `No issues found` |
| macOS XCTest | 通过 | 最新结果 33/33，通过时间 2026-08-03 22:45（Asia/Shanghai） |
| iOS Simulator XCTest | 通过 | 最新结果 32/32，通过时间 2026-08-03 22:16（Asia/Shanghai） |
| React 生产构建 | 通过 | 最近一次 `npm run build` 通过 |
| Rust | 部分通过 | 此检查点之前完整套件 45/45；新增共享 fixture 测试单独通过，当前完整套件尚未重跑 |
| npm 生产依赖审计 | 通过 | `npm audit --omit=dev --audit-level=high` 为 0 个漏洞 |
| Workflow YAML | 通过 | Ruby YAML 解析通过 |

## 本地暂存包

这些文件已保留在 `release-artifacts/`，校验和文件均已通过 `shasum -a 256 -c`：

| 文件 | SHA-256 | 状态 |
| --- | --- | --- |
| `Where-To-Study-v0.1.1-alpha.6-macos-arm64.zip` | `4c48a3c9d08f714064552904de295a3d374373a1011606708039cca9e6ac2fa7` | Tauri macOS arm64，adhoc 签名 |
| `Where-To-Study-v0.1.1-alpha.6-native-macos-universal.zip` | `78ee162cf95a7363d7f25aebef1464605fd88113cb2a8b26d1e9ccfc1c3b6eca` | 原生 macOS x86_64 + arm64，adhoc 签名 |
| `Where-To-Study-v0.1.1-alpha.6-native-ios-unsigned.xcarchive.zip` | `a4e1106db7c724999d3b2ed2ee8c84baafac88fd5ddc6b52b78c0f0e296c582a` | iOS 无签名 Archive |
| `Where-To-Study-v0.1.1-alpha.6-native-android-universal.apk` | `ac520349e2027bdadfee865f2b97880e61fd5baba03f38d70c221c0169f2324e` | Android universal APK，v2 自签名 |
| `Where-To-Study-v0.1.1-alpha.6-native-android.aab` | `782d70db12bab276b803c354618e1f0bc641fc7b8b197d0d7544d13a71a972d3` | Android AAB，自签名 |

注意：这些包的内部版本均为 `0.1.1` / build `5`，且生成时间早于本检查点的最后一批源码和测试。因此它们只作为已完成打包流程的本地暂存证据，不能直接发布为最终 `alpha.6`。

## 待完成（按优先级）

### P1：发布前必须修复

- Android：消除异步课表、空教室、节假日写入与“清除本地数据”的竞态，防止旧请求重新写回缓存。
- Android：密码输入框默认保持空白；仅同一账号留空时保留 Keystore 密码，切换账号必须输入新密码，并禁止 Autofill 回填。
- Android：系统日历导入增加进程级互斥、Activity 重建恢复和学期范围内旧事件清理；避免课程时间/地点变化产生重复事件。
- Android：每日任务增加明确的失败重试、执行窗口和停止后取消旧请求语义。
- Apple：设置页不回填 Keychain 明文密码；实现同账号留空保留、换账号必须输入新密码。
- Apple：EventKit 在当前学期范围内清理本应用已失效事件，避免课程变化后重复。
- Tauri：用进程级写入协调解决清除数据与后台保存竞态，并修正切换账号后的“留空保持密码”提示状态。
- Tauri：复核启动托盘刷新是否重复，并为每日任务的临时失败增加有界重试。

### P1：完整验证

- 重跑当前源码的 Rust 全量测试、React 构建、Android 全量构建、macOS/iOS 全量测试和依赖审计。
- 使用 Android 手机和平板模拟器完成实际截图和交互检查；结束后关闭模拟器、ADB 和 Gradle daemon。
- 使用 iPhone/iPad 模拟器完成实际截图和交互检查；结束后关闭所有 Simulator。
- macOS 在可解锁桌面环境中检查菜单栏、关闭驻留、今日/明日课程和主窗口交互。
- 使用虚构账号完成凭据保存、留空保留、换账号、清除和重启恢复测试；不得把真实账号写入日志或夹具。

### P2：重新打包与发布

- 选择并添加根目录 `LICENSE`（MIT、Apache-2.0 或 GPL-3.0）；选择前不能声称项目已获得开源授权。
- 将 Apple `CURRENT_PROJECT_VERSION` 和 Android `versionCode` 从 5 更新为下一构建号。
- 在所有测试通过后重新生成 macOS、iOS、Android 和 Windows/Tauri 产物，重新计算 SHA-256。
- 安装并验证最新 macOS Tauri 与原生应用；确认二进制哈希与暂存包一致。
- 完成 Apple Developer 签名/公证、Android 正式签名和 Windows 签名；当前 adhoc、自签名或无签名包仅供测试。
- 提交、推送、创建测试 Release，并核对每个平台附件和 Release Notes。

## 恢复工作顺序

1. 先完成 P1 数据一致性、凭据和日历同步修复。
2. 完成四端全量自动化测试与手机、平板、macOS 运行检查。
3. 确认许可证和下一构建号。
4. 重新打包、安装并验证，不复用本页列出的旧包。
5. 最后创建并验证新的测试 Release。
