# Where To Study

北邮空教室与个人课表联动查询应用。当前可用客户端基于 Tauri 2、React 和
Rust；仓库同时在按平台逐步迁移到 SwiftUI 和 Kotlin 原生客户端。

- 只通过移动教务 HTTPS 接口获取并解析北邮个人课表；请求失败时不会静默切换数据源。
- 获取当天空教室信息时会一次拉取西土城与沙河两个校区，并保存到本地缓存。
- 支持西土城与沙河校区查询；沙河教学楼按 `综合教学楼N`、`综合教学楼S`、`教学实验综合楼N`、`教学实验综合楼S`、`智慧教学楼` 识别。
- 按个人空闲节次、教学楼、最少座位数筛选空教室。
- macOS 与 Windows 桌面端可在设置中开启每天 7:30 的今日课程系统通知，并提供课程桌面小组件。
- SwiftUI 与 Android 原生端可选择每天 7:30 接收本地课程摘要，关闭提醒、切换账号或清除数据会撤销后续任务。
- 支持课表本地缓存、教学日历、法定节假日和 Apple 日历导入。

贡献前请先阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。平台迁移范围和验收顺序见
[docs/platform-roadmap.md](./docs/platform-roadmap.md)。

## 平台状态

| 平台 | 当前可用版本 | 原生迁移状态 |
| --- | --- | --- |
| macOS | Tauri 2 迁移期版本 | SwiftUI 原生预览已支持个人课表、系统日历、菜单栏、每日课程摘要、含节假日和当前时间线的教学日历、当天空教室联动查询 |
| Android | Kotlin Views 原生预览 | 已支持个人课表、系统日历、每日课程摘要、含节假日和当前时间线的教学日历、当天空教室联动查询 |
| Windows | Tauri 2，持续维护 | 保留 Tauri，并进行安全和资源占用优化 |
| iOS | 暂不提供签名安装包 | SwiftUI 模拟器与 arm64 真机 archive 可重复构建，已接入个人课表、每日课程摘要、含节假日和当前时间线的教学日历、当天空教室联动查询 |

## 下载

已发布测试版 [v0.1.1-alpha.11](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.1.1-alpha.11)，提供 Windows x64 NSIS、Tauri macOS arm64、SwiftUI macOS Universal、无签名 iOS archive，以及 Android APK/AAB；每个二进制制品都附带相邻的 SHA-256 校验文件。原生 macOS 包同时支持 Apple Silicon 与 Intel，但目前没有 Developer ID 公证签名，首次启动需要在 Finder 中右键选择“打开”；原生 Android APK 使用项目维护者的固定 release key 签名并校验证书指纹。原生预览现已完成功能范围内的个人课表、法定节假日、日/周/月/年日历、当前时间线、每日课程摘要、系统日历导入和当天空教室联动查询。iOS 因缺少公开分发签名暂不提供可直接安装的公开包，Release 中的 archive 仅供开发者后续签名。

## 许可证状态

本项目按 [GNU General Public License v3.0 only](./LICENSE)（SPDX：`GPL-3.0-only`）开源发布。分发本项目或其衍生版本时，必须遵守该许可证；第三方材料仍分别遵循 [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md) 与锁定依赖生成的 [`THIRD_PARTY_LICENSES.html`](./THIRD_PARTY_LICENSES.html) 中记录的条款。从 `v0.1.1-alpha.12` 起，这三份法律文件都会随安装包交付并在打包时逐字节校验。

## 课程提醒与桌面小组件

macOS 与 Windows 桌面端的课程通知默认关闭。用户在设置中显式开启后，应用运行或驻留托盘时会于每天 7:30 根据本地课表发送今日课程摘要；关闭开关或清除本地数据会立即停止后续发送。后台调度只休眠到实际需要的跨日、每天 7:00、已启用的 7:30 或明确的有界重试时间；系统恢复、设置改变或窗口重新聚焦会中断休眠并重算边界，不进行固定间隔轮询。跨日会重建托盘中的今日/明日课程，7:00 获取当天空教室后也会再次重建托盘。

课程桌面小组件可以从托盘菜单的“显示课程小组件”打开，也可以在应用“设置”页点击“打开课程小组件”。小组件显示今日课程和下一节待上课程，并会在课表刷新后自动更新。

SwiftUI 客户端会在系统待处理通知上限内安排最多 63 个未来有课日的 07:30 摘要；Android 使用持久化 `JobScheduler` 在 07:30–08:00 的有效窗口内发送当天摘要。所有平台都默认关闭，只有用户明确开启后才启用；系统权限被撤销、关闭开关或清除本地数据时会同步撤销后续任务。账号切换时，原生端会撤销旧账号的已安排摘要，桌面端则只会在新账号设置保存成功后继续使用当前开关。

## 数据来源与数据安全

应用使用北邮课表和空教室相关接口，因此需要教务系统账号和密码。账号与密码不会写入
普通设置文件：Windows 使用 Credential Manager，macOS/iOS 使用 Keychain，Android
使用 Android Keystore。旧版 `settings.json` 中的凭据会在首次启动时迁移并从普通设置
中删除。迁移先原子替换脱敏设置文件，再写入系统凭据存储。Tauri 为每个已保存账号生成不含账号信息的随机不透明缓存作用域，账号切换或清除失败时会持久化撤销标记并拒绝旧缓存。Tauri 的
`load_saved_settings` 只向 WebView 返回 `has_saved_password`，不会返回真实密码；密码输入留空时保留已有系统凭据，只有显式输入新密码才替换。课程和空教室缓存不包含密码、token 或 cookie。完整基线见
[docs/security.md](./docs/security.md)。

法定节假日运行时数据来自
[cg-zhou/holiday-calendar](https://github.com/cg-zhou/holiday-calendar)，客户端通过其文档列出的
[固定到 1.3.3 版本的 unpkg HTTPS 年度 JSON 地址](https://unpkg.com/holiday-calendar@1.3.3/data/CN/2026.json)按年份读取 `CN`
数据。上游说明中国数据依据国务院办公厅年度节假日安排通知整理，并以 MIT License 发布；完整版权与
许可文本见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。客户端严格核对响应年份、地区、日期、
名称和类型，将 `public_holiday` 与 `transfer_workday` 映射到现有本地契约，未知类型不会写入缓存。
Tauri、SwiftUI 和 Android 客户端都保留一份仅用于首次离线展示的 2026 年兜底日期，其内容对应
[国务院办公厅关于 2026 年部分节假日安排的通知](https://www.gov.cn/yaowen/liebiao/202511/content_7047099.htm)；
远端或本地缓存可用后会使用自动获取的数据。

## 开发与运行

```bash
npm install
npm run tauri dev
```

### 构建桌面端

```bash
npm run tauri:build
```

在 Windows 机器上构建可复现的 64 位 NSIS 安装包：

```bash
npm run tauri:build:windows
```

该脚本固定使用 `--bundles nsis --ci`，产物位于 `src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/`。Windows 构建建议在 Windows 机器或 Windows CI runner 上执行，需要安装 Rust MSVC toolchain、Microsoft C++ Build Tools 和 WebView2 Runtime。

### 原生客户端基线

生成并验证 macOS/iOS SwiftUI 工程：

```bash
./scripts/native-apple-build.sh
```

验证 Android Kotlin 工程：

```bash
./scripts/native-android-build.sh
```

这两个目录用于逐步迁移。当前原生预览包已完成个人课表与本地缓存、每日课程摘要、含法定节假日和当前时间线的日/周/月/年日历，以及仅限当天的空教室联动查询；发布签名、公证和真机分发仍按平台分别受限。

生成本地签名 Android APK/AAB、macOS Universal ZIP 和无签名 iOS 真机 archive：

```bash
./scripts/native-android-package.sh vX.Y.Z-preview.N
./scripts/native-macos-package.sh vX.Y.Z-preview.N
./scripts/native-ios-package.sh vX.Y.Z-preview.N
```

Android 脚本会运行 Release 单元测试与 Lint，构建并校验签名 APK 与 AAB；macOS 脚本只构建双架构 Release 应用、进行临时签名和签名校验；iOS 脚本构建 arm64 真机 archive，并检查应用图标和隐私清单。三个脚本都会在 `release-artifacts/` 中生成产物和 SHA-256 文件。Android 脚本需要本地、已忽略的 release keystore；macOS 预览包不包含 Developer ID 公证票据；iOS archive 未签名，不能直接安装到 iPhone。发布前还应另外运行完整测试和所需的人工运行检查。

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
- `.github/workflows/build-mobile.yml`：仅供手动验证旧 Tauri Android/iOS 迁移基线，不随版本标签或正式 Release 构建。
- `.github/workflows/build-native.yml`：运行 Rust 共享契约/单元测试、macOS 与 iOS 模拟器单元测试、Apple 原生构建，生成无签名原生 iOS 真机 archive，以及运行 Android 单元测试、Lint 和构建。
- `.github/workflows/security.yml`：扫描提交历史中的敏感信息，并审计完整 npm 与 Rust 锁文件依赖。

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
