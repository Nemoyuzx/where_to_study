# App Store 0.2.2 Build 52 截图清单

来源版本：`0.2.2 (52)`。以下效果图由本地 Xcode 在 iPad Pro 13-inch 模拟器中运行审核示例模式并通过专项 UI 测试后生成，均为横屏 `2752 × 2064`、无 Alpha；仓库副本位于 `docs/screenshots/ipad-13-landscape/`。

| 平台 | 文件 | 像素尺寸 | Alpha | SHA-256 |
| --- | --- | --- | --- | --- |
| iPad 13-inch | `planner-weather.png` | `2752 × 2064` | 无 | `39217caf75fe09f0c4d266539b537a40e74119026f321ca3ab065fd2c5e14bc4` |
| iPad 13-inch | `teaching-calendar.png` | `2752 × 2064` | 无 | `011b4d847342404ae86c910a7bd3d44f0b598bb8aebfcbfab26c7e5c664ffc63` |
| iPad 13-inch | `settings.png` | `2752 × 2064` | 无 | `3c247101c561721d58454e7ce9b89575d42b11dabfbd14793821865f397777a7` |
| iPad 13-inch | `privacy.png` | `2752 × 2064` | 无 | `924bc7cd0572cdaa441359d384b4b162d5c75d4d37b49bb398275eb005c2aef8` |

## 0.2.2 验证记录

- 专项测试：`PrimaryNavigationSmokeTests.testStoreIPad13LandscapeScreenshots`，结果为 1/1 通过。
- 已逐张检查方向、尺寸、天气折叠卡片、月历日期详情、竞赛开关拆分、双语参考提示和双语隐私声明。
- 截图只包含内置审核示例数据，不包含真实账号、密码、课程或其他个人信息。

## 历史 App Store Build 25 截图清单（已停用）

来源版本：`0.1.3 (25)`。本清单只追踪历史截图规格和完整性校验值；PNG 文件保存在被 Git 忽略的本地目录 `release-artifacts/app-store/0.1.3-25/screenshots/final/`。这些截图不得用于当前 iOS `0.2.2 (55)` 或 macOS `0.2.2 (52)` 提交；当前可用素材以本页顶部的 0.2.2 清单为准。

| 平台 | 文件 | 像素尺寸 | Alpha | SHA-256 |
| --- | --- | --- | --- | --- |
| iPhone | `iphone/01-planner.png` | `1320 × 2868` | 无 | `46e423faf2f5775a7ac226960026c700816b77ad71793d365dabc0dd1039a934` |
| iPhone | `iphone/02-calendar-week.png` | `1320 × 2868` | 无 | `e20629cfda8dd3a1358a7d2d308e555451be7d9fddb64ed59eec4a896fd7864e` |
| iPhone | `iphone/03-settings.png` | `1320 × 2868` | 无 | `0ee58fea87b1d42e1b8a8fa4d61d0591353076a96bcda6f9459449ee85eb91cb` |
| iPad | `ipad/01-planner-landscape.png` | `2752 × 2064` | 无 | `cfaac96c93361503afb198ee7d4afd1998bf2c1723c5a893ce1376e38fda32f3` |
| iPad | `ipad/02-calendar-landscape.png` | `2752 × 2064` | 无 | `cd585a27121a5b638aa8058b9b655462d623dd9470c366a969e1d748751332ad` |
| iPad | `ipad/03-settings-portrait.png` | `2064 × 2752` | 无 | `730ee4ffabb7a8cdf7e22b44568a5a2c3dc24cc30bded7c9fecf836ce5b20fbe` |
| macOS | `macos/01-planner.png` | `1440 × 900` | 无 | `1752332ca143aaf5f7498698583e2392b4772e64ddaabdec178a72640295aeb7` |

## 验证记录

- iPhone 三张截图来自 iPhone 17 Pro Max 上通过的 `PrimaryNavigationSmokeTests.testReviewDemoShowsLocalDataWithoutAccount`；首次受系统通知遮挡的输出未纳入本清单。
- iPad 素材来自 iPad Pro 13-inch 专项 UI 验证；macOS 素材来自 Build 25 审核示例运行。
- 全部文件使用 `sips` 验证尺寸和 `hasAlpha: no`，并逐张检查标题、课程时间、14 个节次、导航和示例数据无敏感信息及无系统通知遮挡。
