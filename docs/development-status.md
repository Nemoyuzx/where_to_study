# 稳定版发布检查点（2026-08-21）

## 当前状态

- 分支：`main`
- 当前稳定版：[v0.1.9](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.1.9)
- 应用版本：`0.1.9`
- 当前开发构建号：Apple `CURRENT_PROJECT_VERSION=49`；Android `versionCode=27`
- 教务数据源：只使用现有移动教务 SJD HTTPS 接口，没有切换或静默回退到其他数据源
- 本地安装：仅保留最新 SwiftUI Universal 应用 `/Applications/Where To Study.app`；未再检测到其他 Where To Study 安装副本
- 发布边界：`v0.1.9` 使用稳定版本号；Apple Developer 标识符、App Group、分发证书和双平台 App Store Connect 记录已配置，iOS 与 macOS build 49 已上传并只通过 TestFlight 分发；GitHub Release 不上传任何 iOS、macOS 或 `.sha256` 文件；项目按 GPL-3.0-only 开源

## 本次完成内容

### 共享业务规则

- 固化 `contracts/v1` 的课表、空教室和法定节假日契约及脱敏夹具。
- Rust、Swift、Kotlin 统一教室解析：普通教室保留三位号，`202-203`、`217-218` 等双门号码保持为同一间教室。
- 空教室严格只查询当天，保留原教学楼集合；个人课表页面不会跳转到联动查询；“推荐同一教室”已移除。
- 个人课表查询后按账号范围持久化；课程实际存在的第 17、18 个周次标记为“试”。
- 法定节假日自动读取固定版本 `holiday-calendar@1.3.3` 的中国年度数据，严格校验后缓存，并提供 2026 年离线兜底。

### Tauri / Windows / Linux

- 保留 Tauri 2 + React + Rust 作为 Windows/Linux 客户端，并继续提供迁移期 macOS 构建。
- Linux 使用 Ubuntu 22.04 原生 CI 生成 x86_64 Debian 包和 AppImage；Tauri 图形端凭据保存在 Secret Service，独立 TUI 使用用户私有本地文件，打包脚本验证 Tauri 实际检测到的 GTK/WebKitGTK/托盘依赖，并在 Ubuntu 24.04 上安装生成的 Debian 包。
- 完成空教室、教学日历、设置、教学楼/三位教室号、个人课表联动、系统日历导入和托盘；Windows/Linux 不提供课程小组件。
- 教学日历保留绿白配色，支持日/周/月/年、整点与 14 个节次、当前时间红线、节假日、年视图课程热度及日期日程浮层。
- 托盘提供今日/明日课程；关闭主窗口后保持运行；启动和每天 07:00 获取当天空教室；课程摘要默认关闭，用户显式开启后才在 07:30 发送。
- 为每个账号生成不含账号信息的随机不透明缓存作用域；账号切换、清除或持久化失败时采用失效代次和撤销标记拒绝旧数据。
- 设置与安全凭据提交具备回滚；WebView 不接收密码；已删除 Tauri 课程浮窗及其权限和事件面。
- Tauri 空教室、教学日历和设置页与原生 macOS 保持同样的布局与卡片层级，并补齐课程提醒开关和学期自动检测。
- 独立 CLI/TUI 使用共享 Rust 业务核心和用户私有本地凭据文件；发布名称统一为 `where-to-study-cli` 与 `where-to-study-tui`，不再带 `wts-` 前缀。

### Apple 原生端

- SwiftUI macOS/iOS 已实现空教室、教学日历、设置三页和自适应手机、平板、桌面布局。
- 接入 Keychain、本地账号范围缓存、SJD 课表/空教室、节假日、EventKit 真同步和考试标题。
- macOS 菜单栏显示今日/明日课程；关闭主窗口后应用继续驻留。
- macOS 侧栏品牌标题与系统导航行内容对齐，实机窗口截图确认标题、三项导航和 14 个节次均无重叠。
- 可选 07:30 本地课程摘要会在系统上限内安排最多 63 个未来有课日；关闭提醒、撤销权限、切换账号或清除数据会立即撤销旧通知。
- 发布脚本生成 arm64 + x86_64 通用 macOS 预览包和 arm64 无签名 iOS archive，并校验版本、架构、隐私清单、HTTPS 数据源与本地路径泄漏；App Store 脚本另支持双平台正式分发签名、归档、导出与上传。
- 二进制内容校验只依赖 macOS/Linux runner 自带的 `grep`，不再要求额外安装 `ripgrep`；退役 HTTP 地址按固定字符串实际检查。
- Apple 测试脚本按 UDID 选择 runner 上真实存在的 iPhone 模拟器，不再假设指定机型一定安装在全局最新 iOS runtime。
- iPhone/iPad 教学日历使用独立移动布局：紧凑日期导航、可横向切换的完整周日期、日/周/月/年视图，以及不会遮挡时间轴内容的底部导航。
- 日、周、月支持左右滑动翻页；月视图支持带动画的展开/折叠；年视图日期弹窗可跳转到对应日、周或月，周课程卡在手机上完整显示时间、地点和教师。
- 手机月视图点击日期会进入半折叠状态并在下方显示当日日程；日期格中的事件条只用于展示，不再抢占日期点击。横屏月视图只保留完整月与选中周两种状态，日视图摘要使用与页面一致的卡片表面。
- iPhone 横屏取消竖屏底部导航占位；iPad 和 macOS 收起侧栏的选中图标保持居中正方形，设置与联动查询页面保留正常安全边距。
- Windows/Tauri 当前使用的绿色日历课桌图标成为全平台唯一源图；同步脚本生成 Windows、Tauri macOS、原生 iOS 和 Android 图标，Apple AppIcon 同时移除透明通道以满足上传要求。
- iOS/macOS 设置页提供学期自动检测、手动学期参数与 Widget 展示条数/地点偏好；课程提醒使用系统开关且与同列其他卡片等宽。
- iOS/macOS 今日课程 Widget 增加课程数量和教师信息偏好，并在设置页提供与实际尺寸一致的预览；当天无课时直接显示“今日无课”。

### Android 原生端

- Kotlin Views 已实现手机/平板双布局、三页导航、Keystore 凭据、账号范围缓存、课表、空教室、节假日和 Calendar Provider 真同步。
- 可选 07:30 课程摘要使用持久化 `JobScheduler`，只在 07:30-08:00 有效窗口投递；关闭、撤销权限、切换账号和清除数据均采用持久化失效规则。
- 手机和平板 UI 测试按屏幕宽度验证底部导航或固定侧栏，不依赖反射或生产环境测试入口。
- Release APK/AAB 使用固定维护者密钥签名；打包时同时验证版本号、构建号、APK/AAB 证书和仓库内公开指纹。
- Android 手机教学日历与 iOS 保持相同功能层级，窄屏下重排标题、日期带、时间轴和导航，保留原有绿白配色与深浅色适配。
- 手机、折叠屏和平板分别使用自适应列宽和节次密度；空教室页面的临时查询校区与设置默认校区使用独立状态。
- Android 自适应图标使用与 Windows/Tauri 相同的源图，并通过前景安全区兼容圆形和圆角矩形启动器遮罩，避免日历顶部或课桌底部被裁切。
- Android 手机端按 iOS 对应页面统一卡片与控件边线、36dp 输入框和按钮高度、54dp 节次按钮及紧凑设置密度；教学日历的整点实线、节次虚线、日期条、月视图展开单元格和事件小条均完成浅色与深色复核。
- iOS 与 Android 手机教学日历在模式切换、日期选择、前后翻页、滑动换页、月视图展开/折叠及年视图跳转时提供系统触觉反馈。
- Android 月视图点击日期后进入半折叠状态并展示当日日程，日期格内事件不可独立点击；折叠屏与横屏布局不再保留竖屏底部导航空白，收起侧栏图标按固定正方形居中。
- Android 设置页补齐学期自动检测与 Widget 展示条数/地点偏好，并保持课程提醒为系统开关。
- Android 今日课程 Widget 与 Apple 端共享展示语义，可配置课程数量和教师信息；当天无课时直接显示“今日无课”。

### HarmonyOS 原生端

- “今日课程”服务卡片补齐课程数量、地点和教师展示偏好，并统一无课状态。
- 平板、折叠屏和 PC 宽屏日历、设置布局与现有原生端保持功能层级一致；构建及 69 项 ArkTS 单元测试通过。

## 最终本地验证

| 范围 | 结果 |
| --- | --- |
| React | 55/55 业务规则、主题契约、Windows/Linux 无伪小组件、图标安全区、Linux 发布契约与全端版本一致性测试、`npm run build`、许可证新鲜度检查通过 |
| 许可证交付 | 根许可证为 `GPL-3.0-only`；锁定依赖生成的第三方许可证清单通过新鲜度检查；Tauri、Apple 与 Android 制品中的三份法律文件均与仓库逐字节一致 |
| Rust | 共享核心、Tauri、CLI、TUI 的 `fmt`、`check --locked --all-targets`、`clippy -D warnings` 通过；共享核心 43/43、Tauri 105/105、CLI 13/13、TUI 14/14 测试通过 |
| Rust 依赖审计 | `cargo audit 0.22.2`：0 个漏洞；17 个允许警告来自 Tauri 的 Linux GTK3/旧 proc-macro/unic 传递依赖 |
| macOS SwiftUI | 严格 Swift 6 并发；127/127 XCTest 通过 |
| iOS SwiftUI | 严格 Swift 6 并发；128/128 逻辑测试通过；UI 测试最近一次执行 11 项、iPad 专项跳过 1 项、0 失败 |
| Android Debug | 131/131 JVM 测试、Debug APK 与 AndroidTest APK 构建通过 |
| Android Release | 131/131 JVM 测试、`lintRelease`、固定证书签名 APK/AAB 构建通过 |
| Android UI | Medium Phone、WhereToStudy Fold 与 Pixel Tablet 各 4/4 导航及布局测试通过，共 12/12 |
| 浏览器视觉检查 | 日/周/月真实触摸翻页、年视图日/周/月跳转、校区状态隔离通过；手机、折叠屏、平板、桌面深浅色均无横向溢出或文本裁切，控制台 0 错误 |
| HarmonyOS | HAP 构建、69/69 ArkTS 单元测试和宽屏布局静态契约通过 |
| macOS 归档检查 | SwiftUI Universal `0.1.9 (49)` 的 x86_64/arm64、WidgetKit 扩展、版本、签名、权限与统一应用图标复核通过 |
| App Store Connect | iOS 与 macOS `0.1.9 (49)` 均完成正式归档；两个平台的上传任务均收到 Xcode `Upload succeeded`，未额外打开浏览器复核 |
| CLI/TUI 真实数据 | 本机与 Ubuntu 22.04 x86_64 服务器均使用隔离 HOME、隐藏输入和真实教务路径验证登录、学期自动检测、课表刷新与凭据清除；测试凭据文件已删除 |
| Linux 发布 | arm64 在 Ubuntu 26.04 虚拟机、x86_64 在 Ubuntu 22.04 服务器完成 `.deb`、`.AppImage`、CLI、TUI 构建与运行验证；GitHub Release 不上传校验文件 |
| Tauri 托盘实机 | 点击不闪退；显示今日/明日课程、打开主窗口、空教室、教学日历、设置、刷新与退出；Windows/Linux 无课程小组件入口 |
| 敏感信息扫描 | Gitleaks 扫描完整提交历史及当前全部拟提交文件，0 泄漏 |
| 工程静态检查 | `git diff --check`、`actionlint`、`shellcheck scripts/*.sh`、`bash -n scripts/*.sh` 全部通过 |

Apple 测试结果（2026-08-22 使用 `xcresulttool` 复核）：

- macOS：127/127 通过
- iOS：128/128 项逻辑测试通过；UI 测试最近一次执行 11 项、iPad 专项跳过 1 项、0 失败
- 通知权限超时精确测试：20 轮、40/40 通过

## 0.1.9 稳定版发布制品

`v0.1.9` 的 GitHub Release 提供 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及固定 release key 签名的 Android APK/AAB。iOS 与 macOS 只上传 TestFlight，不进入 GitHub Release；脚本或 CI 生成的 `.sha256` 只供内部校验，同样不上传。

## Build 15 稳定版发布制品

`v0.1.2` 通过标签工作流生成 Windows x64 NSIS、Tauri macOS arm64、SwiftUI macOS Universal、无签名 iOS archive，以及固定 release key 签名的 Android APK/AAB。每个二进制制品均带相邻的 LF 行尾 SHA-256 校验文件。

## Build 12 发布制品

以下文件均由 `v0.1.1-alpha.12` 标签的 GitHub Actions 生成并发布。Release 下载件与 Actions artifact 已逐字节比对，相邻 `.sha256` 已逐项回读验证；所有平台包内的 GPL、第三方许可证与第三方声明均与仓库版本一致。

| 文件 | SHA-256 | 签名状态 |
| --- | --- | --- |
| `Where-To-Study-v0.1.1-alpha.12-windows-x64-setup.exe` | `3c95daa9babb647669b76b6f4e28939d66e7fd2aa3a69f44ffcb99737213c125` | Tauri Windows x64 NSIS，无 Authenticode |
| `Where-To-Study-v0.1.1-alpha.12-macos-arm64.zip` | `76685726d95abe562054d03e38dd549bd6f70164307c2f83baa257e9b94154ff` | Tauri macOS arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.12-native-macos-universal.zip` | `6715c89ee1a8d25b758aac97f50b0528af083e7829af78d780a9a791f0c81ee7` | SwiftUI macOS x86_64 + arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.12-native-ios-unsigned.xcarchive.zip` | `052ffe29df2971829e8896bc85010ed8986e04283ba604b4d3dbb44857eed0dd` | iOS arm64 archive，无签名，不可直接安装 |
| `Where-To-Study-v0.1.1-alpha.12-native-android-universal.apk` | `6ab3bbcafe1750efe9650de80c61df005564cc7df989f77c799e0850d5b79c2b` | Android APK，固定 release key |
| `Where-To-Study-v0.1.1-alpha.12-native-android.aab` | `eb9f26b9941918558b0bcd8ab2e48232f0a485bf7a5cf19a63ca8fd9c50d8889` | Android AAB，固定 release key |

## Build 11 发布制品

以下文件均由 `v0.1.1-alpha.11` 标签的 GitHub Actions 生成并发布。Release 下载件与 Actions artifact 已逐字节比对，相邻 `.sha256` 已逐项回读验证。

| 文件 | SHA-256 | 签名状态 |
| --- | --- | --- |
| `Where-To-Study-v0.1.1-alpha.11-windows-x64-setup.exe` | `81fa18f46f13c991c7bcef365a90347614524047c7bffe6c29071826a219bd75` | Tauri Windows x64 NSIS，无 Authenticode |
| `Where-To-Study-v0.1.1-alpha.11-macos-arm64.zip` | `87ebffaf294ff83551789f520e17474bbf37d3ef4285012409d2199b5de02163` | Tauri macOS arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.11-native-macos-universal.zip` | `0c7df6c56bc8abcb42cd1306685e2ddfd82b766a39beed7c595b7efa04fb473d` | SwiftUI macOS x86_64 + arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.11-native-ios-unsigned.xcarchive.zip` | `52344702b7edc146a4556948d2f07f6af680d1814faf136cb49f0c322405203b` | iOS arm64 archive，无签名，不可直接安装 |
| `Where-To-Study-v0.1.1-alpha.11-native-android-universal.apk` | `fac6d84d6b8e7da9ed0aecbe401703d384354106dcc6509a1ee1288fd2eed319` | Android APK，固定 release key |
| `Where-To-Study-v0.1.1-alpha.11-native-android.aab` | `fa14e8e71b744bf3a370e56f6d65e701930bd1bf19fd6c5e7a7b0a4e7d645c56` | Android AAB，固定 release key |

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
- 手动门禁确认固定 keystore、Release 测试、Lint 和 Gradle 签名全部通过；APK 证书读取现兼容不同 `apksigner` 版本的输出流与前缀。
- 原生工作流把手动触发定义为独立 Android 签名门禁，可在创建新标签前单独验证固定签名链路。

## Alpha 9 Android 签名门禁

候选提交 `58d1a3f` 的手动原生工作流 [31306843399](https://github.com/Nemoyuzx/where_to_study/actions/runs/31306843399) 已通过。该门禁只运行 Android signed release job，Apple 和 Android Debug job 按设计跳过。

- 81 项 Release JVM 测试、Lint、APK/AAB 构建、固定 keystore 预检、APK/AAB 二次证书校验和 Actions artifact 上传全部成功。
- 下载后的 CI APK/AAB 已再次通过相邻 SHA-256、`versionName=0.1.1`、`versionCode=9` 和仓库固定公开证书复核。
- 工作流不再引用的旧 Android signing secrets 已删除，只保留验证通过的 `ANDROID_RELEASE_*` 命名空间。

## Alpha 9 CI 回归记录

`v0.1.1-alpha.9` 保留为不可变的失败候选标签，没有创建 GitHub Release。Windows、Tauri macOS、安全检查和 Android signed release 全部通过；Apple job 的 macOS 构建与测试、59 项 iOS 单元测试和 1 项导航 UI 测试通过，但后台通知清理测试在负载较高的 runner 上超过原 2 秒等待上限。

- 失败测试仍通过了“取消调用在 0.25 秒内返回”的非阻塞断言，失败只发生在等待后台清理完成的测试上限。
- 异步完成上限调整为 10 秒，产品代码和非阻塞要求不变；build 10 将先做重复压力测试和完整 Apple 测试再创建标签。

## Alpha 10 Android 签名门禁

候选提交 `4afc1a4` 的手动原生工作流 [31308452212](https://github.com/Nemoyuzx/where_to_study/actions/runs/31308452212) 已通过。该门禁只运行 Android signed release job，Apple 和 Android Debug job 按设计跳过。

- 81 项 Release JVM 测试、Lint、APK/AAB 构建、固定 keystore 预检、APK/AAB 二次证书校验和 Actions artifact 上传全部成功。
- 下载后的 CI APK/AAB 已再次通过相邻 SHA-256、`versionName=0.1.1`、`versionCode=10` 和仓库固定公开证书复核。

## Alpha 10 CI 回归记录

`v0.1.1-alpha.10` 的 Windows、Tauri macOS、Apple/Android 原生和安全工作流全部通过，但下载后的 Windows `.sha256` 使用 CRLF 行尾。GNU/macOS `shasum -c` 会把末尾的 `\r` 解析为文件名一部分，因此没有创建 GitHub Release，标签保持不可变。

- Windows 工作流改为通过 .NET 文件 API 显式写入单个 LF，并在上传前逐字节拒绝 CR 和非预期内容。
- build 11 将先通过手动 Windows 制品门禁和 Android 签名门禁，再创建 `v0.1.1-alpha.11` 标签。

## Alpha 11 发布门禁

候选提交 `83bab78` 的手动 [Windows 工作流 31450555455](https://github.com/Nemoyuzx/where_to_study/actions/runs/31450555455) 和 [Android 签名工作流 31450557116](https://github.com/Nemoyuzx/where_to_study/actions/runs/31450557116) 已通过。

- Windows 干净 runner 完成 React 构建、Rust 测试、严格 Clippy、x86_64 Tauri/NSIS 和 artifact 上传；下载后的 sidecar 确认只有 LF，且本机 `shasum -c` 直接通过。
- Android 完成 81 项 Release JVM 测试、Lint、APK/AAB 构建和固定证书校验；下载后再次确认 `versionName=0.1.1`、`versionCode=11`、相邻 SHA-256 与 APK/AAB 固定证书均正确。

## Alpha 11 测试版发布

标签 `v0.1.1-alpha.11` 指向提交 `cf8078c`。标签触发的 [Windows 31451410812](https://github.com/Nemoyuzx/where_to_study/actions/runs/31451410812)、[Tauri macOS 31451410817](https://github.com/Nemoyuzx/where_to_study/actions/runs/31451410817)、[原生端 31451410813](https://github.com/Nemoyuzx/where_to_study/actions/runs/31451410813) 和 [安全检查 31451410849](https://github.com/Nemoyuzx/where_to_study/actions/runs/31451410849) 全部通过。

- GitHub prerelease 已发布 6 个二进制制品和 6 个相邻 SHA-256 sidecar，并明确 Windows/macOS/iOS 的签名限制。
- 从 Release 重新下载的 12 个附件与 Actions artifact 逐字节一致；版本、构建号、架构、签名、固定 Android 证书、隐私清单和 HTTPS 数据源均通过复核。

## Alpha 12 测试版发布

标签 `v0.1.1-alpha.12` 指向提交 `17798a8`。标签触发的 [Windows 31461935957](https://github.com/Nemoyuzx/where_to_study/actions/runs/31461935957)、[Tauri macOS 31461936039](https://github.com/Nemoyuzx/where_to_study/actions/runs/31461936039)、[原生端 31461935956](https://github.com/Nemoyuzx/where_to_study/actions/runs/31461935956) 和 [安全检查 31461935959](https://github.com/Nemoyuzx/where_to_study/actions/runs/31461935959) 全部通过。

- GitHub prerelease 已发布 6 个二进制制品和 6 个相邻 SHA-256 sidecar；从 Release 重新下载的 12 个附件与 Actions artifact 逐字节一致。
- Windows 干净 runner 实际静默安装 NSIS 后逐字节检查三份法律文件；macOS、iOS 与 Android 包也完成版本、构建号、架构、签名边界和法律文件复核。
- GPL-3.0-only 元数据、锁定依赖许可证清单、npm/Rust 依赖审计和完整 Git 历史密钥扫描均通过标签流水线。

## 后续发布步骤

1. 等待 iOS build 43 与 macOS build 41 处理完成，将对应构建加入内部 TestFlight 群组并完成真机安装与核心流程验证。
2. 使用 `native/apple/AppStore/` 中的元数据、隐私问卷草案、截图方案和审核备注补齐正式提交信息。
3. 由账号持有人确认年龄分级、App Privacy、内容权利、欧盟 DSA、价格与地区等声明，再补齐截图和审核联系人并选择构建提交审核。
4. GitHub 公开下载版如需消除 macOS Gatekeeper 提示，仍需另行完成 Developer ID 签名与公证；Windows 可信签名链路也尚未闭环。

Android 维护者密钥只通过本地忽略文件和 GitHub Actions secrets 提供，不进入仓库或发布日志。
