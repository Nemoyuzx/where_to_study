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
./scripts/native-harmony-build.sh      # assembleHap/assembleApp + 130 个契约单元测试
./scripts/native-harmony-ui-smoke.sh   # UI 冒烟测试（手机 16 项、宽屏 5 项）
```

手动命令（hvigorw 在 DevEco 安装目录下）：`hvigorw assembleHap` 与
`hvigorw test --mode module -p module=entry -p buildMode=test`。
测试源码在 `entry/src/test`（契约用例覆盖日期/节次/公历周与教学周/表单编码/URL 策略/
课表解析/空教室解析/节假日解析/天气与黄历解析、云课堂作业契约、公开 DDL、折叠策略、日历纯逻辑/通知规划与协调）与
`entry/src/ohosTest`（DevEco 内运行的 UI 冒烟套件，对应
native/apple/UITests/PrimaryNavigationSmokeTests 的导航、账号输入、示例模式与日历断言）。

## 签名与发布

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
  （>= 760vp）按窗口宽度自动切换，折叠/展开、分屏、悬浮窗口缩放即时生效。
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

> 构建与运行验证：已通过 DevEco Studio 6.1.1 自带 hvigor 6.24.4 + SDK 6.1.1(24)
> 的 assembleHap/assembleApp 编译；0.2.8 (1002016) Release APP/HAP 已通过 SHA-256、
> 独立 HAP 签名、APP ZIP 结构、版本和三项固定 HTTPS API 校验，130 个契约单元测试全部通过；手机仿真器上的一级导航与 28vp 底部净空设备测试 2/2 通过。DevEco“上传产品”已将
> 0.2.8 (1002016) 上传 AppGallery Connect 用于测试和发布，云测试结果为“通过”。HarmonyOS 安装包仅通过 AppGallery Connect 分发，不上传 GitHub Release。
> 0.2.8 邀请测试已提交并处于“预审中”；[打开邀请页面（链接已含邀请码，审核通过后生效）](https://appgallery.huawei.com/link/invite-test-wap?taskId=b4f098663ce7375007fb19b098feace9&invitationCode=A0IsJpKIcn3)，邀请码为 `A0IsJpKIcn3`。预审通过前公开页可能显示任务不存在。
