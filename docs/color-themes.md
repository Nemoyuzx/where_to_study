# Color themes / 颜色主题

## Shared behavior / 跨平台约定

- Preset IDs and seed colors are defined in `contracts/v1/color-themes.json`: `default`, `ocean`, `violet`, `amber`, `rose`, plus `custom`.
- The initial selection is `default`. It returns each platform's exact existing light/dark palette, rather than regenerating the default from seeds.
- Custom fields are primary, accent, and selected-date colors. Accept only six hexadecimal RGB digits, with an optional leading `#`; trim whitespace and normalize to uppercase `#RRGGBB`. Invalid edits show an error and do not replace the last valid saved selection. Unknown persisted preset IDs fall back to `default`; corrupt persisted color fields fall back to the corresponding default seed.
- Keep custom colors when choosing another preset. Persist locally and restore after relaunch. Restore Default selects the default preset without deleting saved custom colors. Theme changes are UI-only: never trigger account saves, network refreshes, calendar reloads, or navigation-state resets.
- DDL category colors, warnings and current-time indicators retain their semantic palettes. The system's light/dark setting remains independent of the selected color preset.

## Palette derivation / 非默认主题的色板生成

Use sRGB components in the 0–255 range. Linear luminance uses the WCAG sRGB transfer function (`c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)^2.4`) and weights `0.2126, 0.7152, 0.0722`; contrast is `(lighter + 0.05) / (darker + 0.05)`.

For primary and selected-date fills, start with the seed. If white text contrast is below 4.5, blend the original seed towards black in 2% steps (1 through 50), rounding each output component to the nearest integer, and use the first passing color. For primary text on a dark surface, blend the original seed towards white using the same steps until contrast against `#282828` is at least 4.5. Light-mode primary text uses the accessible fill. Apply the same text-color derivation for readable accent text when needed. Decorative accent fills may retain the requested seed. A dark selected-date fill uses the accessible selected-date fill; its tinted surface and outline derive from that seed, not a fixed blue.

For the default preset, platform-native surface/label values remain exactly unchanged. For other presets and Custom, use the low-saturation surface recipes in contracts/v1/color-themes.json: blend the recipe base toward the primary seed using primaryAmount, rounding RGB components to the nearest integer. This applies to the page canvas, cards, elevated/modal surfaces, inputs/segmented controls/navigation and borders, not just previews. The primary seed means the actual preset seed or saved custom primary, never the contrast-adjusted fill. No new saved custom fields are needed.

Use the recipe text/secondaryText inks, then ensure at least 4.5 contrast against the lightest dark surface or darkest light surface among background/surface/elevated/surfaceVariant; adjust toward white in dark mode or black in light mode using the existing 2% rule if necessary. Re-evaluate primary/accent labels against their actual new surfaces. Soft selections use modest tint; preserve readable outlines, white-on-fill contrast, deadline/today/warning semantics and all default palette values. System appearance remains independent of preset. Do not add page resets or network calls.

If text appears on a tinted surface, verify contrast against that actual composite background too; re-adjust the text or use the system label color when necessary. Non-default selected dates must remain identifiable even with a black seed on a dark background: use a readable outline or another clear selection marker without replacing DDL/today semantic borders.

## UI / 设置

Provide a bilingual Color Theme / 颜色主题 settings section with preset swatches, a selected-state indicator, three labeled custom RGB controls, a live preview, and Restore Default / 恢复默认. Keep the settings accessible at narrow widths and large text sizes. Native color pickers may supplement editable hexadecimal text; a color picker is not a replacement for validation.

## Coordinated backgrounds / 背景协调优化（2026-09-09，已上传测试版）

按用户反馈，将四套非默认预设调整为低饱和、相近色相的方案，并同步处理整页背景、卡片、浮层、输入框、导航和边框。深色使用带对应色调的分层底色，浅色使用柔和底色与接近白色的卡片。默认主题仍保留原始平台色板。

自定义主色自动生成这套背景层级，无需增加保存字段；既有自定义三色不丢失。“恢复默认”继续保留自定义方案，清除本地数据才完整重置。预览区改为真实主题变量驱动的背景、卡片、课程行与控件示意。

实际染色层也参与文字对比度检查：修复班车选中时段/提示卡上的次要文字、鸿蒙月历周数/更多提示与全天时间文字、Apple 染色卡次要文字，以及年历高密度课程色块的数字。Web 年历逐格生成实际合成底色与可读墨色，保留原课程密度梯度；default、today、selected 和 DDL 边框优先级保持不变。

### Validation / 验证

- Web/Tauri 共用前端：仓库 161 项测试通过，Vite 构建通过。按用户要求关闭独立 Chrome 调试会话，改用 Microsoft Edge（msedge，Edg/152）完成最终预设×浅深色、背景/卡片实际取色、非法输入、保存重载、恢复默认保留三色、未保存账号输入及零主题网络请求检查；390px 英文视口无横向溢出。黑色自定义主色的年历检查了 71 个实际有课且未选中的日期格，最低文字对比度约 5.17:1。Edge 截图位于忽略目录 `output/playwright/surface-themes/edge/`。
- Apple：macOS 23 项定向检查与后续 15 项回归通过；iPhone 32 项单测、3 项 UI 和最后 8 项回归通过；iPad 3 项 UI 通过，NavigationStack 内部背景修复后追加 7 项单测、2 项 UI 通过。检查了真实模拟器截图与 macOS 离屏渲染图。用户既有审核/支持、产品名、邮箱、版本和存储格式未改。
- Android：209 项 JVM、Debug/APK/androidTest 构建通过，Lint 0 错误、56 警告；13 项主题 UI 检查分别在中文浅色与英文深色通过，最后 4 项半透明叠层/控件恢复检查也分别通过。检查 12 张截图。两个既有基线失败没有重复追查或记为通过。
- HarmonyOS：完整基础背景版构建与 162 项单测通过；补齐实际染色文字后，最终 163 项单测与 HAP 构建通过。随后 DevEco 生成完整 APP 并上传仅测试，最终 APP/HAP 版本和签名校验通过。TUI：36 项测试通过，含各预设×浅深色×真实页面 TestBackend 层级和墨色检查。
- 未做 Windows/Ubuntu 安装态、鸿蒙设备截图或固定桌面 Widget 的系统刷新调度验证；不能将上述浏览器、离屏或单元测试当作这些覆盖。

本次背景优化已以 `75023e1` 提交并推送，包含在 Apple `0.2.9 (89)` TestFlight 和 HarmonyOS `0.2.9 (1002025)` 仅测试包中；两端均有成功回执，鸿蒙快速云测试通过。未提交任何商店审核或 GitHub Release，用户既有 Apple 修改原样保留。详见[上传记录](release-v0.2.9.md)。以后调试本项目的网页界面使用 Edge。截图不加入 README。

The follow-up refines non-default presets and applies coordinated low-saturation canvas, card, elevated, control and text colors across clients. Custom primary colors generate the same background system without a storage migration. Final web checks used Microsoft Edge, not Chrome. Source commit `75023e1` is uploaded in Apple 0.2.9 (89) and HarmonyOS 0.2.9 (1002025) test builds; no store review or public release was submitted.

## Implementation and validation / 实现与验证（2026-09-08）

各图形客户端在设置中增加“颜色主题”；TUI 在设置页按 t 打开独立主题面板。主题仅本地保存，不做设备间或账号间的云同步，不调用教务接口。支持小组件的平台同步本机主题；无小组件能力的平台没有新增小组件。

“恢复默认”仅切换回默认预设，保留用户保存过的三色方案；“清除全部本地数据”则清除整份主题配置和自定义颜色，并同步重置小组件。原生示例模式中的更改只作用于示例，不覆盖真实设置。

| 客户端 | 验证结果 |
| --- | --- |
| Windows/Linux 共用 Tauri 前端 | 156 项仓库测试通过，Vite 生产构建通过；Chromium 实际操作验证五预设、自定义/非法值、保存重载、默认恢复保留自定义、零主题网络请求、未保存账号输入和日历月份保留。检查 390px 英文窄屏、1024px/1365px、浅深色截图。生产构建另验证深色同背景选中日期在月/年历中的轮廓及重载持久化。 |
| macOS | 全套 305 项执行：304 通过、1 既有跳过；后续轮廓补丁 14 项、清理生命周期 33 项及最终 3 项定向验证通过。应用/Widget 构建通过；检查设置与 Widget 的浅/深色渲染图。 |
| iPhone/iPad | iOS 全套 333 项执行：332 通过、1 既有跳过；后续轮廓补丁 38 项通过。iPhone 与 iPad 各 2 项 UI 测试通过，覆盖预设、错误输入、白/黑极端色、大字英文与日历状态保持；使用专用模拟器，不覆盖真实账号数据。 |
| Android | 207 项 JVM 测试通过，Lint 0 错误、56 项警告，APK/androidTest 构建通过；8 项新主题 UI 测试分别在中文浅色和英文深色通过，13 项已有 UI 检查通过；新增清理生命周期 3 项定向检查通过。 |
| HarmonyOS | 158 项 ArkTS 单元测试通过，HAP/APP 构建和包检查通过；覆盖默认资源、HEX、深浅色、存储顺序、示例隔离、小组件绑定、极端选中轮廓及其与 DDL 边框优先级。 |
| TUI | 33 项测试通过，包括 11 项主题用例；TestBackend 覆盖实际配色、100×24 至 1×1 的终端尺寸、输入/账号/网络隔离、保存/恢复/取消、坏配置与保存失败。格式检查通过。 |

验证中发现并修复了染色背景上的文字对比度不足、深色纯黑日期选中态不清晰、按下态误用亮文字色导致白底白字，以及新增主题偏好未随本地数据清除的问题。默认色板与 DDL/今日/警告语义保持原值；原有源码契约测试更新为验证新的响应式配色调用，尺寸和分层断言保留。

Android 两项已有导航测试仍失败，并已在未修改的 HEAD 基线 APK 上复现：dayWeekAgendaShowsSupplementaryItemsAndKeepsCollapsedState（课程 fixture 被当前学期筛选掉）、primaryPagesCanBeNavigatedWithoutCredentials（隐私长文本的可见性查找）。未修改或隐藏这两项测试，也未把它们列为通过。

本次没有 Windows/Ubuntu 安装态真机回归、鸿蒙设备截图或真实桌面 Widget 固定后的系统刷新调度验证；浏览器共用前端测试、原生离屏渲染与单元测试不能替代这些覆盖。纯文本 CLI 输出不增加颜色设置，已有彩色终端 UI 由 TUI 实现主题功能。

主题实现当日（2026-09-08）未上传。随后按用户要求，于 2026-09-09 从提交 `d46844a` 上传了 Apple 0.2.9 (88) TestFlight 与鸿蒙 0.2.9 (1002024) **仅测试**包，均收到成功回执；用户新增的 Apple 审核/支持修复原样保留，未提交任何商店审核。详见[测试上传记录](release-v0.2.9.md)。此前鸿蒙 0.2.9 (1002023) 仅包含 PC 字号修复，不含此功能。后续上传必须递增构建号。截图和本地日志保持在忽略目录，不放进 README。

Color themes are implemented in the shared Windows/Linux frontend, native Apple/Android/HarmonyOS clients and the TUI. All clients preserve their exact original default palette and semantic deadline colors. Validation includes local builds, pure color/persistence tests, native UI tests where available, and browser responsive checks. The two Android baseline failures and device-level coverage gaps above remain explicitly disclosed. Apple 0.2.9 (88) and HarmonyOS 0.2.9 (1002024) were uploaded for testing on September 9, 2026; no store review or public release was submitted.
