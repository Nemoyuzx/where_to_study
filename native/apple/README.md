# Apple 原生客户端

该目录包含共享 SwiftUI 源码，并通过 XcodeGen 生成两个独立原生 target：

- `WhereToStudyMac`：macOS 13+
- `WhereToStudyiOS`：iOS 16+

生成工程并构建：

```bash
./scripts/native-apple-generate.sh
./scripts/native-apple-build.sh
```

账号和密码由 Apple Keychain 保存，普通偏好使用 `UserDefaults`。当前原生预览版已接入移动教务的个人课表和当天两校区空教室请求，课表与空教室数据会分别原子写入应用支持目录并供后续启动离线读取。课程联动、原有教学楼限制、三位教室号、双门教室号、日/周/月/年视图和第 17、18 个实际教学周的“试”标记均复用 `contracts/v1` 的脱敏夹具测试。

空教室数据仅查询当天；应用启动时会在已有凭据且当天缓存缺失时自动刷新，不进行常驻轮询。节假日、当前时间线、菜单栏、通知和系统日历导入仍在后续阶段；需要这些功能时应继续使用 Tauri 客户端。

生成经过测试的 macOS Universal 预览包：

```bash
./scripts/native-macos-package.sh vX.Y.Z-preview.N
```

脚本会构建 arm64 与 x86_64 双架构应用、进行临时代码签名和签名校验，并把 ZIP 与 SHA-256 文件写入 `release-artifacts/`。该包未使用 Developer ID 签名，也未公证。
