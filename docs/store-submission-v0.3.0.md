# 0.3.0 商店提交记录

2026-09-19，用户明确授权正式发布 GitHub 0.3.0，并向 vivo、华为 Android、华为 HarmonyOS、Apple iOS/macOS 提交审核。此前“仅测试”限制已被这次授权替代，但不改变账号、签名、版权主体或既有分发地区。所有 UI 操作使用已登录 Edge；鸿蒙包通过 DevEco 上传。

## 已完成

- GitHub：`Where To Study v0.3.0` 已从预发布转为稳定版，latest 为 v0.3.0，11 个附件；Windows/Linux 新包已补齐。未移动标签，未回下载 Release 资产。精确源码和摘要见[发布记录](release-v0.3.0.md)。
- vivo：App-ID `106144632`，管理入口 `838993`；版本 `0.3.0 (53)` 于 **23:00:18 +0800** 提交，页面显示“审核中”，并提示审核期间无法再次提交。保留原图文、分类、备案、联系人，沿用审核通过立即发布；没有新增测试账号或法律勾选。
- HarmonyOS 包：DevEco“测试和发布”上传 `0.3.0 (1002033)` 成功，云测试通过，AppGallery 软件包管理显示“测试和正式上架／已达标”。最终 APP/HAP 已独立保存、验签，未使用较早 CLI 字节冒充上传文件。
- Apple：此前已经成功上传 iOS／macOS `0.3.0 (97)`，本轮直接选用，没有重复归档上传。

## 已准备但尚未完成最终提交

这些表单继承了真实审核测试账号。为避免在新版本可访问成绩、考试和作业后未经确认继续向审核人员提供真实账号，已向用户询问“沿用后台已保存审核账号”或“只提供内置示例审核”。最终保存／提交等待该选择；不要将以下草稿当成审核成功回执。

| 平台 | 草稿 / 构建 | 当前准备 |
| --- | --- | --- |
| Apple iOS | 0.3.0；97 `112f0764-939f-4abb-8348-8776478aa9af` | 已新建正式版本，选择97，填写双语新增内容；页面仍有未保存修改 |
| Apple macOS | 0.3.0；97 `be547de3-7a5e-497d-9d92-8ea9c780a2e1` | 已新建正式版本，选择97，填写双语新增内容和桌面表头说明；页面仍有未保存修改 |
| 华为 HarmonyOS | `v2043113822486587712`，App-ID `6917614417184645579` | 已选1002033，填写新版特性／审核备注，并最小修正“无应用后端”为只提供公开信息；版本表单未保存／提交 |
| 华为 Android | `v2043117205209514560`，App-ID `118727859` | 53上传成功（23:11:49，1.12MB），应用信息页新增内容已保存；新增权限说明／备注已填写，版本表单未保存／提交 |

华为 Android 保留既有199个分发地区，鸿蒙保留200个及新增地区选项；继承的境外分发同意框未操作。现有分类、描述、截图和联系人未批量覆盖。Apple 当前已批准的描述仍有非官方／适用范围说明；没有用旧仓库元数据恢复或新增品牌背书。Apple旧包内部category字段仍为education，本轮没有重写商店分类或重打已成功包。

新Android权限 `SCHEDULE_EXACT_ALARM` 已说明为用户可选、本地课前提醒用途，未增加 `USE_EXACT_ALARM`；未授权时提示非精确提醒可能延迟。未声明无任何网络传输或保证准时，也未新增版权、权利授权、税务或法律承诺。

## 后续继续的界面

- Apple iOS：`https://appstoreconnect.apple.com/apps/6801054949/distribution/ios/version/inflight`，Edge tab `1440473846`。
- Apple macOS：`https://appstoreconnect.apple.com/apps/6801054949/distribution/macos/version/inflight`，Edge tab `1440473994`。
- 华为鸿蒙：`https://developer.huawei.com/consumer/cn/service/josp/agc/index.html#/myApp/6917614417184645579/v2043113822486587712`，Edge tab `1440473990`。
- 华为Android：`https://developer.huawei.com/consumer/cn/service/josp/agc/index.html#/myApp/118727859/v2043117205209514560`，Edge tab `1440473995`。
- vivo：`https://dev.vivo.com.cn/app/appService/838993`，Edge tab `1440473983`，已送审勿再次提交。

继续时先读现有页面，不盲目 reload，以免丢失尚未保存的表单。不要在公开记录中写入审核账号、密码、电话号码或邮箱字段。若遇新的法律协议或权利声明，单独确认后再处理。
