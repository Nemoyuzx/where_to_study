# 0.3.1-prerelease 构建与验证记录

本轮范围：安卓查询子页切换／异步更新的内容区刷新边界、考试及作业页面间距，以及全部图形端课程成绩卡片／平均绩点的紧凑布局。无认证、网络接口、隐私权限、签名配置或课程提醒行为变更。

发布标签为 `v0.3.1-prerelease`，包内版本 `0.3.1`。同一预发布标签的最新测试包为 Android build **56**、Apple build **99**、HarmonyOS versionCode **1002035**；下文同时保留早期测试包回执。0.3.0 仍为稳定版。本轮班车图标热修复只替换Android APK，不重发Apple或鸿蒙，也不提交正式商店审核。

## 已完成的源代码与验证

- Android：固定查询标题、分段选择器与滚动容器，子页切换仅过渡正文；独立保存滚动位置，异步课程加载不重建查询页面。考试／作业相邻内容间距16dp，成绩与GPA卡片纵向内边距10dp。窄屏分段与iOS使用相同中英短标题，完整无障碍名称保留，大字体才按需要横向滚动。286项JVM、19项查询／教务仪器测试通过，Lint为0错误／68条警告；最终短标题正常及1.5倍字号各4项稳定性测试通过，中英手机／平板与大字体截图已目视检查，未改底部导航或32dp全局按钮尺寸。
- Windows/Linux 共用前端：成绩卡片 vertical/horizontal padding 为 10/12px，元数据自然横排换行，结果区不再额外拉伸，空元数据不留占位。Edge 合成数据同宽测量单卡约 **118.23 → 69.43px**，平均绩点行 **22.5 → 19.60px**；中英与窄桌面显示无溢出，0学分、文字及未公布成绩保留。测试使用本地预览虚构数据，不向学校发送账号。
- Apple：单卡同内容 iPhone/iPad **107 → 59pt**、Mac **96 → 53pt**；三门课程加平均绩点 **389.5 → 221.5pt**（iOS）、**352 → 199pt**（Mac）。Mac 全套403项、标准 iPhone 全套424项均零失败，各跳过1项既有在线测试。iPhone/iPad 中英文查询 UI 各2项通过，成绩渲染、完整长中英字段与AX3字体检查通过。额外 iPad 全量中的两个未修改日历像素测试有6个颜色断言失败，独立复现；相同测试在 iPhone 通过，可能与倍率取样有关，不将该额外整套测试记为通过。
- HarmonyOS：课程卡片 vertical/horizontal padding 10/12vp、内部间距4vp、结果/GPA分组间距8vp；保留字号、全部字段和32vp控件。247项Hypium及正常ArkTS/HAP编译通过。本机无连接设备，不能将主机测试当作鸿蒙设备视觉验证。
- CLI/TUI 成绩原本就是单行表格、平均绩点位于表格标题，没有高卡片区域，保持既有紧凑布局，只同步版本。

以下区分源代码测试、本地签名和各平台上传回执。安装包使用对应平台已封存的源码构建；上传前做本地签名／版本／包结构／摘要核验，上传后仅核对 GitHub API 名称、大小和摘要，不回下载 Release 安装包。Apple 以 `Upload succeeded` 与 `EXPORT SUCCEEDED` 为完成标准，不检查后续处理状态。

## 最终源码与本地签名包

- 最终源码：`602c84585b863ef559f966ce90cd0f0bf38324dc`。首轮 `a498215` 中，Android 新增的窄屏中英短标题导致旧的源码测试精确匹配不再成立，`4073350` 更新对应合约；最终 `602c845` 又补齐设置／空教室请求完成后切入查询页的异步边界。全部修订在 Release 创建之前完成，0.3.0 稳定标签未改动。Apple/Harmony及桌面产品输入从 `a498215` 起保持不变，Android最终包使用 `602c845` 重建。
- 最终 Web/跨平台合约：234项，233通过、1项仅Windows安装后才能运行的PE测试本地跳过；Vite生产构建和许可证检查通过。Rust桌面227通过／3项已有忽略，core100、CLI24、TUI50全部通过。
- Android最终补充回归：4项新增仪器测试覆盖10个延迟场景（设置自动／手动、启动、考试成功与失败、空教室迟到、考试回包保留设置页草稿），与原4项查询稳定性测试合计8项全部通过。失败回包也恢复考试刷新按钮；考试来源不会重建已切到的设置页、丢失未保存输入或焦点。
- 最终签名APK：`Where-To-Study-v0.3.1-prerelease-native-android-universal.apk`，**1,170,970 bytes**，SHA-256 `d0957fbc0566d4ec6648baa0eba1dbbe85b04c21705ed3dfe776022c28e2656e`。buildCommit为 `602c845`，0.3.1（54），Release JVM286/286，Lint0错误／68警告，v2/v3原证书、ZIP对齐、许可证、HTTPS策略及端点检查通过。首轮包保留在本地，不公开发布；AAB也不上传。

本节记录本地构建，不能误读为正式应用商店上架；Apple与鸿蒙测试上传见下文。

## HarmonyOS 测试上传

2026-09-21 **16:18 +0800**：DevEco Studio 中确认主工程、应用 `Where To Study`、版本0.3.1，选择第二项“生成.app包并上传至AppGallery Connect进行测试”，返回 **云测试结果：通过**。未选择测试并发布，未提交正式审核，也未公开上传鸿蒙文件至GitHub。

已独立验签并封存DevEco最后生成、实际上传的字节（不是较早CLI包）：

| 包 | 字节数 | SHA-256 |
| --- | ---: | --- |
| APP | 1,367,156 | `98fb121cf0dbda0e451e475f99c9fbb45727bc991464c3de6b60db1f492e0869` |
| HAP | 2,096,711 | `d62e8f320f137d540928881f597f6c0be216d76f221a70b9757e7f7b119d2421` |

二者pack.info均为 `com.nemoyu.wheretostudy` / **0.3.1（1002034）**；`app.debug=false`、`buildMode=release`、verify-app和release profile验证通过。DevEco窗口中的构建版本1不替代versionCode1002034。云测试通过不代表本机已完成鸿蒙设备视觉测试。

## Apple TestFlight 上传

使用本地Xcode签名和归档，iOS Automatic、macOS Manual，保留既有签名配置。2026-09-21：

- iOS **16:16:25 +0800**：`Upload succeeded`、`EXPORT SUCCEEDED`。首次传输会话创建阶段遇到网络无路由错误，网络恢复后复用同一已验证归档重试成功，没有重复归档或重复成功上传。
- macOS **16:20:01 +0800**：`Upload succeeded`、`EXPORT SUCCEEDED`。
- 两个平台主程序和课程小组件均为 **0.3.1（98）**；iOS arm64，macOS arm64+x86_64。上传前Distribution导出／签名核验通过。
- 依用户边界，上传成功后未检查App Store Connect处理状态，未提交正式审核。
- GitHub原生macOS Universal DMG：**7,950,811 bytes**，SHA-256 `0125f16d568035fddb95f42dd3f0deb6c47d02b0ecc1a9428e17bff4bb18d37d`。只读挂载确认主程序／小组件版本和双架构、签名及许可证；这是ad-hoc签名、未公证的GitHub包，与TestFlight的Distribution签名渠道不同。

## 最终标签 CI

以下运行均对应最终提交 `602c845`；GitHub安装文件只取自这一轮，不使用先前被替代的标签运行。

**7条工作流最终全部成功。** Native包含完整iOS交互回归：英文课前提醒测试首轮在可点击性断言失败，内建第二轮通过，后续全部完成，以工作流最终success为准；没有取消、手动重跑或跳过该标签门禁。

| 工作流 | 运行 |
| --- | --- |
| Windows | [35577999018](https://github.com/Nemoyuzx/where_to_study/actions/runs/35577999018) |
| Linux | [35577999030](https://github.com/Nemoyuzx/where_to_study/actions/runs/35577999030) |
| macOS | [35577999014](https://github.com/Nemoyuzx/where_to_study/actions/runs/35577999014) |
| Native Clients | [35577999037](https://github.com/Nemoyuzx/where_to_study/actions/runs/35577999037) |
| CLI | [35577999060](https://github.com/Nemoyuzx/where_to_study/actions/runs/35577999060) |
| TUI | [35577999053](https://github.com/Nemoyuzx/where_to_study/actions/runs/35577999053) |
| Security Checks | [35577999013](https://github.com/Nemoyuzx/where_to_study/actions/runs/35577999013) |

9个CI安装文件均校验了Actions整档API字节数／SHA-256、包内侧文件、最终源码提交、版本与架构、许可证、HTTPS端点，以及GitHub来源证明（额外限定source digest为 `602c845`）。Windows主程序为x64／PE GUI子系统2；Linux含Ubuntu安装测试及AppImage主机ABI隔离校验。Linux较慢的Actions传输保留已收前缀并按HTTP206分段补齐，再验证整个档案摘要；没有回下载Release文件。来源证明不等于Windows Authenticode签名。

## GitHub 预发布回执

2026-09-21 已公开 [Where To Study v0.3.1-prerelease](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.3.1-prerelease)（Release ID `392833172`）：`draft=false`、`prerelease=true`；`releases/latest` 仍指向 **v0.3.0** 正式版。

恰好11个安装文件：Windows EXE、Linux x86_64/aarch64各一份DEB和AppImage、CLI/TUI各两种Linux架构、Android Universal APK、原生macOS Universal DMG。不含Android AAB、鸿蒙APP/HAP、iOS归档、macOS ZIP或SHA侧文件。

公开前后均使用GitHub API核对全部11个远端文件的名称、大小、uploaded状态及SHA-256，与已封存本地字节一致；最终标签仍解析到 `602c845`。没有下载任何GitHub Release安装文件作回验。GitHub CLI状态查询遇到TLS超时后，改用同一已有GitHub认证的REST请求完成操作，没有改系统网络设置；草稿按已创建的Release ID继续操作，没有重复创建发布。

本地完整清单／最终API回执位于忽略目录 `release-artifacts/v0.3.1-prerelease-verification/`；签名和上传详情分别保存在本轮独立Apple、Android及DevEco输出目录，不写入仓库中的签名配置。

## 同标签手机端热更新（build 55／99／1002035）

本节对应用户反馈后的同版本测试包更新；最终提交、签名包摘要与渠道回执会在完成后补记。首轮已发布的Windows/Linux/CLI/TUI文件不变，不重复下载或替换。

- Android查询栏改为固定等宽五段：手机含横屏始终显示矢量图标，空间够时带短标题，不够时统一仅图标；不再左右拖动。平板宽屏仍显示文字，保留完整中英文无障碍标签。手机“信息查询”标题从34sp降为26sp。
- Android当前学期在按钮和选择列表中追加本地化“当前学期”，避免重复；GPA与空成绩卡片间留10dp。深浅主题导致Activity重建时仅在内存交接成绩仓库、学期、记录类型和查询状态，正常退出仍清空，不写磁盘、不重取网络。
- Android设置开关使用显式启用／关闭／禁用状态色，并修复系统轨道底层透明度导致浅色开启颜色过淡的问题。
- iPhone五段使用原生SF Symbols和完整AX标签；iPad/Mac按实际宽度、本地化文字与动态字体测量，在文字放不下时切为图标。HarmonyOS手机以固定五段原生Symbol呈现，空间不足时仅图标，平板保留文字；二者都不使用横向滚动。
- Android：288项JVM通过，Lint 0错误／68警告／1 hint，debug/androidTest构建通过；常规字体32项、大字体14项、平板大字体3项，共49次隔离模拟器回归通过。人工检查中英、深浅、横屏侧栏、空成绩、主题往返和开关像素；未使用真实教务账号或OEM真机。
- Apple：Mac 25项相关测试、iPhone 25项单元／渲染与3项UI、iPad 3项通过；人工检查iPhone中英×普通/AX3×深浅8张，以及iPad宽／窄布局。测试使用iOS 26.3模拟器，无实体机。
- HarmonyOS：251/251 Hypium通过，release `PackageHap`／`CompileArkTS`和`OhosTestCompileArkTS`成功；本机无hdc设备，设备视觉待DevEco云测，不能将主机测试记为真机视觉通过。
- 独立静态审查发现并修复了Android横屏手机使用侧栏时丢失图标回退的问题；最终三平台生产diff未发现剩余P1/P2。

### 热更新源码与本地签名包

- 产品源码提交：`e340c8f6a61bcf493467a2d58c0fc5e31e5a473e`。首次最终标签运行的Apple测试在第30/35项触发既有50分钟步骤上限；随后只把Native Apple job／step时限从60/50提高到90/80，并同步契约测试。最终标签解析到 `5ffdc0e4db4b718c096f30cbd4ba73ec8ecef9ce`，两次CI提交与产品提交之间的全部Android／Apple／Harmony源代码、打包脚本、许可证输入diff为空，因此签名包无需重建。
- Android APK：**1,172,442 bytes**，SHA-256 `7603288e5a189aadd4405d1b8c647c47d2482d3b779c2b925b4a8f89f3eb53a1`，0.3.1（55）。Release 288项、Lint 0错误／68警告／1 hint、v2/v3原证书、zipalign、许可证、HTTPS策略与旧域名检查通过。对未修改的混淆签名APK另用同证书、任务内临时instrumentation离线注入纯内存合成成绩，验证五个固定图标Tab、13个浅色设置开关、浅→深→浅成绩保留／不重取／退出清空；测试包已卸载、隔离AVD已关闭。AAB只保留本地。
- Apple：iOS与macOS主程序／小组件均为0.3.1（99）。iOS arm64于 **18:22:46 +0800**、macOS arm64+x86_64于 **18:26:09 +0800** 各唯一上传一次，均返回 `Upload succeeded` 与 `EXPORT SUCCEEDED`；随后未检查App Store Connect处理状态或提交审核。Distribution导出签名、App Group、权限、隐私和许可证通过。
- 新的GitHub原生macOS Universal DMG：**7,960,292 bytes**，SHA-256 `9f2af2bd12c22bf5772127c41a2d7f0e88edac8827e9da61d734cb0e3ee323ca`；只读挂载确认主程序／小组件99、双架构、ad-hoc签名和许可证。仍未公证，ZIP、IPA、PKG和侧文件不公开。
- HarmonyOS：DevEco选择第二项“生成.app包并上传至AppGallery Connect进行测试”，0.3.1（1002035）云测试于 **18:24 +0800** 通过；未选择测试并发布，未提交正式审核。DevEco实际上传后APP为 **1,368,187 bytes**／SHA-256 `3c212a400f66db1198ccebace97a04a070bd600830697b90c1daa9bfe62a3a28`，HAP为 **2,103,676 bytes**／SHA-256 `374f46136606b037ee5bb8cc88e42d754f967aa44969ef55598efc247e8e6b0f`。二者pack.info均为1002035，release build mode、verify-app和release profile通过；不上传GitHub。

### 热更新最终CI与GitHub回执

最终标签 `5ffdc0e` 的七条工作流全部成功：

| 工作流 | 运行 |
| --- | --- |
| Windows | [35592732264](https://github.com/Nemoyuzx/where_to_study/actions/runs/35592732264) |
| Linux | [35592732180](https://github.com/Nemoyuzx/where_to_study/actions/runs/35592732180) |
| macOS | [35592732176](https://github.com/Nemoyuzx/where_to_study/actions/runs/35592732176) |
| Native Clients | [35592732213](https://github.com/Nemoyuzx/where_to_study/actions/runs/35592732213) |
| CLI | [35592732104](https://github.com/Nemoyuzx/where_to_study/actions/runs/35592732104) |
| TUI | [35592732182](https://github.com/Nemoyuzx/where_to_study/actions/runs/35592732182) |
| Security Checks | [35592732156](https://github.com/Nemoyuzx/where_to_study/actions/runs/35592732156) |

Native Apple完整测试步骤用时54分58秒并最终返回 `TEST SUCCEEDED`；新增查询图标UI测试首轮通过。两个既有测试出现过首轮等待超时：Custom Feed状态文字和无节假日数据时月份动画，均由脚本的内建第二轮自动通过，没有人工重跑；记录不能表述为“所有尝试零失败”。

同一 [v0.3.1-prerelease](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.3.1-prerelease) 中只替换：

| 资产 | 新字节数 | 新SHA-256 |
| --- | ---: | --- |
| Android Universal APK | 1,172,442 | `7603288e5a189aadd4405d1b8c647c47d2482d3b779c2b925b4a8f89f3eb53a1` |
| 原生macOS Universal DMG | 7,960,292 | `9f2af2bd12c22bf5772127c41a2d7f0e88edac8827e9da61d734cb0e3ee323ca` |

替换后Release仍为 `draft=false`／`prerelease=true`，恰好11个公开资产；另外9个Windows/Linux/CLI/TUI资产的远端ID、大小和摘要与替换前完全一致。GitHub API确认两个新资产均为uploaded且摘要匹配本地，远端注释标签解析到 `5ffdc0e`，`releases/latest` 仍为 **v0.3.0**。未回下载任何Release文件，未公开AAB、鸿蒙包、iOS归档或SHA侧文件。

## Android班车动作图标热修复（build 56）

Android全局控件高度已是32dp，但班车刷新、通知原文和来源外链仍保留四边13dp内边距，导致实际图形区域只有6dp。三个动作现使用独立44dp点击区与24dp图形区域，不再跟随文字控件高度；保留主题tint、完整中英无障碍名称和原点击逻辑。

- Android：288/288 JVM通过，Debug与测试APK构建成功；6组共14项设备回归全部通过，每项覆盖中英。矩阵包含手机竖屏／横屏／平板、浅色100%与深色150%字体。测试按真实vector与ImageView matrix栅格化，要求图形区域24dp、可见墨迹至少16dp、居中且不裁剪；人工检查24张上下截图和底部导航安全区。
- 两项测试误报被限定在测试代码：英文换行尾空格改用Android SDK定义的可视行宽 `getLineMax`；横屏大字体等待已layout的线路视图，不再要求其必须出现在首屏无障碍树。生产布局未因此改动。
- HarmonyOS只读核对：刷新17fp、通知外链18fp、来源外链16fp，均有至少44vp点击区域，不存在Android的padding压缩路径。251/251 Hypium、12项密度／查询契约和release CompileArkTS通过；没有生产diff，本轮不重发鸿蒙包。Apple使用SF Symbols，也没有该Android专用路径，本轮不重发。

### 班车图标热修复发布回执

- 产品提交：`b9e41461502e25137aabb5fedb081a37536f81cb`；Android 0.3.1（56）APK为 **1,172,474 bytes**，SHA-256 `815e9d3569bb94344582207866c9e534724cfb3ddc4436ba98a92f88edaa2c78`。Release 288/288、Lint 0错误／68警告／1 hint、v2/v3固定证书、zipalign、许可证、HTTPS策略和旧端点检查通过。
- 最终混淆签名APK的任务内instrumentation smoke中英×浅深4/4通过：三处44dp点击区、24dp图形区、真实墨迹、AX／tint、离线刷新保留同一缓存，以及两个外链目标均验证；测试拦截外链，不打开浏览器。测试安装和隔离AVD已清理，AAB仅本地。
- 主分支 [Security Checks 35602155868](https://github.com/Nemoyuzx/where_to_study/actions/runs/35602155868) 成功；[Native Clients 35602155888](https://github.com/Nemoyuzx/where_to_study/actions/runs/35602155888) 中与本项相关的Android Debug测试／Lint／构建job成功。窄范围现有资产热修复不移动发布标签，注释标签对象仍为 `1086868e`，解析提交仍为 `5ffdc0e`。
- GitHub只以 `--clobber` 替换同名Android APK；API确认新远端资产为uploaded、字节数和SHA-256与本地一致。Release仍为 `draft=false`／`prerelease=true` 且恰好11个资产，另外10个资产的ID、大小和摘要全部保持不变；`releases/latest` 仍为 **v0.3.0**。
- 按用户要求未回下载GitHub Release文件。Apple 99、HarmonyOS 1002035及其测试渠道均未修改或重发。
