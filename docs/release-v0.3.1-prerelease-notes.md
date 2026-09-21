# Where To Study v0.3.1-prerelease

这是 **0.3.1 预发布版**，用于体验本轮查询界面优化；GitHub 最新稳定版仍为 0.3.0。本页会随同一预发布标签的测试包更新。

## 本次调整

- 安卓在查询子页之间切换时，只过渡内容区，保留标题、选项条及各子页滚动状态；后台课表更新不再刷新整个查询页。
- 安卓考试查询和课程作业页补齐控件、提示与卡片之间的间距，对齐 iOS 的分组方式。
- Android、Apple、HarmonyOS 和 Windows/Linux 的课程成绩卡片、平均绩点区域更紧凑。减少留白、合并元数据行，长名称和大字体仍可自然换行，不裁掉成绩或学分。
- 手机查询选项在空间不足时使用图标，不再横向拖动；宽屏仍显示文字，并保留完整中英文无障碍名称。
- Android 修复空成绩布局、当前学期标记、主题切换后成绩消失、浅色设置开关配色和手机查询标题尺寸。
- Android 班车查询的刷新和外链动作恢复为v0.2.9的48dp按钮、13dp内边距和22dp图形区域。
- Android 重新加载图标更换为中心对齐的 Android Material 标准矢量路径，修复旧路径视觉偏斜。
- 不改变成绩／考试／作业的获取、登录缓存、隐私和课程提醒规则。

## 下载与测试渠道

包内版本为 **0.3.1**：Android **58**，Apple **99**，HarmonyOS **1002035**。各渠道的完成状态见[构建与上传记录](https://github.com/Nemoyuzx/where_to_study/blob/main/docs/release-v0.3.1-prerelease.md)。

GitHub 提供 Windows 安装器、Linux DEB/AppImage、CLI/TUI、Android Universal APK 和原生 macOS Universal DMG。鸿蒙通过 AppGallery 测试渠道，iPhone/iPad 通过 TestFlight；不公开 Android AAB、鸿蒙包或 iOS 归档。Windows 仍无公众信任 Authenticode 签名，GitHub macOS DMG 未公证。

## English

- Android Query switches now animate only the content, keeping the heading, selector and per-section scroll positions stable. Background schedule updates no longer rebuild the whole Query page.
- Added consistent spacing between exam/assignment controls, notices and cards, following the iOS grouping.
- Made course-grade cards and the average-grade-point section more compact across graphical clients. Complete metadata, zero/text/unpublished grades, long names and larger text remain supported without fixed-height clipping.
- Compact phone query selectors now use icons instead of becoming horizontally draggable; wide layouts keep text and all accessibility labels remain available.
- Android fixes include empty-grade spacing, current-semester labels, grade retention across theme changes, light-theme switch colors, and a smaller phone query heading.
- Android shuttle refresh and external-link actions restore the exact v0.2.9 geometry: a 48 dp button, 13 dp insets, and a 22 dp icon viewport.
- Android replaces the skewed reload path with the centered standard Android Material refresh vector.
- Academic retrieval, authentication caching, privacy and reminder behavior are unchanged.

This is a pre-release. **0.3.0 remains the stable GitHub release.** Platform upload receipts are recorded separately from build completion and store availability.
