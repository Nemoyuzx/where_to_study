# Where To Study v0.2.2

## 主要更新

- iOS 与 Android 手机月视图保留“展开 / 收起 / 日程已展开”三档位置；到达最高档后继续上滑会滚动日期详情，课程作业、黄历和统一 DDL 卡片均可完整查看。
- 设置页将“学科竞赛”与“校内竞赛通知”拆成独立开关，并明确校内通知由脚本从学校内部网站公开通知页提取整理。
- 设置页顶部新增“显示数据仅供参考，请以实际情况为准”中英双语提示。
- GitHub、Windows、Linux、macOS、iOS、Android 与 HarmonyOS 的隐私说明统一为中英双语核心内容，补充天气、黄历、公开活动、云课堂作业、系统日历、通知与小组件的数据边界。
- 修复 Android 折叠屏在侧栏收起时，导航图标相对 48dp 选中框纵向偏上的问题。
- 新增 13 英寸 iPad 横屏效果图与对应的 Xcode UI 截图回归。

## Highlights in English

- Month details on iOS and Android can now continue scrolling after the sheet reaches its highest detent, while retaining all three existing sheet states.
- Competition DDL and BUPT school competition notices now have independent settings. School notices are explicitly identified as script-extracted from public pages on the university's internal website.
- Settings now start with a bilingual reference-only notice, and privacy disclosures are aligned across GitHub and every graphical client.
- Collapsed navigation icons are vertically centered on Android foldables.
- New 13-inch iPad landscape screenshots are generated and verified with Xcode UI tests.

## 分发

- Windows：x64 NSIS 安装程序。
- Linux：x86_64 与 aarch64 Debian、AppImage、CLI 和 TUI。
- Android：维护者固定 release key 签名的 Universal APK 与 AAB，版本 `0.2.2 (29)`。
- iOS 与 macOS：正式签名的 `0.2.2 (51)` 仅通过 TestFlight 分发，不作为 GitHub Release 附件。

GitHub Release 不附带 `.sha256` 文件；发布流程仍会在上传前后使用内部校验文件验证制品。
