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
```

需要安装 Android Studio / Android SDK、Android SDK Command-line Tools、NDK 和 rustup 管理的 Android Rust targets。如果命令行缺少 `sdkmanager` 或 NDK，可以先安装 command-line tools，再把 NDK 安装到现有 SDK：

```bash
brew install --cask android-commandlinetools
yes | sdkmanager --sdk_root="$HOME/Library/Android/sdk" --licenses
sdkmanager --sdk_root="$HOME/Library/Android/sdk" "ndk;27.2.12479018"
```

## iOS 开发与构建

首次开发前初始化 iOS 原生工程：

```bash
npm run tauri:ios:init
```

启动调试或构建 IPA：

```bash
npm run tauri:ios:dev
npm run tauri:ios:build
```

需要在 macOS 上安装 Xcode、CocoaPods 和 rustup 管理的 iOS Rust targets；真机或发布构建还需要 Apple 开发者签名配置。可以通过 `APPLE_DEVELOPMENT_TEAM` 环境变量或 `bundle > iOS > developmentTeam` 配置开发团队 ID。

如果不在界面输入学号和教务密码，也可以在启动前配置环境变量：

```bash
export BUPT_USERNAME=你的学号
export BUPT_PASSWORD=你的教务密码
```

默认学期配置：

- 学期：`2025-2026-2`
- 第一周周一：`2026-03-02`

可通过环境变量 `DEFAULT_TERM_ID` 和 `DEFAULT_TERM_START_DATE` 调整。
