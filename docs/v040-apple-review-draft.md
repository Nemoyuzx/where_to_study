# Apple 0.4.0 审核资料待保存稿

2026-10-06：iOS / iPadOS、macOS 0.4.0 build 121 上传成功由本轮构建回执确认。本稿仅供填写并保存，不授权正式审核、Beta 审核、发布或通知测试者。0.3.2 build 108 正在等待审核，不能撤回、覆盖或替换。

Edge Dev 的 App Store Connect 会话已过期，页面要求重新登录。尚未核实是否能并行新建正式 0.4.0 草稿，也未保存以下文字到后台。TestFlight 测试资料与正式版本资料分别记录，保存一处不代表另一处已完成。

保留用户现有去学校名的描述、截图、工具分类、联系资料、隐私配置和审核凭据。本稿不记录审核密码，也不提供新的私人账号。旧带学校名或开发者横幅的截图不上传；Duo 素材另行准备。

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

- 正式 0.4.0 草稿能否新建：未核实，等待已登录会话恢复。
- iOS / iPadOS 正式资料保存：未完成。
- macOS 正式资料保存：未完成。
- TestFlight 测试资料保存：未完成；即使后续保存也不提交 Beta 审核。
- Duo 官方截图规格已于 2026-10-07 核对：外屏1398×2034（或横屏反向）、内屏2007×2853（或横屏反向）；PNG/JPEG，不含Alpha。实际截图管理器是否提供独立槽仍待登录后确认，不根据模拟器尺寸推定商店接受状态。[Apple官方规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
- 不点击“添加以供审核”“提交审核”“发布”或“通知测试者”。
