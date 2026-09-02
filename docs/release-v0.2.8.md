# Where To Study v0.2.8 Release

这是 `0.2.8` 的跨平台正式版发布说明，重点介绍新增的班车与重要事件查询、会议 DDL 和各端自适应布局。所有公开数据仅供参考，请以后勤部、活动主办方、会议官网或校内通知原文为准。

## 综合查询

- Windows、Linux、iOS、macOS、Android 与 HarmonyOS 均将“查询”作为独立一级页面，导航顺序统一为“空教室 → 教学日历 → 查询 → 设置”。
- 页面顶部使用两段滑块切换“班车查询 / 重要事件”；切换只改变本地视图，不把网络请求放进转场动画。
- 班车查询固定使用 `https://where-to-study.cn/api/shuttle-bus` Schema 1.0，按上海日期选择当天正在执行的时段，展示西土城与沙河双向班次、发车地点、已过班次与下一班。
- 当天没有生效时刻表时明确显示空档状态，不会把未来或历史时段当作今日班次；最新通知未安全解析时也不会展示推测数据。
- 重要事件合并 Contest DDL 公开活动与校内竞赛通知，明确排除课程作业和自定义日程；默认隐藏已结束/归档事项并按 DDL 由近到远排列。
- 支持名称、学校/组织方、方向、标签、等级、地点和来源搜索，以及类型、真实分类、来源和“显示已结束”筛选。
- 每条重要事件都复用教学日历的本地收藏；来源关闭、失败或删除条目后，完整收藏快照仍保留在设备上。
- 所有图形客户端首批只渲染 20 条重要事件，接近列表底部时自动追加 20 条；筛选和数据变化同步重置显示窗口，追加过程不触发新的网络请求。
- CLI 新增 `shuttle` / `events` 命令与 JSON 输出；TUI 在“日历”和“设置”之间提供独立“查询”标签，并提供搜索、类型、真实分类、来源、已结束与收藏快捷键。
- iOS build 77 纳入班车接口可空复核记录兼容修复；真实 iPhone 模拟器测试从生产 API 拉取并渲染西土城、沙河双向班次。

## 教学日历

- Contest DDL 的 `conference`、`journal_special_issue` 和 `pre_admission` 类型进入所有图形客户端的日、周、月、年日历链路；TUI 月历同步使用“会/事”标记显示会议与其它重要事件。
- 作业、学科竞赛、学术会议/期刊专题、校内竞赛、夏令营/预推免、黑客松和自定义日程分别使用独立颜色；设置色点、日周全天日程、月/年双层边框、弹窗与详情保持同一映射。
- 日历范围预热、查询页和重复进入页面共享缓存；日期翻页、视图切换与查询滑块均不触发重复网络请求。
- Tauri 桌面端即使只开启“学术会议”，也会正常执行年度预热、跨年范围加载、月详情显示和手动重试。
- HarmonyOS build 1002016 保留手机月视图双页横向翻月与三档日程面板手势，并同步增量事件列表和独立日程颜色；底部导航会读取系统导航指示条/系统避让区，四个交互控件至少避让物理屏幕底部 28vp。
- iPhone 年视图在横竖屏都为悬浮底部导航预留完整净空；12 月最后一日可滚动到导航条上方并点击打开详情。

## 数据与安全

- 班车、活动备用源与校内通知均为固定主机的无凭据 HTTPS GET，拒绝重定向并限制响应大小。
- 班车客户端校验 Schema、后勤部原文主机、日期范围、星期、`HH:mm`、车型、车辆数量和解析状态。
- 查询请求不会携带学号、密码、Cookie、token、个人课表、教室结果、校区偏好或 GPS。
- 中英文隐私声明、App Store 审核材料、第三方来源说明和安全基线已同步更新；API 返回的活动及班车原文不强制翻译。

## 版本矩阵

- Web / Tauri / Rust Core / CLI / TUI：`0.2.8`
- iOS：`0.2.8 (77)`
- 原生 macOS：`0.2.8 (77)`
- Android：`0.2.8 (45)`
- HarmonyOS：`0.2.8 (1002016)`
- Tauri Android 兼容元数据：`versionCode=2011`
- Legacy Tauri iOS：build 47

## 分发说明

- GitHub `v0.2.8` 已发布为正式版并更新稳定版入口 `releases/latest`。
- 正式版共 11 个公开附件：Windows x64 NSIS 1 项；Linux x86_64/arm64 Debian、AppImage、CLI、TUI 共 8 项；签名 Android Universal APK 1 项；原生 macOS Universal DMG 1 项。
- GitHub 不上传 Android AAB、HarmonyOS APP/HAP、iOS、`.sha256` 或原生 macOS ZIP；AAB 保留给应用商店/内部交付，HarmonyOS 仅通过 AppGallery Connect 分发。
- iOS 与正式签名 macOS 通过 TestFlight 分发，不上传 iOS 制品；GitHub macOS DMG 是未公证的开源预览包。
- iOS 与 macOS `0.2.8 (77)` 均由本地 Xcode 完成上传；macOS 流程收到 `Validated signed archive`、`EXPORT SUCCEEDED` 与 `Upload succeeded`。Apple 平台以上传脚本成功为完成边界，按约定不继续检查 App Store Connect processing。
- HarmonyOS `0.2.8 (1002016)` 已由 DevEco 以“测试和正式上架”上传并通过云测试；邀请测试沿用[分享链接（已含邀请码）](https://appgallery.huawei.com/link/invite-test-wap?taskId=b4f098663ce7375007fb19b098feace9&invitationCode=A0IsJpKIcn3)。
- Windows/Linux GUI 分别来自 [main push run 33467351916](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467351916) / [33467352143](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467352143)（`04a355c`）；CLI/TUI 分别来自 [run 33378927605](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927605) / [33378927633](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927633)（`6e92141`）。已证明这些提交到最终 `main` 的全部运行时代码输入无差异，因此没有重复 dispatch。
- 上述刷新附件均来自 main push 构建，tag-only attestation 按设计跳过，不声称具有 tag/Sigstore 来源证明。Windows 安装器仍未使用公众 Authenticode 证书。
- `.sha256` 文件只用于发布前后内部核验，不作为公开附件。

## 正式发布验证

- React/Tauri：139/139 Node 契约测试、Vite 生产构建、真实深浅色渲染与第三方许可证新鲜度检查通过。
- Rust：Tauri 151 项通过、3 项真实在线服务测试按设计忽略；共享 Core 61/61、CLI 16/16、TUI 21/21 通过，四个 crate 的 Clippy `-D warnings` 全部通过。
- Apple：本地 Xcode 严格构建与完整平台测试通过；基础套件 26 项 UI 场景中 21 项通过、5 项设备/线上门控场景按设计跳过、0 失败；横竖屏年视图净空与生产班车 Store/真实 App UI 门控另行执行并通过。
- Android：199/199 Release JVM 测试、Lint、固定证书签名 APK/AAB、证书指纹、ZIP 对齐、版本及 HTTPS-only 打包校验通过。
- HarmonyOS：130/130 ArkTS 单元测试、签名 HAP/APP 构建、版本、HAP 发布签名、三项固定公开 API 打包校验、手机一级导航与 28vp 底部净空设备测试 2/2 及 DevEco 云测试通过。
- 线上固定 API：班车 Schema 1.0、Contest DDL Schema 1.4 与校内通知 Schema 1.0 均通过固定 HTTPS 地址直接返回有效 JSON。
- GitHub：10 个桌面附件已替换，Android Universal APK 保留；全部 11 个公开附件均重新下载并证明与本地发布文件逐字节一致。

---

This is the release note for the cross-platform `0.2.8` stable release, focused on the new shuttle and important-event query surfaces, conference deadlines, and adaptive layouts. Public data is for reference only; rely on the original Logistics Department, organizer, conference, or school notice.

## Query Center

- Windows, Linux, iOS, macOS, Android, and HarmonyOS expose Query as a primary destination, with the shared order Empty Rooms → Teaching Calendar → Query → Settings.
- A two-segment control switches between Shuttle Buses and Important Events without attaching network work to the transition animation.
- Shuttle queries use the pinned `https://where-to-study.cn/api/shuttle-bus` Schema 1.0 endpoint and show only the timetable active on the current Shanghai date, including both directions, stops, departed services, and the next shuttle.
- A timetable gap is shown explicitly; upcoming or historical periods are never presented as today’s service, and unvalidated OCR data is never promoted to a structured timetable.
- Important Events merges public Contest DDL data with school notices, excludes assignments and custom feeds, hides ended/archived entries by default, and sorts by ascending deadline.
- Search covers names, organizations, fields, tags, ranks, locations, and sources. Type, real category, source, and ended-event filters are provided.
- Every event reuses the teaching-calendar favorite snapshot contract and remains locally available if a source is disabled, unavailable, or removes it.
- Every graphical client renders 20 events initially and appends 20 near the scroll edge. Filter/data revisions synchronously reset the window, and rendering never pages the network.
- CLI adds `shuttle` and `events` commands with JSON output. TUI exposes Query as its own tab between Calendar and Settings, with search, type, real-category, source, ended-event, and favorite shortcuts.
- iOS build 77 includes the nullable review-record compatibility fix for the shuttle feed; live iPhone-simulator tests fetched the production API and rendered both campus directions.

## Teaching Calendar

- `conference`, `journal_special_issue`, and `pre_admission` now flow through day, week, month, and year views on every graphical client. The TUI month calendar marks conferences and other important events with separate indicators.
- Assignments, competitions, conferences/journal issues, school notices, summer camps/pre-admission, hackathons, and custom schedules each use their own color across settings legends, all-day rows, month/year borders, dialogs, and details.
- Calendar preheating, Query Center, and repeated presentation share caches. Paging, view switching, and segment animations do not trigger duplicate network requests.
- On Tauri desktop, conference-only settings still drive annual preheating, cross-year range loading, month details, and manual retry.
- HarmonyOS build 1002016 keeps the double-page month transition and three-stop details sheet while adding incremental event rendering and independent deadline colors. The bottom navigation now follows the system/navigation-indicator avoid area and keeps all four controls at least 28vp above the physical display bottom.
- The iPhone year view reserves full floating-tab clearance in both orientations; December 31 remains scrollable, visible above the tab bar, and tappable.

## Data and security

- Shuttle, backup public events, and school notices are credential-free HTTPS GETs to pinned hosts, reject redirects, and enforce response-size limits.
- Shuttle clients validate schema, source hosts, operating dates, weekdays, `HH:mm`, vehicle/count fields, and parser status.
- Requests carry no academic credentials, cookies, tokens, personal schedules, classroom results, campus preference, or GPS.
- Bilingual privacy text, App Store review material, attribution, and the security baseline have been updated. API-provided event and shuttle content intentionally remains in its original language.

## Distribution

- GitHub `v0.2.8` has been published as a stable release and now backs `releases/latest`.
- The stable release contains 11 public assets: one Windows x64 NSIS installer; eight Linux x86_64/arm64 Debian, AppImage, CLI, and TUI packages; one signed Android Universal APK; and one native macOS Universal DMG.
- GitHub publishes no Android AAB, HarmonyOS APP/HAP, iOS artifact, SHA-256 sidecar, or native macOS ZIP. AAB remains store/internal-only, and HarmonyOS is distributed only through AppGallery Connect.
- iOS and the distribution-signed macOS build are delivered through TestFlight. No iOS artifact is published on GitHub; the GitHub DMG remains an unnotarized open-source preview.
- iOS and macOS `0.2.8 (77)` were both uploaded from local Xcode. The macOS flow reported `Validated signed archive`, `EXPORT SUCCEEDED`, and `Upload succeeded`. The upload script is the Apple completion boundary, and App Store Connect processing was intentionally not inspected afterward.
- HarmonyOS `0.2.8 (1002016)` was uploaded for testing and release through DevEco and passed cloud testing. The [invite link with its code](https://appgallery.huawei.com/link/invite-test-wap?taskId=b4f098663ce7375007fb19b098feace9&invitationCode=A0IsJpKIcn3) remains the public test entry.
- Windows and Linux GUI artifacts came from main-push [runs 33467351916](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467351916) and [33467352143](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467352143) at `04a355c`; CLI/TUI came from [runs 33378927605](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927605) and [33378927633](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927633) at `6e92141`. Every runtime code input from those commits through final `main` was proven unchanged, so no duplicate dispatch was needed.
- These refreshed assets are main-push builds, so the tag-only attestation step was skipped by design. No tag/Sigstore provenance claim is made for them. The Windows installer still lacks a public Authenticode publisher certificate.
- SHA-256 sidecars remain internal release-verification files rather than public assets.

## Stable-release verification

- React/Tauri: 139/139 Node contract tests, the Vite production build, real light/dark rendering checks, and third-party license freshness checks passed.
- Rust: 151 Tauri tests passed with three live-service tests intentionally ignored; Core 61/61, CLI 16/16, and TUI 21/21 passed, with `-D warnings` Clippy clean for all four crates.
- Apple: strict local-Xcode builds and the full platform suite passed; 21 of 26 baseline UI scenarios passed with five device/live-gated skips and zero failures. Portrait/landscape year-clearance and the production-shuttle Store/UI gates also passed separately.
- Android: 199/199 release JVM tests, Lint, pinned-certificate APK/AAB signing, signer fingerprints, ZIP alignment, version, and HTTPS-only package checks passed.
- HarmonyOS: 130/130 ArkTS tests, signed HAP/APP builds, packed-version and release-signature checks, all three pinned public-API package checks, 2/2 device checks for primary navigation and 28vp bottom clearance, and DevEco cloud testing passed.
- Live fixed APIs returned valid JSON directly over HTTPS for Shuttle Schema 1.0, Contest DDL Schema 1.4, and school notices Schema 1.0.
- GitHub: ten desktop assets were replaced and the Android Universal APK was retained; all 11 public assets were downloaded again and proved byte-identical to the local release files.
