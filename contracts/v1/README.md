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
- `exam_week_numbers` 是为兼容 v1 旧客户端保留的废弃字段；服务端不再推断“考试周”，该字段始终返回空数组。
- 课程地点使用“教学楼-教室号”；移动教务返回的 `3-335` 规范化为 `335`，但 `202-203`、`217-218` 这类双门教室号必须完整保留。
- 缺失座位数使用 `null`，不得用 `0` 代替未知。
- 缓存不得包含账号、密码、token 或 cookie。
- `saved_settings` 是 Tauri 设置读取响应，只用 `has_saved_password` 表示系统凭据是否存在，绝不包含密码。
- `save_settings_request.password` 是一次性输入；传 `null` 或空字符串时保留已有密码，只有非空新值才替换系统凭据。
- `course.source_course_id` 是可选的上游教学班标识（`jx0408id`），不同于包含教室、周次和时段的行 `id`；旧缓存缺失时以名称与教师识别本地整课删除。单次删除进一步限定上海日期与起止节次，整课删除限定当前学期。
- 可选 `save_settings_request.teaching_cloud_password` 单独覆盖教学云认证密码；空值保留同账号已存覆盖，新账号不得继承旧覆盖。`clear_teaching_cloud_password=true` 明确清除覆盖并恢复教务密码；读取仅返回 `has_saved_teaching_cloud_password`，不得返回秘密。它不用于教务课表或空教室请求。
- 课程删除规则独立于原始课表缓存，按本地账号作用域和学期隔离；有效课表投影用于所有消费者。删除与恢复均不得调用学校的写入接口，原子存储失败不得显示成功。
- `schedule.exam_schedule` 是可选的真实考试安排；缺失或 `null` 表示尚未获取，不改变旧版 `schedule` / `course` 的必填字段。它的 `account_key` 是各平台已有的本地账户作用域摘要，读取前必须验证账户和学期；不存明文账号或密码。
- 课程缓存中的 `courses` 保留原始普通课程；日期投影可附带 `event_kind="exam"`、`event_date`、`start_time`、`end_time`。序列化课程仍保留旧节次字段，但考试的起止时间必须使用显式时间字段，不能用占位节次推断。原生客户端内部的无节次哨兵值不属于 v1 JSON 节次索引。
- 只有同一日期且时间完整有效的考试半开区间 `[start,end)` 才隐藏重叠的单次普通课；相接不冲突，其他日期的普通课不变，考试之间不互相删除。考试不参与旧教学周上限的推断，也不受普通课程删除规则影响。
- 考试 `date` / `start_time` / `end_time` 无法确定时使用空字符串，并保留 `time_text`。无日期项目只显示待定；有日期但时间未知的项目进入当天详情/全天区域，不产生虚构时间块、忙碌节次或倒计时。`end_time="24:00"` 是可选的同日结束边界；不支持的平台保守显示时间待定，不能猜测跨日字符串。
- `exam_schedule.status` 仅为 `fresh`、`stale`、`failed`。成功空数组必须清除旧考试；失败只能复用同账户、同学期已验证的缓存并标 `stale`；没有可复用缓存时为 `failed` 且 `items=[]`。`fresh` / `stale` 保留最近成功获取时间；从未成功获取的 `failed.fetched_at` 可为空。
- `grade_report`（原生平台也称 `GradeSnapshot`）只含课程显示字段，不包含学生姓名/学号、凭据或原始响应。上游数字成绩和学分规范化为字符串，数值 `0` 必须保留为 `"0"`；`score`、`credits`、`average_grade_point` 等可选文本的缺失、`null` 或空字符串表示未公布/未指定，不推算平均绩点。`semester_name` 记录归属学期，`grade_status` 原样保留学校成绩标识，`id` 优先使用 `cj0708id` 的稳定摘要。
- 成绩只进入当前进程的有界缓存，缓存键包含教务凭据版本、学期和记录类型。修改教务密码时，即使独立教学云密码未变，也必须拒绝旧请求回写；成绩不写课表缓存、普通日志、遥测或测试截图。测试产物只能使用明确的合成成绩。
- `daily_course_notification_minutes` 为北京时间（Asia/Shanghai / UTC+8）零点后的整数分钟，范围 `0...1439`，默认 `450`（07:30）；该字段可缺省以兼容旧设置。读取旧版或损坏的时间值时回退默认，保存非法时间时拒绝请求。它是本地偏好，不随账号或课表上传，也不改变默认关闭的提醒开关。
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

## 成绩与考试模型、命令

以下 `$defs` 沿用 snake_case JSON；`grade_terms` 对应 `GradeTerms`，`grade_report` 对应 `GradeReport` / `GradeSnapshot`。Schema 顶层属性只是将各模型放在同一文件中的验证入口，实际命令返回该模型本身。

| 模型 | 内容 |
| --- | --- |
| `academic_term` / `grade_terms` | 学校返回的 `{id,name}` 学期列表与 `current_term_id`；不得根据年份虚构可选学期 |
| `grade_request` | 可选 `term_id` 与 `record_type`，不接收账号、密码或学生标识 |
| `grade_item` / `grade_report` | 成绩、学分、课程代码/属性/性质、考试性质、归属学期、成绩标识及可选平均学分绩点 |
| `exam_arrangement` / `exam_schedule` | 独立考试原始记录、账户作用域、学期、获取时间与同步状态 |
| `course` 可选投影字段 | 将有日期的考试提供给现有日历、导出、提醒和小组件消费者 |

Tauri 的只读命令为 `fetch_grade_terms()` → `grade_terms`，以及 `fetch_grades({ payload: grade_request })` → `grade_report`；现有 `fetch_schedule` 同次登录后同步 `exam_schedule`，考试失败不使成功的普通课表不可用。

`grade_request.term_id` 缺省或为 `null` 时读取学校当前学期，显式空字符串表示全部学期。`record_type` 的 `"1"`、`"0"`、`""` 分别表示最好成绩、首次成绩、全部记录；缺省或 `null` 默认 `"1"`。当前学期成功返回空成绩时应提示可以切换全部学期，不能把历史成绩当作当前学期成绩。上游失败码、缺失数组或错误结构必须作为错误处理，不能伪装成成功空列表。

CLI 对应入口为 `wts grade-terms --json`、`wts grades --term <学校学期ID> --records best --json`、`wts grades --all-terms --records all --json` 和 `wts exams --json`。最后一个命令读取/按现有策略获取课表中的考试安排，可返回 `null`（未获取）。正常界面的班车/重要事件查询不查询成绩，只有进入成绩页或主动刷新才发出成绩请求。

学校协议及字段证据见 [成绩与考试接入契约](../../docs/academic-query-contract.md)。请求直接通过已有教务客户端访问学校 HTTPS 域名，并使用教务密码；参考仓库只提供协议线索，不能接收凭据或私人数据。各平台首次隐私同意、账户切换和数据清除的既有边界同样适用于新查询。

新增样例均为本项目手写的合成数据，文件名包含 `.synthetic`，不是私人响应或真实考试时间格式的采样：

- `grade-terms.synthetic.json`：合成学期列表。
- `sjd-grades.synthetic.json` 与 `grade-report.synthetic.json`：上游字段与规范化成绩，覆盖数值零、文字成绩、未公布、归属学期和成绩标识；没有编造平均绩点。
- `sjd-exams.synthetic.json` 与 `schedule-exams.synthetic.json`：精确时间、正常教学周之外、时间待定和日期待定的考试，以及保持原始普通课程的缓存。后者账户作用域是固定文本 `synthetic-academic-fixture` 的 SHA-256 摘要，不来自真实账号。
- `course-exam.synthetic.json`：临时考试课程投影，说明显式时间不能被节次占位值替代。

`node --test test/academic-contract.test.js` 检查新增 Schema 的关键约束、旧样例兼容、敏感字段拒绝、现有 Harmony 序列化/解析消费者与共享日历时间消费者。完整 Schema 校验还需使用支持 Draft 2020-12 且启用 `format` 断言的验证器；跨字段的账户/学期匹配和实际区间重叠由运行时策略检查。

共享契约的主要验证入口如下：

```bash
cargo test --manifest-path src-tauri/Cargo.toml --lib --locked
./scripts/native-apple-build.sh
./scripts/native-android-build.sh
```

Rust 命令运行共享契约与后端单元测试；Apple 脚本运行 macOS 单元测试并构建 macOS 和 iOS 模拟器目标，但不会启动模拟器；Android 脚本运行 Debug 单元测试、Lint 和 APK 构建。

除上述尚无成功结果的 `exam_schedule.status="failed"` 空值外，所有 `fetched_at` 字段统一使用不含小数秒的 RFC 3339 格式，例如
`2026-01-05T08:00:00+08:00`。各平台写入和读取缓存时都必须执行同一约束。
