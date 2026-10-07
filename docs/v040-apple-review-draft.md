# Apple 0.4.0 审核资料待保存稿

2026-10-06：iOS / iPadOS、macOS 0.4.0 build 121 上传成功由本轮构建回执确认。本稿仅供填写并保存，不授权正式审核、Beta 审核、发布或通知测试者。0.3.2 build 108 正在等待审核，不能撤回、覆盖或替换。

2026-10-07用户重新登录后，iOS／macOS build121的独立TestFlight测试内容均已保存并刷新核验。随后iOS0.3.2已可分发，iOS0.4.0正式草稿已保存并关联121及三张Duo图，未提交审核；macOS仍受0.3.2审核限制。此前无入口的记录保留为历史，不撤回或覆盖旧版本。

保留用户现有描述、工具分类、联系资料、隐私配置和审核凭据。本稿不记录审核密码，也不提供新的私人账号。新Duo素材使用无学校品牌、无开发者横幅的虚构示例数据，原0.3.2截图未改。

## 最新正式草稿检查点（2026-10-07 后续）

iOS 0.3.2 已显示“可分发”，新增版本入口已开放；此前“两端均无入口”的记录为历史状态。已在独立工作页创建 iOS 0.4.0 正式草稿，状态“准备提交”，关联已上传的 build 121（`8caaa067-7d73-41bb-9d5a-f71bbfd74213`）。现有商店本地化只有简体中文：在该现有语言填写中文更新内容，保留继承的原审核备注并追加中英公开审核说明；未新增英文商店本地化或改写既有描述。重新加载后两字段与填写值完全一致，保存按钮禁用。

已从独立素材库引用三张处理完成的 Duo 原图到 **新 iOS 0.4.0** 的 iPhone Duo 截图槽，重新加载后为 3/10：外屏课程、内屏日历、内屏课程。只引用已有素材，没有重新上传、删除或创建重复素材；未点击素材或版本“添加以供审核”。旧 iOS 0.3.2 内容未改。

macOS 0.3.2 仍显示“正在等待审核”，旁边保留 0.3.1“可分发”，没有 macOS 新版本入口；因此未创建 macOS 0.4.0 正式草稿，原有 build 121 TestFlight 测试资料保留。未接受协议、提交正式／Beta 审核、通知测试者或改动联系人、隐私、分类、审核凭据与发布配置。

非敏感凭证：`review-draft-proofs/ios040-formal-draft-duo-saved.jpg`（位于本轮 ignored 交付目录），仅版本标题、保存控件与Duo截图区域，不含审核登录或联系字段。

## iOS / iPadOS：此版本新增内容（中文）

新增五款配色，现提供十款预设主题及自定义颜色；支持十三种界面语言。新增作业提醒，支持教学云平台及 QMplus 的课程任务；首次同步不会将旧任务作为新任务提醒。课程与任务缓存可跨重启复用，日历和课程页共享同步结果。保留全天截止日期区，并在日、周时间轴按北京时间显示准确截止时刻的主题色细条；明确未提交作业标有红点。改进 iPhone Duo 开合布局与状态连续性，保持 iPad 原有导航体验。改进 QMplus 官方 SSO 登录、可选安全自动填写与会话恢复。

## iOS / iPadOS：What's New (English)

Adds five color presets, bringing the total to ten, alongside custom colors and thirteen interface languages. New coursework notices support the teaching-cloud platform and QMplus; the first synchronization does not announce existing tasks as new. Course and coursework caches persist across restarts and are shared by calendar and course views. The all-day deadline area remains available, with theme-colored deadline strips at precise Beijing-time positions in day and week timelines. Explicitly unsubmitted assignments have a red indicator. Improves iPhone Duo folding layouts and state continuity while preserving iPad navigation. Improves official QMplus SSO sign-in, optional secure autofill and session restoration.

## iOS / iPadOS：审核说明（中文）

本次候选版本为 0.4.0（121），不替代正在等待审核的 0.3.2（108）。Where To Study 是独立、非官方、免费开源且无盈利性质的工具，不代表学校或教学平台；没有广告、应用内购买或付费培训。公开查询不要求登录，个人课程、成绩和作业仅在用户选择相应官方服务后查询。请沿用现有审核登录资料，不新增私人账号。QMplus 使用官方 SSO：用户可自愿将独立登录资料保存至本机系统安全存储，并明确授权在核验的官方页面自动选择匹配账号、填写账号密码；验证码、MFA 或未识别分支仍由用户在官方页面完成，不绕过认证。应用不收集上述凭据到开发者服务器。首次完整任务同步只建立基线，后续出现新任务才提醒。截止细条是时间点提示，不是有持续时长的课程；不明确的截止时间不会编造时刻。示例模式和商店截图使用虚构数据，不代表实时账户数据。源码：https://github.com/Nemoyuzx/where_to_study，GPL-3.0-only。

## iOS / iPadOS：Review Notes (English)

This candidate is version 0.4.0 (121), separate from version 0.3.2 (108), which is already waiting for review. Where To Study is an independent, unofficial, free open-source utility with no profit-making purpose, advertisements, in-app purchases or paid training. It does not represent a school or teaching platform. Public information does not require sign-in; personal courses, grades and coursework are queried only when users choose the relevant official services. Please retain the existing review credentials; no new private account is supplied. QMplus uses official SSO. Users may voluntarily save separate credentials in the device's system secure storage and explicitly authorize account selection and autofill on verified official pages. CAPTCHA, MFA and unrecognized steps remain under the user's control; authentication is not bypassed. These credentials are not collected on the developer's servers. Initial complete synchronization establishes a baseline; later newly discovered tasks generate notices. Deadline strips indicate time points, not class durations, and unknown times are not invented. Demonstration mode and store screenshots use fictional data. Source: https://github.com/Nemoyuzx/where_to_study (GPL-3.0-only).

## macOS：此版本新增内容（中文）

新增五款配色，现提供十款预设主题及自定义颜色；支持十三种界面语言。新增作业提醒，支持教学云平台及 QMplus 的课程任务；首次同步不重复提醒旧任务。课程与任务缓存可跨重启复用，课程页和日历共用同步结果。保留全天截止日期区，并在日、周时间轴按北京时间显示准确截止时刻的主题色细条；明确未提交作业标有红点。改进 QMplus 官方 SSO 登录、可选安全自动填写与会话恢复，保留 macOS 既有窗口与导航体验。

## macOS：What's New (English)

Adds five color presets, bringing the total to ten, alongside custom colors and thirteen interface languages. New coursework notices support the teaching-cloud platform and QMplus without announcing existing tasks on initial synchronization. Course and coursework caches persist across restarts and share synchronization results between course and calendar views. The all-day deadline area remains available, with theme-colored strips at precise Beijing-time positions in day and week timelines. Explicitly unsubmitted assignments have a red indicator. Improves official QMplus SSO sign-in, optional secure autofill and session restoration while preserving the established macOS window and navigation experience.

## macOS：审核说明（中文）

本次候选版本为 0.4.0（121），独立于正在等待审核的 0.3.2（108）。应用为独立、非官方、免费开源且无盈利性质的工具，不代表学校；无广告、应用内购买或付费培训。公开查询无需登录，个人查询由用户主动使用。沿用现有审核登录资料、联系信息和隐私配置，不新增私人账号。QMplus 官方 SSO 支持自愿保存独立凭据至本机系统安全存储并授权官方网页自动填写，验证码和 MFA 仍由用户完成；凭据不收集到开发者服务器。新作业提醒复用正常同步结果，不通过额外请求探测；首次同步及缓存恢复不把旧任务算作新增。时间轴细条显示准确截止时刻，不代表课程持续时长。示例数据不代表实时账户数据。本 macOS 说明不包含 iPhone Duo 适配，也不涉及 Android 权限。源码：https://github.com/Nemoyuzx/where_to_study，GPL-3.0-only。

## macOS：Review Notes (English)

This candidate is version 0.4.0 (121), separate from version 0.3.2 (108), which is already waiting for review. This is an independent, unofficial, free open-source utility with no profit-making purpose, advertisements, in-app purchases or paid training. It does not represent a school. Public queries require no login; personal queries are initiated by the user. Please retain existing review credentials, contacts and privacy settings. QMplus official SSO supports voluntary credential storage in the device's system secure storage and authorized autofill on verified official pages; CAPTCHA and MFA remain user-controlled. Credentials are not collected on the developer's servers. Coursework notices reuse normal synchronization without extra detection requests. Initial synchronization and cache restoration do not announce old tasks as new. Timeline strips mark precise deadlines, not class durations. Demonstration data is fictional. These macOS notes do not claim iPhone Duo support or Android permissions. Source: https://github.com/Nemoyuzx/where_to_study (GPL-3.0-only).

## 保存与截图检查记录

- 正式0.4.0草稿：iOS 0.3.2 可分发后已创建并保存独立 0.4.0；macOS 仍无入口，不撤回其正在审核的 0.3.2。
- iOS / iPadOS正式资料保存：已保存现有简体中文更新内容和中英审核备注，关联 121、引用三张 Duo 图；保留既有描述、联系、隐私及审核凭据，旧 0.3.2 未改。详细回执见上方最新检查点。
- macOS 正式资料保存：2026-10-07 已登录复核，侧栏仅 0.3.2“正在等待审核”和 0.3.1“可分发”；macOS 已发布版本页没有新增版本入口，未撤回或改动 0.3.2，未创建独立 0.4.0 正式草稿。上方 macOS 中英正式资料继续作为待粘贴稿，不冒称已保存。
- TestFlight测试资料：iOS／iPadOS和macOS build121中英测试内容均已保存，刷新后全文一致；不提交Beta审核、不加群组、不通知测试者。
- Duo官方截图规格已于2026-10-07核对：外屏1398×2034（或横屏反向）、内屏2007×2853（或横屏反向）；PNG/JPEG，不含Alpha。已清理本轮两条未完成占位并逐张重传，三图均已被识别为Duo并准备提交；已引用到新iOS0.4.0槽位3/10，未提交审核。[Apple官方规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- 不点击“添加以供审核”“提交审核”“发布”或“通知测试者”。

### macOS build 121 TestFlight 实际保存结果（2026-10-07）

在独立 Edge Dev 工作页，仅修改 macOS 0.4.0（121）专属“测试内容”（What to Test），保存中英测试清单：新增五款配色预设（共十款预设及自定义颜色）、十三语言、新作业提醒、来源正确的缓存课程详情、北京时间截止细条及明确未提交红点、跨重启缓存、QMplus 官方 SSO / 可选安全自动填写 / 用户自行完成验证码与 MFA，以及 macOS 原有窗口导航。未混入 iPhone Duo 或 Android 权限。

构建 ID：`181a3fd9-75e5-4693-9946-61fa74247389`。页面保存后显示“已保存”；重新加载核对最终 1,851 字符文本与填写值完全相同。页面提示版本 0.4.0 只能同时有一个构建提交 Beta 审核；本轮未提交 Beta 审核、未添加群组或通知测试者。未修改共享 Beta Review 字段、旧版本元数据、现有描述 / 截图 / 分类 / 隐私 / 联系或审核凭据，也未重复上传构建。

非敏感证据：`release-artifacts/store-sync-2026-10-06/v0.4.0-build121/review-draft-proofs/macos121-testflight-saved.jpg`，仅截取版本标题、保存控件及测试内容区域，不含账户菜单或审核登录资料。此保存仅代表TestFlight build121的测试内容，不代表正式0.4.0审核资料已保存或已送审。

### iOS / iPadOS build121实际保存结果

构建ID `8caaa067-7d73-41bb-9d5a-f71bbfd74213`；中英测试内容2161字符，保存后刷新与填写值逐字一致，保存按钮禁用。包括课程展开／详情、共享缓存、授权QMplus自动填写与本人MFA、新作业提醒、额外主题色截止细条及明确未交红点、十三语言／十主题及Duo状态连续性；不承诺强制蜂窝或永久登录。未改共享Beta Review、联系人、审核凭据、既有描述/截图/分类；未提交Beta审核、通知或重复上传121。证据 `review-draft-proofs/ios121-testflight-saved.jpg`。

### Duo截图与资料库

真正Duo27.1模拟器、build121、内置虚构示例数据，经用户授权用官方`simctl io screenshot`导出原始PNG。三张最终图分别2007×2853、2853×2007和2034×1398，均无Alpha，无外部设备框、学校品牌、账号或私人数据，不缩放或涂改。临时DEBUG截图辅助只隐藏开发者横幅，并未进入TestFlight121；拍摄后已恢复源码，公共DMG也从恢复后的源码重新生成。

三图在独立素材库准备，不修改0.3.2截图。用户要求重传后，仅删除本轮未完成的内屏日历／外屏课程两条占位，原图仍本地保留，再逐张上传；两图均处理完成，与原内屏课程图合计三张。内屏课程ID `74000019-55fd-8ce5-801c-aeed1a9b25c6`不变；新内屏日历ID `ce400019-55fd-8ce5-802c-332eec94f266`，新外屏课程ID `cb400019-55fd-8ce5-8026-eff0b17981b6`。独立页面读取确认三张均可“添加以供审核”，未点击该按钮；随后只引用到新iOS0.4.0草稿，刷新为3/10。文件、尺寸及SHA在忽略目录 `duo-store-screenshots/manifest.json`，原始和最终图均保留。
