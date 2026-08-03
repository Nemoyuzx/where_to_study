# Where To Study

北邮空教室与个人课表联动查询应用。当前可用客户端基于 Tauri 2、React 和
Rust；仓库同时在按平台逐步迁移到 SwiftUI 和 Kotlin 原生客户端。

- 获取北邮个人课表并解析 XLS 课表文件。
- 获取当天空教室信息时会一次拉取西土城与沙河两个校区，并保存到本地缓存。
- 支持西土城与沙河校区查询；沙河教学楼按 `综合教学楼N`、`综合教学楼S`、`教学实验综合楼N`、`教学实验综合楼S`、`智慧教学楼` 识别。
- 按个人空闲节次、教学楼、最少座位数筛选空教室。
- macOS 桌面端在应用运行时每天 7:30 发送今日课程系统通知，并提供课程桌面小组件。
- 支持课表本地缓存、教学日历、法定节假日和 Apple 日历导入。

贡献前请先阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。平台迁移范围和验收顺序见
[docs/platform-roadmap.md](./docs/platform-roadmap.md)。

## 平台状态

| 平台 | 当前可用版本 | 原生迁移状态 |
| --- | --- | --- |
| macOS | Tauri 2，功能完整 | SwiftUI 原生预览已支持个人课表、教学日历和当天空教室联动查询 |
| Android | Tauri 2，功能完整 | Kotlin Views 原生预览已支持个人课表、教学日历和当天空教室联动查询 |
| Windows | Tauri 2，持续维护 | 保留 Tauri，并进行安全和资源占用优化 |
| iOS | 暂不提供签名安装包 | SwiftUI 工程可构建，已接入个人课表、教学日历和当天空教室联动查询 |

## 下载

GitHub Releases 会按阶段提供 Tauri 安装包和明确标注的原生预览包。原生 macOS 包同时支持 Apple Silicon 与 Intel，但目前没有 Developer ID 公证签名，首次启动需要在 Finder 中右键选择“打开”；原生 Android APK 使用项目维护者的本地 release key 签名。原生预览现已完成个人课表、日历查看和当天空教室联动查询，平台通知、托盘、节假日与系统日历导入等功能仍应使用功能完整的 Tauri 客户端。iOS 因缺少公开分发签名暂不提供安装包。

## macOS 通知与小组件

macOS 桌面端会在应用运行或驻留托盘时，于每天 7:30 根据本地保存的课表发送今日课程通知。首次触发时系统可能会请求通知权限。

课程桌面小组件可以从托盘菜单的“显示课程小组件”打开，也可以在应用“设置”页点击“打开课程小组件”。小组件显示今日课程和下一节待上课程，并会在课表刷新后自动更新。

## 数据来源与数据安全

应用使用北邮课表和空教室相关接口，因此需要教务系统账号和密码。账号与密码不会写入
普通设置文件：Windows 使用 Credential Manager，macOS/iOS 使用 Keychain，Android
使用 Android Keystore。旧版 `settings.json` 中的凭据会在首次启动时迁移并从普通设置
中删除。课程和空教室缓存不包含密码、token 或 cookie。完整基线见
[docs/security.md](./docs/security.md)。

## 开发与运行

```bash
npm install
npm run tauri dev
```

### 构建桌面端

```bash
npm run tauri:build
```

在 Windows 机器上构建 64 位 Windows 包：

```bash
npm run tauri:build:windows
```

Windows 构建建议在 Windows 机器或 Windows CI runner 上执行，需要安装 Rust MSVC toolchain、Microsoft C++ Build Tools 和 WebView2 Runtime。

### 原生客户端基线

生成并验证 macOS/iOS SwiftUI 工程：

```bash
./scripts/native-apple-build.sh
```

验证 Android Kotlin 工程：

```bash
./scripts/native-android-build.sh
```

这两个目录用于逐步迁移。当前原生预览包已完成只读个人课表和当天空教室阶段，但尚不是功能完整的 Tauri 客户端替代品。

生成本地签名 Android APK 和 macOS Universal ZIP：

```bash
./scripts/native-android-package.sh vX.Y.Z-preview.N
./scripts/native-macos-package.sh vX.Y.Z-preview.N
```

两个脚本都会先验证对应 Release 构建，并在 `release-artifacts/` 中生成安装包和 SHA-256 文件。Android 脚本需要本地、已忽略的 release keystore；macOS 预览包使用临时签名，不包含 Developer ID 公证票据。

### Android 开发与构建

首次开发前初始化 Android 原生工程：

```bash
npm run tauri:android:init
```

启动调试或构建 APK/AAB：

```bash
npm run tauri:android:dev
npm run tauri:android:build
npm run tauri:android:sign:init
npm run tauri:android:build:local
npm run tauri:android:build:signed
```

其中 `npm run tauri:android:build:local` 会自动补齐 Android Studio JBR、NDK LLVM toolchain 和 Rust PATH，直接产出 arm64 APK。当前验证通过的输出路径为：

```bash
src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release-unsigned.apk
```

Android Studio 调试时，工程现在只保留 `arm64Debug` 和 `universalDebug` 两个主要移动端变体，避免误选 32 位 `armDebug` 并在 64 位真机上触发 ABI 警告。

如果要产出正式签名版 APK，需要再提供 release keystore。仓库已经忽略了 `src-tauri/gen/android/keystore.properties`，可在该文件中填写：

如果本机还没有 keystore，可以直接生成一套本地 release signing 资产：

```bash
npm run tauri:android:sign:init
```

这个命令会在本机生成以下两个已忽略文件：

```bash
src-tauri/gen/android/keystore/where-to-study-upload.jks
src-tauri/gen/android/keystore.properties
```

然后执行：

```bash
npm run tauri:android:build:signed
```

当前签名版 APK 的校验目标输出路径为：

```bash
src-tauri/gen/android/app/build/outputs/apk/universal/release/app-universal-release.apk
```

如果你已经有自己的 release keystore，也可以不用生成脚本，直接在 `keystore.properties` 中填写：

```properties
storeFile=/绝对路径/your-upload-key.jks
storePassword=你的-keystore-密码
keyAlias=你的-key-alias
keyPassword=你的-key-密码
```

也可以不用文件，直接通过环境变量提供同样的值：`ANDROID_SIGNING_STORE_FILE`、`ANDROID_SIGNING_STORE_PASSWORD`、`ANDROID_SIGNING_KEY_ALIAS`、`ANDROID_SIGNING_KEY_PASSWORD`。设置好后运行 `npm run tauri:android:build:signed`，Gradle 会自动切换到 release signing。

需要安装 Android Studio / Android SDK、Android SDK Command-line Tools、NDK 和 rustup 管理的 Android Rust targets。如果命令行缺少 `sdkmanager` 或 NDK，可以先安装 command-line tools，再把 NDK 安装到现有 SDK：

```bash
brew install --cask android-commandlinetools
yes | sdkmanager --sdk_root="$HOME/Library/Android/sdk" --licenses
sdkmanager --sdk_root="$HOME/Library/Android/sdk" "ndk;27.2.12479018"
```

如果 Android Gradle 仍然报 `127.0.0.1:7890` 代理错误，或在 `plugins.gradle.org` 握手失败，先检查 `~/.gradle/gradle.properties` 里是否还保留了失效的 `systemProp.http[s].proxyHost/proxyPort` 设置。

### iOS 开发与构建

首次开发前初始化 iOS 原生工程：

```bash
npm run tauri:ios:init
```

启动调试或构建 IPA：

```bash
npm run tauri:ios:dev
npm run tauri:ios:build
npm run tauri:ios:build:unsigned
npm run tauri:ios:build:signed
```

需要在 macOS 上安装 Xcode、CocoaPods 和 rustup 管理的 iOS Rust targets；真机或发布构建还需要 Apple 开发者签名配置。可以通过 `APPLE_DEVELOPMENT_TEAM` 环境变量或 `bundle > iOS > developmentTeam` 配置开发团队 ID。

首次在本机做 iOS 构建前，先完成 Xcode 初始化：

```bash
sudo xcodebuild -runFirstLaunch
```

`npm run tauri:ios:build:unsigned` 会生成无签名 `xcarchive`，适合本机验证和 CI 归档。首次执行时如果缺少 iOS runtime，Tauri 会提示下载安装。

要生成签名版 iOS 包，需要先在当前 macOS 用户下安装有效的 Apple 签名证书和 provisioning profile，并设置：

```bash
export APPLE_DEVELOPMENT_TEAM=你的-Team-ID
export IOS_EXPORT_METHOD=release-testing
```

然后执行：

```bash
npm run tauri:ios:build:signed
```

如果本机钥匙串里没有有效代码签名身份，`npm run tauri:ios:build:signed` 不会成功。

当前验证通过的输出路径为：

```bash
src-tauri/gen/apple/build/where_to_study_iOS.xcarchive
```

## GitHub Actions

仓库内提供以下构建和安全工作流：

- `.github/workflows/build-windows.yml`：在 `windows-latest` 上构建 Windows 桌面安装包。
- `.github/workflows/build-macos.yml`：在 `macos-15` 上构建并压缩 macOS Apple Silicon 应用。
- `.github/workflows/build-mobile.yml`：构建 Android APK；iOS 有签名配置时输出 IPA，否则输出 unsigned `xcarchive`。
- `.github/workflows/build-native.yml`：验证 SwiftUI 和 Kotlin 原生迁移工程。
- `.github/workflows/security.yml`：扫描提交历史中的敏感信息。

移动端 workflow 使用的 secrets 名称如下：

- Android：`ANDROID_KEYSTORE_BASE64`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`
- iOS：`IOS_CERTIFICATE_P12_BASE64`、`IOS_CERTIFICATE_PASSWORD`、`IOS_MOBILEPROVISION_BASE64`、`APPLE_DEVELOPMENT_TEAM`
- 可选：`IOS_KEYCHAIN_PASSWORD`、`IOS_EXPORT_METHOD`

如果不在界面输入学号和教务密码，也可以在启动前配置环境变量：

```bash
export BUPT_USERNAME=你的学号
export BUPT_PASSWORD=你的教务密码
```

默认学期配置：

- 学期：`2025-2026-2`
- 第一周周一：`2026-03-02`

可通过环境变量 `DEFAULT_TERM_ID` 和 `DEFAULT_TERM_START_DATE` 调整。
