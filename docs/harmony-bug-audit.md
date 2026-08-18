# 鸿蒙（HarmonyOS）平台 BUG 审计报告

> 分支：audit/harmony-bugs（基于 origin/main b8b4987，native/harmony 与 feature/harmonyos@17f9448 一致）
> 范围：native/harmony 鸿蒙客户端（ArkTS/ArkUI，HarmonyOS NEXT 6.1.1 / API 24）
> 方法：逐文件代码审计；关键算术用 Node 复现验证；部分行为在 Pura 90 / Mate X7 / MateBook Pro 模拟器上验证
> 结果：**65 条真实缺陷**（按严重度排序），另附 11 条"核实无误"对照清单
> 说明：每条含 文件:行号；【与iOS一致】表示与参考实现相同的缺陷，但仍是问题

---

## 严重度高

**BUG-001【边界/逻辑】common/StrictDates.ets:120-122 weekdayMonday1 对 1970 年前日期返回非法值**
代码：`return ((e + 3) % 7) + 1;`。JS 负取模：Node 已验证 1969-12-28（周日）返回 0（应为 7）、1968-12-29 返回 0，更早日期可为负数。导致 CalendarFormatters.fullDate/weekdayLabel 对早于 1970 的日期显示空星期或错星期。
建议：`(((e % 7) + 10) % 7) + 1` 并补单测。

**BUG-002【边界/一致】common/StrictDates.ets:135-183 parseFetchedAt 接受 year<=0**
parseDateString（:94）拒绝 `year <= 0`，parseFetchedAt 无此校验：`0000-01-01T00:00:00Z` 会算出合法 epoch（约 -719528 天）而非 null；且 year=0 被 isLeapYear 判为闰年（0%400===0），`0000-02-29` 也被接受。同一日期契约两处解析行为不一致。
建议：解析后校验 `year <= 0 → null`。

**BUG-003【并发/启动】view/RootView.ets:24-27 aboutToAppear 中 launch() 与 refreshClassroomsIfNeeded() 竞态**
launch() 异步（读偏好/ASSET/缓存），紧随其后的 refreshClassroomsIfNeeded() 在凭据尚未加载时执行 refreshClassrooms → credentialsForRequest 抛"请先在设置中填写并保存教务账号和密码。"。已保存凭据的用户每次冷启动都会短暂显示该错误（随后被 launch 的缓存加载覆盖）。iOS 同步初始化无此竞态。
建议：await launch() 完成后再刷新；或让 launch 内部在凭据就绪后触发。

**BUG-004【逻辑/安全】net/HttpUtil.ets:67 响应大小上限按字符数而非字节数**
`body.length > spec.maxBytes` 为 UTF-16 单元数，契约上限是字节数。CJK 密集响应约 1/3 字节即可"合法"绕过上限（多消耗内存）；反之纯 ASCII 会过早拒绝。HolidayClient 的 payload 检查（HolidaySourceParser.ets:13 data.length）同样按字符计。
建议：按 UTF-8 字节数（Utf8.bytes(body).length）比较。

**BUG-005【安全/资源】net/HttpUtil.ets:60-71 响应整体缓冲后才校验大小**
整个响应先读入内存再检查 maxBytes，超大响应在拒绝前已被完整加载（内存 DoS）。iOS 为边读边限流。
建议：分块读取并累计字节数，超限即中止。

**BUG-006【异常】model/AppModel.ets:505-513 restorePersistedSettings 三个无 catch 的 Promise 链**
preferences 读取异常 → 未处理 rejection；鸿蒙端可能触发未捕获异常警告/崩溃，且设置恢复失败无任何提示。
建议：统一 try/catch 并记录。

**BUG-007【并发】model/AppModel.ets:505-519 restorePersistedSettings 与 loadSchedule 的 termID/termStartDate 写回竞态**
两处异步写同一状态：偏好的 .then 可能用旧值覆盖课表缓存加载后的新值，学期信息最终值不确定。
建议：串行化（launch 内部按序 await）。

**BUG-008【并发】model/AppModel.ets:941-975 ensureHolidays 缓存加载与网络刷新竞态**
loadWork（异步读缓存后 set）与 fetch 成功后 set 可交错：旧缓存覆盖新抓取结果；"本地节假日读取失败"状态可在 fetch 成功后残留。
建议：按加载 token/日期做陈旧结果丢弃（参考 refreshClassrooms 的 generation 模式）。

**BUG-009【逻辑】model/AppModel.ets:518 restorePersistedSettings 先于课表加载执行 synchronizeSelectedSlots**
开启"使用个人课表排除已有课程"时，节次联动依赖已加载课表；当前课表加载（异步）完成后不再重新同步 → 冲突节次仍被选中。
建议：课表加载完成后再同步一次。

**BUG-010【一致/网络】net/HolidayClient.ets:42-44 节假日重定向策略与 iOS 主分支不一致**
鸿蒙限定 unpkg.com 同主机重定向；iOS 主分支跟随任意重定向。unpkg 固定版本 URL 未来若重定向到 CDN 主机，鸿蒙端节假日获取失败而 iOS 成功。
建议：与主分支对齐或显式记录取舍。

**BUG-011【边界】net/parsers/SjdScheduleParser.ets:73-94 collectCourses 递归无深度上限**
2MB 上限内可构造深度 >10000 的嵌套结构触发栈溢出（ArkTS 无尾调用优化）；iOS 参考实现有 64 层限制。
建议：增加深度计数上限。

**BUG-049【边界/崩溃】common/Models.ets:81-82 Course.fromJson 不校验 startSlot/endSlot 范围**
缓存/样例数据中 `start_slot` 越界（0 或 >13）时，MobileCalendarTimelineView.ets:354/358 `SlotMetadata.defaults[course.startSlot].start` 访问 undefined 属性 → TypeError 崩溃。解析器有防护（SjdScheduleParser.ets:252），但本地缓存加载路径无校验（ScheduleStore.load 仅校验 termStartDate）。
建议：fromJson 后 clamp/丢弃非法节次。

**BUG-048【边界/逻辑】view/calendar/TeachingCalendarLogic.ets:143-144 年视图移动产生非法日期**
年视图 `movedDate` 直接 `new DateParts(year+direction, month, day)` 不钳制日期：2028-02-29 在年视图点 › 得到 2029-02-29。Node 已验证 epochDay(2029,2,29) == epochDay(2029,3,1)：非法日期被当作 3 月 1 日参与运算，页面显示"2029年2月29日"且星期标签是 3 月 1 日的星期（周四）。月视图有钳制（:153-154）而年视图遗漏。
建议：年视图移动也按目标年 daysInMonth 钳制。

## 严重度中

**BUG-012【资源】view/calendar/MobileTeachingCalendarView.ets:1102 setTimeout 未在 aboutToDisappear 清理**
滚动定位延迟 150ms 触发；离开页面后仍会对已销毁 Scroller 执行 scrollTo。
建议：保存 timer 并在 aboutToDisappear 清除。

**BUG-013【UX】view/calendar/ExpandedTeachingCalendarView.ets:672 跳转面板 position 百分比定位未居中**
`position({ x: '50%', y: '30%' })` 把面板**左上角**放在 50% 处，整体右偏（应为 `x: '50%' + translate(-50%)` 或 `margin: auto`）。
建议：用 align/offset 真正居中。

**BUG-014【UX】view/calendar/MobileTeachingCalendarView.ets:925-926 详情面板 `y:'60%' + height:'40%'`**
小屏/半折叠窗口（高约 700vp）下面板 280vp 高 + 内部 Scroll maxHeight 420 会溢出或遮挡内容；窗口高度变化时不自适应。
建议：改用 `height: '40%'` + 最小高度/底部对齐。

**BUG-015【性能】view/PlannerView.ets:243-244 每个节次格重复计算 personalBusySlots**
每格 chip 调 `personalBusySlots()` 两次（busy + interactive），内部全量遍历课程×节次；课表大时渲染 O(n²)。
建议：在 build 前置算一次并复用。

**BUG-016【异常】model/AppModel.ets:605 preferences.setBool fire-and-forget 无 catch**
偏好写入失败产生未处理 rejection（关闭通知开关路径）。
建议：补 catch。

**BUG-017【资源】common/DeviceState.ets:42 display.on('foldStatusChange') 无注销路径**
Ability onDestroy 未调用 display.off；重复创建/销毁能力实例时监听累积。
建议：提供 off() 并在 onDestroy 调用。

**BUG-018【一致】common/JsonUtil.ets:25-27 string() 对数字返回 fallback**
SJD 客户端 Swift 参考实现兼容 NSNumber（数字转字符串），JsonUtil.string 不兼容 → 上游若传数字字段（如节假日日期为数字），鸿蒙端静默得空值/默认值，语义与 Swift 不一致。
建议：数字也转为字符串。

**BUG-019【边界/一致】net/parsers/HolidaySourceParser.ets:46 名称长度按 UTF-16 计**
Swift 按 unicodeScalars；含 emoji 等代理对的名称在鸿蒙端更快被判"过长"（上限判定不一致）。

**BUG-020【性能】widget/WidgetSync.ets:14-23 + 46-52 refresh 写归档后再次读档解析**
refresh 刚 writeTextAtomic 写入，随后 loadArchive 重新 readText + JSON.parse（绑定数据其实由调用方直接构造）。
建议：refresh 直接构造并返回绑定数据。

**BUG-021【异常】widget/WidgetSync.ets:46-57 loadArchive 解析失败静默返回 null**
归档损坏时卡片降级空态且无日志，问题不可观测。
建议：失败时记录日志/状态。

**BUG-022【UX】view/RootView.ets:22 containerWidth 初始 390 → 宽屏首帧闪 Tabs**
首帧按 390 渲染底部 Tabs，onAreaChange 后才切侧栏；宽屏/2in1 启动时闪一下 tab 栏。
建议：初始值按窗口能力预估或延迟首帧。

**BUG-023【性能】view/PlannerView.ets:266-272/432 todayCourses() 多处重复计算**
ForEach 数据源、分割线条件、汇总行各自调用 todayCourses() 全量重算。
建议：build 内缓存一次。

**BUG-024【一致】view/PlannerView.ets:437/472-474 freeSlotCount 跨午夜不刷新**
自由节次/忙碌节次基于"今天"计算，00:00 后无主动重绘触发（iOS 同缺陷，但鸿蒙无场景刷新机制，页面长时间停留时更明显）。

**BUG-025【一致/能力】notify/DailyCoursePlanning.ets:37 通知上限 30 条（iOS 为 63）**
reminderAgentManager 全局上限 30：课表密集时"已安排未来 N 个有课日"的 N 上限不同（已注释，属平台能力差异，但用户可见语义不同）。

**BUG-026【UX】view/SettingsView.ets:315-317 "浏览内置示例数据"按钮在日历导入进行中无禁用态**
iOS 在 isImportingCalendar 时禁用该入口；鸿蒙端仍可点击（enterReviewDemo 内部有 guard，但无反馈）。
建议：加 disabled 或提示。

**BUG-027【异常/可诊断性】store/HolidayStore.ets:67-75 解析失败统一抛"本地节假日缓存格式不正确"**
decode 过程中更细的错误（:124/:128/:133 根对象/items/条目格式）在调用链上层被替换为通用文案，排障信息丢失（Swift 会保留细分错误）。

**BUG-028【权限】calendar/CalendarImporter.ets:28-36 一次性同时申请读写日历权限**
读取仅在同步比对时使用；iOS 按需分别申请。可最小化为仅写权限（先 WRITE）。
建议：按操作类型拆分权限申请。

**BUG-029【异常】calendar/CalendarImporter.ets:27-36 requestAccess 失败统一返回 false**
系统弹窗被拦截/服务异常/用户拒绝全部表现为 permissionDenied，无法区分"被拒"与"系统错误"（iOS 区分错误与拒绝）。
建议：区分拒绝与错误。

**BUG-030【一致】calendar/CalendarImporter.ets eventMatches 时区严格等于 Asia/Shanghai**
鸿蒙日历事件若 timeZone 字段缺失（null）则永不匹配 → 每次同步都更新事件（无法保持 unchanged）。与 iOS 相同要求，记录。

**BUG-031【异常】calendar/CalendarImporter.ets:93-114 删除/更新失败统一报"系统日历在同步期间发生变化"**
错误归因不准确（可能为权限/IO 错误），可诊断性差。
建议：按错误码细分文案。

**BUG-032【发布】AppScope/app.json5:7 应用图标为普通 PNG（app_icon.png）**
应用级图标未使用分层图标（module 级有 layered_image.json，AppScope 仅单层 PNG）。鸿蒙 6.1 桌面图标规范要求前景+背景分层，普通 PNG 可能被裁剪/变形。

**BUG-033【一致】module.json5:30-31 + entryability/EntryAbility.ets:28-32 最小窗口 400×640 重复定义且偏小**
两处各定义一次（保持一致但冗余）；400vp 宽下 planner 单列拥挤、日历时间线不可用。建议收敛到单一来源并评估提高下限。

**BUG-034【测试】scripts/native-harmony-ui-smoke.sh:97/145 手机/宽屏分段依赖第 2 个参数 'wide'**
不传参数时在宽屏设备上会跑手机段断言（全部失败），无设备类型检测与提示。

**BUG-035【测试】scripts/native-harmony-ui-smoke.sh:28-33 dump_layout 不检查 dump/recv 是否成功**
uitest dumpLayout 失败（无前台窗口等）时 recv 旧文件或空文件，断言基于过期布局，结果不可信。

**BUG-036【测试】entry/src/test/List.test.ets:11-19 测试套件手工注册**
新增测试文件忘记在此注册即不会被运行（无自动发现机制）。
建议：加注册校验脚本。

**BUG-037【边界】common/StrictDates.ets:126-132 formatFetchedAt 对年份 ≥10000 输出 5 位**
"10000-01-01T00:00:00+08:00" 共 26 字符，parseFetchedAt 只接受 20/25 → 自己输出无法被自己解析（契约破坏）。
建议：限定年份范围。

**BUG-038【并发/网络】model/AppModel.ets:864-894 + view/RootView.ets:27/32 启动时重复拉取空教室**
aboutToAppear 与 onPageShow 各调一次 refreshClassroomsIfNeeded；isRefreshingClassrooms 守卫在 credentialsForRequest await 之后才置位（:894），两次调用会并发发起重复请求（token 检查防状态错乱，但网络请求重复、状态消息被覆盖）。
建议：入口加同步守卫或去抖。

**BUG-039【测试】model/LaunchSupport.ets:73/87 ui-tests 偏好域不清空**
iOS 先 removePersistentDomain 再建模型；鸿蒙 ui-tests 域残留状态（开关等）跨测试污染，测试不稳定。
建议：测试启动前清空域。

**BUG-040【一致】widget/TodayCourseWidgetData.ets:92 卡片内容固定最多 3 行**
2*2/2*4/4*4 三种尺寸绑定数据相同（3 行 + "另有 N 门"）；4*4 大卡片信息量浪费。iOS 按 family 区分 courseLimit。
建议：按卡片尺寸差异化。

**BUG-041【一致】net/parsers/HolidaySourceParser.ets 非对象日期条目错误文案不同**
dates 数组元素非对象时 JsonUtil.record 返回 {} → 报"节假日名称不能为空"（Swift 解码失败报"格式不正确"）—— 行为都失败但归因不同。

**BUG-042【逻辑】net/parsers/SjdClassroomParser.ets:284-285 nodeNameToSlot 取首个数字**
节点名如 "2-3节" → slot 1 正确；若含多余数字（"教室12"）→ 取 "12" → slot 11，语义脆弱（与 iOS 相同正则，记录）。

**BUG-043【一致】net/parsers/SjdScheduleParser.ets:113 weekday 取 weekDay 首字符**
weekDay="5（周一）" → 5 ✓；weekDay 为中文"周五" → charAt(0)='周' → NaN → 整门课被丢弃。与 iOS（wholeNumberValue 同样失败）一致，但静默丢课无提示。
建议：解析失败时计入统计/提示。

**BUG-044【逻辑】net/parsers/SjdClassroomParser.ets:159-163 教室名多个括号只取第一处数字为 size**
教室名含"（旧）与（新）"多处数字时只取第一处（与 iOS 一致，记录）。

**BUG-045【UX/主题】view/RootView.ets:133 侧栏选中背景硬编码 '#24000000'**
深浅色模式相同透明度黑色；深色模式下对比不足。
建议：使用主题资源。

**BUG-046【性能】view/calendar/MobileCalendarTimelineView.ets:377-390 placeCourses 每格重复计算**
blockTrackCount/blockTrackWidth 对每个课程块重新执行 placeCourses（O(n²)）；课程多时渲染卡顿。
建议：按天预计算 placement 并缓存。

**BUG-047【发布】common/AppMeta.ets:4 版本号与 AppScope/app.json5 versionName 双源**
两处手写 0.1.6，构建脚本无一致性校验；发布时可能版本漂移（iOS 从 Info.plist 读单一来源）。
建议：构建时注入或校验。

## 严重度低

**BUG-050【一致/资源】model/AppModel.ets:611-613 + notify/DailyCoursePlanning.ets:179 通知开启时每次回到前台全量重排提醒**
onPageShow → refreshDailyCourseNotificationAuthorization → reconcile → coordinator.reconcile 末尾无条件 replacePending → DailyCourseNotifications.ets:46 先 cancelAllReminders 再逐条重发（最多 30 条）。每次前台切换都全量取消+重发，系统 IPC 频繁；cancelAllQuietly 吞掉失败时还会产生重复提醒。
建议：持久化已发布提醒指纹，仅在有变化时重排。

**BUG-051【异常】notify/DailyCourseNotifications.ets:117-139 withTimeout 超时后底层 Promise 仍继续**
超时仅 reject 外层；publishReminder 仍可能稍后成功 → 用户看到"失败"但提醒实际已安排（或相反）。
建议：超时后结果落盘对账。

**BUG-052【性能/资源】view/RootView.ets:147-166 Tabs 模式三页常驻**
TabContent ForEach 同时挂载 Planner/Calendar/Settings 三个页面：各页 aboutToAppear/ensureVisibleHolidays 启动即执行；MobileCalendarTimelineView.ets:66-68 的 30s setInterval 在日历 tab 隐藏时仍运行。
建议：懒加载 TabContent 或暂停后台定时器。

**BUG-053【主题】多处硬编码颜色，深浅色不自适应**
MobileTeachingCalendarView.ets:407 状态条 '#14166B5D'、:687 '+N' '#C766B5B5'、:706 事件胶囊 '#C7FFFFFF'；ExpandedTeachingCalendarView.ets:370/452 同款；TodayCourseCard.ets:20-25/73 '#1A1A1A'/'#F2F4F6'。深色模式下样式与主题组件不一致。
建议：统一走 AppTheme/资源。

**BUG-054【主题/卡片】entry/src/main/resources/base/profile/form_config.json:13 colorMode auto + TodayCourseCard 固定浅色**
卡片声明自适应颜色模式但 UI 全用浅色值：深色模式下卡片仍是浅色背景，突兀。
建议：卡片使用系统资源色。

**BUG-055【性能】六处 @Consumer('appModel') 默认 new AppModel()**
RootView.ets:20 / SettingsView.ets:10 / CalendarSectionView.ets:12 / MobileTeachingCalendarView.ets:32 / ExpandedTeachingCalendarView.ets:31 / PlannerView.ets:20 —— 每个组件首帧在 Provider 值到达前各构造一个临时 AppModel（构造函数实例化 11 个 store/客户端对象，AppModel.ets:206-233）。每次启动产生 6 个废弃实例。
建议：共享单例或惰性初始化默认值。

**BUG-056【逻辑】多处 ForEach 以 course.id 为键，重复课程 id 冲突**
MobileTeachingCalendarView.ets:486-500/982-1003、ExpandedTeachingCalendarView.ets:697-717 用 'summary(-course).'+course.id；id 是 12 位 sha1 摘要（SjdScheduleParser.ets:148），课表含两行相同字段（同一门课重复行）时键冲突 → ArkUI 重复键告警与渲染异常。
建议：键加行下标。

**BUG-057【UX】view/calendar/ExpandedTeachingCalendarView.ets:216-220 内容 maxWidth 1200 左对齐**
≥1200vp 窗口下内容贴左，右侧大片空白（iOS 居中）。
建议：水平居中。

**BUG-058【UX】view/calendar/ExpandedTeachingCalendarView.ets:342 timelineContent 固定高度 720**
窗口高度低于 720+头部时产生双重滚动（页面滚 + 内部滚）；窗口高度变化不响应。
建议：按窗口高度计算。

**BUG-059【逻辑】两处状态条 ForEach 键 'status.' + message 可能重复**
MobileTeachingCalendarView.ets:402 / ExpandedTeachingCalendarView.ets:201 —— model.statusMessage 与 calendarImportStatusMessage 文本相同或同一消息重复时键冲突。

**BUG-060【异常】model/AppModel.ets:673-682 clearLocalData 未等待提醒取消**
cancelDailyCourseNotifications()（:682）fire-and-forget，紧接着清空凭据/课表；取消失败（代理不可用）时旧提醒残留到下次对账（对账可能因凭据已清而不再执行）。
建议：await 取消结果并重试。

**BUG-061【测试】scripts/native-harmony-ui-smoke.sh:78-82 硬编码设备坐标修正**
底部导航点击依赖 y>2740 的钳制（针对 Pura 90 分辨率注释），其他分辨率设备上坐标断言失效。
建议：从布局相对位置推导点击点。

**BUG-062【一致/边界】net/SjdEncoding.ets:79-88 与 common/Utf8.ets:42-49 孤立代理对编码为非法 UTF-8**
`code in D800-DBFF` 且下一字符不是低代理时走 3 字节分支，产出无效 UTF-8 字节；Swift addingPercentEncoding 对孤立代理输出 U+FFFD。表单编码/摘要输入含孤立代理对时结果不一致。
建议：孤立代理替换为 U+FFFD。

**BUG-063【一致】notify/DailyCourseNotifications.ets:40-41 超过 30 条静默截断**
batch 直接 slice(0,30)，超出部分无提示；与 iOS 63 条上限相比更早截断且用户不可见。
建议：截断时给出状态提示。

**BUG-064【UX】view/calendar/ExpandedTeachingCalendarView.ets:167-192 窄宽屏（760-820vp）头部拥挤**
PageTitle + 4 个模式按钮（64×4）+ 间距在 760vp 详情宽度下无收缩策略，标题可能截断/溢出。
建议：窄宽屏隐藏 eyebrow 或换行。

**BUG-065【一致/资源】model/AppModel.ets:1146 WidgetSync.refresh 每次课表变更都重写归档**
刷新/导入/清除都会写卡片归档文件；即使卡片数据未变化也全量写。可先比较再写。

---

## 附录：核实无误清单（排除项）

以下疑点在本次审计中逐一验证为**正确实现**，未计入缺陷数：

1. **SjdEncoding.encodeComponent 代理对编码** —— 正确处理高低代理对（surrogate pair → 4 字节），测试向量通过。
2. **HolidayStore.ets:142-150 exactKeys** —— 键排序后逐一比较，正确。
3. **SjdScheduleParser.ets:55 classTime dropFirst** —— 与 iOS substring 语义一致。
4. **SjdScheduleParser.ets:170+ normalizeCourseRoom '教3-335'** —— 前缀 '教' 剥离与 iOS 一致。
5. **SjdClassroomParser parseCampus 非对象跳过** —— 与 iOS `for case let item as [String:Any]` 等价。
6. **HolidaySourceParser 未知类型 continue 跳过** —— 与 iOS 一致（全部未知时报错）。
7. **CalendarImportLogic weekNumbers 为空不生成草稿 + maximumWeek 兜底** —— 与 iOS 一致。
8. **TeachingCalendarLogic.ets:146-156 addMonths 日钳制** —— 正确处理月末/闰月。
9. **AppModel.ets:757-782 refreshSchedule 持久化 fallback 学期** —— 成功路径确实写回 preferences（:781-782）。
10. **AppModel.ets:783 状态消息 autoDismiss revision 竞态** —— revision 递增保证旧定时器不误清新消息。
11. **AppModel.ets:904-926 refreshClassrooms 陈旧结果丢弃** —— generation + refreshToken 双重校验正确。

---

## 统计与建议优先级

- 高严重度 12 条（日期边界 2、启动/并发 4、网络/内存 3、递归 1、崩溃 1、非法日期 1）
- 中严重度 36 条、低严重度 17 条，合计 **65 条**
- 建议首批修复：BUG-001/002/048（日期正确性）、BUG-003/038（启动竞态）、BUG-049（崩溃）、BUG-050（提醒风暴）、BUG-004/005（网络上限）
- 修复后可回归：45 项单元测试 + UI 冒烟（Pura 90 / Mate X7 / MateBook Pro）
