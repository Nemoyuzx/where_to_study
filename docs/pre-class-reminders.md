# 课前提醒 / Pre-class reminders

## 使用方式

在“设置 → 课程提醒”中打开“课前提醒”。它与每日课程摘要是两个独立开关，默认均关闭，不会在升级时自动开启系统通知。

- 默认一次、提前 **10 分钟**；可添加或删除为 **1–5 次**。
- 每次可填写 **1–1440** 的整数分钟。例如 `[10, 5]` 表示课前十分钟和五分钟各通知一次。
- 不接受重复、负数、小数、空值或超出范围的输入；损坏的历史设置回到 `[10]`。设置只保存在本机。
- 按北京时间课程的真实开始时刻安排，一次连续多节课程只提醒开始，不在每一节重复。明确时间的考试采用课表中的优先覆盖规则；全天／时间待定的考试不虚构开始时间。
- 刷新、删课／恢复、账户变化、清除数据及提醒设置变化会撤销或重排；不重放已经过期的提醒，不为提醒重新发起网络登录／课表查询。

## 平台限制

| 平台 | 调度方式与限制 |
| --- | --- |
| iOS／iPadOS／macOS | 本地系统通知；每日摘要和课前提醒合并按时间占用既有 63 条预算。多次课前提醒会缩短预排覆盖天数，回到前台时补排。系统授权、专注模式、省电等会影响呈现。 |
| Android | 独立通知频道与下一时点 AlarmManager；用户可主动授予 `SCHEDULE_EXACT_ALARM` 的“闹钟和提醒”特殊访问权。未授权时使用大致时间，并说明可能延迟／错过。没有 `USE_EXACT_ALARM`，不自动打开授权页面。每日摘要继续使用原有 JobScheduler。 |
| HarmonyOS | 每日摘要和课前提醒共用串行取消／发布协调器，合并取最近 30 条提醒代理请求，回前台补排。受系统权限、开放能力及数量限制；长期不打开应用不能保证整个学期都已预排。 |
| Windows／Linux Tauri | 独立于网络刷新的本地定时工作线程，只等待实际触发边界，不轮询。需应用运行／驻留托盘；关机、退出或休眠时不能保证送达。仅允许已经安排且仍有效的短暂迟到提醒，过期不补发。 |
| CLI／TUI | 不提供系统通知后台进程，不增加不起作用的开关。 |

提醒不是闹钟可靠性承诺，请勿据此替代考试或上课时间的官方确认。多个提醒使用独立身份，更新一类设置不会永久停掉另一类。单条临时发布失败应保留后续可用提醒及用户设置，恢复尝试有界；明确权限拒绝时不得继续投递。

## Privacy and usage (English)

Pre-class reminders are separate from daily summaries and off by default. The default is one reminder 10 minutes before class; users can configure 1–5 distinct integer lead times from 1 to 1440 minutes. Only the locally cached, effective timetable is used. Timed exams override conflicting classes; unknown/all-day exam times are excluded. Settings and deduplication records stay on the device; this feature does not add a server upload or timetable request.

Apple and HarmonyOS have finite pending-request budgets, so reopening the app is needed to replenish future reminders. Android offers optional Alarms & reminders special access; without it, approximate delivery may be delayed or missed. Windows/Linux require the app to keep running. Delivery remains subject to platform restrictions and is not guaranteed while the device is off, sleeping or notifications are blocked. Expired reminders are not replayed.

## 验证记录

实现与测试使用合成课表和隔离测试存储，不使用真实账户发送测试通知。本轮最终测试与发布结果随[0.3.0 发布记录](release-v0.3.0.md)更新；编译或主机规划测试不能视为所有系统实际通知到达的验证。

封包前验证：JavaScript 230 项通过（1 项实际 Windows PE 检查在 macOS 上跳过）、Tauri Rust 227 项通过（3 项既有在线／环境测试忽略）、严格 Clippy 与生产构建通过；Core 100、CLI 24、TUI 50 项通过。Edge 中英设置增删、重复值拒绝、1–5 次、保存与摘要开关隔离及窄桌面无溢出均已检查。

Apple 最终 macOS 400 项、iOS 421 项单测均 0 失败，各跳过 1 项既有在线测试；新增中英两项设置 UI 及相邻每日摘要／Widget 两项 UI 通过，iPhone 五行与 macOS 360pt 窄栏渲染已目视检查。首轮新增 UI 曾因测试替换文字位置和同值回写清除保存提示失败，保留断言、修正交互及同值早退后复测通过，没有把失败的历史整轮报告记为通过。

Android 286 项 JVM、12 项调度边界／故障注入、每日摘要及权限回归通过。API 36.1 隔离模拟器中，精确授权撤销确实删除精确闹钟并杀进程，非精确保底仍能在不打开 Activity 的情况下唤醒并续排；已过期提醒被跳过，不能将该结果称为准时送达。另验证了独立恢复 Job 在新后台进程执行。鸿蒙 247 项 Hypium 和 ArkTS 编译通过，涵盖单条失败不丢后续、首次偏好、账户取消、时区及有限恢复。

没有 Apple／鸿蒙真机系统通知到达测试，鸿蒙当前无连接设备。Windows/Linux 共用源代码已同步，当前本机验证不等同于这两种系统的实际通知投递；各平台安装包状态以发布记录为准。Android 新增可选特殊访问权，若后续提交正式商店审核，应同步核对商店权限说明；本轮不自动修改正式商店审核表单。
