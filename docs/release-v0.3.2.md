# Where To Study v0.3.2

本版改进语言切换、教学日历动画、班车信息、账号说明和竞赛数据回退，并提供 11 个图形客户端及 Linux 终端工具附件。共享课程目录、QMplus、扩展至 13 种语言和新增作业提醒属于 0.4.0，不包含在本版新增功能中。

## 下载与安装

普通用户按设备选择一个图形客户端即可；CLI/TUI 是另供 Linux 终端用户使用的工具。附件已按正式版本命名，沿用此前校验通过的安装包内容，没有重新构建或混入0.4.0功能。

| 设备 | 选择附件 | 安装方式 |
| --- | --- | --- |
| Android | Universal `.apk` | 在设备上打开 APK，核对来源后按系统提示安装。 |
| macOS，Intel 或 Apple Silicon | Universal `.dmg` | 打开 DMG，将 Where To Study 拖到 Applications。 |
| Windows，Intel／AMD 64 位 | `windows-x64-setup.exe` | 双击安装程序。 |
| Ubuntu／Debian，Intel／AMD 64 位 | `linux-x86_64.deb` | 用软件安装器打开，或在下载目录执行 `sudo apt install ./文件名.deb`。 |
| Ubuntu／Debian，ARM 64 位 | `linux-aarch64.deb` | 同上，选择 ARM 64 位包。 |
| Linux AppImage | 对应架构的 `.AppImage` | 赋予“作为程序执行”权限后打开；系统仍需满足运行依赖。 |
| Linux 命令行／终端界面 | 对应架构的 `where-to-study-cli-*.tar.gz` 或 `where-to-study-tui-*.tar.gz` | 解压后运行 `./where-to-study-cli --help` 或 `./where-to-study-tui --help`。 |

`x86_64` 对应 Intel／AMD 64 位电脑，`aarch64` 对应 ARM 64 位设备。GitHub 的 Source code 下载项是源码，不是安装包；Linux 终端文件不能直接在 macOS 或 Windows 上运行。iOS 和鸿蒙通过各自的测试／商店渠道分发，不在这 11 个 GitHub 附件中。

## iOS / iPadOS

- 切换语言时保留页面位置、输入草稿、筛选和已获取数据，加入全屏系统模糊过渡。
- iPhone 英文底栏四项等距，横屏与旋转返回保持布局及完整无障碍名称。
- 优化教学日历翻页、课程摘要、视图切换及隐私说明动画，清理离页后的延迟回调。
- 班车增加完整时刻表、法定节假日提醒和主题交通图标；账号密码说明更清楚，入口改为图标按钮。
- 竞赛数据增加备用源，按真实更新时间选择较新的可用数据。

0.3.2（108）已提交商店审核，没有选入 0.4.0 构建。提交审核不代表已经上架，可安装版本以 Apple 页面为准。

## macOS

- 全窗语言模糊过渡保留滚动、草稿、查询及日历状态。
- 保持设置和详情弹窗的稳定所有者，优化隐私、帮助及收藏的惰性布局。
- 同步完整班车表、假日提醒、主题图标、密码说明和竞赛备用源。

0.3.2（108）已提交商店审核，GitHub 附件为原生 Universal DMG108。公共 DMG 使用 ad-hoc 临时签名、未经过 Apple 公证，与商店签名包不同；商店是否上架以实际页面为准。

## Android

- 日／周课程摘要支持连续展开、收起、快速反向与离页取消，保留原控件尺寸及间距。
- 全屏语言模糊过渡保留草稿、滚动、查询、日历和缓存。
- 同步完整班车表、假日提醒、主题交通图标、密码说明和竞赛备用源。

0.3.2（65）已提交华为 Android、vivo 商店审核。GitHub 附件是同一固定证书的 APK65，不分发 AAB；商店审核状态与 GitHub 正式发布相互独立，不把审核提交写成已经上架。

## HarmonyOS

- 全屏语言模糊过渡等待目标布局就绪，保留页面位置和草稿，不为整页文字重排叠加动画。
- 修复月翻页、日程展开收起和日／周／月／年切换的延迟回调，保留原控件及布局尺寸。
- 同步完整班车表、假日提醒、主题交通图标、密码说明和竞赛备用源。

0.3.2（1002042，build 2）已提交 AppGallery 审核，复用此前 DevEco 上传并通过云测试的包，没有重复上传。鸿蒙包不放入 GitHub 附件；云测试通过、审核提交与正式上架是不同状态。

## Windows

同步语言模糊过渡及状态保持、班车表、假日提醒、主题图标、密码说明和竞赛备用源。x64 安装包已通过构建、GUI 子系统、版本、许可证与 HTTPS 端点检查，并有 Windows CI 安装验证。

该安装包没有公众信任的 Authenticode“已验证发布者”签名。文件哈希、CI 记录和构建来源证明不能替代代码签名。

## Linux / Ubuntu

同步上述桌面功能。x86_64／aarch64 的 DEB、AppImage 均经过重新构建和架构、版本、法律文件、HTTPS 端点及 AppImage 隔离检查，Ubuntu 24.04 DEB 安装门禁通过。

本页提供四个图形安装包，没有用旧包替代，也没有为打包修改用户服务器上的构建依赖。

## CLI / TUI

竞赛查询按真实生成时间比较主源和备用源，保留有界响应、缓存和失败回退。四个 Linux 压缩包包含可执行文件、项目许可证、第三方许可证和第三方声明；补齐法律文件时原二进制字节没有改变。

两架构的版本输出与单元测试由 Linux CI 实际执行。macOS 上的检查没有被当作 Linux 主机运行测试，也不据此宣称所有真机、所有发行版或所有代码扫描均已通过。

## 工程、来源与分发

正式版本源码使用最终 0.3.2 热修复提交 `7eae8d444b671d4bc4dffaccf2ec9ec80768bdf2`。历史 `v0.3.2-prerelease` 标签保留原指向 `5c951520118927600bc880afa87fc0e0124ef5e0`，不移动或覆盖；它不是这些后续更新附件的统一构建提交。

Windows 的 CI 来源为 `369c6373459f056509bc1b98410e89951ca47cd3`；Linux 与终端二进制来源为 `b07c7a7d46447f87d1a8bc8788df17d4601cf6b3`。原生包对应最终热修复输入 `fced615edbf41a9a61dcf5826fdb00c8f3c8a83b`。这些提交与最终热修复提交之间的差异限于 CI、打包、测试或文档，业务输入保持一致；版本仍为 0.3.2，没有混入 0.4.0。

Windows、Linux 及终端包通过独立公开 Fork 的 CI 构建。修复了 Linux 封装工具下载固定值，保留哈希和架构硬校验；后续终端 CI 也已补上三份法律文件。分支构建与本地补齐后的终端归档不声称具有标签 attestation；标签名称或正式发布状态的变化不会追溯生成这类证明。

11 个附件的远端名称、大小和 SHA-256 已与本地文件逐件核对一致，核验时未回下载 Release。未把 SHA-256 sidecar、AAB、鸿蒙包或 iOS 归档加入附件。具体渠道回执和验证范围见[商店同步记录](https://github.com/Nemoyuzx/where_to_study/blob/codex/v040-localization/docs/store-sync-v032-v040-2026-10-06.md)与[签名及来源说明](https://github.com/Nemoyuzx/where_to_study/blob/v0.3.2/docs/code-signing.md)。

## English — changes by platform

### iOS / iPadOS

Preserves scroll, drafts, filters and data during full-window language blur. Keeps four iPhone tabs evenly spaced, improves calendar/privacy motion, and adds complete shuttle tables, holiday notices, themed icons, clearer account guidance and a freshness-checked contest backup. Version 0.3.2 build108 was submitted for store review; submission does not mean availability. No 0.4.0 build was selected.

### macOS

Adds full-window language blur with state preservation, stable/lazy presentations and the shuttle, account and contest-source improvements. The Universal DMG108 is ad-hoc signed and not notarized; it is separate from the store-signed build108 submitted for review.

### Android

Animates summary expansion without changing control sizes, preserves state during language blur, and includes themed shuttle tables/notices, account buttons and the contest backup. Signed build65 was submitted to Huawei Android and vivo. The GitHub attachment is APK65; no public AAB is included.

### HarmonyOS

Adds layout-ready language blur and calendar lifecycle fixes without resizing controls. Includes the shuttle, account and contest-source changes. Build1002042, build2 was submitted to AppGallery using the prior DevEco upload. Cloud testing, store review and public availability are separate states; no HarmonyOS package is attached to GitHub.

### Windows

Includes shared desktop improvements and an x64 installer with GUI-subsystem, version, legal-resource, HTTPS and Windows CI installation checks. The installer is not Authenticode-verified.

### Linux / Ubuntu

Includes desktop improvements and x86_64/aarch64 DEB/AppImage files with package checks, AppImage isolation and an Ubuntu 24.04 DEB installation gate.

### CLI / TUI

Includes freshness-checked contest backups, bounded responses and complete legal files. Executable bytes were preserved when the archives were completed. Linux CI executed version and unit-test checks; no universal hardware coverage or tag attestation is claimed.

The eleven attachments were matched against local sizes and SHA-256 digests without downloading them again from the Release. The final 0.3.2 source is `7eae8d444b671d4bc4dffaccf2ec9ec80768bdf2`; the old prerelease tag remains historical. Shared course/QMplus, thirteen-language expansion and new-assignment reminders belong to 0.4.0.
