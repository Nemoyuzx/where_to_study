# Where To Study 原生平台路线

## 目标形态

| 平台 | 客户端技术 | 业务核心 | 发布形态 |
| --- | --- | --- | --- |
| Windows | Tauri 2 + React | Rust | MSIX/NSIS（后续确定） |
| Linux | Tauri 2 + React | Rust | Debian/AppImage |
| macOS | SwiftUI | 共享 Rust 核心或等价原生适配层 | `.app` / notarized `.dmg` |
| iOS | SwiftUI | 共享 Rust 核心或等价原生适配层 | TestFlight / App Store |
| Android | Kotlin + Android Views | 共享 Rust 核心或等价原生适配层 | signed AAB/APK |
| HarmonyOS | ArkTS + ArkUI（6.1.1 / API 24） | 等价原生适配层（参考 SwiftUI 实现） | 华为应用市场（待定） |

现有根目录 Tauri 工程只承担 Windows 客户端。Android 的 Tauri 生成工程与构建链已删除，唯一 Android 源码和发布入口是 `native/android`；`src-tauri/gen/apple` 仅保留为待下线的旧 Tauri iOS 生成目录，不作为当前原生客户端源码。

## 不变量

1. 课程、节次、校区、教室与缓存规则在各平台含义一致；不再推断或标注考试周。
2. 图形与原生客户端的账号和密码只能保存在系统安全存储中：Windows Credential Manager、Apple Keychain、Android Keystore、鸿蒙 ASSET 安全存储；独立 TUI 按产品约定使用用户私有本地文件，不调用系统密码库。
3. 仓库、构建日志、测试夹具、截图和 release 资产不得包含真实账号、密码、token、证书或签名私钥。
4. 原生端不嵌入 WebView，不复制 React 页面。
5. 默认不常驻高频轮询；网络请求由用户动作、应用启动和每日计划任务触发。
6. 每个平台维持空教室、教学日历、设置三个一级页面，颜色、术语和状态语义保持一致。

## 迭代阶段

### 阶段 0：基线与安全

- 固化 `contracts/v1` 数据契约。
- 增加原生工程目录和可重复构建脚本。
- 将 Tauri 明文凭据迁移到系统安全存储。
- 增加 tracked-file 凭据扫描与最小 CI 门槛。

完成标准：所有工程能在无真实账号的环境构建；仓库扫描无真实凭据；旧设置迁移不会丢失非敏感设置。

### 阶段 1：只读课表

- 原生端完成账号设置、课表获取、本地缓存。
- 实现日/周/月/年教学日历。
- 实现法定节假日和当前时间线；公历周与教学周并列展示。

完成标准：同一脱敏课表夹具在五个平台生成一致的日期课程集合。

### 阶段 2：空教室

- 接入西土城、沙河实时空教室接口。
- 实现课程联动、教学楼过滤和节次选择。
- 保留当天限制与本地缓存策略。

完成标准：同一脱敏接口响应在五个平台生成一致的教室名称、座位数和可用节次。

### 阶段 3：平台集成

- macOS：菜单栏、关闭主窗口后驻留、每日通知。
- iOS：本地通知、系统日历导入、后台刷新能力评估。
- Android：通知、日历 Provider 导入、`JobScheduler` 定时刷新。
- Windows：托盘、通知、启动性能和 WebView 内存优化。

### 阶段 4：发布

- 自动化单元测试、UI 冒烟测试和 release 构建。
- Android AAB/APK 签名，Apple archive/notarization，Windows 签名。
- 许可证、隐私说明、安全政策和贡献指南完整。

## 资源预算

首轮目标值用于回归比较，不作为未经测量的承诺：

- 空闲状态不得持续发起网络请求。
- 本地课表解析在后台线程执行，主线程只更新最终状态。
- 日历只渲染可见日期；长列表使用惰性容器或复用视图。
- 缓存使用单份结构化数据，避免同时保存多份等价 JSON。
- 原生客户端不引入分析 SDK、广告 SDK 或常驻第三方运行时。

## 当前状态

详细的源码、测试、打包和待完成事项检查点见 [`development-status.md`](development-status.md)。

- Windows/Tauri：教学日历和设置均可进入班车/重要事件查询；班车只显示当天 active 时刻表，重要事件支持公开+校内来源、元数据搜索、真实分类、DDL 升序和完整收藏；会议独立开关、年度预热、跨年加载、双层 DDL 边框、教学周与键盘操作均已完成，React 单文件仍需拆分。
- Linux/Tauri：与 Windows 共享 React/Rust 功能，`v0.2.8` 使用 Ubuntu 22.04 原生 CI 发布 x86_64/arm64 Debian 包与 AppImage，并同步提供 CLI/TUI 查询命令或视图。
- macOS/iOS 原生：共享 SwiftUI 已接入双入口班车/重要事件查询、并行缓存预热、搜索分类/DDL 排序/收藏和会议日历；个人课表、Keychain、节假日、日/周/月/年、天气/黄历、云课堂作业、系统日历和两校区空教室保持完整。
- Android 原生：Kotlin + Android Views 已在手机、折叠屏和平板共享双入口查询、当天班车与活动搜索分类收藏；Keystore、课表/空教室、日/周/月/年、课程摘要、天气/黄历、云课堂作业、双层边框和跨月动画保持完整。
- 鸿蒙原生：ArkTS + ArkUI 的手机、折叠屏、平板与 PC 均接入共享缓存的班车/重要事件双入口及会议日历；DevEco Studio 6.1.1 / API 24 的 `0.2.8 (1002013)` Release APP/HAP 与 122 项单元测试通过，已上传 AGC 并通过云测试。
- 阶段 2 状态：同一脱敏接口响应已在 Rust、Swift、Kotlin 和 ArkTS 生成一致的教学楼、三位教室号、双门教室号、座位数与可用节次；启动时仅在当天缓存缺失且已有凭据时刷新，不进行高频轮询。
- 原生分发限制：Android `0.2.8 (44)` 使用固定维护者密钥签名；Apple iOS 与 macOS `0.2.8 (74)` 已由本地 Xcode 分平台上传 TestFlight；HarmonyOS `0.2.8 (1002013)` 已上传 AGC，邀请测试处于预审中。GitHub `v0.2.8` Pre-release 同步提供 14 项附件，Windows/Linux/CLI/TUI 有来源证明；Windows 公众 Authenticode 和 Linux 原生 APT 信任仍需各自的外部身份/仓库基础设施。
- 开源授权：根目录已加入 GPL-3.0-only 标准许可证文本，项目元数据、贡献指南和发布文档使用同一 SPDX 标识。
