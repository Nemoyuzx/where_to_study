# iOS 0.2.8 App Review preventive fixes

**已于 2026-09-08 完成 iOS `0.2.8 (87)` 重新提交，App Store Connect 状态为“等待审核”。** 本次按开发者要求，将 macOS 审核反馈相关修复同步到 iOS，提前修正学校名称适用范围说明、应用名称和开发者支持信息。

[新 iOS 提交记录（需账户权限）](https://appstoreconnect.apple.com/apps/6801054949/distribution/reviewsubmissions/details/1a97e8ba-4cfc-4232-a1ec-f044826a3694)

## 实现

- 复用已提交的共享修复：侧栏显示“独立非官方工具”，日历品牌标题为“WHERE TO STUDY”；首次使用、账户输入前和关于页面均解释独立非官方身份；iPhone/iPad 可打开离线帮助页，直接联系开发者。
- iOS 产品、`.app`、可执行文件、`CFBundleName` 和 `CFBundleDisplayName` 统一为 `Where To Study`。保留 `WhereToStudyiOS` 模块/target/scheme，以及原 Bundle ID `com.nemoyu.wheretostudy.native.macos`。两个 Widget target 和 macOS 配置未变。
- 正式上传与未签名 iOS 归档脚本采用新路径，并检查三项名称字段。iOS 专项实现提交为 `3ee54d8`，截图方向处理提交为 `776e2e5`。
- 学校名称仅说明当前适用教务服务、校区和数据来源，不表示学校运营、隶属、赞助或背书。

## 验证

- iPhone 17 Pro Max / iOS 26.5：325 项单元测试中 324 项通过、1 项按设计跳过（需显式启用的线上班车测试）；新增中英文审核 UI 流程 2/2 通过。
- iPad Pro 13-inch (M5) / iOS 26.5：同一中英文审核 UI 流程 2/2 通过。
- UI 验证覆盖首次非官方提示、账户说明、帮助页入口、可选取的邮箱文本、邮件链接可达性和关闭帮助页。测试不点击邮件链接。
- 18/18 现有 release-label 测试、Swift 严格并发和警告即错误构建、Shell 语法、双语资源与 App Store 预检通过。

## 签名与上传

使用现有单次 `native-apple-app-store.sh upload ios` 流程，设置 `APPLE_MARKETING_VERSION=0.2.8`、`APPLE_BUILD_NUMBER=87`、`APPLE_IOS_SIGNING_STYLE=Automatic`，团队仅从本机现有证书解析，未提交签名配置。

2026-09-08 22:54:10 +0800 收到 `Upload succeeded`，随后 `EXPORT SUCCEEDED`。主应用与 Widget 的版本均为 `0.2.8 (87)`、架构为 arm64；签名归档及本地 Apple Distribution 导出验证通过，正式导出不含 `get-task-allow`。Automatic 中间 archive 使用 Development 签名，不能与最终分发签名混淆。

## iPad 真实截图

旧 iPad 五张商店截图含有被移除的 BUPT 品牌标题，因此重新拍摄；iPhone 旧主页面截图没有该标题，保留原图。

按开发者此前明确授权，仅复制其真实 `schedule.json` 和当天 `classrooms.json` 到本次新建的隔离模拟器应用容器；没有读取或复制密码、Keychain 或整个偏好文件。App 以正常运行模式展示真实缓存课表和教室，公开班车/活动通过真实 API 读取；未开启示例模式。

后台运行截图 UI 测试，五个页面分别为空教室、周历、月历、班车和重要事件，不包含设置页或凭据字段。使用本地签名的模拟器构建重拍，目视确认未签名截图构建出现的安全存储提示已消失。所有成片为正确方向的 `2752 × 2064` RGB PNG、无 Alpha，未裁切、拉伸或改写界面内容。截图、方向元数据和 SHA-256 manifest 仅保存在忽略目录，不提交真实图片到公开 Git。

## 后台更新

旧 iOS `0.2.8 (77)` 正在等待审核。App Store Connect 明确要求先从审核中移除才能替换构建；在新包、文案和截图准备就绪后，已移除旧提交，更换为 build 87 并完成重新提交。macOS 的待审提交不变。本次不调整 TestFlight 测试群组、iOS 0.2.9 或 GitHub Release。

本地证据目录：`release-artifacts/ios-028-review-sync/`，包括测试结果、上传日志、真实缓存来源摘要、正式归档验证和 `ipad-final/manifest.json`。

- 新构建资源 ID：`dfd5bbba-3b6f-4430-b736-65166536d121`。
- 已更新 iOS 推广文本、描述、关键词、Support URL 和审核备注；学校名称仅用于适用范围与来源说明，支持页含直接邮箱。原审核账号、联系人、备案信息和发布方式保留。
- 五张新 iPad 13 英寸截图上传并按空教室、周历、月历、班车、重要事件排列；重新加载页面确认保存。iPhone 原有五张主页面截图保持不变。
- 完成“添加以供审核 → 提交以供审核”，界面确认“已提交 1 个项目”，iOS `0.2.8` 状态变为“正在等待审核”。
- 新建的两个测试模拟器已关闭；原工作区其他未提交修改保留，未打开模拟器前台窗口。
