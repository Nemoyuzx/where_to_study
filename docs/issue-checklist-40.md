# 全代码库问题清单（40+）

> 生成于对 main 分支（b8b4987）的全面审查。严重程度：
> 🔴 高（真实逻辑 bug）| 🟡 中（行为不一致/健壮性）| 🟢 低（代码质量/优化）

## Rust 后端（src-tauri/src/）

| # | 严重度 | 位置 | 问题 |
|---|--------|------|------|
| 1 | 🟡 | auth.rs:21 | ServiceError.with_status(message, status_code) 接收状态码但完全忽略（参数 _status_code）。调用方期望的 HTTP 状态语义丢失，前端无法区分 400/401/500 |
| 2 | ✅ | schedule.rs:20 | expand_week_numbers 按条目处理单/双标记，混合奇偶周都保留 |
| 3 | ✅ | schedule.rs:167 | ~~parse_sjd_slots skip(1) 假设~~ 已澄清：SJD classTime 格式为"节数+节次编号"（如 1030405），skip(1) 是正确解析；已补充格式注释 |
| 4 | 🟢 | schedule.rs:255 | endTIme（错误拼写）在 endTime（正确）之前被优先查询，代码异味 |
| 5 | ✅ | schedule.rs:279 | 单节课程 section_text 已改为"3节" |
| 6 | 🟡 | schedule.rs:133 | parse_sjd_week_numbers 兜底从 classWeekDetails 提取所有数字，若含年份等非周次数字会误解析 |
| 7 | 🟢 | schedule.rs:277 | course_id 用 SHA1 前 12 位（6 字节），大量课程时碰撞概率非零且不可重试 |
| 8 | 🟡 | schedule.rs:340 | infer_term_start_date 解析失败时静默回退 fallback 日期，用户设置的第一周日期被静默覆盖 |
| 9 | 🟢 | models.rs:57 | SavedSettings.with_defaults 硬编码 CAMPUSES[0]，新增校区时默认值需手动改 |
| 10 | 🟢 | lib.rs:1650 | .icon_as_template(true) 是 macOS-only（tray-icon 标注），Windows/Linux 上为静默 no-op |
| 11 | ✅ | lib.rs:1039 | fetch_classrooms 现在明确拒绝非今天日期，不再静默覆盖 |
| 12 | 🟡 | lib.rs:1658 | keep_main_window_in_tray 关闭窗口直接隐藏到托盘，无二次确认；若托盘初始化失败用户无法恢复窗口 |
| 13 | 🟢 | lib.rs:1140 | 课程小组件窗口 .position(24.0, 80.0) 硬编码，多显示器/高分屏下位置固定不跟随主窗口 |

## Web 前端（src/）

| # | 严重度 | 位置 | 问题 |
|---|--------|------|------|
| 14 | ✅ | planner-domain.js:186 | dateFromString 已严格校验 yyyy-MM-dd，拒绝不可能日期 |
| 15 | ✅ | planner-domain.js:64 | msUntilNextShanghaiMidnight 已改为 UTC 算术，任意时区正确（三时区测试通过） |
| 16 | 🟡 | planner-domain.js:254 | buildMonthDays/月历构建用本地时区，todayDate 用上海时区——非中国时区设备上"今天"高亮与今天日期可能差一天 |
| 17 | 🟢 | planner-domain.js:397 | slotsToRanges label 仅时间（"08:00-09:35"），Swift 端显示"第 1-2 节 08:00-09:35"，跨端显示不一致 |
| 18 | 🟢 | planner-domain.js:50 | fallbackHolidayItems 硬编码 2026 年，2027 年后离线模式无任何节假日数据（Rust 端同样硬编码） |
| 19 | ✅ | App.jsx:917,951 | 加载错误现在显示给用户 |
| 20 | ✅ | App.jsx:937 | 自动获取失败后允许稍后重试 |
| 21 | 🟢 | App.jsx:800 | calendarPopover 关闭时直接置 null，只有进入动画（popover-in）没有退出动画 |
| 22 | ✅ | App.jsx:74 | 隐私对话框打开聚焦关闭按钮，关闭恢复焦点到触发按钮 |
| 23 | ✅ | App.jsx:2406 | 清除确认打开时聚焦取消按钮 |
| 24 | 🟢 | App.jsx:547 | touchmove 监听 effect 空依赖，updateCalendarSwipe 闭包捕获首次渲染值（当前依赖 ref 恰好安全，但脆弱） |
| 25 | 🟢 | App.jsx:1955+ | day/week 视图渲染中每个日期调用 getWeekState（7 次/渲染），无 useMemo 缓存 |
| 26 | 🟢 | App.css | 重复选择器：.summary-band x4、.campus-options button x4、.calendar-today-button x2、.settings-layout x2 等，维护风险 |
| 27 | 🟢 | App.jsx:1448 | 小组件隐藏按钮无确认，误点直接关闭 |
| 28 | 🟡 | App.jsx:1017 | 保存设置成功后 setQueryCampusId(nextSettings.campusId) 同步查询校区；Swift 端 saveSettings 不更新 queryCampusID——跨端行为不一致 |
| 29 | 🟢 | App.jsx:556 | 并发任务时 loading 显示最后一个任务名，被禁用按钮的文本与禁用态不一致（显示"获取空教室信息"但已禁用） |

## Swift 原生（native/apple/）

| # | 严重度 | 位置 | 问题 |
|---|--------|------|------|
| 30 | 🟢 | TeachingCalendarView.swift:999 | TimeZone(identifier: "Asia/Shanghai")! force unwrap（常量安全但代码异味） |
| 31 | 🟡 | HolidayClient.swift:225 | contractDateFormatter.isLenient = false 拒绝非法日期，而 Web 端 dateFromString 会纠正非法日期——前后端日期校验行为不一致 |
| 32 | 🟢 | 三端 | 时间戳格式不一致：Swift ISO8601 默认 UTC（Z）、Rust now_in_app_tz 输出 +08:00、Web contractTimestamp 输出 Z。缓存交叉验证时需注意 |
| 33 | 🟢 | MacMenuBarView.swift:108 | dateFormatter 每次调用创建新实例（性能） |
| 34 | 🟢 | ClassroomClient.swift:48 | formatter(_:) 每次调用创建新 DateFormatter（性能） |
| 35 | 🟡 | AppModel.swift:421 | saveSettings 后 queryCampusID 不更新（Web 端会），用户保存默认校区后 Planner 查询校区不变，跨端不一致 |
| 36 | 🟢 | PlannerView.swift:495 | DesktopColumnLayoutPolicy.widths 固定 1/3 + 2/3 比例，无最小/最大约束，窄窗口下控制面板可能过窄 |

## 测试与 CI

| # | 严重度 | 位置 | 问题 |
|---|--------|------|------|
| 37 | 🟡 | theme-contract.test.js:196 | msUntilNextShanghaiMidnight 测试用 15:59Z（上海 23:59），在 UTC+8 时区才精确通过；其他时区下断言 60000 恰好巧合成立或失败，掩盖了函数本身的跨时区 bug |
| 38 | 🟡 | planner-domain.test.js | 无非法日期（2026-02-30）测试，dateFromString 纠正行为未被发现 |
| 39 | 🟢 | planner-domain.test.js | 无跨时区测试（用 TZ 环境变量跑用例） |
| 40 | 🟢 | build-windows.yml | 仅验证安装后文件存在，无 UI smoke 测试（对比 build-macos.yml 有导航测试） |
| 41 | 🟡 | index.html | 无 CSP meta 标签，浏览器 preview 模式下（非 Tauri）依赖 vite dev 注入，npm run preview 生产预览无 CSP 保护 |
| 42 | 🟢 | vite.config.js:32 | watch.ignored 仅排除 src-tauri，Rust 改动不会触发前端 HMR（tauri dev 自行处理，但纯 vite dev 时无感知） |
| 43 | 🟢 | package.json | 构建脚本间许可校验不一致：macos-package.sh 有 licenses:check 前置，windows CI 依赖 npm run licenses:check 步骤 |
| 44 | 🟡 | 全局 | 桌面自动刷新仅检查 settings.account.hasSavedPassword，若 Keychain 中凭据被系统清除（如系统更新后），自动刷新持续失败且无用户提示 |

## 修复建议优先级

1. **立即修复**：#14（日期纠正）、#15（跨时区）、#1（状态码）、#11（target_date 覆盖）
2. **值得修复**：#2、#3、#19、#20、#22、#23、#28、#31、#35、#37
3. **后续优化**：#5、#9、#10、#17、#18、#21、#24、#25、#26、#33、#34、#36

## Windows 专项新增问题（事件绑定与动画）

| # | 严重度 | 位置 | 问题 | 状态 |
|---|--------|------|------|------|
| W1 | 🟡 | App.jsx day/week 视图 | 仅有 touch 事件，Windows 鼠标用户无法拖拽翻页 | ✅ 已加 pointer swipe |
| W2 | 🟡 | App.jsx 日历页 | 无横向滚轮/触控板滑动支持 | ✅ 已加 wheel 处理器 |
| W3 | 🟡 | App.jsx year 视图 | 双击日期先触发两次单击（选中+打开 popover 后再打开月视图） | ✅ 单击延迟 250ms |
| W4 | 🟢 | App.jsx popover | 右键点击也会关闭 popover（context menu 误关） | ✅ 仅左键关闭 |
| W5 | 🟢 | App.jsx 隐私对话框 | 右键点击背景也会关闭 | ✅ 仅左键关闭 |
| W6 | 🟢 | App.css month-view | height 动画无 will-change，Windows WebView2 掉帧 | ✅ 已加 will-change |
| W7 | 🟢 | App.jsx resize | resize 处理器无防抖，拖动窗口时频繁重算布局 | ✅ rAF 防抖 |
| W8 | 🟢 | App.jsx 设置输入框 | Enter 键不提交表单（Windows 键盘用户习惯） | ✅ 已加 Enter 提交 |
| W9 | 🟢 | index.css | 无 forced-colors（Windows 高对比度）支持 | ✅ 已加 |
| W10 | 🟢 | App.css | 日历拖拽区域无 user-select: none，拖拽时选中文本 | ✅ 已加 |
| W11 | 🟢 | lib.rs 关闭窗口 | 关闭窗口隐藏到托盘无提示，Windows 用户困惑 | ✅ 已加首次提示 |
| W12 | 🟡 | App.jsx week 视图 | 周视图缺少当前时间线（Swift 端有） | ✅ 已修复 |
| W13 | 🟢 | index.css | 主题切换（明/暗）无过渡 | ✅ 已加 |
| W14 | 🟢 | index.css | focus ring 出现无过渡 | ✅ 已加 |
| W15 | 🟢 | App.jsx 清除确认 | 打开时焦点不移动 | ✅ 已加 |
| W16 | 🟡 | App.jsx month 手势 | month-expansion-handle 点击与拖拽冲突风险 | ✅ suppressCalendarClickUntilRef 已有 |
