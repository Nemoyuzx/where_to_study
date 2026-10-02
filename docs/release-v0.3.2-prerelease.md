# 0.3.2 预发布构建与上传记录

本轮包括开放依赖 PR 修复、竞赛镜像择新、个人账户密码说明与图标按钮、班车完整时刻表和法定节假日提醒。版本标签计划为 `v0.3.2-prerelease`，包内版本为 0.3.2；Android 59、Apple 100、HarmonyOS 1002036。

## 已完成的依赖合并

- [PR #66](https://github.com/Nemoyuzx/where_to_study/pull/66)：Android setup action 固定至已核对的 v4.0.4 提交。
- [PR #70](https://github.com/Nemoyuzx/where_to_study/pull/70)：兼容 npm 依赖更新。
- [PR #71](https://github.com/Nemoyuzx/where_to_study/pull/71)：Cargo 锁文件更新、许可证清单同步；将被撤回的 `yoke-derive 0.8.3` 锁回 0.8.2。本地 Rust、npm、许可证与审计通过。

## 数据源验证

2026-10-02 13:03 +0800 核对三个固定 HTTPS 公开源：GitHub 主源与原备用 API 的 `generated_at` 为 `2026-09-29T13:40:36+08:00`、566 条；新镜像为 `2026-10-02T12:35:38+08:00`、572 条。三个响应均为 Schema 1.4/Asia-Shanghai JSON，分别为 1,855,633、1,442,823、1,880,200 bytes，均低于 4 MiB。当前 CLI 的真实请求已选择镜像，桌面公开重要事件的线上测试通过。这是当时的服务端快照，不将客户端抓取时间冒充数据生成时间。

选择规则：验证后按 RFC3339 实际时间比较，镜像严格更新时采用镜像，同时间使用 GitHub；任一源失败时使用另一个有效源，两个静态源都失败才走原备用 API。合法空列表可以作为更新结果清除旧日程。公开请求不附带个人凭据，拒绝重定向，竞赛响应上限 4 MiB。

## 测试与渠道状态

代码、最终签名包与上传结果将在完成后补记。当前 GitHub Actions 作业未启动，检查注释为：`The job was not started because your account is locked due to a billing issue.` 本地验证继续进行；该状态不能作为编译或测试失败。

预发布不会替换 v0.3.1 的稳定版入口。公开资产遵循当前 11 个安装文件的结构，不上传 AAB、鸿蒙 APP/HAP、iOS 归档或校验侧文件。上传后用 GitHub API 的名称、大小和摘要与本地核对，按用户要求不回下载 Release 文件。
