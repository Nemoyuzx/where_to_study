# 鸿蒙（HarmonyOS）平台 BUG 审计报告

> 分支：audit/harmony-bugs（基于 origin/main b8b4987，native/harmony 与 feature/harmonyos@17f9448 一致）
> 范围：native/harmony 鸿蒙客户端（ArkTS/ArkUI，HarmonyOS NEXT 6.1.1 / API 24）
> 方法：逐文件代码审计；关键算术用 Node 复现验证；部分行为在 Pura 90 / Mate X7 / MateBook Pro 模拟器上验证

---

## 修复记录（fix/harmony-audit-issues）

> 修复分支：fix/harmony-audit-issues（基于 audit/harmony-bugs）。每条按修复方式标注：
> ✅=代码修复 + 单测验证；🔧=代码修复（构建验证）；📋=行为核对后确认无需修改/保持与 iOS 一致；⏳=待处理。

### 已修复（代码改动）

| 编号 | 修复内容 | 方式 |
|---|---|---|
| BUG-001 | StrictDates.weekdayMonday1 负纪元归一化 `(((e % 7) + 10) % 7) + 1`，新增 1970 前日期单测 | ✅ |
| BUG-002 | parseFetchedAt 增加 `year <= 0 → null`，与 parseDateString 一致；新增单测 | ✅ |
| BUG-003 | RootView 不再直接并行调用；refreshClassroomsIfNeeded 等待 launchPromise 完成 | 🔧 |
| BUG-004 | HttpUtil 改用 ArrayBuffer 按字节校验上限（`byteLength > maxBytes` 拒绝），不再按 UTF-16 字符数；HolidayStore/HolidaySourceParser 同步改字节计数 | 🔧 |
| BUG-005 | 超限响应在解码前拒绝（ArrayBuffer 分支不执行 TextDecoder）；系统级缓冲无法避免，已注明 | 🔧 |
| BUG-006 | restorePersistedSettings 改为 async + 逐段 try/catch | 🔧 |
| BUG-007 | restore 串行 await，消除与 loadSchedule 的写回竞态 | 🔧 |
| BUG-009 | synchronizeSelectedSlots 移到 loadSchedule 完成之后 | 🔧 |
| BUG-011 | collectCourses 增加 64 层深度上限（对齐 iOS） | 🔧 |
| BUG-012 | 时间线延迟滚动 setTimeout 保存句柄，aboutToDisappear 清理 | 🔧 |
| BUG-013 | 宽屏跳转面板 `translate({x:'-50%'})` 真正水平居中 | 🔧 |
| BUG-014 | 移动端详情面板内 Scroll 改 layoutWeight(1)，随面板高度自适应 | 🔧 |
| BUG-015 | PlannerView busySlotsValue 缓存（@Monitor 驱动），slotChip 不再重复计算 | 🔧 |
| BUG-016 | preferences.setBool 关闭路径补 catch | 🔧 |
| BUG-017 | DeviceState.detach() 注销折叠监听，EntryAbility.onDestroy 调用 | 🔧 |
| BUG-018 | JsonUtil.string 兼容数字（对齐 Swift NSNumber）；新增单测 | ✅ |
| BUG-019 | HolidaySourceParser 名称长度按 Unicode 码点计数；新增单测 | ✅ |
| BUG-021 | WidgetSync 归档解析失败增加 hilog 日志 | 🔧 |
| BUG-022 | RootView containerWidth 初始值改用 DeviceState.screenWidthVp()（新增） | 🔧 |
| BUG-023 | PlannerView todayCoursesValue 缓存（@Monitor 驱动） | 🔧 |
| BUG-024 | PlannerView 60s 定时器检测跨午夜，刷新日期文本并重算派生数据 | 🔧 |
| BUG-026 | SettingsView borderedButton 增加 interactive 参数；浏览示例按钮在导入中禁用 | 🔧 |
| BUG-029 | CalendarImporter.requestAccess 系统异常抛 systemError（新增工厂），与用户拒绝区分 | 🔧 |
| BUG-031 | 日历写入/删除/更新失败按操作归因（operationError），不再统一"同步期间发生变化" | 🔧 |
| BUG-032 | AppScope 增加分层图标（background/foreground/layered_image.json），app.json5 引用 | 🔧 |
| BUG-034 | 冒烟脚本按首屏是否出现侧栏自动选择手机/宽屏段；显式参数可覆盖 | 🔧 |
| BUG-035 | dump_layout 校验 dump/recv 结果，失败显式提示并返回非零 | 🔧 |
| BUG-036 | 构建脚本校验全部 src/test/*.test.ets 已注册进 List.test.ets | 🔧 |
| BUG-037 | formatFetchedAt 年份钳制 1..9999，保证输出可回读；新增单测 | ✅ |
| BUG-038 | refreshClassrooms 同步 in-flight 守卫（credentials await 前置位），杜绝重复请求 | 🔧 |
| BUG-039 | UI 测试偏好域（ui-tests/ui-tests-live）启动时 clearAll 隔离 | 🔧 |
| BUG-043 | weekday 解析兼容中文"周X/星期X"，不再静默丢课 | 🔧 |
| BUG-045 | 侧栏选中背景改用主题资源 app_selection（深浅色独立 alpha） | 🔧 |
| BUG-046 | 课程布局每轮渲染一次计算（placementsFor），父组件传入 @Param，消除 O(n²) | 🔧 |
| BUG-047 | 构建脚本校验 AppMeta.version 与 app.json5 versionName 一致 | 🔧 |
| BUG-048 | 年视图 movedDate 按目标年钳制日（2/29 → 2/28）；新增单测 | ✅ |
| BUG-049 | Course.fromJson 钳制 startSlot/endSlot/weekday 范围；新增单测 | ✅ |
| BUG-050 | 通知对账增加"当日已对账且无变化"门控，回前台不再全量取消重发；开关/课表变化置脏 | 🔧 |
| BUG-052 | 时间线 30s 定时器随 onVisibleAreaChange 启停 | 🔧 |
| BUG-056 | 课程列表 ForEach 键加行下标（summary-course.id.index） | 🔧 |
| BUG-057 | 宽屏内容列 alignSelf(ItemAlign.Center) 居中 | 🔧 |
| BUG-058 | 宽屏时间线高度随视口自适应（contentHeight - 280，下限 360） | 🔧 |
| BUG-059 | 状态条 ForEach 键加下标（status.index.message） | 🔧 |
| BUG-060 | cancelDailyCourseNotifications 返回 Promise；clearLocalData/账号切换路径等待/捕获 | 🔧 |
| BUG-061 | 冒烟脚本底部导航点击改为相对偏移修正（y-65），去掉单设备绝对钳制 | 🔧 |
| BUG-062 | Utf8.bytes 与 SJDFormURLEncoder 孤立代理替换 U+FFFD（对齐 Swift）；新增单测 | ✅ |
| BUG-064 | PageTitle 标题 maxLines(1) + Ellipsis，窄宽屏不溢出 | 🔧 |

### 核对后无需改动（📋）

| 编号 | 结论 |
|---|---|
| BUG-010 | 节假日重定向限制 unpkg.com 是有意为之的安全策略；与主分支差异已在 HolidayClient 注释记录，保持 |
| BUG-020 | 当前代码 refresh 只写归档 + 通知卡片重载，无"写后重读"路径（原报告描述与现码不符，作废） |
| BUG-025 | 30 条上限为 reminderAgentManager 平台能力约束，已在 DailyCoursePlanning 注释说明 |
| BUG-027 | decode 的细分错误（根对象/items/条目）本来就逐层抛出，仅 JSON.parse 失败走通用文案（合理），无需改动 |
| BUG-028 | 同步导入同时需要读（getEvents 比对）与写，拆分申请不成立，保持 |
| BUG-030 | 时区严格匹配与 iOS 一致，保持 |
| BUG-033 | module.json5 与 EntryAbility.setWindowLimits 双处定义且数值一致，属声明式+运行时双保险，保持 |
| BUG-041 | 非对象日期条目先命中 date/type 缺失检查（"节假日数据格式不正确"），行为正确，作废 |
| BUG-042/044 | 教室名/节次解析首数字策略与 iOS 正则一致，保持 |
| BUG-053/054 | 卡片与状态条颜色为深浅色统一的可读色（浅色卡片在深色桌面亦清晰），保持现状，待 UI 走查再议 |
| BUG-055 | @Consumer 默认实例仅构造轻量对象、无副作用，启动期短暂存在，属可接受开销，保持 |
| BUG-063 | 超出 30 条时按序保留前 30 条属合理降级（与 iOS 截断策略一致），保持 |
| BUG-065 | 归档写入为幂等小文件（<10KB），写前比较收益低，保持 |

### 待处理（⏳）

| 编号 | 说明 |
|---|---|
| BUG-040 | 卡片按尺寸差异化行数需 formDimension 传递，涉及卡片运行时改动，下一轮处理 |
| BUG-051 | withTimeout 底层 Promise 残留需持久化对账，下一轮处理 |
