# Where To Study · 鸿蒙（HarmonyOS NEXT）原生客户端

北邮空教室与个人课表联动查询应用的鸿蒙原生客户端，参考 native/apple 的 SwiftUI 实现
逐模块移植，业务语义与 contracts/v1 数据契约、其余三个平台保持一致。

## 技术栈

- DevEco Studio 6.1.1（API 24，HarmonyOS NEXT 6.1.1，Stage 模型；SDK 6.1.1.125）
- ArkTS + ArkUI 声明式 UI（状态管理使用 V2 的 @ObservedV2/@Trace 与 @Provider/@Consumer）
- 网络：@ohos.net.http；安全凭据：@ohos.security.asset（对应 Keychain/Keystore）
- 缓存：@ohos.data.preferences + 沙箱 JSON 文件；测试：hypium

## 目录结构

    native/harmony/
    ├── AppScope/                     # 应用级配置（bundleName、图标、版本）
    ├── entry/src/main/ets/
    │   ├── entryability/             # EntryAbility
    │   ├── pages/                    # Index 根页面（注入唯一 AppModel）
    │   ├── common/                   # 契约模型、日期工具、主题、节次逻辑
    │   ├── model/                    # AppModel 应用状态机
    │   ├── store/                    # 凭据/课表/空教室/节假日存储
    │   ├── net/                      # 移动教务、节假日、天气、黄历与公开 DDL 客户端
    │   └── view/                     # RootView、四个一级页面（含班车/重要事件查询）
    ├── entry/src/test/               # 本地单元测试（hypium，复用 contracts/v1 fixtures）
    └── entry/src/ohosTest/           # 设备侧测试

## 构建与测试

1. 安装 DevEco Studio 6.1.1（含 HarmonyOS NEXT SDK，API 24）。
2. 打开 native/harmony，等待 hvigor 依赖自动安装后直接运行 entry 模块。
3. 命令行构建与单元测试（自动探测 DevEco；测试需要已连接的设备/模拟器）：

```bash
./scripts/native-harmony-build.sh      # assembleHap/assembleApp + 144 个契约单元测试
./scripts/native-harmony-ui-smoke.sh   # UI 冒烟测试（手机 21 项、宽屏 11 项）
```

手动命令（hvigorw 在 DevEco 安装目录下）：`hvigorw assembleHap` 与
`hvigorw test --mode module -p module=entry -p buildMode=test`。
测试源码在 `entry/src/test`（契约用例覆盖日期/节次/公历周与教学周/表单编码/URL 策略/
课表解析/空教室解析/节假日解析/天气与黄历解析、云课堂作业契约、公开 DDL、折叠策略、日历纯逻辑/通知规划与协调）与
`entry/src/ohosTest`（DevEco 内运行的 UI 冒烟套件，对应
native/apple/UITests/PrimaryNavigationSmokeTests 的导航、账号输入、示例模式与日历断言）。

## 签名与发布

最新测试构建为 `0.2.9 (1002026)`：2026-09-09 15:58 +0800 确认 DevEco **仅测试**上传完成，云测试通过；新增自定义每日课程提醒时间和卡片剩余空间的明日课程。复用 175 项单测与完整构建回归，最终 APP/HAP 版本和签名复核通过；没有提交上架审核，未补记设备视觉验证。详见[测试上传记录](../../docs/release-v0.2.9.md)。

此前背景主题测试构建 `0.2.9 (1002025)`：2026-09-09 10:46 +0800 确认 DevEco **仅测试**上传完成，结果页显示云测试通过；没有提交上架审核。低饱和预设同步背景、卡片和控件，并修复实际染色层文字可读性；最终 163 项单元测试、完整 APP 构建、APP/HAP 版本与签名核验通过。设备视觉回归限制保持原记录；详见[测试上传记录](../../docs/release-v0.2.9.md)。

此前 `0.2.9 (1002024)` 于 2026-09-09 通过 DevEco 第二项“生成.app包并上传至AppGallery Connect进行测试”完成 **仅测试**上传，结果页显示云测试通过；没有提交上架审核。158 项主题/逻辑单元测试及验证限制保持历史记录，该包尚不含后续背景协调优化。

`0.2.9 (1002023)` 已于 2026-09-08 通过 DevEco“上传产品 → 测试和发布”上传 AppGallery Connect，快速云测试显示通过：按上架后审核报告统一 PC/2in1 日历的最小字号至 10fp，包含默认、最大化和紧凑窗口；月周标签单独占行，手机/平板原字号不变。144 项本地单元测试、146 项仓库测试、HAP/APP 构建与 release 签名验证通过；设备视觉回归与新完整审核仍待验证，未再次提交上架审核。实际上传产物摘要见[修复与上传记录](../../docs/harmony-pc-typography-v0.2.9.md)。

此前 `0.2.8 (1002022)` 已按 [2026-09-05 完整云测试报告](../../docs/harmony-cloud-test-2026-09-05.md) 优化月视图节点刷新、日期缓存、禁用按钮对比度、侧栏图标与普通滚动边界反馈。141 项单元测试、51 项主题/发布检查和 release 签名验证通过，DevEco 上传完成并显示快速云测试通过；Mate 60 性能、Mate X5 UX 评分及平板/2in1 覆盖仍以新完整报告为准。

- **模拟器/调试**：无需配置签名。hdc 可直接安装 debug HAP；DevEco 运行 entry
  时会自动生成本地调试签名。
- **真机/正式发布**：需要华为开发者账号（AGC）签名。在 DevEco Studio 中打开
  Project Structure → Signing Configs 自动生成签名材料（.p12/.cer/.p7b），或在
  `build-profile.json5` 的 `signingConfigs` 中手动填写 material（storeFile、
  storePassword、keyAlias、keyPassword、certpath、profile、signAlg）。
  本仓库只提供 `build-profile.example.json5` 无秘密模板；复制为已忽略的
  `build-profile.json5` 后再由 DevEco 或 CI Secret 写入本机签名配置。签名材料与密码
  **绝不能提交仓库**（与全仓库的凭据不变量一致）。
- **上架**：在 AppGallery Connect 创建应用、上传签名的 APP/HAP、填写隐私声明
  （本应用隐私文案与 `PRIVACY.md` 一致）与截图。发布前复核
  `native/apple/AppStore/submission-checklist.md` 中与商店审核对应的通用条目。

## 与 iOS 实现的对应关系

每日课程摘要可以在设置中通过 24 小时时分选择器修改，界面明确标注北京时间。
`dailyCourseNotificationMinutes` 保存为 0–1439 的整数，缺省或非法旧值回退至 450（07:30）；
修改后按当前开关、账号、课表和通知权限立即重排，清除本地数据恢复默认时间。
系统日历提醒由规划请求的绝对时刻构造，异步取消和发布串行执行，避免快速改时或关闭后留下旧批次。

桌面服务卡片优先显示今日课程，再按尺寸及用户数量限制用明日课程补位：2×2、2×4 最多两行，
4×4 最多六行，数量限制约束两日合计；明日有独立日期／教学周分组，不显示今日的“进行中”状态。
设置预览复用同一份数据与容量规则。卡片请求北京时间午夜刷新，系统接口的最短刷新间隔为五分钟，
实际回调受系统刷新预算与可见性影响，另保留周期刷新；不新增网络请求。

此项功能的本地主机测试已通过 175 项（含拒绝非法改时、慢授权期间改时立即取消旧提醒、改时竞态、00:00／23:59、跨年日界、跨教学周、
今日空／满、英文分组与预览）。当前 `hdc list targets` 为空，尚未验证设备上的选择器、
三种卡片尺寸的实际渲染和通知到达，不能把编译或主机测试等同于设备验证。

| iOS (SwiftUI) | 鸿蒙 (ArkTS/ArkUI) |
| --- | --- |
| Models.swift | common/Models.ets、common/ScheduleLogic.ets |
| StrictContractDateParser / Calendar.shanghai | common/StrictDates.ets |
| AppTheme.swift | common/AppTheme.ets + resources/{base,dark}/element/color.json |
| AppModel.swift | model/AppModel.ets |
| RootView.swift（Tabs / NavigationSplitView） | view/RootView.ets（Tabs / 侧栏布局，阈值 700vp） |
| CredentialStore（Keychain） | ASSET 安全存储 |
| UserNotificationCourseScheduler | reminderAgent / 通知管理 |
| EventKitCalendarImporter | @ohos.calendarManager |
| WhereToStudyWidget（WidgetKit） | 服务卡片（FormExtensionAbility） |

## 折叠屏与电脑端适配

- **连续布局**：侧栏（>= 700vp）、空教室/设置双列（>= 760vp）、宽屏日历
  （内容区 >= 868vp，使用 macOS 的 156vp 双轴并保证七列不窄于约 97vp）按窗口宽度自动切换，折叠/展开、
  分屏、悬浮窗口缩放即时生效。
- **折叠屏**：监听 foldStatusChange；半折叠（FOLD_STATUS_HALF_FOLDED）时铰链
  横贯屏幕中部，任何宽度都强制单列紧凑布局（规则见 common/DeviceState.ets 与
  entry/src/test/AdaptivePolicy.test.ets 的纯函数用例）。
- **2in1/PC**：ability 声明 fullscreen/split/floating 窗口模式与最小窗口
  400x640（EntryAbility 另调用 setWindowLimits）；宽屏教学日历
  ExpandedTeachingCalendarView（对应 iOS TeachingCalendarView）提供桌面式
  日期导航、课表操作按钮、常展开月网格与年视图跳转面板。
- 已验证：Pura 90 手机端账号/密码输入与系统输入法、Mate X7 折叠屏展开态（侧栏+宽布局）、MateBook Pro 2in1
  （侧栏导航、双列空教室、宽屏日/周/月/年日历）、600x900 悬浮窄窗
  （标签栏+紧凑单列布局回退）、手机端输入焦点和原有 13 项界面断言均已覆盖。

## 不变量

与仓库其他平台一致：账号密码只进系统安全存储；缓存不含凭据；不嵌入 WebView；
默认不常驻高频轮询；保持空教室、教学日历、查询、设置四个一级页面的颜色、术语与状态语义一致。

手机底栏和宽屏侧栏均按“空教室 → 教学日历 → 查询 → 设置”排列；“查询”是独立一级页面。班车只显示当天 active 且通过严格校验的时刻表；重要事件与教学日历共享同一个客户端、请求合并和五分钟缓存，支持真实 categories/元数据搜索、过期切换、DDL 升序与本地收藏，明确排除作业和自定义源。

手机底栏会监听 `TYPE_NAVIGATION_INDICATOR` 与 `TYPE_SYSTEM` 避让区，并确保四个交互控件距离物理屏幕底部至少 28vp；紧凑页面的滚动末端统一预留 100vp，避免最后一项被悬浮导航覆盖。

手机月视图使用并行手势与首轴锁定区分横向翻月、详情滚动和三档开合；current/incoming 页面分别持有 Scroller 和档位，连续翻月保留显式选择的日号。当前月、上月、下月由父层独立预热，网络请求不进入分页动画。

重要事件首批只渲染 20 条，接近列表底部后自动追加 20 条；搜索、筛选和数据变化会重置本地显示窗口，但不会重新请求网络。作业、学科竞赛、会议/期刊、校内竞赛、夏令营/预推免、黑客松与自定义日程分别使用独立颜色，并贯通设置、月/年双层边框、日周全天与详情。

> 构建与运行验证：当前源码已通过 DevEco Studio 6.1.1 自带 hvigor 6.24.4 + SDK 6.1.1(24)
> 的 assembleHap/assembleApp 编译与 139 个契约单元测试；Pura 90 仿真器上的完整设备测试 12/12、手机 UI
> 冒烟测试 21/21、真实 SJD 登录/无请求体课表 POST、重复缓存写入和隔离 ASSET 测试均通过；另以获授权真实账号完成保存、课表获取、强制重启和 ASSET 再读取，测试后已清除模拟器凭据。已上传的 0.2.8 (1002021) Release APP/HAP 另已通过 SHA-256、
> 独立 HAP 签名、APP ZIP 结构、版本和三项固定 HTTPS API 校验。DevEco“上传产品”已将
> 0.2.8 (1002021) 上传 AppGallery Connect 用于测试和发布，云测试结果为“通过”。该构建修复周→月切换时日期条滞后，并在月视图最高档保持六行网格完整高度，以裁剪和平移露出选中周。HarmonyOS 安装包仅通过 AppGallery Connect 分发，不上传 GitHub Release。
> 0.2.8 邀请测试已提交并处于“预审中”；[打开邀请页面（链接已含邀请码，审核通过后生效）](https://appgallery.huawei.com/link/invite-test-wap?taskId=b4f098663ce7375007fb19b098feace9&invitationCode=A0IsJpKIcn3)，邀请码为 `A0IsJpKIcn3`。预审通过前公开页可能显示任务不存在。
