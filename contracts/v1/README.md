# 数据契约 v1

`where-to-study.schema.json` 是原生客户端与 Windows/Tauri 客户端共享的数据边界。字段沿用现有 Rust `models.rs` 的 snake_case JSON 表示，避免平台间二次命名。

约定：

- 节次索引从 `0` 开始，用户界面标签从 `1` 开始。
- `weekday` 使用 `1...7` 表示周一到周日。
- 日期使用 `YYYY-MM-DD`，时间使用 `HH:mm`。
- `week_numbers` 是教务返回并解析后的周号。
- `exam_week_numbers` 是按课表实际存在周正序计数后的第 17、18 周对应周号。
- 缺失座位数使用 `null`，不得用 `0` 代替未知。
- 缓存不得包含账号、密码、token 或 cookie。

修改契约时必须保持向后兼容，破坏性修改需要新建版本目录。

`fixtures/` 只包含虚构、脱敏数据：`sjd-current-week.json` 和
`sjd-curriculum.json` 模拟移动教务响应，`schedule.json` 是两者规范化后的预期课表。
Rust、Swift 和 Kotlin 测试必须复用这些文件，防止不同客户端产生不同课程语义。
