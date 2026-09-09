# 自定义课程提醒与小组件明日课程

2026-09-09 源码变更；随后按用户要求准备提交并上传 Apple 0.2.9 (90) 与鸿蒙 0.2.9 (1002026) 仅测试包，不提交商店审核。成功回执见[发布记录](release-v0.2.9.md)。

## 提醒时间 / Reminder time

- Windows/Linux Tauri、iOS/iPadOS/macOS、Android、HarmonyOS 的已有每日课程摘要均提供时分选择。默认仍为 **07:30**，开关默认关闭。
- 时间基准为 **北京时间（Asia/Shanghai，UTC+8）**，与课程日期一致，不因设备处于其他时区而将课表日期错位。
- 持久化为零点后的整数分钟 `0...1439`，默认 `450`。旧数据、损坏值回默认，用户无效输入不会保存；清除本地数据恢复默认。不开启提醒时也可先选择时间，不自动请求权限。
- 修改时间会重排已开启的提醒，旧 revision/job 不得在新设置之后继续送达。账号切换、清除和关闭继续走原有撤销逻辑，不向服务器传输时间设置。
- Tauri 的“保存提醒设置”复用本地设置接口，只基于已保存设置更改提醒两项，不提交其他账号草稿，也不重置教务自动获取状态。保留原本的后台运行、启动补检查及每日去重策略，07:00 空教室刷新时间不受影响。
- Apple 使用有限数量的本地日历通知，HarmonyOS 使用提醒代理；修改时仅安排未来可用课程日。Android 沿用 JobScheduler 而非新增精确闹钟权限，调度可能被系统延迟，摘要窗口不跨北京时间午夜，不将昨日摘要发到次日。
- 独立 CLI/TUI 原本没有系统通知调度或桌面 Widget，本次不增加无效设置项或后台守护进程；共享模型保持兼容。

All graphical clients with daily course notifications accept a custom Beijing-time hour and minute, retaining 07:30 and notifications off as defaults. The preference is local-only. Existing platform delivery and permission limits still apply; Android does not gain an exact-alarm permission, and Tauri must remain running. Changing reminder settings does not fetch timetable data or submit unrelated account drafts.

## 小组件布局 / Widget layout

- 仅更新支持系统小组件的平台：Apple WidgetKit、Android RemoteViews 与鸿蒙服务卡片。Windows/Linux 不恢复已移除的课程浮窗。
- 先分配今日课程，再在**实际尺寸容量和用户课程条数上限**以内使用剩余空间显示明日。无空间时只显示今日，不缩小课程文字来硬塞明日。
- 明日行始终带明确分组/前缀，不显示今日的“进行中 / 下一节”高亮。今日无课时仍体现今日无课状态，明日有课且放得下时可补充明日；无明日课程不制造占位课程。
- 明日从同一份完整课表缓存按真实下一日筛选，跨月、跨年和教学周转换均重新计算；不复制今日课程、不新增网络请求。
- 实际小组件与设置预览共用布局/行选择逻辑；午夜刷新重新计算今日与明日。系统可能推迟后台刷新，因此不承诺锁屏、省电或系统停调情况下精确在午夜更新。

Widgets prioritize today's courses and append clearly labeled tomorrow rows only when both size and the configured course limit allow them. Tomorrow is resolved from the same cached timetable, including date/teaching-week boundaries, and never receives today's in-progress/next-course styling. Unsupported desktop platforms do not gain widget windows.

## 验证范围

测试使用虚构课程与隔离存储，不修改真实教务账号或已发布版本。

| 范围 | 验证结果 |
| --- | --- |
| Web/Tauri | 164 项 Node 测试通过，Vite 生产构建通过；Tauri 本机 Rust 157 项通过、3 项既有 live 测试忽略。覆盖旧配置、非法值、持久化、00:00/23:59、自定义调度、旧工作失效、跨午夜再检查和每日去重。 |
| Edge | 中文宽布局、英文 600px/390px 窄窗口目检通过，无水平溢出；实际键盘改时并保存 10:15、23:59、00:00，提醒开关与未保存账号草稿隔离通过。使用本地预览，没有向教务提交测试账号。 |
| Apple | macOS 64 项定向测试、iOS 64 项单测通过；iOS 中英时分选择及大小号 Widget 预览 2 项 UI 通过，最后局部复测 3 项全部通过。临近旧提醒时间修改时立即取消旧通知的补丁，两端各 27 项提醒测试通过。严格并发与 Swift 警告检查通过，宿主/扩展均编译。 |
| Android | 221 项 JVM 测试通过，Debug、androidTest APK 与 Lint 通过（零错误，保留既有警告）；API 36.1 隔离模拟器 4 项检查通过，包括真实 JobScheduler、持久化、中英 TimePicker、预览与 RemoteViews。 |
| HarmonyOS | 最终 175 项主机单测、HAP/APP 构建通过；覆盖实际 AppModel 改时入口的立即取消、慢权限查询、新时间发布及非法输入不写入/不调度。 |
| Headless core/TUI | 共享核心 62 项、TUI 36 项测试通过，确认新增共享设置字段未破坏既有终端功能。 |

Apple UI 首轮有一处断言未兼容系统中文选择器返回的“10点”，修正断言后最终复测通过；另修复原有本地数据清除测试等待存储完成但未等主线程发布的竞态，没有掩盖生产失败。Apple、Android 的时间选择器及小组件实际渲染截图均已检查；截图留在忽略目录，不放入 README。

证据：`release-artifacts/reminder-time-tomorrow-widget/` 保存本轮 Web/Rust/core/TUI 日志；Apple `native/apple/DerivedData-reminder-tomorrow-{mac,ios}/` 保存 xcresult、渲染图和 `immediate-cancel.xcresult`；Android `native/android/app/build/ui-reminder-widget/` 保存中英文截图，标准 Gradle 报告保留单测结果；HarmonyOS 测试报告保留在 `native/harmony/entry/.test/default/outputs/test/`。

限制：没有真机系统通知实际到达或等待真实午夜的验证，没有 Apple 系统 Gallery 固定小组件验证。鸿蒙 `hdc` 当前无连接设备，尚无新卡片的设备视觉检查；Linux SSH 可达但当前环境未提供 Cargo/GTK 测试工具，没有把主机测试和 Edge 共用前端检查当作 Windows/Ubuntu 安装态测试。系统通知与午夜刷新仍受权限、省电和平台调度约束。源码实现阶段未发布新包；后续仅测试上传单独记录，不替代这些设备覆盖。
