# 发布候选检查点（2026-08-09）

## 当前状态

- 分支：`codex/native-platform-foundation`
- 目标测试版：`v0.1.1-alpha.9`
- 应用版本：`0.1.1`
- 原生构建号：Apple `CURRENT_PROJECT_VERSION=9`；Android `versionCode=9`
- 教务数据源：只使用现有移动教务 SJD HTTPS 接口，没有切换或静默回退到其他数据源
- 本地安装：Tauri 主应用安装在 `/Applications/Where To Study.app`；SwiftUI 预览安装在 `/Applications/Where To Study Native Preview.app`
- 发布边界：当前是测试版候选，不是已签名、公证的生产版本；仓库仍等待维护者选择根许可证

## 本次完成内容

### 共享业务规则

- 固化 `contracts/v1` 的课表、空教室和法定节假日契约及脱敏夹具。
- Rust、Swift、Kotlin 统一教室解析：普通教室保留三位号，`202-203`、`217-218` 等双门号码保持为同一间教室。
- 空教室严格只查询当天，保留原教学楼集合；个人课表页面不会跳转到联动查询；“推荐同一教室”已移除。
- 个人课表查询后按账号范围持久化；课程实际存在的第 17、18 个周次标记为“试”。
- 法定节假日自动读取固定版本 `holiday-calendar@1.3.3` 的中国年度数据，严格校验后缓存，并提供 2026 年离线兜底。

### Tauri / Windows

- 保留 Tauri 2 + React + Rust 作为 Windows 客户端，并继续提供迁移期 macOS 构建。
- 完成空教室、教学日历、设置、教学楼/三位教室号、个人课表联动、系统日历导入、托盘和课程小组件。
- 教学日历保留绿白配色，支持日/周/月/年、整点与 14 个节次、当前时间红线、节假日、年视图课程热度及日期日程浮层。
- 托盘提供今日/明日课程；关闭主窗口后保持运行；启动和每天 07:00 获取当天空教室，07:30 发送课程摘要。
- 为每个账号生成不含账号信息的随机不透明缓存作用域；账号切换、清除或持久化失败时采用失效代次和撤销标记拒绝旧数据。
- 设置与安全凭据提交具备回滚；WebView 不接收密码；课程小组件权限缩减为仅监听所需事件。

### Apple 原生端

- SwiftUI macOS/iOS 已实现空教室、教学日历、设置三页和自适应手机、平板、桌面布局。
- 接入 Keychain、本地账号范围缓存、SJD 课表/空教室、节假日、EventKit 真同步和考试标题。
- macOS 菜单栏显示今日/明日课程；关闭主窗口后应用继续驻留。
- macOS 侧栏品牌标题与系统导航行内容对齐，实机窗口截图确认标题、三项导航和 14 个节次均无重叠。
- 可选 07:30 本地课程摘要会在系统上限内安排最多 63 个未来有课日；关闭提醒、撤销权限、切换账号或清除数据会立即撤销旧通知。
- 发布脚本生成 arm64 + x86_64 通用 macOS 预览包和 arm64 无签名 iOS archive，并校验版本、架构、隐私清单、HTTPS 数据源与本地路径泄漏。
- 二进制内容校验只依赖 macOS/Linux runner 自带的 `grep`，不再要求额外安装 `ripgrep`；退役 HTTP 地址按固定字符串实际检查。
- Apple 测试脚本按 UDID 选择 runner 上真实存在的 iPhone 模拟器，不再假设指定机型一定安装在全局最新 iOS runtime。

### Android 原生端

- Kotlin Views 已实现手机/平板双布局、三页导航、Keystore 凭据、账号范围缓存、课表、空教室、节假日和 Calendar Provider 真同步。
- 可选 07:30 课程摘要使用持久化 `JobScheduler`，只在 07:30-08:00 有效窗口投递；关闭、撤销权限、切换账号和清除数据均采用持久化失效规则。
- 手机和平板 UI 测试按屏幕宽度验证底部导航或固定侧栏，不依赖反射或生产环境测试入口。
- Release APK/AAB 使用固定维护者密钥签名；打包时同时验证版本号、构建号、APK/AAB 证书和仓库内公开指纹。

## 最终本地验证

| 范围 | 结果 |
| --- | --- |
| React | `npm ci`、`npm run build` 通过；完整 `npm audit --audit-level=high` 为 0 漏洞 |
| Rust | `fmt`、`check --locked --all-targets`、`clippy -D warnings` 通过；81/81 测试通过 |
| Rust 依赖审计 | `cargo audit 0.22.2`：0 个漏洞；17 个允许警告来自 Tauri 的 Linux GTK3/旧 proc-macro/unic 传递依赖 |
| macOS SwiftUI | 严格 Swift 6 并发、警告视为错误；60/60 XCTest 通过 |
| iOS SwiftUI | 严格 Swift 6 并发、警告视为错误；60 项单元测试 + 1 项真实导航 UI 测试，共 61/61 通过 |
| Android Debug | 81/81 JVM 测试、`lintDebug`、Debug APK 构建通过 |
| Android Release | 81/81 JVM 测试、`lintRelease`、签名 APK/AAB 构建通过 |
| Android UI | Medium Phone 与 Pixel Tablet 各 1/1 导航冒烟测试通过 |
| 浏览器视觉检查 | 桌面与手机空教室/设置/日历通过；节假日标题、14 节次与整点、年视图浮层、红色时间线、移动端三列摘要均无重叠；控制台 0 错误 |
| macOS 安装检查 | Tauri arm64 与 SwiftUI universal 安装包版本/架构/adhoc 签名通过；两端关闭窗口后均保持运行 |
| Tauri 托盘实机 | 点击不闪退；显示今日/明日课程、打开主窗口、小组件、空教室、教学日历、设置、刷新与退出 |
| 敏感信息扫描 | Gitleaks 扫描完整提交历史及当前全部拟提交文件，0 泄漏 |
| 工程静态检查 | `git diff --check`、`actionlint`、`shellcheck scripts/*.sh`、`bash -n scripts/*.sh` 全部通过 |

Apple 测试报告：

- macOS：`native/apple/DerivedData/tests/Logs/Test/Test-WhereToStudyMac-2026.08.09_16-46-01-+0800.xcresult`
- iOS：`native/apple/DerivedData/iOS/Logs/Test/Test-WhereToStudyiOS-2026.08.09_16-46-07-+0800.xcresult`

## Build 9 本地产物

所有文件位于被 Git 忽略的 `release-artifacts/`，相邻 `.sha256` 已逐项回读验证。

| 文件 | SHA-256 | 签名状态 |
| --- | --- | --- |
| `Where-To-Study-v0.1.1-alpha.9-macos-arm64.zip` | `9e00e157ed19a53de838608bd7c6e5ec2f53252d451148565c2b460a687b0ae3` | Tauri macOS arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.9-native-macos-universal.zip` | `d39035f63c60eaed5710c0955ead2382e95ad5278eff736528e2b4175e8b1bb4` | SwiftUI macOS x86_64 + arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.9-native-ios-unsigned.xcarchive.zip` | `5ddefe39773956e68b34de498210a371b540eaa73e632a586bcff10978a8834a` | iOS arm64 archive，无签名，不可直接安装 |
| `Where-To-Study-v0.1.1-alpha.9-native-android-universal.apk` | `01f87ec07a02769598a911cdc752de2706668edecde4a1675532187557633329` | Android APK，固定 release key |
| `Where-To-Study-v0.1.1-alpha.9-native-android.aab` | `f304360baab38f503ee3dcac6d0bad2f50233274c5420f18f3c4018314a94280` | Android AAB，固定 release key |

## Alpha 6 CI 回归记录

`v0.1.1-alpha.6` 保留为不可变的失败候选标签，没有创建 GitHub Release。该标签在干净 runner 上发现并推动修复了以下发布环境问题：

- Xcode 26.6 无法在时限内推断日历课程块的深层 SwiftUI 表达式；已拆为显式辅助视图，并在本地严格 Swift 6 构建和测试中通过。
- GitHub Actions 中的 Android signing secret 与仓库固定证书不一致；已从本地忽略的维护者密钥安全重置 secrets，未输出密钥内容。
- Tauri/Apple 打包脚本依赖 runner 未预装的 `rg`；已改为系统工具并补充可移植性正反向测试。

## Alpha 7 CI 回归记录

`v0.1.1-alpha.7` 同样保留为不可变的失败候选标签，没有创建 GitHub Release。Windows、Tauri macOS 和安全检查均通过；原生工作流发现两个 runner 差异：

- `iPhone 16e` 在 runner 上只存在于 iOS 26.2，而 `OS=latest` 指向 26.5；脚本现从可用设备列表选择真实 UDID，并已在本机跑完 60 项 iOS 单元测试和 1 项导航 UI 测试。
- Android Release 构建、81 项 JVM 测试和 Lint 均通过，但 Actions secret 中的证书未匹配固定指纹；四个 secret 已从本地忽略且逐字节验证的维护者密钥重新安全写入，未输出密钥内容。

## Alpha 8 CI 回归记录

`v0.1.1-alpha.8` 保留为不可变的失败候选标签，没有创建 GitHub Release。Windows、Tauri macOS、安全检查以及 Apple 原生构建和测试全部通过，证明动态模拟器 UDID 修复有效；Android Release 再次在 APK 证书比对处失败。

- Android signing 改用全新的 `ANDROID_RELEASE_*` secret 名称，避免继续依赖旧 secret 的不可观测状态。
- 打包脚本会在 Gradle 前直接验证解码后的 keystore 证书，并分别报告 keystore、APK 和 AAB 的证书读取或不匹配错误。
- 原生工作流把手动触发定义为独立 Android 签名门禁，可在创建新标签前单独验证固定签名链路。

## 发布前剩余步骤

1. 先通过原生工作流的手动 Android 签名门禁，再创建并推送 `v0.1.1-alpha.9` 标签。
2. 等待标签触发的 Windows、Tauri macOS、Apple/Android 原生和安全工作流全部通过。
3. 下载 CI 产物并复核相邻 SHA-256、版本和签名，再创建 GitHub prerelease。
4. Release Notes 必须明确 Windows 未做 Authenticode、两套 macOS 未做 Developer ID 公证、iOS archive 未签名且不可直接安装。
5. 维护者选择 MIT、Apache-2.0 或 GPL-3.0 后再添加根 `LICENSE`；在此之前只能称为公开测试代码，不能声称已完成开源授权。

正式生产发布仍需要 Apple Developer ID 签名与公证、可分发的 iOS 签名以及 Windows Authenticode。Android 维护者密钥只通过本地忽略文件和 GitHub Actions secrets 提供，不进入仓库或发布日志。
