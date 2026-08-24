# 数据契约 v1

`where-to-study.schema.json` 是原生客户端与 Windows/Tauri 客户端共享的数据边界。字段沿用现有 Rust `models.rs` 的 snake_case JSON 表示，避免平台间二次命名。

`custom-deadline-feed.schema.json` 定义用户可配置的自定义日程源。它复用现有 DDL 字段，
由客户端把来源标记为 `custom`，并按 `primary_deadline` 的日期进入教学日历全天区；网络与
收藏语义见 [自定义日程接口规范](../../docs/custom-schedule-api.md)。

约定：

- 节次索引从 `0` 开始，用户界面标签从 `1` 开始。
- `weekday` 使用 `1...7` 表示周一到周日。
- 日期使用 `YYYY-MM-DD`，时间使用 `HH:mm`；设置读写中的学期号和开学日期允许以空字符串表示“没有持久化默认值”。
- `week_numbers` 是教务返回并解析后的周号。
- `exam_week_numbers` 是按课表实际存在周正序计数后的第 17、18 周对应周号。
- 课程地点使用“教学楼-教室号”；移动教务返回的 `3-335` 规范化为 `335`，但 `202-203`、`217-218` 这类双门教室号必须完整保留。
- 缺失座位数使用 `null`，不得用 `0` 代替未知。
- 缓存不得包含账号、密码、token 或 cookie。
- `saved_settings` 是 Tauri 设置读取响应，只用 `has_saved_password` 表示系统凭据是否存在，绝不包含密码。
- `save_settings_request.password` 是一次性输入；传 `null` 或空字符串时保留已有密码，只有非空新值才替换系统凭据。
- `saved_settings` 与 `save_settings_request` 的 `term_id`、`term_start_date` 可以同时为空；自动模式请求课表时临时按上海日期推断，手动模式保存或请求时必须提供完整值。成功的 `schedule` 响应仍必须包含非空学期号和有效开学日期。

修改契约时必须保持向后兼容，破坏性修改需要新建版本目录。

`fixtures/` 只包含虚构、脱敏数据：`sjd-current-week.json`、
`sjd-before-first-week.json` 和
`sjd-curriculum.json` 模拟移动教务课表响应，`schedule.json` 是规范化后的预期课表；
`sjd-classrooms-xitucheng.json`、`sjd-classrooms-shahe.json` 模拟当天空教室响应，
`classrooms.json` 是合并两校区后的预期缓存；`holiday-source.json` 模拟节假日数据源响应，
`holidays.json` 是规范化后的预期节假日缓存；`custom-deadline-feed.json` 是自定义日程
接口的虚构示例。Rust、Swift、Kotlin 与 ArkTS 测试必须复用这些
文件，防止不同客户端产生不同课程、教学楼、教室号、节次和节假日语义。
两个节假日 fixture 均为本项目编写的虚构测试数据，不是运行时上游数据的副本。运行时来源、
HTTPS Raw 地址及其许可证状态说明见根目录 [README](../../README.md#数据来源与数据安全)。

共享契约的主要验证入口如下：

```bash
cargo test --manifest-path src-tauri/Cargo.toml --lib --locked
./scripts/native-apple-build.sh
./scripts/native-android-build.sh
```

Rust 命令运行共享契约与后端单元测试；Apple 脚本运行 macOS 单元测试并构建 macOS 和 iOS 模拟器目标，但不会启动模拟器；Android 脚本运行 Debug 单元测试、Lint 和 APK 构建。

所有 `fetched_at` 字段统一使用不含小数秒的 RFC 3339 格式，例如
`2026-01-05T08:00:00+08:00`。各平台写入和读取缓存时都必须执行同一约束。
