# Where To Study

北邮空教室与个人课表联动查询应用。Windows 与 Linux 客户端使用 Tauri 2、React 和 Rust，
macOS/iOS 客户端使用 SwiftUI，Android 客户端使用 Kotlin 与 Android Views，
鸿蒙（HarmonyOS NEXT）客户端使用 ArkTS 与 ArkUI；macOS 同时保留 Tauri Apple
Silicon 兼容构建。

- 只通过移动教务 HTTPS 接口获取并解析北邮个人课表；请求失败时不会静默切换数据源。
- 获取当天空教室信息时会一次拉取西土城与沙河两个校区，并保存到本地缓存。
- 支持西土城与沙河校区查询；沙河教学楼按 `综合教学楼N`、`综合教学楼S`、`教学实验综合楼N`、`教学实验综合楼S`、`智慧教学楼` 识别。
- 空教室查询支持按个人空闲节次和教学楼筛选；Tauri 桌面端另支持最少座位数筛选。
- macOS 与 Windows 桌面端可在设置中开启每天 7:30 的今日课程系统通知；原生 macOS 提供 WidgetKit 系统小组件，Tauri 桌面端保留应用内课程浮窗。
- SwiftUI、Android 与鸿蒙原生端可选择每天 7:30 接收本地课程摘要，关闭提醒、切换账号或清除数据会撤销后续任务。
- 支持课表本地缓存、教学日历、法定节假日，以及 Apple EventKit、Android Calendar Provider 或鸿蒙 Calendar Kit 系统日历导入；日、周、月可左右滑动翻页，月视图可展开或折叠，年视图可将所选日期跳转到日、周或月。

贡献前请先阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。平台支持范围和验收顺序见
[docs/platform-roadmap.md](./docs/platform-roadmap.md)。

## 平台状态

| 平台 | 客户端技术 | 发布状态 |
| --- | --- | --- |
| macOS | SwiftUI 原生；另提供 Tauri 2 兼容构建 | `0.1.7 (44)` 正式签名 Universal 构建；公开 GitHub Release 另提供临时签名预览包 |
| Android | Kotlin + Android Views | 发布固定维护者密钥签名的 Universal APK/AAB；支持手机、折叠屏和平板布局、系统日历和课程提醒 |
| Windows | Tauri 2 + React + Rust | 持续维护并发布 x64 NSIS 安装包 |
| Linux | Tauri 2 + React + Rust | 发布 x86_64 Debian 包与 AppImage |
| CLI | Rust（复用 Tauri 核心逻辑） | `wts-cli` 纯命令行客户端，当前提供 macOS 构建，见 [wts-cli/README.md](./wts-cli/README.md) |
| 终端 TUI | Rust + ratatui（复用 Tauri 核心逻辑） | `wts-tui` 可视化终端客户端，当前提供 macOS 构建，见 [wts-tui/README.md](./wts-tui/README.md) |
| iOS | SwiftUI 原生 | `0.1.7 (44)` 正式签名构建；公开 GitHub Release 暂仍为无签名开发者 archive |
| HarmonyOS | ArkTS + ArkUI（HarmonyOS NEXT 6.1.1 / API 24） | 原生功能与手机、折叠屏、平板布局已移植并通过 45 项单元测试；发布签名与 AGC 上架尚待配置 |

## 下载

稳定版 [v0.1.7](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.1.7) 提供 Windows x64 NSIS、Linux x86_64 Debian/AppImage、Tauri macOS arm64、SwiftUI macOS Universal、无签名 iOS archive、Android APK/AAB，以及 macOS `wts-cli` 和 `wts-tui`。本版加入学期编号与开学日期自动识别，完善桌面端悬停、动画和触控板翻页，修复 Windows 与 HarmonyOS 平台问题，并让 Linux 凭据改用 Secret Service；Debian 包会在 Ubuntu 24.04 上实际安装验证运行时依赖。每个公开制品都附带 SHA-256 校验文件。GitHub Release 中的原生 macOS 包同时支持 Apple Silicon 与 Intel，但没有 Developer ID 公证签名，首次启动可能需要在 Finder 中右键选择“打开”；原生 Android APK 使用项目维护者的固定 release key 签名并校验证书指纹。正式签名的 iOS 与 macOS 当前均为 `0.1.7 (44)`；公开 Release 中的 iOS archive 仍仅供开发者后续签名，不是可直接安装的 TestFlight 包。

## 许可证状态

本项目按 [GNU General Public License v3.0 only](./LICENSE)（SPDX：`GPL-3.0-only`）开源发布。分发本项目或其衍生版本时，必须遵守该许可证；第三方材料仍分别遵循 [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md) 与锁定依赖生成的 [`THIRD_PARTY_LICENSES.html`](./THIRD_PARTY_LICENSES.html) 中记录的条款。这三份法律文件都会随安装包交付并在打包时逐字节校验。

## 课程提醒与桌面小组件

macOS 与 Windows 桌面端的课程通知默认关闭。用户在设置中显式开启后，应用运行或驻留托盘时会于每天 7:30 根据本地课表发送今日课程摘要；关闭开关或清除本地数据会立即停止后续发送。后台调度只休眠到实际需要的跨日、每天 7:00、已启用的 7:30 或明确的有界重试时间；系统恢复、设置改变或窗口重新聚焦会中断休眠并重算边界，不进行固定间隔轮询。跨日会重建托盘中的今日/明日课程，7:00 获取当天空教室后也会再次重建托盘。

Tauri 桌面端的课程浮窗可以从托盘菜单的“显示课程小组件”打开，也可以在应用“设置”页点击“打开课程小组件”。原生 macOS 的 WidgetKit 小组件需要从系统小组件图库添加，通过 App Group 读取应用同步的今日课程；两种展示都会在课表刷新后更新。

SwiftUI 客户端会在系统待处理通知上限内安排最多 63 个未来有课日的 07:30 摘要；Android 使用持久化 `JobScheduler` 在 07:30–08:00 的有效窗口内发送当天摘要。所有平台都默认关闭，只有用户明确开启后才启用；系统权限被撤销、关闭开关或清除本地数据时会同步撤销后续任务。账号切换时，原生端会撤销旧账号的已安排摘要，桌面端则只会在新账号设置保存成功后继续使用当前开关。

## 数据来源与数据安全

应用使用北邮课表和空教室相关接口，因此需要教务系统账号和密码。账号与密码不会写入
普通设置文件：Windows 使用 Credential Manager，macOS/iOS 使用 Keychain，Linux
使用 Secret Service（GNOME Keyring / KWallet 等系统密钥环），Android 使用
Android Keystore。旧版 `settings.json` 中的凭据会在首次启动时迁移并从普通设置
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

macOS/iOS 与 Android 原生客户端在用户已授权系统日历访问时，会优先从设备自带的“中国（大陆）节假日”日历读取休息日（并仍以远端数据补充“调休/补班”上班日，因为系统日历通常不标注补班）。由于中国目前没有官方的机器可读节假日 JSON 接口（国务院通知为 HTML 页面），Tauri 桌面端继续使用上述固定版本数据源。

## 开发与运行

所有平台的应用主图标以 `src-tauri/icons/icon.png`（Windows/Tauri 当前绿色日历课桌图标）为唯一源图。修改源图后运行 `npm run icons:sync`，同步生成 Windows/macOS Tauri、原生 iOS 和 Android 启动图标；macOS 菜单栏与 Android 通知图标仍使用符合系统规范的单色模板资源。

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

在 Debian 12/Ubuntu 22.04 或兼容的 x86_64 Linux 环境构建 Debian 包与 AppImage：

```bash
npm run tauri:build:linux
./scripts/linux-package.sh vX.Y.Z
```

Linux 打包脚本会解包校验版本、架构、Tauri 按构建环境检测出的 GTK/WebKitGTK/托盘运行时依赖、正式 HTTPS 数据源和三份法律文件，并输出带相邻 SHA-256 文件的 `.deb` 与 `.AppImage`。仓库的 `Build Linux` 工作流使用 Ubuntu 22.04 作为兼容构建基线，并在 Ubuntu 24.04 runner 上实际安装生成的 `.deb`。

### 原生客户端

生成并验证 macOS/iOS SwiftUI 工程：

```bash
./scripts/native-apple-build.sh
```

验证 Android Kotlin 工程：

```bash
./scripts/native-android-build.sh
```

验证鸿蒙（HarmonyOS NEXT）ArkTS 工程（需要 DevEco Studio 6.1.1+ 与已连接的设备/模拟器）：

```bash
./scripts/native-harmony-build.sh
```

`native/apple`、`native/android` 与 `native/harmony` 是当前 macOS、iOS、Android 和鸿蒙客户端源码。它们已完成个人课表与本地缓存、每日课程摘要、含法定节假日和当前时间线的日/周/月/年日历，以及仅限当天的空教室联动查询。Apple 客户端还提供不连接教务服务的内置示例模式，供首次体验与 App Review 审核。鸿蒙客户端当前在 `feature/harmonyos` 分支开发，尚未合入发布流程。

Android 仅使用 `native/android` 的 Kotlin + Android Framework Views 工程，不依赖 Tauri 或 WebView。旧 `src-tauri/gen/android` 工程、Tauri Android npm 命令和 CI 构建任务均已移除，避免误生成或误发布另一套 Android 包。

生成本地签名 Android APK/AAB、macOS Universal ZIP 和无签名 iOS 真机 archive：

```bash
./scripts/native-android-signing-init.sh
./scripts/native-android-package.sh vX.Y.Z
./scripts/native-macos-package.sh vX.Y.Z
./scripts/native-ios-package.sh vX.Y.Z
```

Android 脚本会运行 Release 单元测试与 Lint，构建并校验签名 APK 与 AAB；macOS 脚本构建双架构 Release 应用、进行临时签名和签名校验；iOS 脚本构建 arm64 真机 archive，并检查应用图标和隐私清单。三个脚本都会在 `release-artifacts/` 中生成产物和 SHA-256 文件。Android 脚本需要本地、已忽略的 release keystore；macOS 包不包含 Developer ID 公证票据；iOS archive 未签名，不能直接安装到 iPhone。发布前还应另外运行完整测试和所需的人工运行检查。

面向 Mac App Store、iOS App Store 或 TestFlight 的正式签名归档使用：

```bash
./scripts/native-apple-app-store.sh preflight all
APPLE_DEVELOPMENT_TEAM=XXXXXXXXXX APPLE_BUILD_NUMBER=31 \
  ./scripts/native-apple-app-store.sh archive all
```

脚本还支持 `export` 与 `upload` 动作，并可单独指定 `ios` 或 `macos`。本地正式构建使用已安装的 Apple Distribution、Mac Installer Distribution 证书及三个 App Store 描述文件；团队、描述文件覆盖值和 App Store Connect API 私钥只通过环境变量传入。`Build Native Clients` 工作流也提供受保护的手动上传入口。完整账户配置、CI secrets、元数据和审核步骤见 [`native/apple/AppStore/submission-checklist.md`](./native/apple/AppStore/submission-checklist.md)。

## GitHub Actions

仓库内提供以下构建和安全工作流：

- `.github/workflows/build-windows.yml`：在 `windows-latest` 上构建 Windows 桌面安装包。
- `.github/workflows/build-macos.yml`：在 `macos-15` 上构建并压缩 macOS Apple Silicon 应用。
- `.github/workflows/build-native.yml`：在主分支及手动触发时运行 Rust/Apple 测试，在主分支运行 Android Debug 门禁；版本标签额外生成 SwiftUI macOS Universal、无签名 iOS archive，以及签名 Android APK/AAB。
- `.github/workflows/security.yml`：扫描提交历史中的敏感信息，并审计完整 npm 与 Rust 锁文件依赖。

正式原生 Android 标签构建使用以下 secrets：`ANDROID_RELEASE_KEYSTORE_BASE64`、`ANDROID_RELEASE_STORE_PASSWORD`、`ANDROID_RELEASE_KEY_ALIAS`、`ANDROID_RELEASE_KEY_PASSWORD`。公开 GitHub Release 的原生 iOS 资产仍是无签名 archive；App Store 构建使用本地、Xcode Cloud 或受保护 CI 环境中的 Apple 分发凭据，不把证书或私钥提交到仓库。

如果不在界面输入学号和教务密码，也可以在启动前配置环境变量：

```bash
export BUPT_USERNAME=你的学号
export BUPT_PASSWORD=你的教务密码
```

默认学期配置：

- 学期：`2025-2026-2`
- 第一周周一：`2026-03-02`

可通过环境变量 `DEFAULT_TERM_ID` 和 `DEFAULT_TERM_START_DATE` 调整。

学期与开学日期支持自动识别：

- 设置页提供「按当前日期自动检测」按钮，按校历规律（春季 3 月初 / 秋季 9 月初）
  预填当前学期的学期号与开学日期。
- 获取/刷新个人课表成功后，会以教务返回的权威学期号与开学日期自动更新并保存设置，
  无需手动填写。
