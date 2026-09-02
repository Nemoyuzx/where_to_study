（进来给个🌟吧） 赞助（建站和apple年费真的很昂贵）：https://ifdian.net/a/Nemoyuzx

# Where To Study

北邮空教室与个人课表联动查询应用。Windows 与 Linux 客户端使用 Tauri 2、React 和 Rust，
macOS/iOS 客户端使用 SwiftUI，Android 客户端使用 Kotlin 与 Android Views，
鸿蒙（HarmonyOS NEXT）客户端使用 ArkTS 与 ArkUI；macOS 同时保留 Tauri Apple
Silicon 兼容构建。

- 只通过移动教务 HTTPS 接口获取并解析北邮个人课表；请求失败时不会静默切换数据源。
- 获取当天空教室信息时会一次拉取西土城与沙河两个校区，并保存到本地缓存。
- 支持西土城与沙河校区查询；沙河教学楼按 `综合教学楼N`、`综合教学楼S`、`教学实验综合楼N`、`教学实验综合楼S`、`智慧教学楼` 识别。
- 空教室查询支持按个人空闲节次和教学楼筛选；Tauri 桌面端另支持最少座位数筛选。
- macOS 与 Windows 桌面端可在设置中开启每天 7:30 的今日课程系统通知；仅在原生 iOS、macOS 与 Android 等具备系统小组件能力的平台保留今日课程小组件，Windows 与 Linux 不提供应用内课程浮窗。
- SwiftUI、Android 与鸿蒙原生端可选择每天 7:30 接收本地课程摘要，关闭提醒、切换账号或清除数据会撤销后续任务。
- 支持课表本地缓存、教学日历、法定节假日，以及 Apple EventKit、Android Calendar Provider 或鸿蒙 Calendar Kit 系统日历导入；ISO 8601 公历周与教学周并列显示，且不再推断或标注考试周。日、周、月可左右滑动翻页，月视图可展开或折叠，年视图可将所选日期跳转到日、周或月。
- 联动查询顶部提供默认折叠的今日/明日校区天气卡片；月视图日期详情按“课程日程 → 云课堂作业 DDL → 黄历宜忌 → 统一活动 DDL”排列，学科竞赛、校内竞赛通知、夏令营与黑客松均可独立关闭。
- 图形客户端的一级导航条在“教学日历”和“设置”之间提供独立“查询”页：顶部滑块切换当天校区班车与重要事件。班车按当前执行时段展示西土城/沙河双向班次和下一班；重要事件可搜索名称、学校与方向，按类型/分类/来源筛选并默认按 DDL 由近到远排列。
- 作业 DDL、校内竞赛、公开活动和自定义日程同时进入日/周全天区、月格和年视图日期详情；超出紧凑区域时使用可点击的 `+N` 展开完整列表。
- Contest DDL 中的学术会议与期刊专题已进入教学日历；重要事件查询只合并公开活动和校内竞赛通知，不包含课程作业或自定义源，并可直接复用教学日历的本地收藏。
- 终端客户端同步支持公开查询：CLI 提供 `shuttle` / `events` 与 JSON 输出；TUI 在“日历”和“设置”之间提供独立“查询”标签，并与 CLI 共享安全的本地活动收藏。
- 活动日程可以收藏为完整的本地快照：即使关闭对应来源、接口暂时失败或上游删除条目，收藏仍会保留在原日期；设置中提供独立收藏管理页。还可填写符合[自定义日程接口规范](./docs/custom-schedule-api.md)的 HTTPS JSON 地址，将自有日程并入同一教学日历。
- 图形客户端支持跟随系统、简体中文与 English；静态界面切换语言，第三方 API 返回的课程、天气、黄历、作业和竞赛内容保持原文。

贡献前请先阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。平台支持范围和验收顺序见
[docs/platform-roadmap.md](./docs/platform-roadmap.md)。

Windows 与 Linux 发布制品的签名边界、GitHub/Sigstore 来源证明及下载后验证命令见
[Windows / Linux 签名与构建来源验证](./docs/code-signing.md)。

bupt校内的其它非官方学生组织可以联系我在网站上添加友链

## 反馈与交流群

遇到问题、发现 bug 或有功能建议时，可以提交 [GitHub Issue](https://github.com/Nemoyuzx/where_to_study/issues)，也可以扫码加入交流群。

<table>
  <tr>
    <th align="center">QQ 交流群</th>
    <th align="center">微信交流群</th>
  </tr>
  <tr>
    <td align="center">群号：<code>873443704</code></td>
    <td align="center">Where To Study 问题与 bug 反馈</td>
  </tr>
  <tr>
    <td align="center"><img src="./docs/assets/feedback-qq-group.jpg" alt="Where To Study QQ 交流群二维码" width="280"></td>
    <td align="center"><img src="./docs/assets/feedback-wechat-group.jpg" alt="Where To Study 微信交流群二维码" width="280"></td>
  </tr>
</table>

> 微信群二维码可能会过期；失效后请优先通过 QQ 群或 GitHub Issue 反馈，并以仓库后续更新的二维码为准。

## 平台状态

| 平台 | 客户端技术 | 发布状态 |
| --- | --- | --- |
| macOS | SwiftUI 原生；另提供 Tauri 2 兼容构建 | `0.2.8 (77)` 正式签名构建已上传 TestFlight；Universal DMG 已从最终运行时代码重建并进入 GitHub 正式版 |
| Android | Kotlin + Android Views | `0.2.8 (45)` 使用固定维护者密钥签名；GitHub 正式版只公开 Universal APK，AAB 仅用于商店/内部交付；支持手机、折叠屏和平板布局、系统日历、课程提醒与桌面小组件 |
| Windows | Tauri 2 + React + Rust | `v0.2.8` 正式版 x64 NSIS 来自 [main push run 33467351916](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467351916)（`04a355c`）；公众 Authenticode 仍需外部身份配置 |
| Linux | Tauri 2 + React + Rust | `v0.2.8` 正式版 GUI 来自 [run 33467352143](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467352143)（`04a355c`），CLI/TUI 来自 [runs 33378927605](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927605) / [33378927633](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927633)（`6e92141`） |
| CLI | Rust（复用共享核心逻辑） | `v0.2.8` 的 `where-to-study-cli` 发布 Linux x86_64/arm64 构建，并新增班车/重要事件命令，见 [wts-cli/README.md](./wts-cli/README.md) |
| 终端 TUI | Rust + ratatui（复用共享核心逻辑） | `v0.2.8` 的 `where-to-study-tui` 发布 Linux x86_64/arm64 构建；主分支已将班车/重要事件改为独立一级“查询”标签，见 [wts-tui/README.md](./wts-tui/README.md) |
| iOS | SwiftUI 原生 | `0.2.8 (77)` 日历与事件渲染修复构建已上传 TestFlight；不作为 GitHub Release 附件 |
| HarmonyOS | ArkTS + ArkUI（HarmonyOS NEXT 6.1.1 / API 24） | `0.2.8 (1002018)` 的 136 项单元测试、12/12 设备测试、手机 UI 21/21、真实教务登录/课表/重启读取链路、签名 APP/HAP 与 DevEco 云测试已通过；安装与测试仅通过 AppGallery Connect 分发，不在 GitHub 上传安装包 |

> Apple 平台内测：需要 iOS 或 macOS 内测版本的同学，请将自己的 iCloud 邮箱发送至作者邮箱 [2099905168@qq.com](mailto:2099905168@qq.com)，由作者添加至 TestFlight 内测名单。
> Apple 平台公测链接（版本可能不是最新，最新需要等待审核通过）：https://testflight.apple.com/join/yuzpAtDJ
>
> HarmonyOS 测试：`0.2.8 (1002018)` 已由 DevEco 上传 AppGallery Connect 且云测试通过；[打开 0.2.8 邀请页面（链接已含邀请码，审核通过后生效）](https://appgallery.huawei.com/link/invite-test-wap?taskId=b4f098663ce7375007fb19b098feace9&invitationCode=A0IsJpKIcn3)，邀请码为 `A0IsJpKIcn3`。预审通过前公开页可能显示任务不存在；HarmonyOS APP/HAP 不作为 GitHub Release 附件。

## 下载

[**Where To Study v0.2.8**](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.2.8) 正式版提供 11 项公开附件：Windows x64 NSIS 1 项；Linux arm64/x86_64 Debian、AppImage、CLI、TUI 共 8 项；固定维护者密钥签名的 Android `0.2.8 (45)` Universal APK 1 项；原生 macOS Universal DMG 1 项。10 个桌面附件已替换，Android APK 保留；11 个附件均从 GitHub 重新下载并与本地发布文件逐字节一致。Windows/Linux GUI 分别来自 [run 33467351916](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467351916) / [33467352143](https://github.com/Nemoyuzx/where_to_study/actions/runs/33467352143)（`04a355c`），CLI/TUI 分别来自 [run 33378927605](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927605) / [33378927633](https://github.com/Nemoyuzx/where_to_study/actions/runs/33378927633)（`6e92141`）；已证明这些提交到最终 `main` 的全部运行时代码输入无差异，因此没有重复触发构建。这些是 main push 构建，tag-only attestation 按设计跳过，不声称刷新附件具有 tag/Sigstore 来源证明。GitHub 不上传 Android AAB、HarmonyOS APP/HAP、iOS、`.sha256` 或原生 macOS ZIP。本版本新增班车与重要事件查询、滚动增量渲染、完整本地收藏、按开关区分的日程颜色和鸿蒙系统导航条安全区适配；完整中英文改动见 [0.2.8 发布说明](./docs/release-v0.2.8.md)。iOS 与 macOS `0.2.8 (77)` 均已由本地 Xcode 上传 TestFlight；按约定不检查 App Store Connect processing。GitHub DMG 是未公证的开源预览包，Windows 安装器尚无公众 Authenticode 签名。

隐私声明 / Privacy Policy：[中文与 English 完整版本](./PRIVACY.md)。应用内各平台设置页提供同一组双语核心条款；所有天气、黄历、作业及活动截止信息仅供参考，请以实际官方信息为准。

## 许可证状态

本项目按 [GNU General Public License v3.0 only](./LICENSE)（SPDX：`GPL-3.0-only`）开源发布。分发本项目或其衍生版本时，必须遵守该许可证；第三方材料仍分别遵循 [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md) 与锁定依赖生成的 [`THIRD_PARTY_LICENSES.html`](./THIRD_PARTY_LICENSES.html) 中记录的条款。这三份法律文件都会随安装包交付并在打包时逐字节校验。

## 课程提醒与桌面小组件

macOS 与 Windows 桌面端的课程通知默认关闭。用户在设置中显式开启后，应用运行或驻留托盘时会于每天 7:30 根据本地课表发送今日课程摘要；关闭开关或清除本地数据会立即停止后续发送。后台调度只休眠到实际需要的跨日、每天 7:00、已启用的 7:30 或明确的有界重试时间；系统恢复、设置改变或窗口重新聚焦会中断休眠并重算边界，不进行固定间隔轮询。跨日会重建托盘中的今日/明日课程，7:00 获取当天空教室后也会再次重建托盘。

Windows 与 Linux 不注册课程小组件窗口、权限或托盘入口。原生 iOS 与 macOS 的 WidgetKit 小组件从系统小组件图库添加，通过 App Group 读取应用同步的今日课程；Android 原生桌面小组件读取应用私有课表缓存。三个原生平台的小组件会显示日期、星期、教学周、当前或下一节状态、课程时间、节次、教室与教师，并根据尺寸最多展示 6 门课程；设置页可用虚构示例实时预览各尺寸样式及地点、教师开关效果。课表刷新或清除后会更新小组件，当天无课程或尚未获取课表时统一显示“今日无课”。

SwiftUI 客户端会在系统待处理通知上限内安排最多 63 个未来有课日的 07:30 摘要；Android 使用持久化 `JobScheduler` 在 07:30–08:00 的有效窗口内发送当天摘要。所有平台都默认关闭，只有用户明确开启后才启用；系统权限被撤销、关闭开关或清除本地数据时会同步撤销后续任务。账号切换时，原生端会撤销旧账号的已安排摘要，桌面端则只会在新账号设置保存成功后继续使用当前开关。

## 数据来源与数据安全

图形与原生客户端使用北邮课表和空教室相关接口，因此需要教务系统账号和密码。账号与密码不会写入
普通设置文件：Windows 使用 Credential Manager，macOS/iOS 使用 Keychain，Linux Tauri 图形端
使用 Secret Service（GNOME Keyring / KWallet 等系统密钥环），Android 使用
Android Keystore。旧版 `settings.json` 中的凭据会在首次启动时迁移并从普通设置
中删除。迁移先原子替换脱敏设置文件，再写入系统凭据存储。Tauri 为每个已保存账号生成不含账号信息的随机不透明缓存作用域，账号切换或清除失败时会持久化撤销标记并拒绝旧缓存。Tauri 的
`load_saved_settings` 只向 WebView 返回 `has_saved_password`，不会返回真实密码；密码输入留空时保留已有系统凭据，只有显式输入新密码才替换。课程和空教室缓存不包含密码、token 或 cookie。完整基线见
[docs/security.md](./docs/security.md)。

`where-to-study-cli` 与 `where-to-study-tui` 按终端客户端的独立约定，不调用系统密码库：
账号和密码分别保存在用户配置目录下权限受限的专用本地文件中，且不会自动读取或迁移
图形客户端的系统凭据。具体路径与风险说明见 [wts-cli/README.md](./wts-cli/README.md)
和 [wts-tui/README.md](./wts-tui/README.md)。

法定节假日运行时数据来自
[cg-zhou/holiday-calendar](https://github.com/cg-zhou/holiday-calendar)，客户端通过其文档列出的
[固定到 1.3.3 版本的 unpkg HTTPS 年度 JSON 地址](https://unpkg.com/holiday-calendar@1.3.3/data/CN/2026.json)按年份读取 `CN`
数据。上游说明中国数据依据国务院办公厅年度节假日安排通知整理，并以 MIT License 发布；完整版权与
许可文本见 [THIRD_PARTY_NOTICES.md](./THIRD_PARTY_NOTICES.md)。客户端严格核对响应年份、地区、日期、
名称和类型，将 `public_holiday` 与 `transfer_workday` 映射到现有本地契约，未知类型不会写入缓存。
Tauri、SwiftUI 和 Android 客户端都保留一份仅用于首次离线展示的 2026 年兜底日期，其内容对应
[国务院办公厅关于 2026 年部分节假日安排的通知](https://www.gov.cn/yaowen/liebiao/202511/content_7047099.htm)；
远端或本地缓存可用后会使用自动获取的数据。

Android 原生客户端在用户已授权系统日历访问时，可从设备自带的“中国（大陆）节假日”日历读取休息日，并仍以远端数据补充“调休/补班”上班日。iOS/macOS 设备日历会混入不等于休息日的普通节日，因此 Apple 客户端与 Tauri 桌面端都只使用上述固定版本权威数据源标记“休/班”。

校区天气和基础黄历信息来自 [UAPI 天气接口](https://uapis.cn/docs/api-reference/get-misc-weather)与[农历接口](https://uapis.cn/docs/api-reference/get-misc-lunartime)，黄历中的“宜/忌”由 [Timeless API](https://api.timelessq.com/docs/api-15277838)补充。西土城按海淀区行政区划代码查询，沙河按昌平区查询；黄历请求只提交所选日期或由其换算的时间戳和上海时区，不会附带教务凭据、课表或空教室数据。Windows、Linux、iOS、macOS、Android 与 HarmonyOS 图形客户端的天气区域统一为默认折叠卡片，折叠时保留校区与当前天气摘要，展开后显示今日、明日详情和数据来源；设置中可以完全关闭天气或黄历卡片。

学科竞赛、学术会议、期刊专题、夏令营、预推免与黑客松 DDL 的主数据来自 [Contest DDL](https://nemoyuzx.github.io/contest-ddl/) 的[公开 JSON](https://nemoyuzx.github.io/contest-ddl/data/competitions.json)，应用下载后仅在本地按所选日期和已开启类别筛选。主源不可用时，支持的平台会尝试固定 HTTPS 备用地址 [`https://where-to-study.cn/api/contest-events`](https://where-to-study.cn/api/contest-events)。独立的[北邮校内竞赛通知 API](https://where-to-study.cn/api/contest-notices)由服务器脚本从学校内部网站的公开通知页提取并整理截止节点，条目链接回云课堂 HTTPS 原文。两条固定接口都只发送不含账号、密码、Cookie、token、课表、教室或作业数据的 HTTPS GET，并拒绝重定向。学科竞赛、学术会议、校内竞赛通知、夏令营和黑客松各有独立的教学日历开关，卡片底部会标明全部第三方来源。

校区班车来自固定的[班车 API](https://where-to-study.cn/api/shuttle-bus)。服务器每小时增量检查北京邮电大学后勤部公开通知，只把通过严格校验的官方表格识别结果作为结构化班次；客户端按上海日期选择当前执行时段和当天星期，并标记已发车、下一班与计划班次。最新通知尚未安全解析时只会明确显示提示或上一份完整表作为对照，不会发布推测班次。请求不包含教务凭据、课表、校区设置或 GPS，节假日及临时调整请以后勤部原文为准。

用户还可以启用[自定义日程接口](./docs/custom-schedule-api.md)。客户端只接受不含凭据、片段、回环地址或私网字面量的公开 HTTPS JSON 地址，拒绝重定向并限制响应大小、条目数与查询频率；API 返回的文字保持原文。收藏操作会把单条日程的完整快照保存在当前设备，不上传也不跨设备同步；来源关闭、失败或移除条目后仍会在教学日历中显示，取消收藏或“清除本地数据”才会删除。

课程作业解析以[北邮云课堂官方作业页](https://ucloud.bupt.edu.cn/uclass/course.html#/student/studentAssignmentListPage?ind=3)的真实 `records` / `undoneList` 响应契约为准。启用日期详情中的作业卡时，客户端从系统安全存储临时读取已保存的教务账号和密码，仅通过 HTTPS 提交给 `auth.bupt.edu.cn` 完成统一认证，再以内存中的一次性票据换取云课堂访问令牌并读取当前课程和作业；不会读取浏览器 Cookie/token，也不会把密码发送给 `ucloud.bupt.edu.cn` 或 `apiucloud.bupt.edu.cn`。票据、Cookie 和令牌不写入磁盘；用于跨日期查询的全量作业结果最多复用 10 分钟，已显示的日期结果只保留在当前进程内，并在切换账号或清除本地数据时立即失效。

## 开发与运行

所有平台的应用主图标以 `src-tauri/icons/icon.png`（Windows/Tauri 当前绿色日历课桌图标）为唯一源图。修改源图后运行 `npm run icons:sync`，同步生成 Windows/macOS Tauri、原生 iOS 和 Android 启动图标；macOS 菜单栏与 Android 通知图标仍使用符合系统规范的单色模板资源。

```bash
npm install
npm run tauri dev
```

### 构建桌面端

```bash
npm run tauri:build
```

在 Windows 机器上构建可复现的 64 位 NSIS 安装包：

```bash
npm run tauri:build:windows
```

该脚本固定使用 `--bundles nsis --ci`，产物位于 `src-tauri/target/x86_64-pc-windows-msvc/release/bundle/nsis/`。Windows 构建建议在 Windows 机器或 Windows CI runner 上执行，需要安装 Rust MSVC toolchain、Microsoft C++ Build Tools 和 WebView2 Runtime。

在 Debian 12/Ubuntu 22.04 或兼容的 x86_64 Linux 环境构建 Debian 包与 AppImage：

```bash
npm run tauri:build:linux
./scripts/linux-package.sh vX.Y.Z
```

Linux 打包脚本会解包校验版本、架构、Tauri 按构建环境检测出的 GTK/WebKitGTK/托盘运行时依赖、正式 HTTPS 数据源和三份法律文件，并输出带相邻 SHA-256 文件的 `.deb` 与 `.AppImage`。仓库的 `Build Linux` 工作流使用 Ubuntu 22.04 作为兼容构建基线，并在 Ubuntu 24.04 runner 上实际安装生成的 `.deb`。

Linux 终端客户端可以直接从 Release 安装。以 x86_64 为例：

```bash
mkdir -p ~/.local/bin
curl -L https://github.com/Nemoyuzx/where_to_study/releases/download/v0.2.8/where-to-study-cli-linux-x86_64.tar.gz | tar -xz
curl -L https://github.com/Nemoyuzx/where_to_study/releases/download/v0.2.8/where-to-study-tui-linux-x86_64.tar.gz | tar -xz
install -m 0755 where-to-study-cli where-to-study-tui ~/.local/bin/
```

arm64 Linux 将文件名中的 `x86_64` 改为 `aarch64`。也可以按 CLI/TUI 各自 README
中的步骤从源码构建；请确保 `~/.local/bin` 已加入 `PATH`。

### 原生客户端

生成并验证 macOS/iOS SwiftUI 工程：

```bash
./scripts/native-apple-build.sh
```

验证 Android Kotlin 工程：

```bash
./scripts/native-android-build.sh
```

验证鸿蒙（HarmonyOS NEXT）ArkTS 工程（需要 DevEco Studio 6.1.1+ 与已连接的设备/模拟器）：

```bash
./scripts/native-harmony-build.sh
```

`native/apple`、`native/android` 与 `native/harmony` 是当前 macOS、iOS、Android 和鸿蒙客户端源码。它们已完成个人课表与本地缓存、每日课程摘要、含法定节假日和当前时间线的日/周/月/年日历，以及仅限当天的空教室联动查询。Apple 客户端还提供不连接教务服务的内置示例模式，供首次体验与 App Review 审核。HarmonyOS 源码已合入 `main` 并纳入本地构建与单元测试；AGC 正式签名和商店发布仍需维护者的华为开发者账号配置。

Android 仅使用 `native/android` 的 Kotlin + Android Framework Views 工程，不依赖 Tauri 或 WebView。旧 `src-tauri/gen/android` 工程、Tauri Android npm 命令和 CI 构建任务均已移除，避免误生成或误发布另一套 Android 包。

生成本地签名 Android APK/AAB、macOS Universal ZIP/DMG 和无签名 iOS 真机 archive：

```bash
./scripts/native-android-signing-init.sh
./scripts/native-android-package.sh vX.Y.Z
./scripts/native-macos-package.sh vX.Y.Z
./scripts/native-ios-package.sh vX.Y.Z
```

Android 脚本会运行 Release 单元测试与 Lint，构建并校验签名 APK 与 AAB；macOS 脚本构建双架构 Release 应用、进行临时签名和签名校验，并生成带 Applications 快捷方式且通过 `hdiutil verify` 的 DMG；iOS 脚本构建 arm64 真机 archive，并检查应用图标和隐私清单。三个脚本都会在 `release-artifacts/` 中生成产物和 SHA-256 文件。Android 脚本需要本地、已忽略的 release keystore；macOS GitHub 包不包含 Developer ID 公证票据；iOS archive 未签名，不能直接安装到 iPhone。发布前还应另外运行完整测试和所需的人工运行检查。

面向 Mac App Store、iOS App Store 或 TestFlight 的正式签名归档使用：

```bash
./scripts/native-apple-app-store.sh preflight all
APPLE_DEVELOPMENT_TEAM=XXXXXXXXXX APPLE_BUILD_NUMBER=31 \
  ./scripts/native-apple-app-store.sh archive all
```

脚本还支持 `export` 与 `upload` 动作，并可单独指定 `ios` 或 `macos`。本地正式构建使用已安装的 Apple Distribution、Mac Installer Distribution 证书及 iOS/macOS 主应用和 Widget 共四个 App Store 描述文件；团队、描述文件覆盖值和 App Store Connect API 私钥只通过环境变量传入。`Build Native Clients` 工作流也提供受保护的手动上传入口。完整账户配置、CI secrets、元数据和审核步骤见 [`native/apple/AppStore/submission-checklist.md`](./native/apple/AppStore/submission-checklist.md)。

## GitHub Actions

仓库内提供以下构建和安全工作流：

- `.github/workflows/build-windows.yml`：在 `windows-latest` 上构建 Windows 桌面安装包。
- `.github/workflows/build-linux.yml`：在 Ubuntu x86_64/arm64 runner 上构建、安装验证 Linux Debian/AppImage，并为标签制品生成来源证明。
- `.github/workflows/build-cli.yml` 与 `.github/workflows/build-tui.yml`：构建两个架构的 Linux 终端制品，并为标签制品生成来源证明。
- `.github/workflows/build-macos.yml`：在 `macos-15` 上构建并压缩 macOS Apple Silicon 应用。
- `.github/workflows/build-native.yml`：在主分支及手动触发时运行 Rust/Apple 测试，在主分支运行 Android Debug 门禁；版本标签额外生成 SwiftUI macOS Universal、无签名 iOS archive，以及签名 Android APK/AAB，但公开 GitHub Release 只接收 APK，AAB 保留给商店/内部交付。
- `.github/workflows/security.yml`：扫描提交历史中的敏感信息，并审计完整 npm 与 Rust 锁文件依赖。

正式原生 Android 标签构建使用以下 secrets：`ANDROID_RELEASE_KEYSTORE_BASE64`、`ANDROID_RELEASE_STORE_PASSWORD`、`ANDROID_RELEASE_KEY_ALIAS`、`ANDROID_RELEASE_KEY_PASSWORD`。标签工作流生成的未签名 iOS archive 与 macOS 构建仅作为受限的 Actions artifact 用于内部验证，不上传到公开 GitHub Release；App Store 构建使用本地、Xcode Cloud 或受保护 CI 环境中的 Apple 分发凭据，不把证书或私钥提交到仓库。

Windows/Linux 标签构建使用 GitHub OIDC 短期身份生成来源证明，不保存 Sigstore 私钥。Windows 的 Authenticode“已验证发布者”必须另行完成公众信任身份验证；不要用自签名证书或把新购证书假定为可导出的 PFX。完整配置边界见 [docs/code-signing.md](./docs/code-signing.md)。

如果不在界面输入学号和教务密码，也可以在启动前配置环境变量：

```bash
export BUPT_USERNAME=你的学号
export BUPT_PASSWORD=你的教务密码
```

学期号与开学日期的持久化默认值保持为空；自动模式会在请求课表时按上海时区的
当前日期生成临时兜底值，手动模式则要求用户完整填写。

学期与开学日期支持自动识别：

- 设置页提供「按当前日期自动检测」按钮，按校历规律（春季 3 月初 / 秋季 9 月初）
  预填当前学期的学期号与开学日期。
- 教务当前周课表返回的学期号、周次和日期为权威信息；客户端由此反推第一周周一并保存。
- 保存有效教务凭据且开启自动检测后，应用启动时会自动刷新一次个人课表以校验学期；
  教务暂时缺少该元数据时，才使用当前日期推断作为临时兜底。
