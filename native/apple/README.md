# Apple 原生客户端

该目录包含共享 SwiftUI 源码，并通过 XcodeGen 生成原生应用与扩展 target：

- `WhereToStudyMac`：macOS 13+
- `WhereToStudyWidget`：内嵌于 macOS 应用的 WidgetKit 今日课程小组件
- `WhereToStudyiOS`：iOS 16+
- `WhereToStudyiOSWidget`：内嵌于 iOS 应用的 WidgetKit 今日课程小组件

应用主图标不单独维护：`src-tauri/icons/icon.png` 是与 Windows 桌面版一致的唯一源图，运行 `npm run icons:sync` 后会更新本目录的 iOS AppIcon 资源以及 Tauri 各平台图标。macOS 菜单栏图标继续使用系统模板渲染，以便自动适配浅色和深色菜单栏。

生成工程、构建 macOS/iOS，并运行两个平台的原生单元测试：

```bash
./scripts/native-apple-generate.sh
./scripts/native-apple-build.sh
```

`WhereToStudyNative.xcodeproj` 与 `Generated/` 由 XcodeGen 确定性生成，因此不提交到仓库。
Xcode Cloud 会在克隆后自动运行可执行的
`native/apple/ci_scripts/ci_post_clone.sh`：缺少 XcodeGen 时通过构建环境自带的 Homebrew
安装，然后调用同一份 `native-apple-generate.sh` 并校验共享 Scheme。Xcode Cloud 工作流必须继续
指向 `native/apple/WhereToStudyNative.xcodeproj`；不要删除或移动该 post-clone 脚本。

账号和密码由 Apple Keychain 保存，普通偏好使用 `UserDefaults`。当前原生预览版已接入移动教务的个人课表和当天两校区空教室请求，课表与空教室数据会分别原子写入应用支持目录并供后续启动离线读取。课程联动、原有教学楼限制、三位教室号、双门教室号、日/周/月/年视图和第 17、18 个实际教学周的“试”标记均复用 `contracts/v1` 的脱敏夹具测试。

空教室数据仅查询当天；应用启动和重新进入前台时会在已有凭据且当天缓存缺失时自动刷新，不进行常驻轮询。macOS 常驻时使用单次睡眠到下一个 07:00 的调度任务更新当天空教室，不做分钟级检查。教学日历支持本地缓存的法定节假日、当前时间线和日/周/月/年视图，并可在用户授权后把实际上课日期或本机已收藏日程幂等写入系统日历；收藏使用完整本地快照和独立稳定标记，重复导入会更新同一事件且不会误删课程事件。Apple 目标包含统一应用图标与 `PrivacyInfo.xcprivacy`；隐私清单声明 `UserDefaults` 的实际用途，不声明跟踪或开发者数据收集。macOS 还提供菜单栏入口、今日与明日课程、关闭主窗口后常驻及明确退出命令。设置页明确说明这是非官方客户端，并提供完全离线的内置示例模式；示例数据不会读写真实 Keychain、缓存、系统日历、系统通知或 Widget App Group。

iOS 与 macOS 安装包都内嵌真正的 WidgetKit extension，可在系统小组件图库中添加“今日课程”。小组件支持小号、中号和大号样式，展示日期、星期、教学周、当前或下一节状态、时间、节次、教室与教师，大号最多显示 6 门课程。设置页直接复用小组件视图提供三种尺寸的虚构示例预览，并可实时查看课程数量、地点与教师开关效果。主应用在读取、刷新或清除个人课表时写入原子化的小组件快照并刷新 timeline，课程开始与结束时也会切换状态；主应用与扩展使用一致的 App Group entitlement。当天没有课程或尚未获取课表时，小组件统一显示“今日无课”。正式 App Store 构建只使用已签名的 App Group 容器，本地 ad-hoc 预览包另保留应用支持目录兼容副本。

用户可选择每天 07:30 接收当日课程摘要。应用会扫描课表实际最后教学周，并在 iOS 的 64 条待处理本地通知限制内预留一个名额，最多安排 63 个未来有课日；应用启动、课表刷新或重新进入前台时会续排并重新核对系统权限。关闭提醒、切换账号或清除本地数据时会立即按本应用持有的通知标识取消待处理及已送达摘要，不会枚举或移除其他功能的通知。UI 测试模式使用显式 no-op 调度器，不访问系统通知中心。

iOS 模拟器构建会使用 Xcode 的本地临时签名，以便 Keychain 在调试安装中正常工作。`native-apple-build.sh` 会在 macOS 与 iPhone 模拟器上运行原生单元测试及主导航、日历模式、示例模式 UI 测试，并在退出时关闭测试模拟器。账号保存、应用重启后恢复和清除凭据已使用虚构账号做过人工运行验证。无签名真机 archive 可以在没有开发者账号的环境中构建；TestFlight、iOS App Store 与 Mac App Store 使用 `native-apple-app-store.sh` 和有效的 Apple Developer 团队签名。

生成并校验无签名 iOS 真机 archive：

```bash
./scripts/native-ios-package.sh vX.Y.Z
```

脚本会生成仅含 arm64 真机应用的 `xcarchive.zip` 和 SHA-256 文件，并检查应用图标资源、隐私清单、根 GPL 许可证与第三方许可文件。该 archive 供 CI 验证和后续签名使用，不能直接安装到 iPhone。

生成并校验 macOS Universal 预览包：

```bash
./scripts/native-macos-package.sh vX.Y.Z
```

脚本会构建 arm64 与 x86_64 双架构应用、检查二进制架构、根 GPL 许可证与第三方许可文件、进行临时代码签名和签名校验，并把 ZIP 与 SHA-256 文件写入 `release-artifacts/`。脚本不会运行单元测试或启动应用做运行时测试；发布前应另外运行 `native-apple-build.sh` 并完成所需的人工运行检查。该包未使用 Developer ID 签名，也未公证。

## App Store Connect

iOS 与 macOS 主应用共用 `com.nemoyu.wheretostudy.native.macos`，以便在 App Store Connect 中作为一个通用购买记录发布。两个平台的 WidgetKit 扩展共用独立扩展标识符 `com.nemoyu.wheretostudy.native.macos.widget`，但分别使用对应平台的描述文件。

先运行静态预检，再使用开发团队生成、导出或直接上传 iOS/macOS 正式归档：

```bash
./scripts/native-apple-app-store.sh preflight all
APPLE_DEVELOPMENT_TEAM=XXXXXXXXXX \
  ./scripts/native-apple-app-store.sh upload all
```

本地正式构建默认使用手动分发签名和已安装的 App Store 描述文件，校验非 ad-hoc 签名、版本/构建号、`get-task-allow`、macOS App Sandbox、网络/日历 entitlement、双平台主应用与 Widget App Group、隐私清单及三份许可证文件。使用 Xcode 管理的描述文件时，可将 `APPLE_IOS_SIGNING_STYLE` 或 `APPLE_MACOS_SIGNING_STYLE` 设为 `Automatic`；手动签名仍是默认值。macOS 手动导出会自动按团队查找 Installer Distribution 身份，也可通过 `APPLE_INSTALLER_SIGNING_CERTIFICATE` 覆盖；CI 可另外传入 `APPLE_AUTH_KEY_PATH`、`APPLE_AUTH_KEY_ID`、`APPLE_AUTH_KEY_ISSUER_ID`。当前待分发构建为 iOS `0.2.5 (68)` 与 macOS `0.2.5 (68)`；正式提交选择对应平台的最新构建，Apple 制品不作为 GitHub Release 附件。账户侧配置、商店元数据、隐私问卷草案、截图方案、App Review 说明和 GPL 发布确认见 [`AppStore/`](./AppStore/)。
