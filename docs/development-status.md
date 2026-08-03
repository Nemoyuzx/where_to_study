# 开发冻结检查点（2026-08-04）

## 当前状态

- 分支：`codex/native-platform-foundation`
- 上一个远端检查点：`db4297b`（`feat: checkpoint native platform integrations`）
- 数据源：继续使用现有移动教务 SJD 接口，没有切换数据源
- 版本：应用版本 `0.1.1`；Apple `CURRENT_PROJECT_VERSION=5`；Android `versionCode=5`
- 发布状态：开发中检查点，不是可发布版本，未创建新的 GitHub Release
- 二进制暂存：`release-artifacts/` 仅保存在本机并由 `.gitignore` 排除
- 停止状态：所有子任务、构建进程、开发服务器、Android 模拟器和 iOS Simulator 已停止

本检查点按用户要求冻结。源码中包含已完成且通过验证的改动，也包含已识别但尚未修复或尚未完成最终验证的改动。恢复开发时必须先处理下方 P0/P1 项，不能直接打包发布。

## 已完成功能

### 共享契约与业务规则

- 固化 `contracts/v1` 课表、空教室和节假日结构及脱敏夹具。
- Rust、Swift、Kotlin 统一教室名称解析：教学楼与教室号分开，普通教室保留三位号，`202-203`、`217-218` 等双门号码保持为同一间教室。
- 空教室只查询当天，使用原有教学楼集合；已移除“推荐同一教室”。
- 个人课表持久化到本地；课表实际存在第 17、18 周时将对应课程标记为“试”。
- 保留原有浅色、绿色品牌样式，日/周/月/年仅复用系统日历的功能和交互模式。

### Apple 原生端

- SwiftUI macOS/iOS 三个一级页面：空教室、教学日历、设置。
- 接入个人课表、当天空教室、法定节假日、本地缓存和 Keychain。
- 日/周/月/年日历、课程节次与整点刻度、今日/选中日期状态、年视图课程热度、日期日程浮层和当前时间线。
- EventKit 课程导入、考试标题、五分钟前提醒和应用自有事件标记。
- macOS 菜单栏图标与今日/明日课程内容；关闭主窗口后保持菜单栏运行。
- 启动时按需刷新当天空教室；macOS 每日 07:00 低频刷新任务。
- 密码不回填到界面；同账号留空保留 Keychain 密码，换账号要求新密码。
- 账号切换时使课表、空教室和日历导入操作代次失效，并清理账号范围内的本地缓存。
- 原生图标、隐私清单、通用 macOS 构建和无签名 iOS Archive 脚本。

### Android 原生端

- Kotlin + Android Views 手机/平板布局及三个一级页面。
- 接入个人课表、当天空教室、法定节假日、Keystore 凭据和 `AtomicFile` 缓存。
- 日/周/月/年日历、节次与整点刻度、课程热度、日期浮层、法定节假日和当前时间线。
- Android Calendar Provider 学期范围真同步：更新已有事件、删除当前学期内失效/重复事件，并保留其他应用事件。
- 日历导入增加进程级互斥、Activity 重建后的结果恢复和权限拒绝恢复。
- 本地数据代次与单飞协调已覆盖课表、空教室和节假日，旧请求不能在清除后写回缓存。
- 密码不回填；同账号留空保留 Keystore 密码，换账号必须输入新密码；切换/清空账号会清理账号范围缓存。
- 启动刷新与 `JobScheduler` 每日 07:00 刷新；临时错误最多重试两次，永久错误不重试。
- APK/AAB 本地签名与打包脚本。

### Tauri / Windows 基线

- 保留 Tauri + React 作为 Windows 客户端，并保持现有 macOS 迁移期构建能力。
- 只使用当前 SJD 请求路径，移除旧接口/XLS 回退和旧 macOS User-Agent 分支。
- 密码不返回 WebView；系统安全存储、旧明文设置迁移及敏感结构内存清理已接入。
- 托盘、今日/明日课程、通知、日历导入、节假日和本地数据清除命令已接入。
- 托盘重复刷新已移除；桌面每日任务支持临时错误有界重试。
- `LOCAL_DATA` 已增加代次与 I/O 锁，课表、教室、设置、托盘和节假日写入具备基础旧请求保护。
- 后端凭据规则已覆盖同账号留空保留、换账号必须输入新密码、空账号清除凭据；React 提示状态已同步。

### 工程与安全

- GitHub Actions 第三方 Action 固定到提交 SHA，并增加 Dependabot 配置。
- 增加隐私、安全、贡献、行为准则、Issue 与 PR 模板。
- 忽略环境文件、证书、签名密钥、构建目录和发布二进制。
- 测试只使用虚构账号和脱敏夹具；真实账号和密码不得进入源码、测试、日志或 Release。

## 最新验证记录

| 范围 | 结果 | 最后记录 |
| --- | --- | --- |
| Android Debug JVM 测试 | 通过 | 63/63，0 失败；包含凭据切换、代次、重试、日历同步和 Activity 重建用例 |
| Android Lint | 通过 | `lintDebug`：`No issues found` |
| Android Debug APK | 通过 | `assembleDebug` 成功；尚未按下一构建号重新发布打包 |
| Android 运行检查 | 通过但需最终复测 | Pixel Tablet 与 Medium Phone 已检查空教室及日/周/月/年视图；模拟器已清理并关闭 |
| Rust 格式检查 | 通过 | `cargo fmt --all -- --check` |
| Rust Clippy | 通过 | `cargo clippy --lib --all-targets -- -D warnings` |
| Rust 测试 | 通过 | 55/55，0 失败 |
| React 生产构建 | 通过 | `npm run build` |
| iOS Simulator XCTest | 通过 | 39/39，0 失败；2026-08-04 00:05（Asia/Shanghai） |
| macOS XCTest | **未通过** | 最新 38/40；2026-08-04 00:25，两项 CalendarImport 测试失败 |
| npm 生产依赖审计 | 通过（早于最后改动） | 最近一次 `npm audit --omit=dev --audit-level=high` 为 0 个漏洞，最终发布前需重跑 |
| 敏感信息模式扫描 | 通过 | 2026-08-04；私钥、常见 Token/API Key、常见个人邮箱模式无命中；密码字面量均为测试夹具或环境变量名 |
| 工作树空白错误检查 | 通过 | `git diff --check` 无输出 |

最新 macOS 测试失败项：

- `CalendarImportTests/testExpectedMarkerOutsideTheTermIsUpdatedInsteadOfInsertedAgain()`
- `CalendarImportTests/testSyncPlanRemovesStaleAndDuplicateEventsButKeepsOutsideAndUnownedEvents()`

## 本地暂存包

以下文件保留在被忽略的 `release-artifacts/`。2026-08-04 已重新执行全部相邻 SHA-256 校验，五项均为 `OK`。

| 文件 | SHA-256 | 状态 |
| --- | --- | --- |
| `Where-To-Study-v0.1.1-alpha.6-macos-arm64.zip` | `4c48a3c9d08f714064552904de295a3d374373a1011606708039cca9e6ac2fa7` | Tauri macOS arm64，adhoc 签名 |
| `Where-To-Study-v0.1.1-alpha.6-native-macos-universal.zip` | `78ee162cf95a7363d7f25aebef1464605fd88113cb2a8b26d1e9ccfc1c3b6eca` | 原生 macOS x86_64 + arm64，adhoc 签名 |
| `Where-To-Study-v0.1.1-alpha.6-native-ios-unsigned.xcarchive.zip` | `a4e1106db7c724999d3b2ed2ee8c84baafac88fd5ddc6b52b78c0f0e296c582a` | iOS 无签名 Archive |
| `Where-To-Study-v0.1.1-alpha.6-native-android-universal.apk` | `ac520349e2027bdadfee865f2b97880e61fd5baba03f38d70c221c0169f2324e` | Android universal APK，v2 自签名 |
| `Where-To-Study-v0.1.1-alpha.6-native-android.aab` | `782d70db12bab276b803c354618e1f0bc641fc7b8b197d0d7544d13a71a972d3` | Android AAB，自签名 |

这些包的内部版本均为 `0.1.1` / build `5`，生成时间早于本检查点最后一批源码修改。它们只用于暂存已完成的打包流程，**不能直接发布，也不能代表本次冻结源码**。

## 待完成任务

### P0：恢复后首先处理

- Apple：修正上列两个 EventKit 同步规划测试失败，明确“预期事件被移出学期范围”与“历史范围事件”的更新/保留语义。
- Apple：将按年份进行中的节假日加载由集合改为带令牌的状态，避免清除数据后的旧任务 `defer` 删除新任务标记并造成重复请求。
- Tauri：账号 A 切换到账号 B 或清空账号时，在同一次 `LOCAL_DATA` 代次内原子清除课表和空教室缓存。
- Tauri：账号切换必须使账号 A 的在途请求失效；同账号仅改密码必须保留缓存。
- Tauri：补齐 A→B、A→空、同账号改密和在途请求失效的单元测试。

### P1：发布前完整验证

- 修复 P0 后重跑 Rust `fmt`、`clippy`、全量测试、React 构建和 npm 依赖审计。
- 重跑 Android 63 项以上 JVM 测试、`lintDebug`、Debug/Release 组装，并检查账号切换和日历导入生命周期。
- 重跑 macOS 与 iOS 全量 XCTest，要求 0 失败；保留 `.xcresult` 摘要。
- 使用 Android 手机和平板完成最终截图和交互检查；结束后关闭模拟器、ADB 和 Gradle daemon。
- 使用 iPhone/iPad 完成最终截图和交互检查；结束后关闭全部 Simulator。
- 在 macOS 实机检查菜单栏点击不闪退、顶部可点击区域、动态高度、今日/明日课程、关闭主窗口后驻留和退出。
- 在 Windows GitHub Actions 或 Windows 实机完成 Tauri 构建及托盘行为检查。
- 重新执行敏感信息扫描，确认无真实账号、密码、Token、私钥或签名材料进入提交和产物。

### P2：版本、打包、安装与发布

- 由维护者选择并添加根目录 `LICENSE`：MIT、Apache-2.0 或 GPL-3.0；选择前不能声称仓库已获得开源授权。
- 将 Apple `CURRENT_PROJECT_VERSION` 和 Android `versionCode` 从 5 更新为下一构建号。
- 全部测试通过后重新生成 Tauri macOS/Windows、原生 macOS、iOS Archive、Android APK/AAB，并重新计算 SHA-256。
- 安装并验证最新 Tauri macOS 与原生 macOS 应用，确认安装包、安装后二进制和校验和对应。
- 完成 Apple Developer 签名/公证、Android 正式签名和 Windows 签名；当前 adhoc、自签名或无签名包只适合本地测试。
- 提交最终发布改动、推送、创建测试 Release，逐项下载并核对附件与 Release Notes。

## 恢复顺序

1. 先修复 Apple 两项失败测试和节假日加载竞态。
2. 完成 Tauri 账号切换的原子清理、在途请求失效和对应测试。
3. 完成四端自动化测试、安全扫描和手机、平板、macOS、Windows 运行检查。
4. 确认开源许可证和下一构建号。
5. 重新打包、安装、校验并发布；不得复用本页列出的旧包。
