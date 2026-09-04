# v0.2.8 正式发布检查点（2026-09-03）

## 当前状态

- 分支：`main`
- 当前稳定版本：[Where To Study v0.2.8](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.2.8)；GitHub Release 已转为正式版并更新 `releases/latest`
- 应用版本：`0.2.8`
- 当前构建号：Apple `CURRENT_PROJECT_VERSION=77`；Android `versionCode=45`；HarmonyOS `versionCode=1002018`；Tauri Android `versionCode=2011`
- 教务数据源：只使用现有移动教务 SJD HTTPS 接口，没有切换或静默回退到其他数据源
- 本地安装：发布构建不会自动安装到 `/Applications`；Apple UI 验证完成后已关闭测试模拟器，Android 签名打包未启动模拟器
- 发布边界：iOS 与 macOS build 77 均由本地 Xcode 上传，macOS 已收到 `Validated signed archive`、`EXPORT SUCCEEDED` 与 `Upload succeeded`，按约定不检查 App Store Connect processing；HarmonyOS 1002018 已由 DevEco 上传且云测试通过，只通过 AppGallery Connect 分发。GitHub 正式版固定为 11 项公开附件，不含 Android AAB、HarmonyOS APP/HAP、iOS、`.sha256` 或原生 macOS ZIP；Android APK 已从 `49f23bc` 重新构建并替换，远端下载后与本地签名包逐字节一致，其余 10 个附件未改变。项目按 GPL-3.0-only 开源

## 本次完成内容

### 共享业务规则

- 固化 `contracts/v1` 的课表、空教室和法定节假日契约及脱敏夹具。
- Rust、Swift、Kotlin 统一教室解析：普通教室保留三位号，`202-203`、`217-218` 等双门号码保持为同一间教室。
- 空教室严格只查询当天，保留原教学楼集合；个人课表页面不会跳转到联动查询；“推荐同一教室”已移除。
- 个人课表查询后按账号范围持久化；公历周统一使用 ISO 8601 并与教学周并列显示，不再推断或标注考试周。
- 法定节假日自动读取固定版本 `holiday-calendar@1.3.3` 的中国年度数据，严格校验后缓存，并提供 2026 年离线兜底。

### Tauri / Windows / Linux

- 保留 Tauri 2 + React + Rust 作为 Windows/Linux 客户端，并继续提供迁移期 macOS 构建。
- Linux 使用 Ubuntu 22.04 原生 CI 生成 x86_64 Debian 包和 AppImage；Tauri 图形端凭据保存在 Secret Service，独立 TUI 使用用户私有本地文件，打包脚本验证 Tauri 实际检测到的 GTK/WebKitGTK/托盘依赖，并在 Ubuntu 24.04 上安装生成的 Debian 包。
- 完成空教室、教学日历、设置、教学楼/三位教室号、个人课表联动、系统日历导入和托盘；Windows/Linux 不提供课程小组件。
- 教学日历保留绿白配色，支持日/周/月/年、整点与 14 个节次、当前时间红线、节假日、年视图课程热度及日期日程浮层。
- 托盘提供今日/明日课程；关闭主窗口后保持运行；启动和每天 07:00 获取当天空教室；课程摘要默认关闭，用户显式开启后才在 07:30 发送。
- 为每个账号生成不含账号信息的随机不透明缓存作用域；账号切换、清除或持久化失败时采用失效代次和撤销标记拒绝旧数据。
- 设置与安全凭据提交具备回滚；WebView 不接收密码；已删除 Tauri 课程浮窗及其权限和事件面。
- Tauri 空教室、教学日历和设置页与原生 macOS 保持同样的布局与卡片层级，并补齐课程提醒开关和学期自动检测。
- 导航条已增加位于教学日历和设置之间的独立查询页；班车只展示上海当天 active 时刻表，重要事件合并公开活动与校内通知、排除作业，支持元数据搜索、真实分类、DDL 升序与完整本地收藏。会议作为唯一开启类型时也会驱动年度预热、跨年加载、月详情和重试。
- 重要事件首批渲染 20 条，接近底部自动追加 20 条；筛选代次同步失效旧批次，视图追加完全复用本地缓存，不触发新网络请求。
- 作业、学科竞赛、会议/期刊、校内竞赛、夏令营/预推免、黑客松和自定义日程分别使用独立颜色，并贯通设置色点、月/年双层边框、日周全天与详情。
- Tauri 月视图的星期栏、日期、周数、事件行、字号、间距和选中态进一步对齐原生 macOS；月/年日期格使用最多两层同心边框表达不同 DDL 分类，今天与选中状态独立显示。
- 教学日历日期详情通过原生 Rust HTTP 客户端复用安全存储凭据完成北邮统一认证，实时读取云课堂当前课程与作业，不依赖浏览器会话。
- 日/周全天区、月格与年视图日期详情统一显示作业和校内竞赛通知；可见范围用批量命令和短时原始数据缓存一次发布，日期/月份动画不等待网络结果。
- 设置新增跟随系统、简体中文与 English；静态页面、状态和托盘菜单本地化，课程、作业、竞赛、天气与黄历原始内容保持不变。
- 独立 CLI/TUI 使用共享 Rust 业务核心和用户私有本地凭据文件；发布名称统一为 `where-to-study-cli` 与 `where-to-study-tui`，不再带 `wts-` 前缀。

### Apple 原生端

- SwiftUI macOS/iOS 已实现空教室、教学日历、设置三页和自适应手机、平板、桌面布局。
- 接入 Keychain、本地账号范围缓存、SJD 课表/空教室、节假日和 EventKit 真同步；考试周推断与考试标题已移除。
- macOS 菜单栏显示今日/明日课程；关闭主窗口后应用继续驻留。
- macOS 侧栏品牌标题与系统导航行内容对齐，实机窗口截图确认标题、三项导航和 14 个节次均无重叠。
- 可选 07:30 本地课程摘要会在系统上限内安排最多 63 个未来有课日；关闭提醒、撤销权限、切换账号或清除数据会立即撤销旧通知。
- 发布脚本生成 arm64 + x86_64 通用 macOS ZIP/DMG 预览包和 arm64 无签名 iOS archive，并校验版本、架构、隐私清单、HTTPS 数据源与本地路径泄漏；App Store 脚本另支持双平台正式分发签名、归档、导出与上传。
- 二进制内容校验只依赖 macOS/Linux runner 自带的 `grep`，不再要求额外安装 `ripgrep`；退役 HTTP 地址按固定字符串实际检查。
- Apple 测试脚本按 UDID 选择 runner 上真实存在的 iPhone 模拟器，不再假设指定机型一定安装在全局最新 iOS runtime。
- iPhone/iPad 教学日历使用独立移动布局：紧凑日期导航、可横向切换的完整周日期、日/周/月/年视图，以及不会遮挡时间轴内容的底部导航。
- 日、周、月支持左右滑动翻页；月视图支持带动画的展开/折叠；年视图日期弹窗可跳转到对应日、周或月，周课程卡在手机上完整显示时间、地点和教师。
- 手机月视图点击日期会进入半折叠状态并在下方显示当日日程；日期格中的事件条只用于展示，不再抢占日期点击。横屏月视图只保留完整月与选中周两种状态，日视图摘要使用与页面一致的卡片表面。
- iOS 月视图手势在开始时直接读取 UIKit 滚动区的实时偏移；详情已到顶时第一次继续下拉即可切换档位，从非顶部开始的手势仍完整归详情滚动区处理。
- iOS 展开月视图的课程/节日条不再形成日期点击死区；拖动结束后的选择抑制只保留到下一事件循环，新的日期点击可以接管尚未结束的档位动画。
- iOS 月份分页仅替换月格，详情 ScrollView 与手势层保持稳定；详情通过连续高度、裁剪和淡化更新，日期驱动的单一可取消任务负责触发 Store 加载。
- iPhone 横屏取消竖屏底部导航占位；iPad 和 macOS 收起侧栏的选中图标保持居中正方形，设置与联动查询页面保留正常安全边距。
- iPhone 年视图在横竖屏都保留 104pt 悬浮导航净空；12 月最后一天可滚动到导航条上方并打开详情，两个方向均有真实 UI 用例。
- Windows/Tauri 当前使用的绿色日历课桌图标成为全平台唯一源图；同步脚本生成 Windows、Tauri macOS、原生 iOS 和 Android 图标，Apple AppIcon 同时移除透明通道以满足上传要求。
- iOS/macOS 设置页提供学期自动检测、手动学期参数与 Widget 展示条数/地点偏好；课程提醒使用系统开关且与同列其他卡片等宽。
- iOS/macOS 今日课程 Widget 增加课程数量和教师信息偏好，并在设置页提供与实际尺寸一致的预览；当天无课时直接显示“今日无课”。
- iOS/macOS 联动查询顶部的校区天气统一为默认折叠卡片；折叠时显示当前天气摘要，展开后显示今日、明日详情与来源。
- 查询已改为教学日历和设置之间的独立一级导航；两个数据源首次出现时并行预热，顶部滑块只切换本地视图，会议和期刊专题通过独立开关进入教学日历。
- iOS/macOS 月视图日期详情已按日程、云课堂作业、黄历宜忌、统一活动 DDL 排列，并提供天气、黄历、学科竞赛、校内竞赛通知、夏令营和黑客松六个独立开关与第三方来源声明；云课堂作业使用 Keychain 凭据与原生 CAS 客户端实时同步，不读取浏览器会话。
- iOS/macOS 日、周、月、年均显示作业和校内竞赛通知；日/周按日聚合首项与 `+N`，iOS 课程摘要可折叠，快速换日时共享范围请求不会因 SwiftUI 任务取消而丢失。
- 主应用和 WidgetKit 小组件均支持 System / 简体中文 / English；语言通过 App Group 同步，小组件静态状态本地化而课程名、教室和教师等数据保持原文。
- 月/年日期格可同时渲染两类 DDL 的同心边框，按“作业 > 校内竞赛 > 其它 DDL”选择外层与内层；今天和选中日期不占用 DDL 边框层级。

### Android 原生端

- Kotlin Views 已实现手机/平板双布局、三页导航、Keystore 凭据、账号范围缓存、课表、空教室、节假日和 Calendar Provider 真同步。
- 可选 07:30 课程摘要使用持久化 `JobScheduler`，只在 07:30-08:00 有效窗口投递；关闭、撤销权限、切换账号和清除数据均采用持久化失效规则。
- 手机和平板 UI 测试按屏幕宽度验证底部导航或固定侧栏，不依赖反射或生产环境测试入口。
- Release APK/AAB 使用固定维护者密钥签名；打包时同时验证版本号、构建号、APK/AAB 证书和仓库内公开指纹。
- Android 手机教学日历与 iOS 保持相同功能层级，窄屏下重排标题、日期带、时间轴和导航，保留原有绿白配色与深浅色适配。
- 手机、折叠屏和平板分别使用自适应列宽和节次密度；空教室页面的临时查询校区与设置默认校区使用独立状态。
- Android 自适应图标使用与 Windows/Tauri 相同的源图，并通过前景安全区兼容圆形和圆角矩形启动器遮罩，避免日历顶部或课桌底部被裁切。
- Android 手机端按 iOS 对应页面统一卡片与控件边线、36dp 输入框和按钮高度、54dp 节次按钮及紧凑设置密度；教学日历的整点实线、节次虚线、日期条、月视图展开单元格和事件小条均完成浅色与深色复核。
- iOS 与 Android 手机教学日历在模式切换、日期选择、前后翻页、滑动换页、月视图展开/折叠及年视图跳转时提供系统触觉反馈。
- Android 月视图点击日期后进入半折叠状态并展示当日日程，日期格内事件不可独立点击；折叠屏与横屏布局不再保留竖屏底部导航空白，收起侧栏图标按固定正方形居中。
- Android 设置页补齐学期自动检测与 Widget 展示条数/地点偏好，并保持课程提醒为系统开关。
- Android 今日课程 Widget 与 Apple 端共享展示语义，可配置课程数量和教师信息；当天无课时直接显示“今日无课”。
- Android 已接入与其他图形端一致的两校区天气查询，并使用默认折叠、按需展开的卡片布局。
- 教学日历溢出菜单和设置均可进入班车/重要事件查询；共享缓存提供当天 active 班车、公开与校内事件搜索/分类/DDL 排序及收藏，平板与折叠屏复用同一入口逻辑。
- Android 月视图日期详情已接入云课堂原生 CAS 登录与实时作业同步、黄历宜忌和统一活动 DDL 卡片；天气、黄历、学科竞赛、校内竞赛通知、夏令营和黑客松六个开关与来源声明和 Apple 端一致。手机日期详情到达最高档后可继续滚动到底，滚动视口使用圆角边缘遮罩约束卡片层级；日期选择只进行纵向月格/详情动画，横向位移仅属于真正的月份分页。黄历、DDL、作业和节假日返回后只局部更新当前节点，不再重建页面；折叠屏收起侧栏时图标在选中框内保持纵向居中。
- iOS 与 Android 云课堂作业客户端按账户共享一次全量请求，不同日期只在内存中过滤；清除账号会取消或失效旧请求，阻止延迟结果回写。
- Android 日/周只折叠选中日期的完整课程列表，全天日程始终可见；日视图为横向 3 项胶囊与 `+N`，周视图为 7 列首项与 `+N`。作业、校内竞赛和学科竞赛/夏令营/黑客松均进入月格、年视图与独立居中日程弹窗；月/年格以 `1.2dp` 外框和 `0.8dp` 内框按“作业 > 校内竞赛 > 其它 DDL”显示前两类，选中日期使用独立蓝色且关闭年视图弹窗后保持。三种设备形态均支持 System / 简体中文 / English，所有应用字号缩小一级，通知和桌面小组件同步跟随。
- Android 手机查询页移除重复副标题，班车列表底部来源声明会完整避让悬浮导航，“重要事件”选中滑块不再裁切；底部导航调矮、加宽并加入 220ms 选中态动画。月视图最高详情档保持六行月格的完整测量高度，并由专用 viewport 强制裁剪画布；选择第二至第六周日期后上划都会只露出对应选中周，不再显示首周、额外周或空白；设置“关于”区域显示并链接 APP 备案号 `琼ICP备2026012322号-2A`。

### HarmonyOS 原生端

- “今日课程”服务卡片补齐课程数量、地点和教师展示偏好，并统一无课状态。
- 联动查询页补齐两校区天气与默认折叠卡片，折叠时保留摘要，展开后显示今日和明日详情。
- 查询已改为教学日历和设置之间的独立一级导航；AppModel 共享请求合并与五分钟缓存，支持当天 active 班车、真实分类/元数据搜索、过期切换、DDL 升序和完整本地收藏，并明确排除作业与自定义源。
- 月视图日期详情补齐云课堂原生 CAS 登录与实时作业同步、黄历宜忌与竞赛/夏令营/黑客松统一 DDL 卡片，设置页提供天气、黄历、学科竞赛、校内竞赛通知、夏令营和黑客松六个独立开关与来源声明。
- 手机、平板、折叠屏和 PC 宽屏日历均补齐作业/全部活动 DDL 全天区、独立居中 `+N` 弹窗、月/年双层 DDL 同心边框、只折叠课程的日周摘要、独立的今天/选中状态、范围缓存和中英文界面；日/周时间轴轴区与日期区均使用整点实线和节次虚线；手机月视图修复双页横向翻月、三档详情手势、31 日锚点、动画外相邻月预热及翻页完成后的月份状态提交；构建及 136 项 ArkTS 单元测试通过。
- 设置页输入控件不再受手机全屏根容器的焦点属性阻断；账号与密码框显式启用触摸聚焦和系统输入法，键盘弹出时使用 RESIZE 避让，Pura 90 实测及设备侧自动化均通过。

## 0.2.8 正式发布最终验证

| 范围 | 结果 |
| --- | --- |
| 固定公开 API | 班车 Schema 1.0、Contest DDL Schema 1.4、校内通知 Schema 1.0 均直接返回 HTTP 200 JSON 且无重定向；公开活动 454 条、会议 67 条、校内通知 15 条，查询源均无作业 |
| React/Tauri UI | 141/141 Node 契约与回归测试、Vite 生产构建、深浅色实际渲染和许可证新鲜度检查通过；会议唯一开启链路覆盖预热、跨年加载、月详情、来源声明与重试 |
| Rust | Tauri 151 项通过、3 项真实在线服务测试按设计忽略；共享 Core 61/61、CLI 16/16、TUI 21/21 通过，四个 crate 的 Clippy `-D warnings` 全部通过 |
| Apple | 本地 Xcode 严格构建与完整平台测试通过；基础套件 26 项 UI 中 21 通过、5 项设备/线上门控跳过、0 失败；横竖屏年视图和生产班车 Store/UI 门控另行执行并通过 |
| TestFlight | iOS 与 macOS `0.2.8 (77)` 均已上传；macOS 收到 `Validated signed archive`、`EXPORT SUCCEEDED` 与 `Upload succeeded`。按约定以上传脚本成功为完成边界，不打开 App Store Connect 检查 processing 或测试组状态 |
| Android | `0.2.8 (45)` 的 201/201 Release JVM 测试、Lint、固定证书签名 APK/AAB、指纹、ZIP 对齐、版本及 HTTPS-only 校验通过；API 36 手机查询页 5/5、浅色和深色完整导航、非首周月视图滚动交接通过，并对第二周与第五周完成深浅色视觉复核 |
| HarmonyOS | `0.2.8 (1002018)` 的 136/136 ArkTS 单元测试、签名 HAP/APP、打包版本、发布签名和三项 API 校验通过；Pura 90 完整设备测试 12/12、手机 UI 21/21、真实 SJD 登录/无请求体课表 POST、重复缓存写入及获授权真实账号“保存→课表→重启→ASSET 再读取”均通过；DevEco 已上传 AGC 且云测试为“通过” |
| GitHub | `v0.2.8` 已发布为正式版并更新 `releases/latest`；Android APK 已从 `49f23bc` 重新构建并替换，SHA-256 为 `b9fc08cf0229af709c57f5992e512fd48e087e1194e26e385f01189dff6581d8`，远端下载后与本地签名包逐字节一致，其余 10 个附件的名称、大小、摘要与资产 ID 未改变。Windows/Linux GUI 为 [runs 33467351916](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467351916) / [33467352143](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467352143)（`04a355c`），CLI/TUI 为 [runs 33378927605](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927605) / [33378927633](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927633)（`6e92141`）；桌面刷新附件来自 main push，Android APK 使用本地固定维护者密钥构建，tag-only attestation 已跳过，不声明 tag/Sigstore 来源证明 |

完整中英文发布说明见 [`release-v0.2.8.md`](release-v0.2.8.md)。

## 0.2.7 最终本地验证

| 范围 | 结果 |
| --- | --- |
| 域名/API | `contest-events` 与 `contest-notices` 的 `https://where-to-study.cn` 固定接口均直接返 `200 application/json`、无重定向，实际 JSON 契约与现有解析器兼容 |
| React/Tauri UI | 116/116 Node 契约、主题、全平台版本和 HTTPS 域名门禁通过；Vite 生产构建与许可证新鲜度检查通过 |
| Rust | Tauri 146 项自动测试通过，1 项需真实账号和在线服务的测试按设计忽略；共享 Core 55/55、CLI 14/14、TUI 14/14 通过 |
| macOS SwiftUI | 212/212 XCTest、严格 Swift 6/警告即错误构建、正式签名归档、Universal DMG 双架构、Widget/隐私/许可证/新域名与镜像验证通过 |
| iOS SwiftUI | 219/219 单元测试通过；23 项 UI 回归中 19 通过、4 项仅 iPad 条件跳过、0 失败；正式归档与新域名/ATS 检查通过；本地 App Store export 的主应用与 Widget 均为 Apple Distribution 签名且不含 `get-task-allow` |
| TestFlight | iOS 与 macOS `0.2.7 (73)` 均收到 `Upload succeeded` / `EXPORT SUCCEEDED`；按约定未打开 App Store Connect 检查 processing 或测试组状态 |
| Android | `0.2.7 (43)` 的 186/186 Release JVM 测试、`lintRelease`、固定维护者证书签名 APK/AAB、证书指纹、ZIP 对齐、许可证、版本、旧主机缺席与 HTTPS-only 网络策略校验通过 |
| HarmonyOS | `0.2.7 (1002012)` 的 113/113 ArkTS 单元测试、assembleHap/assembleApp、独立 HAP 签名、APP ZIP 结构和旧主机缺席检查通过；DevEco `Upload Product` 已上传 AGC，云测试结果为“通过” |

完整中英文发布说明见 [`release-v0.2.7.md`](release-v0.2.7.md)。

## 0.2.6 最终本地验证

| 范围 | 结果 |
| --- | --- |
| React/Tauri UI | 114/114 Node 契约与主题测试、Vite 生产构建、许可证新鲜度检查通过；Playwright 覆盖宽/窄屏、深/浅色、中/英文的联动查询、日/周/月/年、设置与收藏，年弹卡真实滚轮 `scrollTop 0 → 420` |
| Rust/Tauri | 146 项自动测试通过，1 项依赖本机安全存储与北邮在线服务的真实作业同步测试按设计忽略；共享 Core 55/55、CLI 14/14、TUI 14/14 通过 |
| macOS SwiftUI | 204 项 XCTest、严格 Swift 6/警告即错误 Universal 构建、月格 DDL 去重、年弹卡滚动和宽屏空教室两栏视觉回归通过 |
| iOS SwiftUI | 210 项 XCTest、iPhone 两项核心 UI、示例模式导航和 iPad Pro 13 英寸横屏回归通过；收藏管理为顶层页，公历周/教学周与宽屏双栏均有截图证据 |
| TestFlight | iOS 与 macOS `0.2.6 (72)` 正式签名归档均通过并收到 `Upload succeeded` / `EXPORT SUCCEEDED`；iOS 使用 Automatic、macOS 使用 Manual；按约定未打开 App Store Connect 检查 processing 或测试组状态 |
| Android | `0.2.6 (42)` 的 186/186 Release JVM 测试、`lintRelease`、固定维护者证书签名 APK/AAB、版本/证书/ZIP/许可证/网络策略校验通过；Phone/Fold UI smoke 与平板/折叠屏视觉检查通过 |
| HarmonyOS | `0.2.6 (1002011)` Release 签名 HAP/App 构建、签名摘要验证、113/113 ArkTS 单元测试、Pura 90 手机 16/16 UI 冒烟与 MateBook Pro 宽屏 5/5 导航回归通过；DevEco 已更新上传 AGC 且云测试通过，GitHub 同步提供签名 APP/HAP；[测试邀请链接（已含邀请码）](https://appgallery.huawei.com/link/invite-test-wap?taskId=dfc32d0293987b9d09911717759ac063&invitationCode=A0IsJpKIcn3)，邀请码为 `A0IsJpKIcn3` |
| macOS DMG | 原生 Universal DMG 的 `0.2.6 (72)`、`arm64 + x86_64`、主应用/Widget 临时签名、Applications 快捷方式、覆盖安装文件名与 `hdiutil verify` 均通过；该 GitHub 预览包未做 Developer ID 公证 |
| 法律与安全 | `npm run licenses:check`、自定义 HTTPS 源安全边界、完整本地收藏快照及中英双语隐私说明通过；v1 `exam_week_numbers` 仅作兼容且新数据始终为空 |

完整中英文变更见 [`release-v0.2.6.md`](release-v0.2.6.md)，自定义日程公开契约见 [`custom-schedule-api.md`](custom-schedule-api.md)。

## 0.2.5 最终本地验证（历史）

| 范围 | 结果 |
| --- | --- |
| React/Tauri UI | 110/110 Node 契约与业务测试、`npm run build` 通过；Playwright 额外验证自动模式显示当前推断、手动空值/非法学期号拒绝，以及收藏、全天日程、动画和键盘路径 |
| Rust/Tauri | `cargo fmt --check`、严格 Clippy 与 145/145 自动测试通过；1 项依赖本机安全存储和北邮在线服务的真实作业同步测试按设计忽略；共享 Core 56/56、CLI 13/13、TUI 14/14 同时通过；托盘、导入和通知不再读取旧学期缓存 |
| macOS SwiftUI | 本地 Xcode 26.6 严格 Swift 6 与警告即错误构建通过；203/203 XCTest 通过，包含自动学期冷启动、旧缓存隔离、凭据变更、空默认与 `week=0` 契约 |
| iOS SwiftUI | 本地 Xcode 26.6 的 208/208 逻辑测试通过；iPhone UI 回归 19/19 通过，4 项仅限 iPad 的用例按设备条件跳过；语言往返、月视图滚动/分页、年视图反向动画和设置均通过 |
| TestFlight | iOS 与 macOS `0.2.5 (69)` 正式签名归档均通过并收到 `Upload succeeded` / `EXPORT SUCCEEDED`；按约定未打开 App Store Connect 检查 processing 或测试组状态 |
| Android | `0.2.5 (41)` 的 185/185 Release JVM 测试、`lintRelease`、固定维护者证书签名 APK/AAB、版本/证书/ZIP/许可证/网络策略校验通过；旧学期缓存已从 UI、小组件和课程通知隔离，Android 16 模拟器 UI 19/19 保持通过 |
| HarmonyOS | `0.2.5 (1002008)` HAP 构建与 112/112 ArkTS 单元测试通过；自动学期、空默认、旧保存/清理并发门禁、收藏导入、月内联、真实教学周和 PC 全天列均通过编译与契约测试。当前 `hdc` 无真机目标 |
| 法律与安全 | `npm run licenses:check`、自定义 HTTPS 源安全边界、2 MiB/5000 项/100 项每日/370 天限制、5 分钟刷新、完整本地收藏快照及中英双语隐私说明通过 |

完整中英文变更见 [`release-v0.2.5.md`](release-v0.2.5.md)，自定义日程公开契约见 [`custom-schedule-api.md`](custom-schedule-api.md)。

## 0.2.4 最终本地验证（历史）

| 范围 | 结果 |
| --- | --- |
| React | 87/87 业务规则、主题契约、全端 DDL 显示与月/年双层边框、高对比选中日期、设置分类色点、Switch 控件、日周时间轴实线/虚线、独立居中弹窗、跨端语言、范围缓存、公开 DDL 启动预热与 Tauri IPC 权限、桌面天气边距和节次居中、设置顺序、Windows/Linux 无伪小组件、Android 折叠侧栏居中、Android 发布网络策略、Apple UI 自动化重试与诊断保留、ARM64 工作流、AppImage 宿主 ABI 隔离、Linux 发布契约与全端版本一致性测试、`npm run build`、许可证新鲜度检查通过 |
| 许可证交付 | 根许可证为 `GPL-3.0-only`；锁定依赖生成的第三方许可证清单通过新鲜度检查；Tauri、Apple 与 Android 制品中的三份法律文件均与仓库逐字节一致 |
| Rust | 共享核心、Tauri、CLI、TUI 的全部门禁通过；Tauri `fmt`、`clippy -D warnings` 与 120/120 自动测试通过，另 1 项需本机安全存储和北邮在线服务的真实同步测试按设计忽略；共享核心 43/43、CLI 13/13、TUI 14/14 测试通过 |
| Rust 依赖审计 | `cargo audit 0.22.2`：0 个漏洞；17 个允许警告来自 Tauri 的 Linux GTK3/旧 proc-macro/unic 传递依赖 |
| macOS SwiftUI | 本机 Xcode 严格 Swift 6 并发和警告即错误构建通过；159/159 全量 XCTest、Universal Release 归档及 `0.2.4 (65)` 正式签名上传通过 |
| iOS SwiftUI | 本机 Xcode 严格 Swift 6 并发；166/166 逻辑测试、17 项 UI（15 通过、2 项仅 iPad 条件跳过）及 `0.2.4 (65)` 正式签名上传通过 |
| Android Debug | 162/162 JVM 测试、Lint、Debug APK 与 AndroidTest APK 构建通过 |
| Android Release | `0.2.4 (37)` 的 162/162 Release JVM 测试、`lintRelease`、固定证书签名 APK/AAB、证书指纹、ZIP 对齐、许可证与包内版本校验通过；该历史版本的竞赛备用源例外已在后续版本迁移到 `https://where-to-study.cn` 并移除 |
| Android UI | Medium Phone API 36.1 为 11/11；WhereToStudy Fold 与 Pixel Tablet 各 11 项通过、1 项仅手机导航几何按设计跳过；覆盖日周课程/全天一致性、持久选中日期、DDL 色点、实线/虚线、月动画、月/年边框和折叠侧栏居中 |
| 浏览器视觉检查 | 桌面与手机宽度的 English 设置、周/月独立居中日程弹窗、全部公开 DDL，以及月/年格“作业 > 校内 > 其它”三档实际计算边框通过；开发服务器唯一控制台消息是浏览器忽略 meta 中 `frame-ancestors` 的已知 CSP 提示 |
| HarmonyOS | HAP 构建、91/91 ArkTS 单元测试、ohosTest HAP 编译和宽屏日/周/月/年静态契约通过；当前无连接设备，未执行 ohosTest 设备运行 |
| macOS 归档检查 | SwiftUI Universal `0.2.4 (65)` 的 x86_64/arm64、WidgetKit 扩展、版本、签名、沙盒权限、隐私清单与统一应用图标复核通过 |
| App Store Connect | iOS 与 macOS `0.2.4 (65)` 均由本地 Xcode 完成上传并收到 `Upload succeeded` / `EXPORT SUCCEEDED`；按当前发布约定未再打开 App Store Connect 检查后续状态 |
| CLI/TUI 真实数据 | 本机与 Ubuntu 22.04 x86_64 服务器均使用隔离 HOME、隐藏输入和真实教务路径验证登录、学期自动检测、课表刷新与凭据清除；测试凭据文件已删除 |
| Linux 发布 | GitHub-hosted Ubuntu 22.04 x86_64/arm64 工作流均完成 `.deb`、`.AppImage`、CLI、TUI 构建；AppImage 重打时移除会与新宿主 Mesa 冲突的旧 Wayland ABI 库并隔离 GIO 模块，Ubuntu 25.04 ARM64 桌面复测通过；GitHub Release 不上传校验文件 |
| Tauri 托盘实机 | 点击不闪退；显示今日/明日课程、打开主窗口、空教室、教学日历、设置、刷新与退出；Windows/Linux 无课程小组件入口 |
| 敏感信息扫描 | Gitleaks 扫描完整提交历史及当前全部拟提交文件，0 泄漏 |
| 工程静态检查 | `git diff --check`、`actionlint`、`shellcheck scripts/*.sh`、`bash -n scripts/*.sh` 全部通过 |

GitHub-hosted Xcode 26.6 曾在 17 项长流程 UI smoke 中分别随机失败于月视图第三次手柄点击和中英文往返后的标签几何，而本地 Xcode 26.3 全量 15/15 可执行项及月视图 targeted 3/3 重复均通过。两次 CI 失败点漂移且不涉及同一产品状态路径，因此 Apple CI 对单个失败测试增加一次 Xcode 原生重试、将 job 上限扩至 45 分钟，并在仍失败时保留 `.xcresult`；持久失败仍会使门禁失败。

Apple 测试结果（2026-08-24 使用 `xcresulttool` 复核）：

- macOS：0.2.4 最终源码 159/159 项逻辑测试通过
- iOS：0.2.4 最终源码 166/166 项逻辑测试通过；17 项 UI smoke 中 15 项通过、2 项仅 iPad 条件跳过、0 项失败
- 通知权限超时精确测试：20 轮、40/40 通过

## 0.2.8 正式版制品

`v0.2.8` 正式版固定为 11 项公开附件：Windows x64 NSIS 1 项；Linux arm64/x86_64 Debian/AppImage/CLI/TUI 共 8 项；固定 release key 签名的 Android `0.2.8 (45)` Universal APK 1 项；原生 macOS `0.2.8 (77)` Universal DMG 1 项。GitHub 不上传 Android AAB、HarmonyOS APP/HAP、iOS、`.sha256` 或原生 macOS ZIP；HarmonyOS 只通过 AppGallery Connect 分发。Android APK 已从 `49f23bc` 重新构建并替换，远端下载后与本地发布文件逐字节一致，其余 10 个附件未改变。桌面刷新附件来自 main push，Android APK 使用本地固定维护者密钥构建；tag-only attestation 按设计跳过，不声明 tag/Sigstore 来源证明。DMG 未做 Developer ID 公证，Windows 安装器尚无 Authenticode。

## 0.2.7 稳定版发布制品

`v0.2.7` 的 GitHub Release 附件范围为 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI、固定 release key 签名的 Android `0.2.7 (43)` APK/AAB、HarmonyOS `0.2.7 (1002012)` APP/HAP，以及原生 macOS `0.2.7 (73)` Universal DMG 预览包。iOS 与正式签名 macOS build 73 由本地 Xcode 分平台上传 TestFlight；不上传 iOS 或 `.sha256` 文件。DMG 未做 Developer ID 公证。按发布约定，Apple 以上传成功为完成标准，不再打开 App Store Connect 检查后续处理状态。

## 0.2.6 稳定版发布制品

`v0.2.6` 的 GitHub Release 附件范围为 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI、固定 release key 签名的 Android `0.2.6 (42)` APK/AAB、HarmonyOS `0.2.6 (1002011)` 签名 APP/HAP，以及刷新后的原生 macOS `0.2.6 (72)` Universal DMG 预览包。iOS 与正式签名 macOS build 72 由本地 Xcode 分平台上传 TestFlight；不上传 iOS 或 `.sha256` 文件。DMG 未做 Developer ID 公证，内部应用文件名与 TestFlight 安装一致。`v0.2.6` 标签不强制移动，刷新的 Apple/HarmonyOS 资产来自标签后的 `main` 修复。按发布约定，Apple 以上传成功为完成标准，不再打开 App Store Connect 检查后续处理状态。

## 0.2.5 稳定版发布制品

`v0.2.5` 的 GitHub Release 附件范围为 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及固定 release key 签名的 Android `0.2.5 (41)` APK/AAB。iOS 与 macOS `0.2.5 (69)` 由本地 Xcode 上传 TestFlight，不进入 GitHub Release；脚本或 CI 生成的 `.sha256` 只供内部校验，同样不上传。按发布约定，Apple 以上传成功为完成标准，不再打开 App Store Connect 检查后续处理状态。

## 0.2.4 稳定版发布制品

`v0.2.4` 的 GitHub Release 附件范围为 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及固定 release key 签名的 Android `0.2.4 (37)` APK/AAB。iOS 与 macOS `0.2.4 (65)` 已由本地 Xcode 上传 TestFlight，不进入 GitHub Release；脚本或 CI 生成的 `.sha256` 只供内部校验，同样不上传。

## 0.2.3 稳定版发布制品

`v0.2.3` 的 GitHub Release 提供 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及固定 release key 签名的 Android `0.2.3 (36)` APK/AAB。iOS 与 macOS `0.2.3 (64)` 仅上传 TestFlight，不进入 GitHub Release；脚本或 CI 生成的 `.sha256` 只供内部校验，同样不上传。

## 0.2.2 稳定版发布制品

`v0.2.2` 的 GitHub Release 提供 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及固定 release key 签名的 Android `0.2.2 (33)` APK/AAB。iOS `0.2.2 (57)` 与 macOS `0.2.2 (52)` 已上传 TestFlight，不进入 GitHub Release；脚本或 CI 生成的 `.sha256` 只供内部校验，同样不上传。

## 0.2.1 稳定版发布制品

`v0.2.1` 的 GitHub Release 提供 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及固定 release key 签名的 Android APK/AAB。iOS 与 macOS `0.2.1 (50)` 已上传 TestFlight，不进入 GitHub Release；脚本或 CI 生成的 `.sha256` 只供内部校验，同样不上传。

## 0.1.9 稳定版发布制品

`v0.1.9` 的 GitHub Release 提供 Windows x64 NSIS、Linux arm64/x86_64 Debian/AppImage/CLI/TUI，以及固定 release key 签名的 Android APK/AAB。iOS 与 macOS 只上传 TestFlight，不进入 GitHub Release；脚本或 CI 生成的 `.sha256` 只供内部校验，同样不上传。

## Build 15 稳定版发布制品

`v0.1.2` 通过标签工作流生成 Windows x64 NSIS、Tauri macOS arm64、SwiftUI macOS Universal、无签名 iOS archive，以及固定 release key 签名的 Android APK/AAB。每个二进制制品均带相邻的 LF 行尾 SHA-256 校验文件。

## Build 12 发布制品

以下文件均由 `v0.1.1-alpha.12` 标签的 GitHub Actions 生成并发布。Release 下载件与 Actions artifact 已逐字节比对，相邻 `.sha256` 已逐项回读验证；所有平台包内的 GPL、第三方许可证与第三方声明均与仓库版本一致。

| 文件 | SHA-256 | 签名状态 |
| --- | --- | --- |
| `Where-To-Study-v0.1.1-alpha.12-windows-x64-setup.exe` | `3c95daa9babb647669b76b6f4e28939d66e7fd2aa3a69f44ffcb99737213c125` | Tauri Windows x64 NSIS，无 Authenticode |
| `Where-To-Study-v0.1.1-alpha.12-macos-arm64.zip` | `76685726d95abe562054d03e38dd549bd6f70164307c2f83baa257e9b94154ff` | Tauri macOS arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.12-native-macos-universal.zip` | `6715c89ee1a8d25b758aac97f50b0528af083e7829af78d780a9a791f0c81ee7` | SwiftUI macOS x86_64 + arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.12-native-ios-unsigned.xcarchive.zip` | `052ffe29df2971829e8896bc85010ed8986e04283ba604b4d3dbb44857eed0dd` | iOS arm64 archive，无签名，不可直接安装 |
| `Where-To-Study-v0.1.1-alpha.12-native-android-universal.apk` | `6ab3bbcafe1750efe9650de80c61df005564cc7df989f77c799e0850d5b79c2b` | Android APK，固定 release key |
| `Where-To-Study-v0.1.1-alpha.12-native-android.aab` | `eb9f26b9941918558b0bcd8ab2e48232f0a485bf7a5cf19a63ca8fd9c50d8889` | Android AAB，固定 release key |

## Build 11 发布制品

以下文件均由 `v0.1.1-alpha.11` 标签的 GitHub Actions 生成并发布。Release 下载件与 Actions artifact 已逐字节比对，相邻 `.sha256` 已逐项回读验证。

| 文件 | SHA-256 | 签名状态 |
| --- | --- | --- |
| `Where-To-Study-v0.1.1-alpha.11-windows-x64-setup.exe` | `81fa18f46f13c991c7bcef365a90347614524047c7bffe6c29071826a219bd75` | Tauri Windows x64 NSIS，无 Authenticode |
| `Where-To-Study-v0.1.1-alpha.11-macos-arm64.zip` | `87ebffaf294ff83551789f520e17474bbf37d3ef4285012409d2199b5de02163` | Tauri macOS arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.11-native-macos-universal.zip` | `0c7df6c56bc8abcb42cd1306685e2ddfd82b766a39beed7c595b7efa04fb473d` | SwiftUI macOS x86_64 + arm64，adhoc |
| `Where-To-Study-v0.1.1-alpha.11-native-ios-unsigned.xcarchive.zip` | `52344702b7edc146a4556948d2f07f6af680d1814faf136cb49f0c322405203b` | iOS arm64 archive，无签名，不可直接安装 |
| `Where-To-Study-v0.1.1-alpha.11-native-android-universal.apk` | `fac6d84d6b8e7da9ed0aecbe401703d384354106dcc6509a1ee1288fd2eed319` | Android APK，固定 release key |
| `Where-To-Study-v0.1.1-alpha.11-native-android.aab` | `fa14e8e71b744bf3a370e56f6d65e701930bd1bf19fd6c5e7a7b0a4e7d645c56` | Android AAB，固定 release key |

## Alpha 6 CI 回归记录

`v0.1.1-alpha.6` 保留为不可变的失败候选标签，没有创建 GitHub Release。该标签在干净 runner 上发现并推动修复了以下发布环境问题：

- Xcode 26.6 无法在时限内推断日历课程块的深层 SwiftUI 表达式；已拆为显式辅助视图，并在本地严格 Swift 6 构建和测试中通过。
- GitHub Actions 中的 Android signing secret 与仓库固定证书不一致；已从本地忽略的维护者密钥安全重置 secrets，未输出密钥内容。
- Tauri/Apple 打包脚本依赖 runner 未预装的 `rg`；已改为系统工具并补充可移植性正反向测试。

## Alpha 7 CI 回归记录

`v0.1.1-alpha.7` 同样保留为不可变的失败候选标签，没有创建 GitHub Release。Windows、Tauri macOS 和安全检查均通过；原生工作流发现两个 runner 差异：

- `iPhone 16e` 在 runner 上只存在于 iOS 26.2，而 `OS=latest` 指向 26.5；脚本现从可用设备列表选择真实 UDID，并已在本机跑完 60 项 iOS 单元测试和 1 项导航 UI 测试。
- Android Release 构建、81 项 JVM 测试和 Lint 均通过，但 Actions secret 中的证书未匹配固定指纹；四个 secret 已从本地忽略且逐字节验证的维护者密钥重新安全写入，未输出密钥内容。

## Alpha 8 CI 回归记录

`v0.1.1-alpha.8` 保留为不可变的失败候选标签，没有创建 GitHub Release。Windows、Tauri macOS、安全检查以及 Apple 原生构建和测试全部通过，证明动态模拟器 UDID 修复有效；Android Release 再次在 APK 证书比对处失败。

- Android signing 改用全新的 `ANDROID_RELEASE_*` secret 名称，避免继续依赖旧 secret 的不可观测状态。
- 打包脚本会在 Gradle 前直接验证解码后的 keystore 证书，并分别报告 keystore、APK 和 AAB 的证书读取或不匹配错误。
- 手动门禁确认固定 keystore、Release 测试、Lint 和 Gradle 签名全部通过；APK 证书读取现兼容不同 `apksigner` 版本的输出流与前缀。
- 原生工作流把手动触发定义为独立 Android 签名门禁，可在创建新标签前单独验证固定签名链路。

## Alpha 9 Android 签名门禁

候选提交 `58d1a3f` 的手动原生工作流 [31306843399](https://github.com/Nemoyuzx/where_to_study/actions/runs/31306843399) 已通过。该门禁只运行 Android signed release job，Apple 和 Android Debug job 按设计跳过。

- 81 项 Release JVM 测试、Lint、APK/AAB 构建、固定 keystore 预检、APK/AAB 二次证书校验和 Actions artifact 上传全部成功。
- 下载后的 CI APK/AAB 已再次通过相邻 SHA-256、`versionName=0.1.1`、`versionCode=9` 和仓库固定公开证书复核。
- 工作流不再引用的旧 Android signing secrets 已删除，只保留验证通过的 `ANDROID_RELEASE_*` 命名空间。

## Alpha 9 CI 回归记录

`v0.1.1-alpha.9` 保留为不可变的失败候选标签，没有创建 GitHub Release。Windows、Tauri macOS、安全检查和 Android signed release 全部通过；Apple job 的 macOS 构建与测试、59 项 iOS 单元测试和 1 项导航 UI 测试通过，但后台通知清理测试在负载较高的 runner 上超过原 2 秒等待上限。

- 失败测试仍通过了“取消调用在 0.25 秒内返回”的非阻塞断言，失败只发生在等待后台清理完成的测试上限。
- 异步完成上限调整为 10 秒，产品代码和非阻塞要求不变；build 10 将先做重复压力测试和完整 Apple 测试再创建标签。

## Alpha 10 Android 签名门禁

候选提交 `4afc1a4` 的手动原生工作流 [31308452212](https://github.com/Nemoyuzx/where_to_study/actions/runs/31308452212) 已通过。该门禁只运行 Android signed release job，Apple 和 Android Debug job 按设计跳过。

- 81 项 Release JVM 测试、Lint、APK/AAB 构建、固定 keystore 预检、APK/AAB 二次证书校验和 Actions artifact 上传全部成功。
- 下载后的 CI APK/AAB 已再次通过相邻 SHA-256、`versionName=0.1.1`、`versionCode=10` 和仓库固定公开证书复核。

## Alpha 10 CI 回归记录

`v0.1.1-alpha.10` 的 Windows、Tauri macOS、Apple/Android 原生和安全工作流全部通过，但下载后的 Windows `.sha256` 使用 CRLF 行尾。GNU/macOS `shasum -c` 会把末尾的 `\r` 解析为文件名一部分，因此没有创建 GitHub Release，标签保持不可变。

- Windows 工作流改为通过 .NET 文件 API 显式写入单个 LF，并在上传前逐字节拒绝 CR 和非预期内容。
- build 11 将先通过手动 Windows 制品门禁和 Android 签名门禁，再创建 `v0.1.1-alpha.11` 标签。

## Alpha 11 发布门禁

候选提交 `83bab78` 的手动 [Windows 工作流 31450555455](https://github.com/Nemoyuzx/where_to_study/actions/runs/31450555455) 和 [Android 签名工作流 31450557116](https://github.com/Nemoyuzx/where_to_study/actions/runs/31450557116) 已通过。

- Windows 干净 runner 完成 React 构建、Rust 测试、严格 Clippy、x86_64 Tauri/NSIS 和 artifact 上传；下载后的 sidecar 确认只有 LF，且本机 `shasum -c` 直接通过。
- Android 完成 81 项 Release JVM 测试、Lint、APK/AAB 构建和固定证书校验；下载后再次确认 `versionName=0.1.1`、`versionCode=11`、相邻 SHA-256 与 APK/AAB 固定证书均正确。

## Alpha 11 测试版发布

标签 `v0.1.1-alpha.11` 指向提交 `cf8078c`。标签触发的 [Windows 31451410812](https://github.com/Nemoyuzx/where_to_study/actions/runs/31451410812)、[Tauri macOS 31451410817](https://github.com/Nemoyuzx/where_to_study/actions/runs/31451410817)、[原生端 31451410813](https://github.com/Nemoyuzx/where_to_study/actions/runs/31451410813) 和 [安全检查 31451410849](https://github.com/Nemoyuzx/where_to_study/actions/runs/31451410849) 全部通过。

- GitHub prerelease 已发布 6 个二进制制品和 6 个相邻 SHA-256 sidecar，并明确 Windows/macOS/iOS 的签名限制。
- 从 Release 重新下载的 12 个附件与 Actions artifact 逐字节一致；版本、构建号、架构、签名、固定 Android 证书、隐私清单和 HTTPS 数据源均通过复核。

## Alpha 12 测试版发布

标签 `v0.1.1-alpha.12` 指向提交 `17798a8`。标签触发的 [Windows 31461935957](https://github.com/Nemoyuzx/where_to_study/actions/runs/31461935957)、[Tauri macOS 31461936039](https://github.com/Nemoyuzx/where_to_study/actions/runs/31461936039)、[原生端 31461935956](https://github.com/Nemoyuzx/where_to_study/actions/runs/31461935956) 和 [安全检查 31461935959](https://github.com/Nemoyuzx/where_to_study/actions/runs/31461935959) 全部通过。

- GitHub prerelease 已发布 6 个二进制制品和 6 个相邻 SHA-256 sidecar；从 Release 重新下载的 12 个附件与 Actions artifact 逐字节一致。
- Windows 干净 runner 实际静默安装 NSIS 后逐字节检查三份法律文件；macOS、iOS 与 Android 包也完成版本、构建号、架构、签名边界和法律文件复核。
- GPL-3.0-only 元数据、锁定依赖许可证清单、npm/Rust 依赖审计和完整 Git 历史密钥扫描均通过标签流水线。

## 后续发布步骤

1. 等待 iOS build 43 与 macOS build 41 处理完成，将对应构建加入内部 TestFlight 群组并完成真机安装与核心流程验证。
2. 使用 `native/apple/AppStore/` 中的元数据、隐私问卷草案、截图方案和审核备注补齐正式提交信息。
3. 由账号持有人确认年龄分级、App Privacy、内容权利、欧盟 DSA、价格与地区等声明，再补齐截图和审核联系人并选择构建提交审核。
4. GitHub 公开下载版如需消除 macOS Gatekeeper 提示，仍需另行完成 Developer ID 签名与公证；Windows 可信签名链路也尚未闭环。

Android 维护者密钥只通过本地忽略文件和 GitHub Actions secrets 提供，不进入仓库或发布日志。
