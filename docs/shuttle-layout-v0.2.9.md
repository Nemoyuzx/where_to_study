# 0.2.9 班车查询布局 / Shuttle layout

Android 与 HarmonyOS 以现有 iOS `InformationQueriesView.swift` 及真实模拟器渲染为参考。
本次改动调整展示，不改变班车 API、有效时段选择、工作日筛选和缓存获取规则。

## 展示规则

- 页面标题为“信息查询 / Information Search”，一级导航仍为“查询”；班车页面由同一个外层滚动容器承载标题、分段选择、卡片和来源说明。
- 状态卡包含图标、今日运行状态、方向与计划班次数、刷新，以及分隔线下的通知标题、发布日期与原文入口。
- 方向卡显示路线、有效日期及候车地点。方向卡按最小 280 点、间距 16 点自适应分列；班次方块按最小 86 点、间距 8 点分列，大字号时减少列数。
- 时间使用系统粗体的等宽数字，不替换为整段等宽字体。下一班使用 12% 主色浅底和小圆点，并提供可读的无障碍说明。
- 来源说明保留信息与外链图标、12 点内边距、10 点圆角和 8% 主色浅底；来源与提示可以完整滚至底部导航上方。
- 候车地点和乘车提示没有为对齐外观而删除，作为方向卡／状态卡的辅助信息保留。第三方通知和班次文字保持原文，静态界面提供中英文。

Android 修复了短列表网格最后一行的空位测量：空位只占列宽，显式使用最小高度，避免撑满滚动容器、挤掉后一张卡片。列数在测量时同步调整。HarmonyOS 使用静态 Column/Row 分组，避免内外 Grid/Scroll 的滚动和高度竞争；空位不可点击且不进入无障碍树。

## 验证与限制

- Android：240 项 JVM 测试通过；手机浅色 100% 5 项、深色 130% 5 项、深色 200% 3 项、宽屏浅色 2 项、宽屏深色 130% 2 项，共 **17 项设备 instrumentation 测试**，每项检查中英文。包括默认短列表、较多班次、下一班点、刷新及栏目状态、完整滚动范围、来源说明与导航的实际几何边界。保留 20 张最终截图；截图明确标注示例数据，不能作为真实乘车安排。
- iOS：使用已编译的 iPhone 16e 应用运行现有查询 UI 测试，1/1 通过，取得真实模拟器参考截图；另参考相关代码未改变的历史中英文截图。没有重新上传同一 Apple 构建。
- HarmonyOS：最终 **198 项 Hypium 测试**、ArkTS／资源编译、HAP／APP 构建和实际 Release 模式检查通过；布局覆盖 320/390/760/1024 宽度及 1.0/1.3/2.0 字号比例。现有模拟器镜像与运行时已被清理，没有可连接设备，因此**未做鸿蒙设备视觉实测**。编译和纯布局测试不能证明所有鸿蒙设备的像素级效果或替代无障碍交互验收。

内部证据保存在忽略目录 `release-artifacts/v0.2.9-final/` 的 `android-shuttle-qa/`、`shuttle-reference-ios/` 和 `harmony-shuttle-alignment/`，不放入 README。实际上传版本、签名和后续审核状态见[发布记录](release-v0.2.9.md)。

## English

Android and HarmonyOS follow the iOS shuttle page's hierarchy: one scrolling page, a status/notice card, adaptive route cards and departure tiles, a subtle next-departure marker and a source notice. Pickup locations and rider guidance remain available; network and daily-service rules are unchanged.

Android validation includes 240 JVM tests and 17 device instrumentation cases across Chinese/English, light/dark, large text and wide layouts. HarmonyOS has 198 passing unit tests and successful Release builds, but no device visual check because this machine's emulator runtime/images are unavailable. Screenshots are explicitly marked test data, not live shuttle advice.
