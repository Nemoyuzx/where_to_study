# 0.3.2 预发布构建与上传记录

本轮包括开放依赖 PR 修复、竞赛镜像择新、个人账户密码说明与图标按钮、班车完整时刻表和法定节假日提醒。版本标签计划为 `v0.3.2-prerelease`，包内版本为 0.3.2；Android 59、Apple 100、HarmonyOS 1002036。

## 已完成的依赖合并

- [PR #66](https://github.com/Nemoyuzx/where_to_study/pull/66)：Android setup action 固定至已核对的 v4.0.4 提交。
- [PR #70](https://github.com/Nemoyuzx/where_to_study/pull/70)：兼容 npm 依赖更新。
- [PR #71](https://github.com/Nemoyuzx/where_to_study/pull/71)：Cargo 锁文件更新、许可证清单同步；将被撤回的 `yoke-derive 0.8.3` 锁回 0.8.2。本地 Rust、npm、许可证与审计通过。

## 数据源验证

2026-10-02 13:03 +0800 核对三个固定 HTTPS 公开源：GitHub 主源与原备用 API 的 `generated_at` 为 `2026-09-29T13:40:36+08:00`、566 条；新镜像为 `2026-10-02T12:35:38+08:00`、572 条。三个响应均为 Schema 1.4/Asia-Shanghai JSON，分别为 1,855,633、1,442,823、1,880,200 bytes，均低于 4 MiB。当前 CLI 的真实请求已选择镜像，桌面公开重要事件的线上测试通过。这是当时的服务端快照，不将客户端抓取时间冒充数据生成时间。

选择规则：验证后按 RFC3339 实际时间比较，镜像严格更新时采用镜像，同时间使用 GitHub；任一源失败时使用另一个有效源，两个静态源都失败才走原备用 API。合法空列表可以作为更新结果清除旧日程。公开请求不附带个人凭据，拒绝重定向，竞赛响应上限 4 MiB。

## 测试与渠道状态

已完成的本地验证：

- Rust：Tauri 229 项通过、3 项线上用例默认跳过；公开重要事件线上用例另行运行通过。Core 101、CLI 24、TUI 50 项通过。
- 前端最终 **238 项通过 / 1 项 Windows 已安装 PE 用例按环境跳过**；完整班车表、法定休息日、跨上海午夜、通知变更、重叠时段和无序班次均有回归覆盖。Edge 中英布局、窄宽度与完整时刻表目视核对通过。
- 前端构建、npm 依赖审计、五份 Cargo 锁文件审计、glib 补丁校验、许可证清单与已暂存代码的 Gitleaks 扫描通过。Cargo 中已有 unmaintained 提示未当成漏洞或忽略新增 unsound 问题。
- Android 0.3.2（59）：最终 release JVM **294/294**、Lint **0 errors / 73 warnings / 1 hint**；APK/AAB 构建、原证书 v2/v3 验签、ZIP 对齐、许可证、HTTPS 策略及各公开端点检查通过。未宣称 Lint 零警告。
- Android 手机中英／明暗、平板中英布局仪器测试通过，官方节假日缓存仪器测试通过。最新时段日期与状态画面已串行重拍核对；曾出现一次模拟器 System UI ANR 弹窗，未将其遮挡截图当作有效证据。视觉测试使用明确标记的示例，不冒称真实课表或实时班次。
- HarmonyOS：最终 **258/258** Hypium 通过，release ArkTS/HAP/APP 构建通过；独立 `verify-app`、release profile 与 `pack.info` **0.3.2（1002036）**验证通过。本机没有连接鸿蒙设备，不能将主机测试写成真机视觉通过。

本地已签名 Android APK 为 `Where-To-Study-v0.3.2-prerelease-native-android-universal.apk`，**1,178,886 bytes**，SHA-256 `8ebf60a716881c9cd769fe472652fc3e3b6fd5deacce710749e910a5a25fd96b`，构建源码提交 `81b03f9`。本地 AAB 仅保留，不上传 GitHub。

Apple 首轮完整脚本完成 macOS 构建／测试和 iOS 434 项逻辑测试，但 iOS UI 有两项用例失败：数字键盘遮挡提醒保存按钮；国庆日月格折叠了旧测试硬找的作业行。已增加数字输入“完成”键，并让月格回归点击实际可见事件，不通过增加无效滑动次数绕过问题。最终本地 Xcode 定向门禁：iOS **51 项通过 / 1 项线上测试按条件跳过 / 0 失败**，macOS **46 项通过 / 1 项跳过 / 0 失败**。覆盖镜像择新、缺失／谎报长度的 4 MiB 按块上限、传输取消、完整时刻表、重叠时段、法定假日、账户按钮与原两项失败。iPhone16e 模拟器示例画面已核对；未将它宣称为真机或 Mac/iPad 视觉检查。中英 `.strings` lint 通过。最终 Apple 源码提交 `9804008`。

GitHub 用原生 macOS Universal DMG 已生成：`Where-To-Study-v0.3.2-prerelease-native-macos-universal.dmg`，**8,068,113 bytes**，SHA-256 `b905715e76da17d54538ad24997ee778ca87c54572df2f14184ee14c9b30a754`。严格并发／警告编译、主程序和 WidgetKit 扩展签名、许可证、隐私清单、公共 HTTPS 端点和 DMG 校验通过。GitHub DMG 是 ad-hoc 签名、未公证，与 Apple Distribution/TestFlight 渠道不同。

## Apple TestFlight 上传

本地 Xcode 使用现有 Apple Distribution 证书与配置：iOS Automatic、macOS Manual，没有改写仓库中的签名字段。

- **2026-10-02 13:37:05 +0800**：iOS **0.3.2（100）**返回 `Upload succeeded` 和 `EXPORT SUCCEEDED`。自动签名导出的 IPA 已验证 Distribution 签名、主程序／Widget 版本与隐私清单。
- **2026-10-02 13:38:38 +0800**：macOS **0.3.2（100）**返回 `Upload succeeded` 和 `EXPORT SUCCEEDED`，主程序和 Widget 均包含 arm64+x86_64。
- 遵照用户要求，上传成功后未检查 App Store Connect 处理状态，未提交正式商店审核，也不宣称已经对所有测试者可安装。
- 上传日志和导出仅保留在忽略目录 `release-artifacts/v0.3.2-prerelease-apple/`，未上传 GitHub。

## HarmonyOS 与 GitHub 待完成项

DevEco 当前需要重新登录，已在 Edge 打开官方登录页，未绕过 IDE 改用其他上传方式。签名 HAP/APP 已准备，但 **0.3.2 尚未上传 AppGallery**；收到用户登录完成消息后，沿用第二项“生成.app包并上传至AppGallery Connect进行测试”，不提交正式审核。当前渠道版本仍是已有的 0.3.1（1002035）。

本轮功能源码 `980400892897b42d278c1e6ea567acec21d38d81` 已推送至 `main`。该提交 GitHub Actions 作业仍未启动，检查注释为：`The job was not started because your account is locked due to a billing issue.` [对应 Windows 运行](https://github.com/Nemoyuzx/where_to_study/actions/runs/36969029201)。Windows/Linux/标签构建仍等待账户解除锁定；该状态不能作为编译或测试失败，也不能据此复用旧版安装包发布新版本。

## 已保存的 GitHub 预发布草稿

- 已推送注释标签 `v0.3.2-prerelease`，指向 `5c951520118927600bc880afa87fc0e0124ef5e0`；与已验证安装包对应的功能源码相比，仅增加构建与上传记录，不移动已有标签。
- 已创建 **Where To Study v0.3.2-prerelease** 草稿，Release ID **401567537**：[维护者可访问的草稿](https://github.com/Nemoyuzx/where_to_study/releases/tag/untagged-a241ced12a66cd275b78)。API 确认为 `draft=true`、`prerelease=true`，**尚未公开发布**。
- 已上传上述 Android APK 与 macOS DMG，共 **2 个**资产。GitHub API 的名称、大小和 `sha256` digest 均与本地签名文件一致；没有回下载 Release 文件。
- 待补 Windows 安装器 1 个、Linux DEB/AppImage 4 个、CLI 2 个、TUI 2 个，以及标签 CI／安全门禁，共形成预定的 11 个公开安装文件。解除 GitHub 账户锁定后，在最终确认的发布源码上重跑工作流；新补丁的包状态见下节，不重复 Apple 上传，不使用旧包冒充新版。
- 已核对 `releases/latest` 仍为 **v0.3.1**。文档收尾提交只更新回执，不更改应用代码或发布标签。

## 后续安卓课程摘要动画修复

根据新增反馈，安卓日／周视图顶部课程摘要的折叠与展开改为单个可取消的 `ValueAnimator`：逐帧更新课程视口高度、透明度和箭头，时间轴随布局连续移动；不改变课程字体、间距或固定标题行高度。快速反向从当前高度继续；日期／页面切换取消旧动画，旧回调不能回写新视图；公开日程刷新只在动画完成后重建当前摘要。空课程日期不产生额外高度，系统关闭动画时直接落到终态。

- 最终 Release JVM **294/294**，Lint **0 errors / 73 warnings / 1 hint**；前端契约 **238 通过 / 1 项 Windows 环境用例跳过**。同时修正旧 Apple 班车契约断言，验证抽出的有效期筛选与按方向择最新时段逻辑，不回退 Apple 运行代码。
- 只读手机模拟器 **4/4** 定向回归通过；手机视觉复测 **2/2**、平板 **2/2**通过，均未跳过。测试真实中间帧高度、透明度、箭头角度、时间轴位置、快速反向、空日期、跨日期／页面的取消以及禁用系统动画。示例截图已目视检查，保留在忽略目录 `release-artifacts/v0.3.2-agenda-animation/`，不放 README。
- 测试夹具的学期编号改为当前合法编号，避免被生产环境的当前学期校验正确过滤；未放宽生产校验。更新旧设置测试计数以包括已存在的课前提醒开关。视觉复测在启动测试进程前配置动画比例，避免沿用上一个测试进程的禁用动画状态。
- **当前草稿中的 Android 59 APK 尚不包含这次动画修复**。本次只提交代码和测试，不替换安装包、不移动已推送标签。最终公开前必须把该补丁和契约测试修订纳入最终标签源码、补做新的 Android 签名构建；不可直接公开当前旧 APK 或使用旧标签构建代替。Apple 运行代码未变，已经成功上传的 100 不需要重传；macOS DMG 无需重构建。

预发布不会替换 v0.3.1 的稳定版入口。公开资产遵循当前 11 个安装文件的结构，不上传 AAB、鸿蒙 APP/HAP、iOS 归档或校验侧文件。上传后用 GitHub API 的名称、大小和摘要与本地核对，按用户要求不回下载 Release 文件。

## 随后跨平台同类动画复核

上述“Apple 运行代码未变、100 不需要重传”只适用于前一节的安卓单项修复。随后追加的跨平台动画复核已更改 Android、Apple、HarmonyOS 与 Tauri 运行代码，详见 [动画与生命周期复核](motion-consistency-audit-v0.3.2.md)。因此现有草稿 APK 59／DMG 100 和已经上传的 TestFlight 100 均不能作为包含本轮全部修复的安装包。

本次只提交源码及验证记录，不重复上传现有 100、不移动既有标签、不公开草稿。最终预发布仍须在最终源码上重新构建各平台安装包，Apple 使用新的构建号，Android／HarmonyOS 也按渠道规则递增。GitHub 账户构建锁定和 DevEco 登录这两个外部待完成项保持前述状态，不用旧包替代。

## 班车图标、主题提示及入口全称

后续源码补齐各端班车内容专属交通图标：状态、无班次和节假日不再复用事件／考试日历图标，桌面班次标记不再复用成绩勾选或作业时钟图标。刷新、外链仍保留通用操作语义。普通缓存、节假日和时段说明统一使用次要主题文字，主要图标使用主题主色；桌面提示容器改用主题中性色，真实错误提示不被普通提示替代。

各端显示文字、英文与无障碍动作统一为“打开教学云平台” / “Open Teaching Cloud Platform”。鸿蒙作业动作区在宽度不足时换行，不调整按钮原有高度、字号或内边距。修正安卓作业来源末尾箭头导致本地化未匹配的问题。网络获取、身份认证、缓存和上轮动效逻辑不改动，安卓网络异常仅作名称文案修订。

- 前端 244 通过、1 项 Windows 已安装 PE 测试按环境跳过；Vite 构建通过。包含各平台完整名称／专属图标契约，以及预设与极端自定义主题的提示／链接 4.5:1 对比度回归。Edge 实跑核对默认／玫瑰主题提示色和窄屏英文按钮；观察到的窄屏 CSS 视口为 487px，不将浏览器缩放后的值冒称 390px。
- Android Release JVM 294/294，Lint 0 errors / 73 warnings / 1 hint；应用及仪器 APK 编译通过。两项定向仪器测试通过、无跳过，包含中英入口名称／来源与辅助描述、有无班次、stale／节假日，以及默认／海洋／玫瑰／极端自定义主题的实际提示色与对比度。图标测试先发现同一公交矢量在缓存密度下有 4 个抗锯齿边缘像素差异；改用 99% 交并比识别轮廓，同一阈值也用于拒绝其它查询图标，未修改生产图形或控件几何来迁就测试。
- Apple 本地 Xcode：macOS 主题渲染 2/2、iOS 定向 UI 2/2，通过完整中英入口可见／可点击／不超出横向范围及原成绩／考试示例回归。共享 SwiftUI 在两端编译通过，本机验证新增公交 SF Symbols 可用，中英 `.strings` lint 通过。
- HarmonyOS release HAP 编译通过、Hypium 261/261，包含完整入口名称双语断言；公交符号沿用现有已编译资源。此小轮没有新开鸿蒙模拟器，不能称已做本轮鸿蒙真机／视觉回归。

本轮测试不使用真实个人凭据；日志在忽略目录 `release-artifacts/v0.3.2-shuttle-icons/`，Apple 结果在本机 `/tmp/wts-apple-animation-audit-{mac,phone}/Logs/Test/`。重型构建串行、仅一台模拟器运行，已关闭本轮安卓／iOS 测试设备和 Edge 临时测试页、停止临时 Vite 服务；没有操作用户其它页面或应用。仍是源码修正，不上传、审核或公开新的安装包，前述旧包与最终源码不一致的待发布边界继续有效。
