# HarmonyOS cloud-test fixes / 鸿蒙云测试修复

## Report / 报告

[AGC 上架测试报告 1302805728016945540](https://developer.huawei.com/consumer/cn/service/josp/agc/cloud-testing/cn/index.html#/newTestReports/agAppStoreReport/1302805728016945540?productId=101653523864826096&ScenesType=14&source=AGC_COMPONENT) 于 2026-09-05 完成，测试版本为 0.2.8、API 24。兼容性、稳定性、功耗通过；完整上架报告因性能与 UX 问题不通过，不能用先前上传流程的快速测试结果代替本报告。

| 场景 | 报告检测值 | 标准 |
| --- | --- | --- |
| Mate 60 点击响应 | 263 ms | 250 ms |
| Mate 60 最大连续丢帧 | 9 帧 | 4 帧 |
| Mate 60 卡顿率 | 561.7 ms/s | 35 ms/s |
| Mate X5 设置页禁用“保存设置” | 1.88:1 文字对比度 | 正文 4.5:1 |
| Mate X5 侧栏日历 SymbolGlyph | 90.03–90.38（抽查两项） | 锯齿阈值 90 |

普通 Scroll 到边界缺少回弹也被警告。报告覆盖了直板机和折叠屏，未覆盖已声明支持的平板、2in1。

## Evidence and changes / 证据与修复

- 下载报告的 `OH_AppTraversal4_6_20260905_014855.perfdata` 与 `OH_AppTraversal4_7_20260905_014912.perfdata`，使用本地 DevEco `trace_streamer` 转为 SQLite 分析。两者均为月视图选日/上下展开场景；不是凭静态截图推断性能原因。
- 点击 trace 中，最长 UI 刷新为 256.024 ms，其中 `FlushDirtyNodeUpdate` 为 204.644 ms；42 个不同 ForEach 节点各被更新六次，还出现整页 key 替换和每日信息卡的销毁/重建。滑动 trace 中，手势结束的 JS 回调为 142.400 ms，动画内两次节点刷新分别为 55.475 ms、57.622 ms。这些是调用链数据，不等同于报告指标的计算方式。
- 月页 key 改为年月、年页 key 改为年份。当前月选中态和选中周直接观察 session 日期，跨月 incoming 页仍保留独立日期；每日信息卡通过 `@Param` 更新日期，仅重建依赖值参数的课程摘要。
- 各日期的课程、节假日、作业、活动和月格事件复用有界缓存，来源数据、收藏、显示开关、语言和示例模式变化时失效；拖动不再重复筛选/排序。选中周索引使用常数时间计算，不再在每个格子布局时生成 42 天数组。
- 设置禁用按钮保留原生 `enabled(false)`，通过内容定制避免系统对整块按钮再次淡化。禁用文字/表面对比度为浅色 5.54:1、深色 7.05:1。
- 仅将被报告反复标记的侧栏日历图标改为 20vp、Medium 字重并居中；普通列表和年视图恢复边界回弹。月详情 List 仍保留无回弹，以保持到顶后下拉直接交接折叠手势的既定行为。

## Validation / 验证

本地 `assembleHap`、`assembleApp`、141 项 ArkTS 单元测试、51 项主题/发布契约检查全部通过；独立 `hap-sign-tool verify-app` 验证 release 签名成功，APP 的 `pack.info` 已核对为 `0.2.8 (1002022)`。

`0.2.8 (1002022)` 已通过 DevEco“构建 → 上传产品 → 测试和发布”上传 AppGallery Connect，上传流程显示“云测试结果：通过”。已再次核对 DevEco 生成的 `pack.info` 为 versionCode 1002022、versionName 0.2.8（单独 build 字段为 1）；该快速检查不代表上述完整上架性能/UX 报告已达标。

上传产物摘要：APP SHA-256 `25464544658f8927eac39ae23c8f3186862b3c8fcf7d7a2b95afed882988cc6d`；HAP SHA-256 `e89ce189e3de0453725e41de79b4dee5f6f2f65cab470610773d4144b1eedfdd`。鸿蒙安装包只通过 AppGallery 分发，不上传 GitHub 附件。

本机 DevEco 设备管理器显示既有模拟器均缺少系统镜像，hdc 没有连接设备，因此本次未把设备视觉回归或新的性能指标报为通过。新包是否达到 Mate 60 的时延/丢帧门槛、Mate X5 的图标评分，以及平板/2in1 覆盖，仍需新的完整云测试验证。

The original full AGC report failed performance and UX checks despite passing compatibility, stability, and power tests. The fixes preserve month/year page instances, reuse bounded day-data caches, update selected-day content reactively, improve disabled-button contrast and sidebar calendar-symbol rendering, and restore boundary feedback for ordinary scroll views. The month-details gesture handoff remains unchanged. Local compilation and logic checks are distinct from device performance measurements; a new full cloud report is required to confirm the reported thresholds and tablet/2in1 coverage.
