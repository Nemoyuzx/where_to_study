# Where To Study v0.3.2-prerelease

GitHub 预发布仍为草稿，未公开。11 个安装文件已补齐，各商店的 0.3.2 正式审核已提交；审核中不等于已经上架。课程、QMplus、新语言及新作业提醒属于 0.4.0，不包含在本版本。

## iOS / iPadOS

- 切换语言保留页面位置、草稿、筛选和已获取数据，加入全屏系统模糊过渡。
- iPhone 英文底栏四项等距，横屏与旋转返回保持正常布局和完整无障碍名称。
- 优化教学日历翻页、课程摘要、视图切换及隐私说明的动画，清理离页后的延迟回调。
- 班车补齐完整时刻表、法定节假日提醒、主题交通图标；账号密码说明更清楚，入口改为图标按钮。
- 竞赛数据新增备用源，主源较旧时自动使用更新的数据。

渠道：最新 0.3.2（108）已正式提交，正在等待审核。没有选入较新的 0.4.0 构建。

## macOS

- 全窗语言模糊过渡保留滚动、草稿、查询与日历状态。
- 保持设置和详情弹窗的稳定所有者，优化隐私、帮助及收藏的惰性布局。
- 同步完整班车表、假日提醒、主题图标、密码说明与竞赛备用源。

渠道：最新 0.3.2（108）正式审核中等待处理。GitHub 草稿保留原生 Universal DMG108；公共 DMG 为 ad-hoc 签名、未公证，与商店签名包不同。

## Android

- 日/周课程摘要连续展开、收起，支持快速反向和离页取消，不改变原控件尺寸及间距。
- 全屏语言模糊过渡保留草稿、滚动、查询、日历及缓存。
- 同步完整班车表、假日提醒、主题交通图标、清楚的密码说明和竞赛备用源。

渠道：0.3.2（65）已提交华为 Android、vivo 正式审核，均审核中。GitHub 草稿为同一固定证书 APK65，不上传 AAB。

## HarmonyOS

- 全屏语言模糊过渡等待目标布局就绪，保留位置和草稿，不给整个文字重排添加动画。
- 修复月翻页、日程展开收起、日周月年切换的延迟回调，保留原控件和布局尺寸。
- 同步完整班车表、假日提醒、主题交通图标、密码说明及竞赛备用源。

渠道：最新 0.3.2（1002042，build 2）已正式提交 AppGallery，当前预审中。复用此前 DevEco 已上传并通过云测试的包，未重复上传；鸿蒙包不上传 GitHub。

## Windows

同步语言模糊过渡和状态保持、班车表、假日提醒、主题图标、密码说明及竞赛备用源。新 x64 安装包已通过构建、GUI 子系统、版本、许可证和 HTTPS 端点检查。

渠道：已加入 GitHub 预发布草稿。它不是 Authenticode“已验证发布者”签名包，哈希与构建来源证明不等于代码签名。

## Linux / Ubuntu

同步上述桌面功能。x86_64 / aarch64 DEB、AppImage 已重新构建，架构、版本、法律文件、HTTPS、AppImage 隔离及 Ubuntu 24.04 DEB 安装门禁通过。

渠道：四个包已加入 GitHub 预发布草稿，未用旧包代替，未修改用户服务器的构建依赖。

## CLI / TUI

竞赛查询按真实生成时间比较主源和备用源，保留有界响应、缓存及失败回退。两架构终端包包含许可证和第三方声明，补法律文件时原二进制字节未改变。

渠道：四个终端包已加入草稿。CI 实跑版本及单元测试，不把 Mac 检查当成 Linux 主机运行测试。

## 工程与分发

使用用户指定的 nemoyuzx-byte 独立公开 Fork 构建，未迁移原仓库、修改账单、复制签名秘密或安排定时任务。修复失效的 Linux 封装工具下载固定值，保留哈希及架构硬校验；后续终端 CI 打包已补三份法律文件。

共 11 个文件的远端大小/SHA-256 与本地一致，未回下载 Release 校验。未上传校验侧文件、AAB、鸿蒙包或 iOS 归档，未公开草稿或移动标签；稳定入口仍为 0.3.1。详细回执见[商店同步记录](store-sync-v032-v040-2026-10-06.md)。

## English — changes by platform

### iOS / iPadOS

Preserves scroll, drafts, filters and data during full-window language blur. Keeps four iPhone tabs evenly spaced, improves calendar/privacy motion, and adds full shuttle tables, holiday notices, themed icons, clearer account guidance and a freshness-checked contest backup.

Delivery: latest 0.3.2 build108 submitted for formal review; waiting. No 0.4.0 build was selected.

### macOS

Adds full-window language blur with state preservation, stable/lazy presentations, and the shuttle, account and contest-source changes.

Delivery: build108 waiting for formal review. The draft Universal DMG is ad-hoc signed and not notarized.

### Android

Animates summary expansion without changing control sizes, preserves state during language blur, and includes themed shuttle tables/notices, account buttons and the contest backup.

Delivery: signed build65 is under Huawei Android/vivo formal review; APK65 is in the draft. No public AAB.

### HarmonyOS

Adds layout-ready language blur and calendar lifecycle fixes without resizing controls. Includes the shuttle, account and contest-source changes.

Delivery: build1002042, build2 formally submitted and in pre-review. Existing DevEco upload reused; no HarmonyOS GitHub package.

### Windows

Includes shared desktop updates and a newly built x64 installer with GUI-subsystem and package checks.

Delivery: added to the GitHub draft; not Authenticode-verified.

### Linux / Ubuntu

Includes desktop updates and new x86_64/aarch64 DEB/AppImage files with package checks and an Ubuntu 24.04 DEB installation gate.

Delivery: four files added to the GitHub draft.

### CLI / TUI

Includes freshness-checked contest backups, bounded responses and complete legal files. Executable bytes were preserved during archive completion.

Delivery: four Linux archives added to the GitHub draft. All 11 files are present, but the complete pre-release remains a draft and 0.3.1 remains stable. Course/QMplus/new-language/new-assignment features belong to 0.4.0.
