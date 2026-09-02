# Apple 商店提交清单

## 账户侧一次性配置

- 在 Apple Developer 中注册以下 Bundle ID：
  - iOS 与 macOS 主应用共用 `com.nemoyu.wheretostudy.native.macos`
  - `com.nemoyu.wheretostudy.native.macos.widget`
- 注册 `group.com.nemoyu.wheretostudy.native`，并把 iOS/macOS 主应用与两个平台的 Widget 扩展都关联到该 App Group。
- 在 App Store Connect 创建一个同时勾选 iOS 与 macOS 的 App 记录；两个平台共用主应用 Bundle ID、Apple ID 和 SKU。
- 确认付费应用协议、税务和银行信息状态满足当前发布方式。
- 确认开发者对北邮教务服务名称、接口及数据的使用具有发布所需授权。
- GPL-3.0-only 与 App Store 分发条款的兼容性由版权持有人在提交前完成法律确认；仓库不会自动更改许可证或添加额外例外。

## App Store Connect 元数据

- 应用名称：`Where To Study`
- 主分类：教育
- 隐私政策：`https://github.com/Nemoyuzx/where_to_study/blob/main/PRIVACY.md`
- 支持页面：`https://github.com/Nemoyuzx/where_to_study/issues`
- 营销页面：`https://github.com/Nemoyuzx/where_to_study`
- 加密出口合规：应用声明 `ITSAppUsesNonExemptEncryption=false`。
- App Privacy：依据实际数据流回答；当前代码不含广告、分析或跟踪 SDK，项目维护者不接收教务凭据或课程数据。提交人仍需确认 Apple 对学校服务作为第三方接收方的分类要求。
- App Review Notes：使用同目录的 `review-notes-zh-Hans.md`，并补充可联系人员与测试说明。
- 产品页文案：使用同目录的 `metadata-zh-Hans.md`。
- 隐私、年龄分级和合规问卷：按 `privacy-questionnaire-zh-Hans.md` 逐项由账号持有人确认。
- 截图：按 `screenshot-plan.md` 使用内置示例模式生成，不使用真实账号或课表。

## 构建与上传

```bash
./scripts/native-apple-app-store.sh preflight all

export APPLE_DEVELOPMENT_TEAM=XXXXXXXXXX
export APPLE_BUILD_NUMBER=76

# 本机已验证路径：iOS 使用 Xcode 管理的描述文件，必须启用 Automatic。
# 不要把名称以 "iOS Team Store Provisioning Profile" 开头的 Xcode-managed
# profile 作为 Manual profile 传入，否则归档会在签名阶段被拒绝。
APPLE_IOS_SIGNING_STYLE=Automatic \
  ./scripts/native-apple-app-store.sh upload ios

# iOS 成功后再单独上传 macOS。macOS 使用已安装的手动 App Store profile，
# 脚本会按 Team ID 自动选择 Mac Installer Distribution 证书。
export APPLE_MACOS_PROFILE_SPECIFIER="Where To Study macOS App Store"
export APPLE_WIDGET_PROFILE_SPECIFIER="Where To Study Widget App Store"
APPLE_MACOS_SIGNING_STYLE=Manual \
  ./scripts/native-apple-app-store.sh upload macos
```

`upload` 每次都会重新创建、签名、校验归档并直接上传，不会复用先前 `archive` 或 `export` 的产物；因此正式发布应按上面的 iOS → macOS 顺序各运行一次，不要预先再跑 `archive → export`。每个平台收到 `Upload succeeded` 与 `EXPORT SUCCEEDED` 后即停止，不再为确认 processing 而打开 App Store Connect。构建上传不会代替 App Store 元数据与法律声明；正式提交审核时仍需完成截图、描述、年龄分级、隐私问卷、价格与地区和构建选择。

钥匙串中有多个匹配的 Installer 身份时，可在 macOS 命令前设置 `APPLE_INSTALLER_SIGNING_CERTIFICATE`。CI 不使用本机 Xcode 登录态，需另外配置 `APPLE_AUTH_KEY_PATH`、`APPLE_AUTH_KEY_ID` 与 `APPLE_AUTH_KEY_ISSUER_ID`。

GitHub Actions 的 `Build Native Clients` 工作流也支持勾选 `publish_apple` 后上传。先创建受保护环境 `app-store-production`，再配置以下 secrets：

- `APPLE_DEVELOPMENT_TEAM`
- `APPLE_AUTH_KEY_BASE64`、`APPLE_AUTH_KEY_ID`、`APPLE_AUTH_KEY_ISSUER_ID`
- `APPLE_DISTRIBUTION_CERTIFICATE_P12_BASE64`、`APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `APPLE_INSTALLER_CERTIFICATE_P12_BASE64`、`APPLE_INSTALLER_CERTIFICATE_PASSWORD`
- `APPLE_IOS_PROFILE_BASE64`、`APPLE_IOS_WIDGET_PROFILE_BASE64`、`APPLE_MACOS_PROFILE_BASE64`、`APPLE_WIDGET_PROFILE_BASE64`

证书、私钥与描述文件只能放入受保护环境 secrets，不得提交到仓库或普通构建产物。团队 API Key 必须具备上传构建所需权限；工作流使用预先生成的描述文件，不依赖 API Key 动态创建 provisioning profile。

## 发布前验证

- `./scripts/native-apple-build.sh` 全部通过，并确认测试模拟器已关闭。
- iOS 真机检查登录、课表刷新、空教室、日历权限、通知权限、Widget App Group、深浅色和前后台切换。
- macOS 检查沙盒网络、Keychain、日历、菜单栏、关闭窗口驻留、Widget App Group 和深浅色。
- 在最终 App Store 导出包中确认主应用与 Widget 都不含 `get-task-allow`、使用 Apple Distribution 签名，且隐私清单与许可证已内嵌。iOS Automatic 的中间 archive 可以是 Development 签名，但上传前的本地 App Store export 必须通过上述检查。
- 每次上传使用递增的整数构建号；稳定版本号使用 `X.Y.Z`，不添加 `alpha.1234` 一类后缀。
- 每个完成版本必须同步 GitHub Release，并将同一份已验证源码的 iOS 与 macOS 构建上传 TestFlight；发布记录写明实际构建号和处理状态。

## 当前本机状态（2026-09-01）

- Xcode 已登录有效的 Apple Developer Program 团队，当前账户角色为 Admin。
- 主 App ID、Widget App ID、App Group 与双平台 App Store Connect 记录已创建；App Store Connect Apple ID 为 `6801054949`。
- 本机已安装有效的 Apple Development、Apple Distribution 与 Mac Installer Distribution 证书；iOS 主应用和 Widget 使用 Xcode 自动管理描述文件，macOS 主应用和 Widget 使用手动 App Store 描述文件。证书私钥和团队标识不写入仓库。
- 当前候选 iOS `0.2.8 (77)` 与 macOS `0.2.8 (77)` 已完成本地 Xcode 正式签名归档和分平台上传；两端均收到 `Upload succeeded`，iOS build 77 的本地 Apple Distribution 导出验证与脚本流程成功。
- build 77 纳入独立一级“查询”导航、班车复核兼容、重要事件增量渲染、独立日程颜色与横竖屏年视图底部净空，并通过生产 API Store/真实 App UI 测试。
- TestFlight 发布以本地 Xcode 的 `Upload succeeded` 和 `EXPORT SUCCEEDED` 为完成标准，不再额外打开 App Store Connect 检查 processing 或测试组状态。
- 13 英寸 iPad 横屏四张 0.2.2 效果图已由专项 Xcode UI 测试生成并写入 `screenshot-manifest.md`；Build 25 素材只保留作历史校验。正式提交仍需按 `screenshot-plan.md` 补齐产品页所需的 iPhone 与 macOS 最新截图。
- 尚未代替账号持有人填写或接受年龄分级、App Privacy、内容权利、欧盟 DSA、价格与地区等声明，也尚未提交 App Review。

## 正式提交前的账号持有人确认

- 确认对北邮教务服务、接口名称及返回内容的访问和展示权利；无法确认时不要提交内容权利声明。
- 确认 GPL-3.0-only 与 App Store 分发条款的法律兼容性；仓库不会自动增加许可证例外。
- 核实北邮服务对账号、密码、课程和教室请求的实际保留行为，再决定 App Privacy 是否可以回答“不收集数据”。
- 填写真实版权主体、App Review 联系人姓名/电话/邮箱，并确认支持 URL 提供用户可用的联系方式。
- 完成年龄分级、欧盟 DSA 身份、价格、税务类别、销售地区和中国大陆 ICP 状态；没有有效 ICP 时不要勾选中国大陆销售地区。
- 分别在真机和实际 Mac 上继续验证 iOS build 77 / macOS build 77 的登录、课表、空教室、综合查询、日历导入、通知、深浅色和前后台切换。
- 使用对应平台的最新构建重新生成并上传商店截图，填入本目录的中英文审核说明与简体中文元数据，最后再选择最新构建提交审核。

## Apple 官方核对入口

- [App 信息字段](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [平台版本信息与字段长度](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [截图上传说明](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots)
- [截图尺寸规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [App Privacy 数据定义](https://developer.apple.com/app-store/app-privacy-details/)
- [管理 App Privacy 回答](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [年龄分级](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating/)
- [欧盟 DSA 交易者要求](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)
- [价格设置](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price)
- [App 与提交状态](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses)
