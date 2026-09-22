# 0.3.1 正式版发布记录

本轮将 [0.3.1 预发布](release-v0.3.1-prerelease.md)转为 GitHub 正式版:**无产品代码、签名配置、隐私权限或渠道行为变更**,11 个公开安装包与预发布最终测试包字节一致,仅文件名去掉 `-prerelease`。包内版本仍为 0.3.1:Android **58**、Apple **99**、HarmonyOS **1002035**。

## 标签与源码

- 发布标签 `v0.3.1` 指向本提交(即 main 顶端)。各安装包的应用源码提交均为其祖先:`602c845`(Windows/Linux/CLI/TUI CI 构建)、`e340c8f`(Apple/Harmony 热更新源码)、`f0029a7`(Android build 58);其间差异仅限 Android 班车图标热修复、CI 时限与文档,且本文确认 `602c845..v0.3.1` 对 `src/`、`src-tauri/`、`where-to-study-core/`、`wts-cli/`、`wts-tui/` 及根 `package.json`/`package-lock.json` 的 diff 为空,标签即全部安装包的完整应用源码。
- 各包的构建、测试、签名与 CI 回执沿用[预发布记录](release-v0.3.1-prerelease.md),本轮不重新构建、不重新上传 Apple/鸿蒙测试渠道。

## 资产改名与摘要

预发布 11 个资产按 `v0.3.1-prerelease → v0.3.1` 改名,字节不变;CLI/TUI 压缩包原名不含版本,直接沿用。

| 正式版资产 | 字节数 | SHA-256 |
| --- | ---: | --- |
| Where-To-Study-v0.3.1-windows-x64-setup.exe | 4,314,424 | `cd50ea50f9da716a9789ffa65ec01626cbb445541c243223c9dd6bd63c0a5e42` |
| Where-To-Study-v0.3.1-linux-x86_64.deb | 8,201,342 | `17916900df45885032fe45a6d47d9fa3b8739f47be6308350308878c63e56c55` |
| Where-To-Study-v0.3.1-linux-x86_64.AppImage | 85,883,384 | `a885e77d7ae95e1a371904f672bd68869fb911a9bbe0ee1ae473b09a41914007` |
| Where-To-Study-v0.3.1-linux-aarch64.deb | 8,324,600 | `92b53c7b383abbc4249aba44b9c0fd10a398a314990339caf2a92216227acb26` |
| Where-To-Study-v0.3.1-linux-aarch64.AppImage | 84,183,560 | `fa96b8287c7d01aaceeb8f77257d74c593ac6b1db71395c1c10bca23ed189e5a` |
| Where-To-Study-v0.3.1-native-android-universal.apk | 1,172,534 | `c38b80734df0a82b6f75f318bd37a290f30090b1c17141adffc7dc4396bab9ba` |
| Where-To-Study-v0.3.1-native-macos-universal.dmg | 7,960,292 | `9f2af2bd12c22bf5772127c41a2d7f0e88edac8827e9da61d734cb0e3ee323ca` |
| where-to-study-cli-linux-x86_64.tar.gz | 3,608,843 | `cf0f0553584da1d2678f48e478097abc1a9c55c8fb2eed52afc02625d42641ea` |
| where-to-study-cli-linux-aarch64.tar.gz | 3,377,312 | `0f428cff09751f4038269025d240d170249c5597d5ebdbac552f359985ed8499` |
| where-to-study-tui-linux-x86_64.tar.gz | 3,635,482 | `4c82be4739cc2e88135e61b1ddbf7c6366431f6352ae8939448a23125df4226e` |
| where-to-study-tui-linux-aarch64.tar.gz | 3,410,815 | `9a6ebeb17d4aed976723749da0c05e913c661716fba1ec227ff8c9ad48f2b4fe` |

上传前在本地逐一核对了 11 个文件的字节数与 SHA-256,与预发布记录中对应最终包完全一致(Android 取 build 58 居中刷新包、macOS 取 build 99 热修复 DMG,其余 9 个为首轮 CI 后未再变动的文件)。仍不公开 Android AAB、鸿蒙 APP/HAP、iOS 归档或 SHA 侧文件。

## 渠道状态

- Android 0.3.1(58)与 macOS DMG 经 GitHub 发布;iOS/macOS 0.3.1(99)在 TestFlight,鸿蒙 0.3.1(1002035)在 AppGallery 测试渠道,均未提交正式商店审核。商店可用性以各渠道页面为准。
- Windows 无公众信任 Authenticode 签名,GitHub macOS DMG 未公证,见[下载与验证说明](code-signing.md)。

## GitHub 正式版回执

2026-09-22 已公开 [Where To Study v0.3.1](https://github.com/Nemoyuzx/where_to_study/releases/tag/v0.3.1)(Release ID `393396287`):`draft=false`、`prerelease=false`,`releases/latest` 已从 v0.3.0 指向 **v0.3.1**。轻量标签 `v0.3.1` 由 `gh release create` 在 `ca33070ce4901ee04d5205d6a997c307a81f5a6b` 上创建。

恰好 11 个资产,上传后通过 GitHub API 逐一核对名称、字节数与 SHA-256 digest,与本地上售前核验值全部一致;未回下载 Release 安装包。

标签推送触发 7 条工作流(运行 ID):Windows [35676014653](https://github.com/Nemoyuzx/where_to_study/actions/runs/35676014653)、Linux [35676014733](https://github.com/Nemoyuzx/where_to_study/actions/runs/35676014733)、macOS [35676014765](https://github.com/Nemoyuzx/where_to_study/actions/runs/35676014765)、Native Clients [35676014713](https://github.com/Nemoyuzx/where_to_study/actions/runs/35676014713)、CLI [35676014744](https://github.com/Nemoyuzx/where_to_study/actions/runs/35676014744)、TUI [35676014689](https://github.com/Nemoyuzx/where_to_study/actions/runs/35676014689)、Security Checks [35676014816](https://github.com/Nemoyuzx/where_to_study/actions/runs/35676014816)。安装包字节与预发布最终包一致,正式版不依赖本轮标签 CI 产物;运行结论以 Actions 页面为准。

预发布 Release 与 `v0.3.1-prerelease` 标签按用户默认保留作测试渠道历史;预发布页不再是最新推荐下载。
