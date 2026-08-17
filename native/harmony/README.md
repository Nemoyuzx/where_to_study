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
    │   ├── net/                      # 移动教务与节假日 HTTP 客户端
    │   └── view/                     # RootView 与三个一级页面
    ├── entry/src/test/               # 本地单元测试（hypium，复用 contracts/v1 fixtures）
    └── entry/src/ohosTest/           # 设备侧测试

## 构建

1. 安装 DevEco Studio 6.1.1（含 HarmonyOS NEXT SDK，API 24）。
2. 打开 native/harmony，等待 hvigor 依赖自动安装后直接运行 entry 模块。
3. 命令行构建（安装 hvigor 后）：hvigorw assembleHap。

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

## 不变量

与仓库其他平台一致：账号密码只进系统安全存储；缓存不含凭据；不嵌入 WebView；
默认不常驻高频轮询；保持空教室、教学日历、设置三个一级页面的颜色、术语与状态语义一致。

> 构建验证：本目录已通过 DevEco Studio 6.1.1 自带 hvigor 6.24.4 + SDK 6.1.1(24)
> 的 assembleHap 编译（debug 产物 entry-default-unsigned.hap）。移植完成后还会在
> 真实设备/模拟器上执行与 native/apple/Tests 对等的单元测试与 UI 冒烟测试。
