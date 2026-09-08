# macOS App Review — 2026-09-08

**已完成重新提交：macOS `0.2.8 (85)`，2026-09-08 21:51 +0800，App Store Connect 状态为“等待审核”。** 这是新一轮审核已排队，不表示 Apple 已批准上架。

[App Store Connect 提交记录（需账户权限）](https://appstoreconnect.apple.com/apps/6801054949/distribution/reviewsubmissions/details/1da525b0-b059-4dc5-9e35-7a49633b6a8b)

## 拒审与修复

Apple 于 2026-09-08 在 MacBook Pro（14-inch, Nov 2024）审核 `0.2.8 (77)`，提出以下三项问题。提交 ID 为 `1da525b0-b059-4dc5-9e35-7a49633b6a8b`。

| 规则 | 原问题 | 已完成的修复和说明 |
| --- | --- | --- |
| 4.1(b), Copycats | 学校相关内容可能造成授权或关联误解 | 移除侧栏 `BUPT` 和日历 `BUPT CLASSROOM PLANNER` 品牌标题；首次使用、凭据输入前、关于页面显示独立非官方说明；副标题采用“独立课表与空教室工具”，关键词删除学校名称。已向审核员说明学校名称仅指明适用教务服务、校区和公开通知来源，不代表学校运营、隶属、赞助或背书 |
| 5.2.5, Apple Products | 安装显示名含有 `Mac` | `.app`、产品名、可执行文件、`CFBundleName` 和 `CFBundleDisplayName` 统一为 `Where To Study`。Bundle ID、内部 target/scheme/模块名不变；正式及预览打包脚本增加名称校验 |
| 1.5, Developer Information | 旧 Support URL 只有 GitHub Issues | 发布专用支持页面，提供直接邮箱、反馈方式和常见问题；应用内新增离线帮助页；后台 Support URL 已改为专用页面 |

现有图标是通用课桌与日历，未发现校名或校徽。学校服务域名、真实服务范围和数据来源披露保留；不把事实性的适用范围描述隐藏掉。

## 源码与验证

修复源码提交为 `e6afd393be989965509dfb8482dee558e87d334e`，已推送 GitHub `main`。使用从已提交 HEAD `2e7aa28966507fa9be92d5f1577af2da708947c2` 创建的独立 worktree 精准移植审核修复，原工作区尚未提交的主题等功能保留，没有纳入这个商店构建。

- macOS 严格 Swift 并发、警告即错误构建与全量 XCTest：302 项中 301 项通过、1 项按设计跳过（需显式启用的线上班车 API 测试），0 失败。
- iOS Simulator 共享界面编译通过，未上传 iOS 构建。
- 18/18 现有 release-label 测试通过；Shell 语法、双语 strings、许可证、App Store 静态预检通过。
- 原工作区首次验证曾停在未提交的主题渲染测试；独立修复 worktree 的完整测试已经通过。

## 签名与上传

使用现有 Manual macOS 签名流程执行一次 `native-apple-app-store.sh upload macos`，通过环境变量指定 `APPLE_MARKETING_VERSION=0.2.8`、`APPLE_BUILD_NUMBER=85`。团队标识仅从本机现有签名证书解析，未写入仓库。

- 2026-09-08 21:15 +0800：日志出现 `Upload succeeded` 和 `EXPORT SUCCEEDED`。
- Universal `x86_64 arm64`，主应用与 Widget 签名、沙盒、App Group、隐私和许可证校验通过。
- 正式归档的三项名称均为 `Where To Study`；主 Bundle ID 保持 `com.nemoyu.wheretostudy.native.macos`。
- 后台完成处理，构建资源 ID 为 `6e2fc28c-518f-4739-bd11-13e64bdaad48`，已替换版本记录中的 build 77。

## 线上资料和回复

- [支持页面](https://github.com/Nemoyuzx/where_to_study/blob/main/SUPPORT.md) 已发布，已验证未登录也能看到联系邮箱和常见问题。
- 副标题、macOS 推广文本、描述、关键词、Support URL 和审核备注已保存。macOS 描述已移除错误的 iPhone/iPad 布局文案。
- 关键词：`个人课表,课程表,空教室,自习教室,教学日历,校历,课程提醒,班车查询,活动日程,校园工具,教室查询`。
- 2026-09-08 21:31 +0800：已发送 [英文审核回复](../native/apple/AppStore/review-response-en.md)，消息列表确认送达。
- 保留原有私有审核账号、联系人、备案信息、内容权利和发布方式配置。

## 真实截图

开发者明确授权用其真实账号截取主功能页面，排除设置页，并要求不打扰前台使用。最终截图由后台 CUA 读取实际应用窗口，通过隐藏的本机页面保存；不再使用系统截图覆盖层或切换前台窗口。截图仅用于 App Store Connect，不提交真实图片到公开 Git。

五张截图按以下顺序上传并替换旧图，重新加载页面已确认顺序和数量：

1. `01-planner.png` — 真实课表联动的空教室查询。
2. `02-calendar-week.png` — 真实周课表。
3. `03-calendar-month.png` — 真实月历。
4. `04-shuttle.png` — 班车查询。
5. `05-important-events.png` — 重要事件查询。

成片均为 `1280 × 800`、RGB PNG、无 Alpha。仅做等比缩放和深色补边，未裁切内容、拉伸或改写界面。五张原图与成片均逐张目视检查：完整侧栏和新品牌可见，无设置页、账号密码字段、示例横幅或外部窗口叠层。原图、旧版截图备份和带 SHA-256 的 `manifest.json` 保存在忽略目录 `release-artifacts/app-store/review-resubmission/screenshots/`。

## 提交结果

2026-09-08 21:51 +0800 完成“更新审核 → 重新提交至 App 审核”。提交详情同时显示 `macOS App 0.2.8`、构建 `0.2.8 (85)` 和“等待审核”。审核回复和五张真实截图均已包含在本次提交准备中。

本次没有创建或修改 GitHub Release。后台截图接收页面和临时本机服务已关闭。签名与测试日志保存在忽略目录 `release-artifacts/app-store/review-resubmission/`。

## 同步到 macOS 0.2.9

按开发者后续要求，相同审核修复已构建为 macOS `0.2.9 (86)` 并于 2026-09-08 22:09:37 +0800 上传成功。新主应用及 Widget 的版本、Universal 架构、签名、名称与沙盒校验通过。此次只做 0.2.9 构建同步和上传，未变更 0.2.8 (85) 审核、TestFlight 群组、iOS 或 GitHub Release。详细范围和回执见 [0.2.9 发布记录](release-v0.2.9.md)。
