# Apple 原生客户端

该目录包含共享 SwiftUI 源码，并通过 XcodeGen 生成两个独立原生 target：

- `WhereToStudyMac`：macOS 13+
- `WhereToStudyiOS`：iOS 16+

生成工程、构建 macOS/iOS，并运行两个平台的原生单元测试：

```bash
./scripts/native-apple-generate.sh
./scripts/native-apple-build.sh
```

账号和密码由 Apple Keychain 保存，普通偏好使用 `UserDefaults`。当前原生预览版已接入移动教务的个人课表和当天两校区空教室请求，课表与空教室数据会分别原子写入应用支持目录并供后续启动离线读取。课程联动、原有教学楼限制、三位教室号、双门教室号、日/周/月/年视图和第 17、18 个实际教学周的“试”标记均复用 `contracts/v1` 的脱敏夹具测试。

空教室数据仅查询当天；应用启动和重新进入前台时会在已有凭据且当天缓存缺失时自动刷新，不进行常驻轮询。macOS 常驻时使用单次睡眠到下一个 07:00 的调度任务更新当天空教室，不做分钟级检查。教学日历支持本地缓存的法定节假日、当前时间线和日/周/月/年视图，并可在用户授权后把实际上课日期幂等写入系统日历。Apple 目标包含统一应用图标与 `PrivacyInfo.xcprivacy`；隐私清单声明应用容器文件元数据和 `UserDefaults` 的实际用途，不声明跟踪或开发者数据收集。macOS 还提供菜单栏入口、今日与明日课程、关闭主窗口后常驻及明确退出命令。

用户可选择每天 07:30 接收当日课程摘要。应用会扫描课表实际最后教学周，并在 iOS 的 64 条待处理本地通知限制内预留一个名额，最多安排 63 个未来有课日；应用启动、课表刷新或重新进入前台时会续排并重新核对系统权限。关闭提醒、切换账号或清除本地数据时会立即按本应用持有的通知标识取消待处理及已送达摘要，不会枚举或移除其他功能的通知。UI 测试模式使用显式 no-op 调度器，不访问系统通知中心。

iOS 模拟器构建会使用 Xcode 的本地临时签名，以便 Keychain 在调试安装中正常工作。`native-apple-build.sh` 会在 macOS 与 iPhone 模拟器上运行原生单元测试，并在退出时关闭测试模拟器。账号保存、应用重启后恢复和清除凭据已使用虚构账号做过人工运行验证；这部分交互仍不属于自动化 UI 测试。无签名真机 archive 可以在没有开发者账号的环境中构建，但安装到真机、TestFlight 或 App Store 分发仍需要配置开发团队、签名身份和 provisioning profile。

生成并校验无签名 iOS 真机 archive：

```bash
./scripts/native-ios-package.sh vX.Y.Z-preview.N
```

脚本会生成仅含 arm64 真机应用的 `xcarchive.zip` 和 SHA-256 文件，并检查应用图标资源与隐私清单。该 archive 供 CI 验证和后续签名使用，不能直接安装到 iPhone。

生成并校验 macOS Universal 预览包：

```bash
./scripts/native-macos-package.sh vX.Y.Z-preview.N
```

脚本会构建 arm64 与 x86_64 双架构应用、检查二进制架构、进行临时代码签名和签名校验，并把 ZIP 与 SHA-256 文件写入 `release-artifacts/`。脚本不会运行单元测试或启动应用做运行时测试；发布前应另外运行 `native-apple-build.sh` 并完成所需的人工运行检查。该包未使用 Developer ID 签名，也未公证。
