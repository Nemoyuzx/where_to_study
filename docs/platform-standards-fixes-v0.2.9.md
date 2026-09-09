# 平台规范审查修复 / Platform standards follow-up

2026-09-09。对应上一轮 0.2.9 (90) / HarmonyOS 1002026 审查；Apple 0.2.9 (91)、HarmonyOS 0.2.9 (1002027) 已上传测试，不提交商店审核。上传与 CI 最终回执单独记录在 [0.2.9 发布记录](release-v0.2.9.md)。本记录不是平台审核或法律合规认证。

## Apple

- 宿主隐私清单声明自身偏好 `CA92.1` 与 App Group 偏好 `1C8F.1`；iOS/macOS Widget 分别打包独立清单，声明实际 App Group 用途。对应 [required-reason API 规定](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)。
- 新增 `native/apple/scripts/validate-privacy-bundles.sh`，构建及 App Store 归档/导出/上传均检查实际 `.app/.appex` 内的 manifest 与理由。缺少任意清单或用途时失败，而非仅检查源码。
- “设置同步到 iPhone、iPad、Mac”改为应用到本机小组件，并更新中英文相关说明。
- 私人课程标记为 `privacySensitive`。采用系统 Widget 容器边距；最大辅助字号下空间不足时减少元数据/明日条目，以紧凑布局保留首门课及完整时间，不硬塞明日。

验证：macOS 51 项、iOS 52 项定向测试通过；修复辅助字号裁切后，两端各 5 项渲染回归通过；14 项实际 bundle 目录门禁夹具通过。无签名 `APP_STORE_BUILD` Release 的 iOS/macOS 宿主与 Widget 都通过新门禁。专用 iOS 26.5 模拟器 SpringBoard 实际小组件的默认、深色、Tinted、Clear 样式已检查；截图和结果在 `release-artifacts/apple-standards-fix/`。这不代替实体设备和所有系统版本的验证。

## Android

- `reconcile` 保留匹配的有效计划；处于当天投递窗口且尚未发送时恢复当天任务，不因 resume/reboot/日期广播无条件跳到明日。
- `onStopJob` 区分撤销/失效与系统暂时停止；有效计划重试，窗口结束后续排下一天。23:59 的 deadline 同样截止当日，不用新增精确闹钟权限。
- 广播本地 I/O 经 `goAsync`、8 秒有界后台与一次性 `finish`；小组件每批只读取一次课表，并在发布前检查数据代次/刷新版本。
- AAB 关闭语言拆分。实际 AAB 已核对 `LANGUAGE=3 / negate=true` 与中英文资源，符合 [应用内语言切换分包要求](https://developer.android.com/guide/app-bundle/configure-base#handling_language_changes)。
- 使用 `StaticLayout` 测量系统字号及 CJK 回退字体的真实高度。最小尺寸/200% 字体下减少次要字段，完整详情保留在无障碍描述，实际 Host 与预览共用布局决策。

验证：224/224 JVM；Lint 0 errors、58 warnings、1 hint（原 `AppBundleLocaleChanges` 已消除）；Debug APK/AAB 与 AndroidTest APK 构建通过。隔离 API 36.1 模拟器调度 4 项、权限撤销 1 项、普通字体 UI 4 项、200% 字体 UI 1 项通过。真实 AppWidgetHost 覆盖 180×110、250×205、320×328dp，中英×100%/200%，截图位于 `native/android/app/build/outputs/review-widgets/`。未等待自然午夜，也未覆盖所有 OEM Doze 或 Android 7 真机。

## HarmonyOS

- 统一以原始 `Context.filesDir` 为路径参数，修复课程/主题多拼一层 `WhereToStudyNative`；错误旧路径只删除、不导入，避免恢复其他账号或已清空数据。
- 归档写入按文件流串行并采用 generation；清除/账号切换等待已开始的旧写入，示例模式不覆盖真实 Widget 归档。通过设备上的生产 writer→reader 文件回归验证，不只测试纯绑定数据。
- 下一次刷新取常规 30 分钟和距午夜的较小值，下限 5 分钟；首次添加不对尚未注册的卡片设置预约，去掉被周期配置覆盖的定点字段。遵守 [系统刷新模型和配额](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/form/arkts-ui-widget-passive-refresh.md)。
- 发布前重验未来时间；原生时间验证返回时已过期则跳过单项，继续后续有效提醒；按实际成功数量反馈。
- 修复尺寸选择状态闭包不更新、2×2 实卡空态文字越界；UI 冒烟脚本补明确测试参数，绕过首启隐私仅限 Debug＋测试模式，Release 实装验证不能绕过。

验证：181/181 主机单测、HAP/APP 构建；设备文件集成回归 1/1；手机脚本 18 项通过，4 项输入检查被模拟器“小艺输入法”首次隐私协议阻挡，未接受该第三方条款。旧 ohosTest 全套为 5/8，仍有旧页面初始状态/月视图断言，不记为全绿。本轮真实视觉覆盖 07:30→08:30、三尺寸样例预览、桌面 2×2 实卡空态；生产 writer→reader 的课程数据验证和桌面空态截图是不同证据，不能混称同一张有课实卡截图。证据保留在 `/tmp/wts-harmony-fix-qa.6qKzSI/` 及 Harmony 构建/测试报告中。

尚未确认服务端代理提醒开放能力是否批准，亦未验证整日刷新、所有系统版本与真实通知到达。上传快速云测试不能替代这些验证。

## Windows/Linux 与 Tauri macOS

- 移除会在内部另起任务并吞掉发送结果的通知插件。Windows 直接调用 WinRT `Show/Hide` 并用固定 tag/group 清理本功能历史；Linux 使用有 5 秒方法超时的同步 D-Bus `Notify/CloseNotification`，清理失败保留 ID 并返回错误，绑定 unique owner 防止服务重启后错删。
- 迁移期 Tauri macOS 改用 `UNUserNotificationCenter`，等待真实完成回调。UUID 防跨重启 ID 复用，超时晚回调仅撤销自己；清理枚举本功能前缀并在 8 秒总预算中复查，不清除其他功能通知。
- 未打包的 Tauri macOS 开发进程先检查 Bundle ID，避免通知中心抛出 Objective-C 异常；发送返回明确错误，清理和权限请求不访问系统通知中心。该迁移期代码不属于原生 Apple 上传包，单独完成 7 项模块回归。
- 实际发送与设置/账号撤销处于同一有效性检查范围，不再只保护“入队”。失败采用有上限的分钟级重试，空课表日不发送无用摘要。
- 设置/缓存读写与清理 IPC 转后台阻塞工作线程；异步排队的旧设置保存携带 generation，清空后不得重新写回旧凭据。冷启动后台清除自身历史通知后再启动调度器，避免关闭/默认值相同时漏掉历史清理。
- 新增隔离 D-Bus 协议回归，并接入 Linux CI；只在 `dbus-run-session` 和明确测试变量下运行，不访问用户桌面通知服务。Linux 依赖纳入第三方许可证清单。

本地 Tauri Rust 最终 169 项通过、3 项既有 live 测试忽略；严格 Clippy 通过。新增通知模块按 Windows MSVC 与 Linux GNU 目标条件编译和严格 Clippy 检查通过。首轮 CI 中 Windows 完整测试、NSIS 打包及安装校验通过；Linux 两架构 Rust 162 项、私有 D-Bus 协议各 1 项、严格 Clippy 和初始包构建通过，但原有可变 continuous 工具下载被旧摘要门禁拒绝。已将工具固定到官方 release asset ID，独立下载验证 GitHub API SHA-256/大小/ELF 架构，并增加正确/错误下载和缓存回归；没有放宽摘要校验。更新后的完整 Linux 打包回执见发布记录，不能将条件编译当作安装态或系统通知视觉测试。所有本地日志集中在 `release-artifacts/standards-fix-029-testing/`。

## 边界

通知依旧可能受系统权限、省电、调度配额与用户关闭应用影响；本次没有用精确闹钟或高频轮询绕过这些限制。默认提醒仍关闭、时间仍为北京时间 07:30。没有把服务端授权或未完成的设备测试记为通过，发布仅限用户授权的测试渠道。
