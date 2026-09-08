# macOS App Review — 2026-09-08

## 实际审核记录

通过 App Store Connect 实时读取，审核日期为 2026-09-08，设备为 MacBook Pro（14-inch, Nov 2024），被审构建为 **macOS 0.2.8 (77)**。提交 ID：`1da525b0-b059-4dc5-9e35-7a49633b6a8b`，状态“问题未解决 / 被拒绝”。

[审核原文（需账户权限）](https://appstoreconnect.apple.com/apps/6801054949/distribution/reviewsubmissions/details/1da525b0-b059-4dc5-9e35-7a49633b6a8b)

| 规则 | 审核员指出的问题 | 本地修复 |
| --- | --- | --- |
| 4.1(b), Copycats | 应用或元数据中存在类似北京邮电大学的内容，可能造成授权或关联误解；要求说明与品牌所有者的关系 | 去除侧栏 `BUPT`、日历 `BUPT CLASSROOM PLANNER` 品牌标题；使用应用自身名称，首次使用和凭据输入前显示独立非官方说明；副标题和关键词移除学校品牌 |
| 5.2.5, Apple Products | 设备显示的安装应用名含 `Mac` | 产品、`.app`、可执行文件、`CFBundleName` 和 `CFBundleDisplayName` 统一为 `Where To Study`；保留原主 Bundle ID、内部 target/scheme/模块名；修正正式与预览打包路径并增加名称校验 |
| 1.5, Developer Information | Support URL 的 GitHub Issues 页面没有提供可用的求助信息 | 增加应用内离线“帮助与支持”页，提供开发者邮箱、反馈入口和常见问题；新增 `SUPPORT.md`，本地商店资料改为专用支持页地址，发布后才能填入后台 |

现有图标是通用绿色课桌与日历，未发现校名或校徽，保持不变。学校服务域名、班车和作业的数据来源、真实服务范围和隐私披露保留，不隐藏第三方数据来源。

后台 macOS 描述实际误用了包含 iPhone/iPad 布局的 iOS 文案，推广文本与关键词仍突出学校名称；审核备注只有备案信息。本次已整理本地平台文案与完整审核说明，后台字段尚未更新。

## 本地验证

- `native-apple-app-store.sh preflight macos` 通过，当前本地配置为 `0.2.8 (79)`，没有签名或上传。
- 本机 Xcode 严格 Swift 并发、警告视为错误的 macOS Debug 构建通过；实际 `Where To Study.app` 的 `CFBundleName`、`CFBundleDisplayName`、`CFBundleExecutable` 均为 `Where To Study`，Bundle ID 保持 `com.nemoyu.wheretostudy.native.macos`。生成的 scheme 和测试宿主路径也使用新 `.app` 名。
- 共享界面的 iOS Simulator 构建通过（未启动模拟器）。
- 18/18 现有 release-label 测试通过；Shell 语法、双语 strings 和 `git diff --check` 通过。
- 首次全量 macOS 回归在既有 `ColorThemeMacRenderingTests.testSettingsAndWidgetRenderAcrossThemesAndAppearances` 停止推进，已中断，因此不宣称全量测试通过。随后单独运行本次 `AppStorePresentationTests` 与 `PrivacyConsentTests`，6/6 通过。修复截图工具的 RGBA 格式并增加非空像素检查后，4 项审核测试再次通过；中英文首次使用页与帮助页共 4 张图已逐张目视检查，文字完整可读。

离屏渲染的主界面附件能够检查日历标题和详情内容，但不能完整捕获系统原生侧栏，因此不作为完整主窗口 QA 或商店截图；侧栏目前完成源码与编译检查，正式提交仍需实际窗口截图检查。所有附件均为带 Alpha 的内部 QA 图，不是可直接上传的商店素材。

日志、测试结果与界面 QA 附件保存在被 Git 忽略的 `release-artifacts/macos-review-2026-09-08/`。工作树原有跨平台主题与日历修改保留；本次不变更版本号、上传构建或创建 Release。

## 重新提交前仍需完成

1. 发布 `SUPPORT.md`，以未登录状态验证支持页能够显示邮箱、反馈方式与常见问题，再把 macOS Support URL 改为 `https://github.com/Nemoyuzx/where_to_study/blob/main/SUPPORT.md`。
2. 使用本次修复源码和新的递增构建号签名、上传 macOS；选择新构建，不能再次选择被拒的 build 77。
3. 更新 macOS 推广文本、关键词、平台描述以及共享 App 信息副标题；共享字段会涉及同一 App 记录的 iOS，需要一并核对。使用修复构建重拍商店截图，旧截图仍有学校品牌眉题。
4. 按开发者确认的情况回复审核员：学校名称只说明适用教务服务、校区和数据来源；本应用与学校不存在隶属、赞助或背书关系，不使用学校名称作为产品品牌，也不使用学校校徽。请求按这些明确的适用范围说明重新审核，并在仍有具体误导元素时请审核员指出。
5. 将新构建号、帮助页路径、独立身份提示位置与示例模式操作写入审核备注，再决定回复和重新提交。

本次没有向 Apple 发送回复、变更线上商店资料、上传构建或重新提交审核。

## 本地材料

- [支持页面](../SUPPORT.md)
- [中文元数据](../native/apple/AppStore/metadata-zh-Hans.md)
- [中文审核说明](../native/apple/AppStore/review-notes-zh-Hans.md)
- [英文审核说明](../native/apple/AppStore/review-notes-en.md)
- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

## 完整重新提交进度

2026-09-08 开发者授权完成支持页发布、修复构建上传、资料更新、回复和重新提交。使用从已提交 HEAD `2e7aa28966507fa9be92d5f1577af2da708947c2` 创建的独立 worktree，仅移植审核修复，未纳入原工作区未提交的主题等功能。后台已核实 macOS 最新 TestFlight 为 `0.2.9 (81)`、iOS 最新为 `0.2.9 (84)`；本次沿用被拒的 macOS 商店版本 `0.2.8`，使用新构建号 `85`。

独立修复 worktree 的 macOS 严格构建和全量 XCTest 已通过：302 项中 301 项通过、1 项按设计跳过（需要显式启用的线上班车 API 测试），0 失败。此前原工作区的主题测试卡住未出现在这个仅含审核修复的提交中。
