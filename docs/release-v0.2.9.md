# Where To Study 0.2.9 — Release and upload record

## Published / 已正式公开 — 2026-09-11

**[Where To Study v0.2.9](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.2.9)** 于 **2026-09-11 22:37:00 +0800** 正式公开，Release ID 为 `387037069`。已验证 `releases/latest` 指向 `v0.2.9`，`draft=false`、`prerelease=false`，公开附件恰为 **11 个**；标题保持 `Where To Study v0.2.9`。没有改动已发布的 0.2.8。

最终代码 tag 指向 **`223e4703693f93b2ae37ec13b17913483981d4bf`**。这份完成回执是之后追加的纯文档记录，不移动已正式公开的 tag，不改变已核验的安装包。

| 最终 tag 工作流 | 运行 ID | 结果 |
| --- | --- | --- |
| Windows | [34606368848](https://github.com/Nemoyuzx/where_to_study/actions/runs/34606368848) | success |
| Linux | [34606368885](https://github.com/Nemoyuzx/where_to_study/actions/runs/34606368885) | success |
| macOS | [34606368862](https://github.com/Nemoyuzx/where_to_study/actions/runs/34606368862) | success |
| Native Clients | [34606369020](https://github.com/Nemoyuzx/where_to_study/actions/runs/34606369020) | success |
| CLI | [34606368815](https://github.com/Nemoyuzx/where_to_study/actions/runs/34606368815) | success |
| TUI | [34606368846](https://github.com/Nemoyuzx/where_to_study/actions/runs/34606368846) | success |
| Security Checks | [34606368875](https://github.com/Nemoyuzx/where_to_study/actions/runs/34606368875) | success |

Native CI 最后成功于 **14:34:56 UTC**。实际测试结果：macOS 345 项（344 通过、1 条件跳过、0 失败），iOS unit 370 项（369 通过、1 条件跳过、0 失败），iOS UI 42 项（35 通过、7 平台条件跳过、0 失败），共享 Rust 177 通过／3 ignored／0 失败。修复的节假日提示翻月用例首轮通过，CI 记录 104 帧、102 个不同位置，并验证动画期间状态冻结、完成后显示新状态；没有用删除断言或跳过此用例换取通过。

Windows/Linux 的 9 个文件验证了来源证明，11 个公开文件全部重新下载并与本地逐字节摘要一致。最终 CodeQL 四语言分析通过，open CodeQL alerts、Dependabot alerts、PR 均为 **0**；依赖未维护提示仍在，不把“无开放告警”表述成绝对无风险。

商店状态分别见下面最终上传记录：Apple 两端 (92) 上传成功，vivo (48) 审核中，鸿蒙 (1002029) 预审中；华为 Android (48) 已上传保存，仍需确认重传原承诺函后提交审核。上传、预审、人工审核和正式上架是不同阶段。下次上传须采用未用过的递增构建号，不重复本次成功的 Apple/DevEco 上传。

## Final package uploads / 最终包上传

发布代码为 **`223e4703693f93b2ae37ec13b17913483981d4bf`**，`v0.2.9` 的 annotated tag 为 `dff809118cce6af205b20e66f93cc682eca696b9`。此提交相对 `1720bfc` 仅修复 Windows 上 CI 测试的 CRLF 换行兼容，不改变应用代码。该修复已经过真实 Windows CI，未跳过原预算检查。

首轮标签均为本次任务创建且尚未公开的草稿标签；因用户追加班车布局修改及随后暴露的 Windows 测试兼容问题，使用精确旧 tag SHA 的 `--force-with-lease` 更新至最终提交。未改动任何已公开的旧版本标签或 0.2.8 资产。首轮未完成的 Native CI 已取消，最终发布门禁只采用上述最终提交的 tag 工作流。

- **Apple**：保留已成功上传的 iOS/iPadOS、macOS **0.2.9 (92)**。其 Release 应用代码未因之后仅 DEBUG／测试修正改变，未重复归档上传。实际已上传包和 DMG 的源提交仍准确记为 `446ab44`，不追溯改成后来的提交。
- **vivo**：最终 **0.2.9 (48)** 于 **2026-09-11 21:48:22 +0800** 重新提交，页面显示 **审核中**；审核通过后立即发布。此前 (47) 的提交已经撤回，不是最终包。
- **华为 Android**：最终 **0.2.9 (48)** 于 **21:43:21 +0800** 上传并保存到版本 `2037245361105446080`。仍为 **准备提交**，旧授权材料下载链接过期的问题尚待用户确认重传原承诺函后解决，不记为审核成功。
- **HarmonyOS**：最终 **0.2.9 (1002029)** 通过 DevEco 第一项“测试和发布”上传；AGC 软件包行记录 **21:50:55 +0800**，DevEco 显示 **云测试结果：通过**。已绑定至版本 `2037251738360139840` 并再次提交，页面显示 **预审中**；此前 (1002028) 的预审已撤回。没有重复使用测试专用上传选项。

Android/HarmonyOS 的包名、证书／公钥、权限及 SDK／设备范围与已上架 0.2.8 已逐项验证一致；发布地区、上架方式与鸿蒙包加密设置沿用旧版本。只有版本号、更新说明和必要隐私说明变化。

| 最终产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| Android Universal APK (48) | 1,127,110 | `c6c956f7bb88c66b87c02b09308af9ed202994cde4db03740915430bfbed69b6` |
| native macOS Universal DMG (92) | 7,240,272 | `1b9c5d27740f819b368c6ced73884230594ba2b971c07a9b9c01482c9e5188ed` |
| DevEco 实际 APP (1002029) | 1,311,809 | `a3be673972501b7f77f2678e77dc74edbb3116c86073b67bd9c4d59d0131fe35` |
| DevEco 实际 HAP (1002029) | 1,968,160 | `11e6d4452c633ad616760f71a2f809bea47cb2aea51d1674e7d1c0f6d575aba7` |

最终 Android：Release JVM **240/240**，Lint **0 errors / 61 warnings / 1 hint**；设备中英文矩阵 **17 项**通过。最终 HarmonyOS **198/198** 测试、编译与 Release 模式门禁通过，但缺少可运行的模拟器／真机，未宣称设备视觉实测。见[班车布局验证](shuttle-layout-v0.2.9.md)。

GitHub 的 11 个候选资产已上传至草稿，逐个核对服务端大小／SHA-256，并重新下载验证与本地字节一致。Windows/Linux 的 9 个文件另外通过固定仓库、tag、workflow、GitHub 托管 runner、source digest 和 signer digest 的来源证明检查；这不代表 Windows 获得 Authenticode 签名。原生 DMG 仍未公证。

最终七条 tag 工作流均成功，GitHub 已正式公开，见文首回执。忽略目录 `release-artifacts/v0.2.9-final/` 保留 `github-release-verification.json`、`github-ci-final/manifest.json`、`android-shuttle-qa/` 与 `harmony-deveco1002029/receipt.md`。不将 APP/HAP、AAB、iOS 归档、ZIP 或校验侧文件作为公开附件。

## 2026-09-11 — follow-up before public release

首轮上传后，用户追加要求 Android/HarmonyOS 班车查询布局与 iOS 一致。因此 **vivo 0.2.9 (47)** 的审核和 **HarmonyOS 0.2.9 (1002028)** 的预审均已撤回，准备完成布局对齐后使用 **Android (48)**、**HarmonyOS (1002029)** 重新提交。0.2.8 已上架版本未动；Apple 0.2.9 (92) TestFlight 上传保持成功，不重复上传未改业务逻辑的 Apple 包。GitHub 0.2.9 仍为未公开草稿，不能把下面首轮回执视为最终公开版本已完成。

同时修复 Apple CI 的两处动画采样时序误报：慢速 CI 的跨进程 accessibility 查询可能越过两秒动画窗口。改为仅 DEBUG、显式测试参数启用的进程内逐帧记录，结束后验证实际位移与状态栏冻结。定向 UI 1/1 通过，采集 109 帧、107 个不同位置；Release 条件代码与已上传的 `446ab44` 一致。旧 CI `34597848960` 因 45 分钟预算到期被取消，测试仍在推进；改为 job 60 分钟、测试步骤 50 分钟，并保留失败诊断上传。未跳过或删除动画验证。

华为 0.2.8 配置核对：Android 旧 0.2.8 (46) 原包与新包证书及公钥、包名、全部权限、支持设备、minSdk 24 / targetSdk 36 一致。HarmonyOS 已从 AGC 下载准确的 0.2.8 (1002022) APP，SHA-256 `25464544658f8927eac39ae23c8f3186862b3c8fcf7d7a2b95afed882988cc6d` 与旧上传记录一致；证书及公钥、包名、phone/tablet/2in1、全部五项权限和 API 6.1.1(24) 均与 1002028 一致。两个渠道沿用各自的旧发布地区及审核通过立即上架设置，鸿蒙沿用软件包加密。新版本仅按需要改变版本号、功能说明、审核指引和隐私权利入口。

华为 Android 旧授权材料链接的实际只读访问返回 **AccessDenied / Request has expired**，与新版本提交时的旧材料解析失败相符；不能把问题归因于 APK 签名变化，也不能仅凭本地另一份 ZIP 推断旧文件损坏。原承诺函正文和签名不修改，重新上传等待用户确认。

## 2026-09-11 — first upload receipts (superseded mobile submissions)

本轮移动端与 Apple 安装包的应用源码来自 `446ab44296b20845412f5ca6babfb530cf48b23f`。后续若仅修正 CI 或 DEBUG 自动化探针，应单独记录，不应把已经成功上传的包改称来自后来的提交。

- **iOS/iPadOS 0.2.9 (92)**：本地 Xcode 于 **20:47:18 +0800** 返回 `Upload succeeded` 与 `EXPORT SUCCEEDED`。
- **macOS 0.2.9 (92)**：同一 `upload all` 调用于 **20:49:55 +0800** 返回上述两项成功回执。四个 host/Widget 版本与实际导出签名通过；89 个 Apple 文件上传前后摘要一致。未检查 App Store Connect processing，未修改 App Store 审核或测试群组。
- **vivo Android 0.2.9 (47)**：新 APK 上传、表单保存和正式审核提交完成。应用详情显示 **2026-09-11 20:48:37** 的最新提交为 **审核中**；选择审核通过后立即发布。保留备案信息，按实际权限保持敏感权限申请列表为空，更新功能说明和演示数据测试指引；纠正旧备注中“开源软件无著作权”的错误措辞。
- **华为 Android 0.2.9 (47)**：同一 APK 已于 **20:46:26 +0800** 上传并绑定新版本 `2037245361105446080`，更新了隐私权利入口、具体日历权限用途和审核说明。提交被平台的 **“授权书及其他材料”压缩包解析失败** 阻止，尚未进入审核。已准备不改正文及签名的承诺函重打包副本，等待用户确认后再上传，不能记为发布成功。
- **HarmonyOS 0.2.9 (1002028)**：通过 DevEco“上传产品 → 测试和发布”上传一次，结果页显示 **云测试结果：通过**。AppGallery 正式更新 `2037251738360139840` 已选取此版本、保存新特性并提交；页面显示 **正在预审**，预审通过后才进入人工审核，尚不能声称上架。未重复上传，也未把鸿蒙包放入 GitHub。

本轮本地验证：仓库 **199/199**；Apple 定向核心回归 **63/63**；Android Release 单测 **238/238**，Lint **0 errors / 62 warnings / 1 hint**；HarmonyOS **189/189**。正式签名与版本、HTTPS 地址、许可证和隐私打包门禁通过。新增鸿蒙实际包检查确保每个 HAP 为 `release` 且 `debug=false`；已保存的历史 1002027 上传包也确认为 Release，不能因工作目录曾残留 Debug 包而声称历史上传错误。

实际产物与证据在忽略目录 `release-artifacts/v0.2.9-final/`：

| 产物 | Bytes | SHA-256 |
| --- | ---: | --- |
| Android Universal APK (47) | 1,121,458 | `d02268512b313a8426c6b803f8c2410d5da2fec78f0f0e9b695e3f7dc7e5adab` |
| native macOS Universal DMG (92) | 7,240,272 | `1b9c5d27740f819b368c6ced73884230594ba2b971c07a9b9c01482c9e5188ed` |
| DevEco 实际 APP (1002028) | 1,302,445 | `b641a68e62140437eb4c50109d138ec933f11d987d14524f59b1bdfcbaec360d` |
| DevEco 实际 HAP (1002028) | 1,947,883 | `749ff8cd688a167995a1569205c13b42190fe8b4c42562c27bf8a173e833f9fd` |

DMG 为 ad-hoc 签名、未公证的开源预览分发，不等同于 TestFlight Distribution 包。`harmony-deveco/` 副本为上传后实际文件，已与原件逐字节比对；`harmony-cli/` 是此前 CLI 验证副本，不能混作上传回执。

## 2026-09-11 — formal release preparation

本轮用户已授权正式发布 **Where To Study v0.2.9**，并上传 vivo、华为 Android、华为 HarmonyOS；Apple 仅上传 TestFlight，不修改 App Store 审核提交。以下较早的“仅代码”或“仅测试”记录均是历史范围，不限制本轮，也不代表最新包已经上传。

本轮版本：Android **0.2.9 (47)**、HarmonyOS **0.2.9 (1002028)**、iOS/iPadOS 与 macOS **0.2.9 (92)**；Windows、Linux、CLI 和 TUI 均为 **0.2.9**。保留已有用户 Apple 改动及签名身份，签名配置不提交仓库。正式成功回执将在完成后单独补记，不能把准备状态视为已上传或已上架。

GitHub 仅发布 11 个供用户下载的文件：Windows x64 安装程序、Linux x86_64/arm64 的 DEB 与 AppImage、同两种架构的 CLI/TUI 压缩包、Android Universal APK、原生 macOS Universal DMG。不发布 HarmonyOS APP/HAP、Android AAB、iOS 归档、macOS ZIP 或校验侧文件。源代码压缩包由 GitHub 自动提供，不是安装程序。

发布途径沿用已验证流程：Apple 使用本地 Xcode 一次 `native-apple-app-store.sh upload all`（iOS Automatic、macOS Manual），以 `Upload succeeded` 和 `EXPORT SUCCEEDED` 为完成边界；HarmonyOS 使用 DevEco“上传产品 → 测试和发布”；Android 的同一签名 APK 分别上传 vivo 和华为 Android；GitHub 先核对 tag 构建、安装包和远端摘要再发布稳定版。商店审核状态与上传成功分别记录，不重复上传成功的构建。

本轮包含三个依赖 PR 的合并、安全与严格质量检查修复、GLib 上游兼容补丁、账号缓存隔离、可恢复的课程本地删除、独立教学云密码、Android 导航与卡片优化，以及此前 0.2.9 的主题、提醒、小组件和日历性能改进。用户版说明见 [0.2.9 更新说明](release-v0.2.9-notes.md)，测试细节继续保留在各专项记录中。

## 2026-09-11 — course management and separate teaching cloud password (code only)

各平台源码增加课程单次／整学期本地删除、刷新后保留及恢复，并在个人账户中增加教学云平台独立密码。
桌面托盘、小组件、课程提醒与空闲节次使用有效课表；未设置独立密码时兼容原有教务密码。
详细行为、安全边界和测试见[课程管理说明](course-management-v0.2.9.md)。此前 Android 视觉优化以独立提交保留。

所有客户端的开发版本统一为 **0.2.9**，现有分发构建计数不在本轮递增。
**本轮仅提交并推送代码，不创建 tag/Release，不上传 TestFlight/AppGallery 或其它商店包，也不修改待审版本。**
下面的历史上传记录保持原样，不能视为包含本轮新功能。

## Platform standards fixes — 2026-09-09 testing-only follow-up

本轮修复隐私清单和打包门禁、鸿蒙卡片读写目录及刷新、Android 任务恢复/语言分包/大字体布局，以及桌面通知实际发送/撤销边界。详细验证与未覆盖范围见[规范修复记录](platform-standards-fixes-v0.2.9.md)。

原生上传源码提交 `f66000f98418ef4db7760efcddb4eab28a77477b` 已推送 `main`。Apple `0.2.9 (91)`（iOS/iPadOS、macOS）TestFlight 和 HarmonyOS `0.2.9 (1002027)` **仅测试**包均上传成功；不提交商店审核，不修改现有待审版本、测试群组或 GitHub Release。后续 Tauri macOS 未打包进程保护与 Linux 打包工具固定资产修复不改变原生 Apple/HarmonyOS 代码，因此不重复上传相同原生包。

### Success receipts / 成功回执

- iOS/iPadOS：本地 Xcode 于 **2026-09-09 17:42:25 +0800** 返回 `Upload succeeded` 和随后 `EXPORT SUCCEEDED`。主应用与 Widget 均为 `0.2.9 (91)`；Automatic 归档、Distribution 导出及实际两处隐私清单门禁通过。
- macOS：本地 Xcode 于 **2026-09-09 17:44:53 +0800** 返回 `Upload succeeded` 和随后 `EXPORT SUCCEEDED`。主应用与 Widget 均为 `0.2.9 (91)`，Universal/Manual 签名及实际隐私清单门禁通过。
- HarmonyOS：**2026-09-09 17:49 +0800** 确认 DevEco 结果页“云测试结果：通过”。明确选择第二项“生成.app包并上传至AppGallery Connect进行测试”。实际 APP/HAP `pack.info` 均为 `0.2.9 (1002027)`，单独 build 字段为 `1`；两份产物签名和摘要复核通过。

Apple 沿用单次 `scripts/native-apple-app-store.sh upload all`，设置 `APPLE_MARKETING_VERSION=0.2.9`、`APPLE_BUILD_NUMBER=91`、iOS Automatic/macOS Manual；团队读取本机现有证书，没有提交签名配置。仅一次依次归档、校验和上传，成功后不检查 App Store Connect processing。新增门禁验证的是归档/导出 `.app/.appex` 内真实 `PrivacyInfo.xcprivacy`，不是只看源码。上传前后 88 个 Apple 源码/配置/隐私清单文件 SHA-256 一致，用户产品名、审核支持和既有主题修改保留。

HarmonyOS 使用 DevEco“从磁盘全部重新加载 → 同步和刷新项目 → 构建 → 上传产品 → 仅测试”。最初列表为空时通过账号工具栏刷新已有登录态，恢复后仅发起一次上传。最终 APP 及同次生成 HAP 副本与上传后产物逐字节一致。忽略目录 `release-artifacts/standards-fix-029-testing/` 保存回执、两端 Apple 归档、源文件前后校验和鸿蒙签名日志：

- APP：1,288,376 bytes；SHA-256 `1325eb99196a07bb02f82fc9dab4a0aab2a588dd8ebcf453758581f522cf5d70`。
- HAP：1,913,768 bytes；SHA-256 `87c48d587f4b269bd9844130fc40611cdf4c29b60e5b0d4731244e78ac9daca3`。

### CI / 持续集成

首轮 [Windows CI](https://github.com/Nemoyuzx/where_to_study/actions/runs/34335921285) 已完成 Rust 162 项（3 项既有忽略）、严格 Clippy、NSIS 打包/静默安装及工件上传。[Linux 首轮](https://github.com/Nemoyuzx/where_to_study/actions/runs/34335921220) 两架构 Rust 与隔离 D-Bus 协议、Clippy 均通过；初始包构建通过，但硬化重打包所用 upstream continuous 资产已经更换，固定摘要正确拒绝了新字节。没有把该失败记为通过。

后续提交 `4a93a6c15e53b47708024536038d3f1c87f39d6b` 固定官方工具资产 ID，并独立核验摘要/大小/架构，同时补充迁移期 Tauri macOS 的未打包保护；原生 Apple/HarmonyOS 源码不变，未重复上传。该提交的 [Windows CI](https://github.com/Nemoyuzx/where_to_study/actions/runs/34337790532) 已整体成功，包括 Rust、严格 Clippy、NSIS 打包、安装资源校验和工件上传。[Linux 新 CI](https://github.com/Nemoyuzx/where_to_study/actions/runs/34337790471) 也已整体成功：x86_64/ARM64 的 Rust、私有 D-Bus 协议、Clippy、deb/AppImage 构建、硬化重打包、工件上传及 Ubuntu 24.04 安装验证均通过。

Linux 重打包日志确认使用摘要匹配的缓存工具，移除 4 个捆绑 Wayland 库后成功重打包；官方固定 asset ID 的冷下载已在本机独立核验，新增打包工具契约测试 19/19 通过。固定的是重打包工具本体；其内部仍使用官方 type2-runtime/continuous，不能据此声称整个工具链的所有输入都已固定。最终本地网页/契约测试 181 项、Tauri macOS 169 项（3 项既有忽略）、严格 Clippy 通过。CI 工件不等于公开 Release 更新。

Native code from `f66000f` was uploaded as Apple 0.2.9 (91) and HarmonyOS 0.2.9 (1002027), testing only. No review submission or public Release update occurred. Upload/cloud-test success does not imply completed review or every device scenario passing; limitations remain in the linked standards-fix record.

## Custom reminder time and tomorrow widgets — 2026-09-09 testing-only follow-up

提交各图形平台自定义每日课程提醒时间，以及 Apple/Android/HarmonyOS 小组件剩余空间的明日课程。保留默认 07:30、北京时间基准、今日优先、权限/账号撤销与用户 Apple 审核支持信息；完整行为、测试与未覆盖范围见[功能记录](reminder-time-and-tomorrow-widget.md)。

源码提交 `8ffbef8b2f75a96ead963e8cdc3a18ea92ef6500` 已推送 GitHub `main`。Apple `0.2.9 (90)`（iOS/iPadOS、macOS）TestFlight 和 HarmonyOS `0.2.9 (1002026)` **仅测试**上传均已完成。不提交任何商店审核，不修改现有待审版本、测试群组或 GitHub Release；未上传 Android/vivo 包。Apple 构建号通过环境参数覆盖，没有改动用户项目版本配置、产品名或审核支持内容。

### Success receipts / 成功回执

- iOS/iPadOS：本地 Xcode 于 **2026-09-09 15:58:17 +0800** 返回 `Upload succeeded`，随后 `EXPORT SUCCEEDED`。主应用与 Widget 为 `0.2.9 (90)`；Automatic 归档及 Distribution 导出验证通过，无 `get-task-allow`。
- macOS：本地 Xcode 于 **2026-09-09 16:00:41 +0800** 返回 `Upload succeeded`，随后 `EXPORT SUCCEEDED`。主应用与 Widget 为 `0.2.9 (90)`；Manual Distribution 签名验证通过，二者均为 arm64/x86_64 Universal，宿主名称与可执行文件保持 `Where To Study`。
- HarmonyOS：**2026-09-09 15:58 +0800** 确认 DevEco 结果页 **“云测试结果：通过”**。上传时明确选择第二项“生成.app包并上传至AppGallery Connect进行测试”，未选择“测试和发布”。最终 APP 及同次生成的 HAP 的 `pack.info` 均为 `0.2.9 (1002026)`，单独 build 字段仍为 `1`；两者签名/摘要校验通过，保存副本与上传后产物逐字节一致。

Apple 仅运行一次 `scripts/native-apple-app-store.sh upload all`，设置 `APPLE_MARKETING_VERSION=0.2.9`、`APPLE_BUILD_NUMBER=90`、iOS Automatic/macOS Manual；团队来自本机现有 Distribution 证书，没有提交签名配置。脚本依次完成归档、校验和上传，没有另行重复这些步骤，成功后未检查 App Store Connect processing 或测试员可用状态。HarmonyOS 使用 DevEco“打开已保存的 harmony 工程 → 从磁盘全部重新加载 → 同步和刷新项目 → 构建 → 上传产品 → 仅测试”，仅发起一次上传，没有重新提交商店审核。

复用[功能回归与限制](reminder-time-and-tomorrow-widget.md)，提交前另外执行仓库测试 **164/164 通过**、`git diff --check` 与 Apple 保留内容审查。上传前后 **86** 个 Apple 源码/配置文件 SHA-256 全部一致，四个宿主/Widget bundle 的严格签名校验通过。快速鸿蒙云测试和 Apple 上传回执不代表商店审核通过或补齐尚未覆盖的真机测试。

忽略目录 `release-artifacts/reminder-widget-029-testing/` 保存上传日志、build 90 两端归档、Apple 前后校验/初始差异，以及最终鸿蒙产物与签名日志：

- APP：1,285,324 bytes，SHA-256 `a3a39498369393bbd4552a4f28d65b07b8dbac5277a374853d4f8b6b779ceadd`。
- HAP：1,903,609 bytes，SHA-256 `345b7f1080cc8045d18c41b23db69d5f7be45986a467ec8dfcf44f7154a601d3`。

Source commit `8ffbef8` was uploaded as Apple 0.2.9 (90) and HarmonyOS 0.2.9 (1002026) for testing only. Store review submissions, test groups and public GitHub Release assets were not changed. Later uploads must increment these build numbers; do not repeat the successful uploads recorded here.

## Coordinated theme surfaces — 2026-09-09 testing-only follow-up

按用户要求提交低饱和预设与背景/卡片/控件联动配色，以及实际染色文字可读性修复；保持默认主题、DDL/今日标识、Apple 审核身份与支持信息。验证范围见[背景主题记录](color-themes.md)。

源码提交 `75023e1592f09a1672e08fee563a0c26bc239158` 已推送 GitHub `main`。Apple `0.2.9 (89)`（iOS/iPadOS、macOS）TestFlight 和 HarmonyOS `0.2.9 (1002025)` **仅测试**上传均已完成；不提交审核、不修改待审版本、测试群组或 GitHub Release。Apple 版本继续通过构建参数覆盖，不修改用户项目版本配置。上传前后 85 个 Apple 源码/配置文件 SHA-256 全部一致，两个新增主题 Swift 文件已包含在源码提交中。

### Success receipts / 本轮成功回执

- iOS/iPadOS：本地 Xcode 于 **2026-09-09 10:36:48 +0800** 返回 `Upload succeeded`，随后 `EXPORT SUCCEEDED`。宿主与 Widget 均为 `0.2.9 (89)`，Automatic 归档及 Apple Distribution 导出校验通过。
- macOS：本地 Xcode 于 **2026-09-09 10:39:37 +0800** 返回 `Upload succeeded`，随后 `EXPORT SUCCEEDED`。Universal 宿主与 Widget 均为 `0.2.9 (89)`，Manual 签名归档校验通过，产品名保持 `Where To Study`。
- HarmonyOS：**2026-09-09 10:46 +0800** 确认 DevEco 结果页显示 **“云测试结果：通过”**。明确选择第二项“生成.app包并上传至AppGallery Connect进行测试”，未选择“测试和发布”。最终 APP/HAP 的 `pack.info` 均为 `0.2.9 (1002025)`，单独 build 字段为 `1`。两份产物均通过 `verify-app` 与 SHA-256 摘要校验，保存副本与上传后原件逐字节一致。

Apple 沿用单次 `scripts/native-apple-app-store.sh upload all`，设置 `APPLE_MARKETING_VERSION=0.2.9`、`APPLE_BUILD_NUMBER=89`、iOS Automatic/macOS Manual；团队读取本机现有证书，不提交签名配置。脚本一次依次完成两端归档、校验和上传，没有重复构建或上传，也未在成功后检查 App Store Connect processing。DevEco 依次使用“从磁盘全部重新加载 → 同步和刷新项目 → 构建 → 上传产品”；应用列表首次因 401 为空，用户中心工具栏动作刷新会话后恢复，随后仅发起一次测试上传。

复用[背景配色回归结果与限制](color-themes.md)，本轮提交前另外执行仓库测试 **161/161 通过**、`git diff --check`，并完成 Apple 源码保留审查和签名归档核验。DevEco 重新生成最终完整 APP；快速云测试通过不等同于完整商店审核或鸿蒙真机视觉回归。

忽略目录 `release-artifacts/theme-surfaces-029-testing/` 保存两端 Apple 上传日志、build 89 归档、Apple 前后校验与初始差异，以及鸿蒙最终上传包和签名日志：

- APP：1,279,025 bytes，SHA-256 `a7a123a48e3cad85833d2f199b3d737428f838b0b125b49482df98b1d701a2af`。
- HAP：1,888,844 bytes，SHA-256 `c8aa76ccb5fed441d822152f530214d1338e4f681cb798518de3b185f4a1f669`。

Source commit `75023e1` includes the coordinated background refinement and preserves the user's Apple review/support changes. Apple 0.2.9 (89) and HarmonyOS 0.2.9 (1002025) were uploaded for testing only. No store review, test-group change, Android/vivo upload or GitHub Release publication was performed. Use new build numbers for later uploads; do not repeat these successful uploads.

## Color themes — 2026-09-09 testing-only uploads

本轮源码提交为 `d46844aa7445ac1b3fc49c32d6851b81ab518c93`，已推送 GitHub `main`。提交各平台颜色主题与鸿蒙 PC 字号修复的当前源码，保留 `c2ccb7b` 及其之前的 Apple 身份、产品显示名、离线帮助和支持邮箱修复，也原样保留上传前工作区的 Apple 修改，不还原旧版本。上传前后 Apple 源文件 SHA-256 全部一致。

已完成 Apple `0.2.9 (88)`（iOS/iPadOS、macOS）TestFlight 上传，以及 HarmonyOS `0.2.9 (1002024)` 的 AppGallery Connect **仅测试**上传。Apple 通过构建参数覆盖版本，没有改动用户的项目配置。未提交 App Store/AppGallery 上架审核，未修改现有待审版本、测试群组或 GitHub Release。

之前的主题验证范围与限制见[颜色主题测试说明](color-themes.md)。本轮上传前另执行 `AppStorePresentationTests`、`ColorThemeTests`、`AppModelLoadingTests` 共 19 项检查，全部通过；验证宿主实际名称、非官方声明、离线支持、邮箱/反馈和用户修改均保留。仓库 156 项测试通过。没有将此前未覆盖的设备视觉回归补记为通过。

### Success receipts / 成功回执

- iOS/iPadOS：Xcode 于 **2026-09-09 08:35:03 +0800** 返回 `Upload succeeded`，随后 `EXPORT SUCCEEDED`；主应用与 Widget 均为 `0.2.9 (88)`，Automatic 归档及 Apple Distribution 导出校验通过。
- macOS：Xcode 于 **2026-09-09 08:37:42 +0800** 返回 `Upload succeeded`，随后 `EXPORT SUCCEEDED`；Universal 主应用与 Widget 均为 `0.2.9 (88)`，Manual 签名归档校验通过，产品名称保持 `Where To Study`。
- HarmonyOS：2026-09-09 08:36 +0800 DevEco 结果页显示 **“云测试结果：通过”**。上传前明确选择第二项“生成.app包并上传至AppGallery Connect进行测试”，不是“测试和发布”。最终 APP/HAP 的 `pack.info` 均为 `0.2.9 (1002024)`，单独 build 字段仍为 `1`；两份实际上传产物签名复核通过。

Apple 使用一次 `native-apple-app-store.sh upload all`，设置 `APPLE_MARKETING_VERSION=0.2.9`、`APPLE_BUILD_NUMBER=88`、iOS Automatic/macOS Manual。团队从本机现有证书读取，不提交签名配置。脚本内部依次完成两端归档、校验和上传，没有另行重复归档，也没有在成功后检查 App Store Connect processing。HarmonyOS 沿用 DevEco“从磁盘全部重新加载 → 同步和刷新项目 → 构建 → 上传产品”，但本次按用户要求选 **仅测试**；没有重复上传。

忽略目录 `release-artifacts/color-themes-029-testing/` 保留上传日志、Apple 源文件前后校验、初始差异快照和鸿蒙实际上传包。Harmony APP SHA-256 为 `d43d2e7c327f9e45cf1661380343c10c747735dd1398e5655e9e49cf24bbc91c`，HAP 为 `39219bbd70bfc3424186301339e38007b6f51c374b0d91f865e86fd10862a417`。后续上传必须使用新的构建号；不能复用 88/1002024。

Source commit d46844a preserves the user's Apple review/support changes. Apple 0.2.9 (88) and HarmonyOS 0.2.9 (1002024) were uploaded for testing only. No store review submission, existing review replacement, test-group change or GitHub Release publication was performed. Upload success and the quick Harmony cloud test do not imply completed store review or real-device visual coverage.

## macOS 0.2.9 (86) — App Review fixes synchronized

2026-09-08 使用已验证的审核修复源码 `e6afd393be989965509dfb8482dee558e87d334e`，在独立 worktree 从 `2ef6941` 重新生成 macOS `0.2.9 (86)`。同步内容包括：安装显示名统一为 `Where To Study`、独立非官方身份及学校名称适用范围说明、应用内离线帮助和直接联系邮箱；主 Bundle ID、模块名及原有服务边界保持不变。详见[审核修复记录](macos-app-review-2026-09-08.md)。

本次只改变上传时的版本和构建号，应用源码、资源和打包脚本与已验证的 build 85 相同，复用此前 301 项通过、1 项按设计跳过的完整 macOS 回归及视觉检查。新的 Universal 主应用与 Widget 均已核对为 `0.2.9 (86)`，`arm64`/`x86_64`、Apple Distribution 签名、App Sandbox、App Group、无 `get-task-allow`、名称和许可证检查通过。

通过现有 `native-apple-app-store.sh upload macos` 单次完成归档、校验和上传；设置 `APPLE_MARKETING_VERSION=0.2.9`、`APPLE_BUILD_NUMBER=86`、`APPLE_MACOS_SIGNING_STYLE=Manual`，团队由本机证书解析且不提交到仓库。Xcode 于 **2026-09-08 22:09:37 +0800** 返回 **`Upload succeeded`**，随后 **`EXPORT SUCCEEDED`**。

本次完成上传，没有修改 0.2.8 (85) 的 App Review 提交、TestFlight 测试群组或 GitHub Release，也没有上传 iOS 构建。上传后未额外检查后台 processing 或测试员可用状态。独立构建目录保留了此前 build 85 的签名归档。

忽略目录下的证据：`release-artifacts/macos-029-review-sync/macos-upload-86.log`、`archive-verification.json` 及对应签名导出记录。

## HarmonyOS 0.2.9 (1002023) — uploaded through DevEco

2026-09-08 按用户提供的上架后报告修复 PC 默认/最大化窗口中的小字号问题：周视图全天 DDL、课程时段、月周标签、年星期/日期统一遵循至少 10fp，PC 窄窗口回退到紧凑日历时同样生效。月周标签改为独立布局行，手机和平板原字号保持不变。

本地 144 项鸿蒙单元测试、146 项仓库测试、HAP/APP 构建和正式签名验证通过；版本核对为 `0.2.9 (1002023)`。2026-09-08 16:12 +0800 已按用户要求通过 DevEco“上传产品 → 测试和发布”上传 AppGallery Connect，结果页显示“云测试结果：通过”。已核对并保存 DevEco 最终产物及其摘要，具体范围、上传记录和验证边界见[鸿蒙 PC 字号记录](harmony-pc-typography-v0.2.9.md)。设备视觉回归仍待完成；上传快速云测试不代表完整上架审核通过，未再次提交商店审核或更新 GitHub Release。鸿蒙安装包继续不作为 GitHub 附件发布。

## 0.2.9 (84) — first year-date detail sheet animation

Uploaded from local **Xcode 26.6** on **2026-09-06**, from application-source commit `c25f6e6`. The iOS app and Widget archives both report **`0.2.9 (84)`**. Signed archive and Apple Distribution export validation passed. The Release executable was checked to exclude the detail-presentation test probe.

年视图首次点日期时，先同步年份窗口再打开详情，避免年份页的无动画重置连带取消弹窗动画。本地 Xcode 已复现修复前首次呈现时长为 `0`；修复后首次打开、同日重开和换日打开均记录到 `0.4` 秒的 UIKit 呈现动画。24 项定向单元测试和 3 项 iPhone UI 流程全部通过，详见[性能与动画记录](ios-month-paging-performance-v0.2.9.md)。

Xcode reported **`Upload succeeded` at 10:44:17 +0800** and **`EXPORT SUCCEEDED`**. No App Store Connect processing or test-group checks were performed afterward.

Upload route: one invocation of `scripts/native-apple-app-store.sh upload ios`, with `APPLE_MARKETING_VERSION=0.2.9`, `APPLE_BUILD_NUMBER=84`, `APPLE_IOS_SIGNING_STYLE=Automatic`, and the development team resolved locally from the installed Apple Distribution identity. The script archived, validated, exported and uploaded; none of those stages were separately repeated. A later upload must increment the build number.

Ignored receipt: `release-artifacts/ios-calendar-paging-029/ios-upload-84.log`. This is an iOS-only TestFlight update.

## 0.2.9 (83) — iOS holiday-transition fix and year paging

Built and uploaded with local **Xcode 26.6** on **2026-09-06**, from application-source commit `2b4df61`. The iOS app and Widget archives both report **`0.2.9 (83)`**. Signed archive validation and Apple Distribution export validation, including the no-`get-task-allow` check, succeeded.

Xcode reported **`Upload succeeded` at 10:24:01 +0800** and **`EXPORT SUCCEEDED`**. No App Store Connect processing or test-group checks were performed afterward.

月视图在节假日不可用提示出现时继续完成水平动画；手机年视图支持左右切年、反向返回和保持纵向滚动位置，iPad 宽布局同步支持年份滑动。后台全年投影及可复用月份图层减少切换开销。具体性能结果与限制见[日历性能记录](ios-month-paging-performance-v0.2.9.md)。

The already-validated source has 325 iOS unit tests executed with one expected network skip and no failures; focused iPhone holiday-animation/year-navigation/detail flows and 13-inch iPad year navigation passed. Existing validation was reused for this upload rather than repeated.

Upload route: `scripts/native-apple-app-store.sh upload ios`, with `APPLE_MARKETING_VERSION=0.2.9`, `APPLE_BUILD_NUMBER=83`, and `APPLE_IOS_SIGNING_STYLE=Automatic`. The team was resolved locally from the installed Apple Distribution identity. This single invocation archived, validated, exported and uploaded once. The next upload must increment the build number.

Ignored receipt: `release-artifacts/ios-calendar-paging-029/ios-upload-83.log`. This upload is iOS-only; the GitHub stable Release and other platform packages are unchanged.

## 0.2.9 (82) — iOS month paging follow-up

Built with local Xcode 26.6 and uploaded on **2026-09-05**, from application-source commit `c0de962`. The iOS application and Widget archives both report **`0.2.9 (82)`**. Automatic-signing archive validation and local Apple Distribution export validation passed, including the no-`get-task-allow` check. The shipping executable contains no DEBUG month-frame probe label.

Xcode reported **`Upload succeeded` at 21:41:38 +0800** and **`EXPORT SUCCEEDED`**. No App Store Connect processing or test-group inspection was performed after that receipt. This is an iOS-only TestFlight follow-up: no macOS upload, GitHub Release replacement, or Android/HarmonyOS/Windows/Linux artifact rebuild is included.

### 中文说明

针对左右翻月掉帧，改用三个固定循环页面与可复用原生日期控件，后台准备月份快照，离屏页分行预热；避免翻页开头整页重建及收尾集中排版。等待目标页真正完成布局后才开始动画，保留反向连续翻页、跨月选日和折叠交互。修复零尺寸边框导致的图形错误日志，并加强切换账号、清空数据时的缓存隔离。

### Validation / 验证

- Final iOS unit suite: 292 executed, 1 opt-in live-network skip, 0 failures.
- Seven distinct focused UI flows passed: continuous gesture reversals, unobserved frame replay, out-of-month day selection, month expansion/year jumps, landscape stops/detail scrolling, week-agenda/month-details behavior, and English controls. The final cache-hit recency adjustment received another complete iOS unit run and frame replay.
- Shared-code macOS suite: 276 executed, 1 opt-in live-network skip, 0 failures. Repository contracts: 142/142 passed.
- Local screenshots were visually checked. Timing records, intermediate results and the explicit simulator/real-device limitations are in [the month-paging audit](ios-month-paging-performance-v0.2.9.md). The final replay improved first-callback latency and animation-start intervals; residual completion intervals remain, so this is not a zero-hitch or physical-device FPS guarantee.

### Upload receipt / 发布记录

Used the existing single command `scripts/native-apple-app-store.sh upload ios`, with `APPLE_MARKETING_VERSION=0.2.9`, `APPLE_BUILD_NUMBER=82`, and `APPLE_IOS_SIGNING_STYLE=Automatic`. The team was resolved from the locally installed Apple Distribution identity, not committed. The script performs archive, validation, export and upload; these steps were not separately repeated.

Ignored local evidence: `release-artifacts/ios-month-paging-029/ios-upload-82.log`, final unit/UI/replay logs, and screenshot folders. A later TestFlight upload must use a new build number; do not resend build 82 or check App Store Connect after this successful upload.

## 0.2.9 (81) — iOS and macOS loading follow-up

Both platforms were built with local Xcode 26.6 and uploaded on **2026-09-05**, from application-source commit `1ae10f2`. Main application and Widget versions were verified as `0.2.9 (81)` in both archives.

- iOS: Automatic signing, archive validation, local Apple Distribution export validation (including no `get-task-allow`), and upload completed. Xcode reported **`Upload succeeded` at 17:53:06 +0800** and **`EXPORT SUCCEEDED`**. A developer-services TLS warning occurred earlier in the same upload; that process continued and succeeded without resubmitting the build.
- macOS: Manual App Store profiles and the installed Installer Distribution identity; signed archive validation and upload completed. Xcode reported **`Upload succeeded` at 17:55:43 +0800** and **`EXPORT SUCCEEDED`**.
- No App Store Connect processing or test-group checks were performed after upload. Upload success is not a claim that Apple has finished processing or that every tester can already install the build.
- The GitHub stable Release and repository-wide default version remain `0.2.8`. This Apple-only TestFlight update does not replace other platform artifacts or publish an iOS binary on GitHub.

### 中文说明

将正式启动的课表/空教室缓存读取与解析、节假日缓存读取和刷新落盘移出主线程；避免缓存尚未恢复就重复获取数据。使用代际校验防止清除数据、修改账号或切换模式后旧结果回写。iOS/macOS 导航状态独立于全局业务数据，查询服务持久复用并区分真实/示例模式。重要事件在后台建立并复用搜索索引，翻页不重复解析全量截止时间。日历使用有界会话缓存、合并数据失效通知和预计算课程轨道，分钟刷新缩小到时间相关内容；同时修复首次数据早于缓存订阅到达导致全天区空白的竞态。

### Validation / 验证

- macOS: 254 unit tests executed, 1 opt-in network skip, 0 failures.
- iPhone: 261 unit tests and 28 UI tests executed, 6 combined conditional skips, 0 failures; an additional final four-flow UI run passed 4/4 with an isolated result bundle.
- iPad: English controls, all-day event/header alignment and corner selection, rotation/sidebar retention, primary navigation — 4/4 passed.
- Repository contracts: 142/142 passed. Local live-data visual checks and background-worker stack sampling are documented in [the performance audit](apple-performance-v0.2.9.md), including the limitations of those measurements.

### Repeatable upload path / 后续发布路径

Use `scripts/native-apple-app-store.sh upload ios` with `APPLE_IOS_SIGNING_STYLE=Automatic`, then `upload macos` with `APPLE_MACOS_SIGNING_STYLE=Manual`. For this release set `APPLE_MARKETING_VERSION=0.2.9` and `APPLE_BUILD_NUMBER=81`; a later upload must increment the build number. Resolve `APPLE_DEVELOPMENT_TEAM` from the locally installed Apple Distribution identity rather than committing signing configuration. Each `upload` call already archives, validates and uploads: do not separately repeat `archive → export → upload`. Stop at successful upload, not an App Store Connect browser check.

Ignored local evidence: `release-artifacts/apple-performance-029/ios-upload-81.log`, `macos-upload-81.log`, unit/UI logs and isolated `.xcresult` bundles.

## Earlier iOS-only 0.2.9 (80)

`0.2.9 (80)` is an iOS-only performance hotfix built and uploaded from local Xcode on 2026-09-05. The repository-wide default version and the GitHub stable release remain `0.2.8`; macOS, Android, HarmonyOS, Windows, Linux, CLI, and TUI packages were not rebuilt or replaced.

## 中文说明

- 将 iPhone/iPad 一级栏目选择从全局数据模型中隔离，避免切换底部导航或侧栏时让全部重页面同时重绘。
- 教学日历离开页面后继续保留有界的月/年快照缓存，返回时不再无条件重建当前月或全年数据。
- 月视图完全展开时不再构造不可见的当日日程、课程作业、黄历和活动 DDL 卡片树；收起后仍完整恢复原有详情、滚动和手势逻辑。
- iOS 启动后提前异步获取班车数据，查询页不再把首次请求初始化绑定到切换首帧；真实数据与内置示例数据使用独立缓存，互不覆盖。
- 本机 Xcode 完整测试累计 267 项通过、6 项设备或显式联网门控跳过、0 失败；最终模式隔离补丁另有 15 项针对性测试通过、1 项显式联网门控跳过、0 失败。Debug 模拟器连续切换采样未发现网络或 JSON 解析阻塞主线程。
- 正式归档中的 iOS 主应用与 Widget 均为 `0.2.9 (80)`。签名归档、Apple Distribution 导出校验和上传均成功，并收到 `Upload succeeded` 与 `EXPORT SUCCEEDED`；按发布约定未继续检查 App Store Connect processing。

## English

- Isolated iPhone and iPad primary navigation selection from the global data model so tab and sidebar changes no longer invalidate every heavyweight page at once.
- Preserved the bounded month/year snapshot cache while the calendar tab is hidden, avoiding unconditional reconstruction when users return.
- Replaced the fully hidden month-detail card tree with a lightweight, geometry-stable viewport while the month is expanded. Daily schedule, assignment, almanac, deadline, scrolling, and gesture behavior still return when details are shown.
- Prewarms shuttle data asynchronously at the iOS root and reuses it in Query. Live and built-in sample data use separate stores so stale requests cannot cross runtime modes.
- Local Xcode validation completed with 267 passing tests, 6 device or opt-in live-network skips, and no failures. The final mode-isolation change received another 15 focused passes, one opt-in live-network skip, and no failures. Repeated Debug Simulator switching samples showed no network or JSON parsing work blocking the main thread.
- Both the iOS app and Widget in the signed archive report `0.2.9 (80)`. Automatic-signing archive, Apple Distribution export validation, and upload completed with `Upload succeeded` and `EXPORT SUCCEEDED`. App Store Connect processing was intentionally not inspected afterward.

No iOS binary is attached to GitHub Releases.
