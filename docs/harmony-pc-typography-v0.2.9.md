# HarmonyOS 0.2.9 PC typography review / 鸿蒙 PC 字号审核修复

## Report and scope / 报告与范围

2026-09-08 用户提供的上架后审核附件 `b6e949eb794c4daba25b06ed76614e4f.zip`，报告 ID 为 `1303001060060714003`，规则为 `7.1.1.4.2`。附件 SHA-256：`9d83b4636d19b196931b69e2552b1e49655aedf7b4ebb32f5866ca56a9923eef`。原始附件、带审核标记的截图不纳入仓库。

报告的五组发现都是同一要求：PC 默认窗口和最大化窗口中的文本字号不得小于 10fp。共 620 处检测记录（包含重复场景，不是 620 个独立组件）。

| 报告组 | 场景 | 检测记录 | 原字号 |
| --- | --- | ---: | --- |
| 1 | 周视图全天 DDL 时间、标题、`+N`、课程时段 | 32 | 9fp |
| 2 | 月视图公历周与教学周标签 | 6 | 8fp |
| 3 | 周视图（带状态提示）全天区与课程时段 | 34 | 9fp |
| 4 | 年视图星期与日期 | 278 | 8/9fp |
| 5 | 年视图另一窗口状态 | 270 | 8/9fp |

## Changes / 修改

- `CalendarTypography.fontSize` 为 PC/2in1 设置 10fp 下限，保留更大字号与系统字体缩放；设备类型判断与窗口宽度无关，缩到紧凑布局后也不会退回 8/9/9.5fp。
- 覆盖宽屏全天时间/标题/数量、课程时段/课程信息、月周标签、年星期/日期；同步覆盖紧凑布局中的公历周/教学周、休班标记、月事件、年日期和时间轴。
- PC 月格的周标签改为正常纵向布局中的独立 14vp 行，不再绝对定位叠在日期上；所有日期保留相同的行高，避免周一与其它日期错位。保留事件和溢出数量显示。
- PC 紧凑日期条的休班标记行增加到 14vp；手机、折叠屏和平板原有字号与排版不变。没有改动业务数据获取、凭据、收藏或其他平台。

## Validation / 验证

- 本地 DevEco SDK API 24：`assembleHap`、144 项 ArkTS 单元测试、`assembleApp` 全部通过。
- 仓库 Node 测试 146/146 通过；新增测试执行真实字号策略，扫描三个日历组件的字号表达式及宽/紧凑、日/周分支，并回归非 PC 原字号。
- 独立 `hap-sign-tool verify-app` 分别验证 HAP 与 APP 外层包签名/摘要，确认为 release profile；APP ZIP 结构验证通过，APP/HAP 的 `pack.info` 均为 `0.2.9 (1002023)`。APP 内的模块字节码与独立签名 HAP 相同；APP 内部模块不单独作为可安装签名 HAP 使用。
- 原有 API 弃用和异常处理编译警告仍存在；未将它们描述为本次报告中的新问题。
- 设备视觉复查与华为新一轮完整审核是不同验证层级；本地测试不代表已通过新的云审核。
- 本机 DevEco 设备管理器错误地将已有镜像显示为缺失；其 `devecocli emulator image list` 确认镜像已下载，使用 `devecocli emulator start 'MateBook Pro'` 成功启动已有 PC 模拟器。`hdc` 已核对设备为 `2in1`，安装并启动了 `0.2.9 (1002023)` 的隔离示例模式。当前桌面控制工具无法连接该模拟器窗口，SDK 界面操作/截图复查仍待完成，不能把成功安装当作视觉通过。

## Upload receipt / 上传记录

用户要求先上传后，已于 **2026-09-08 16:12 +0800** 通过 DevEco Studio 的“构建 → 上传产品 → 测试和发布”完成鸿蒙 `0.2.9 (1002023)` 上传；结果页显示 **“云测试结果：通过”**。这是上传流程的快速云测试，不代表新一轮完整审核、PC 字号评分或设备视觉回归已通过。未进入 AppGallery Connect 再次提交上架审核，未修改 GitHub Release 或其他平台版本。

本次先执行“从磁盘全部重新加载”“同步和刷新项目”，再上传一次；没有重复运行本地构建/单元测试流程。DevEco 重新生成的 APP/HAP `pack.info` 均为 `0.2.9 (1002023)`，对话框单独 build 字段为 `1`。最终两份产物均再次通过独立 `hap-sign-tool verify-app` 验证。

实际上传产物保存在忽略目录 `release-artifacts/harmony-pc-typography-029/uploaded/`，不能与下方的早期 CLI 候选混用：

| 产物 | 大小（字节） | SHA-256 |
| --- | ---: | --- |
| `Where-To-Study-v0.2.9-harmonyos-signed.app` | 1,255,780 | `49b8fc9a84bdcd223885612962747fdb172fe98827f6681af33b6c2a0b1918db` |
| `Where-To-Study-v0.2.9-harmonyos-entry-signed.hap` | 1,839,587 | `b5589b2cd1d3d3ac07969c0e790b7065c97c569d81ed4228292fd16d4a2f9cdd` |

### Earlier local candidates / 早期本地候选

本地候选包与验证日志保存在忽略目录 `release-artifacts/harmony-pc-typography-029/`：

- `Where-To-Study-v0.2.9-harmonyos-signed.app`，SHA-256 `dca0e3b33ea998995f9078a4aff9f7ad9a72cb4745f28a346b30639ed9b16063`。
- `Where-To-Study-v0.2.9-harmonyos-entry-signed.hap`，SHA-256 `0a6bce1deaa6155d9bad3c2b533a5de68a29365ab4e8ef9ced3dfafd4629c2a8`。

后续上传应递增构建号，沿用 DevEco Studio 的“构建 → 上传产品 → 测试和发布”，核对实际生成包内 `pack.info`，不要使用对话框中可能固定为 `1` 的单独 build 字段判断版本。鸿蒙包不上传到 GitHub Release。

The post-publication attachment contains five groups of PC text-size findings, totaling 620 detections. The update enforces a 10fp minimum independently of window width, covers both wide and compact calendars, and gives the month week label its own layout row. Existing phone/tablet typography is preserved. HarmonyOS 0.2.9 (1002023) was uploaded through DevEco on September 8, 2026, with the upload flow reporting a passed cloud test. Both final signed artifacts were verified and retained separately from the earlier CLI candidates. No new store-review submission was made; local checks and the quick cloud test are not a replacement for full Huawei review or device visual regression.
