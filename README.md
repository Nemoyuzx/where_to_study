# Where To Study

一个基于 Tauri 2、React 和 Rust 的跨平台空教室查询应用。功能对齐本地 `agenda_with_empty_classroom` 网站：

- 获取北邮个人课表并解析 XLS 课表文件。
- 查询当天空教室，优先使用微信教务实时接口，失败时回退到 Jraaay 公共实时数据源。
- 按个人空闲节次、教学楼、最少座位数筛选空教室。
- 推荐可以连续待着、不用换教室的候选教室。

## 开发运行

```bash
npm install
npm run tauri dev
```

## 构建桌面端

```bash
npm run tauri build
```

在 Windows 机器上构建 64 位 Windows 包：

```bash
npm run tauri:build:windows
```

Windows 构建建议在 Windows 机器或 Windows CI runner 上执行，需要安装 Rust MSVC toolchain、Microsoft C++ Build Tools 和 WebView2 Runtime。

## Android 开发与构建

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

## iOS 开发与构建

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

仓库内已提供两条手动触发 / `v*` 标签触发的工作流：

- `.github/workflows/build-windows.yml`：在 `windows-latest` 上构建 Windows 桌面安装包。
- `.github/workflows/build-mobile.yml`：在 GitHub Actions 上构建 Android APK，并在存在 signing secrets 时产出 signed Android APK 和 signed iOS IPA；如果 iOS secrets 缺失，则回退为 unsigned `xcarchive`。

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
