# 成绩与考试安排接入契约

## 已核验接口

协议参考：<https://github.com/Yokumii/bupt-api-collected> 的 `src/jwgl/routes.ts`。
字段与选择方式另核对学校公开前端 `https://jwglweixin.bupt.edu.cn/sjd/static/js/app.5ba0be10818f7a9e9d89.1741852738390.js`，不执行该脚本，也不通过第三方 Worker 发送凭据。

复用现有客户端登录，直接 POST `https://jwglweixin.bupt.edu.cn/bjyddx` 下的固定路径，携带原有 `token` 请求头：

- `/currentTerm`：`data[0].semesterId`；可选 `semesterName`。
- `/semesterList`：`data[]` 的 `semesterId`、`semesterName`。学校成绩页确实使用此接口，不根据当前年份虚构学期列表。
- `/student/termGPA`：query `semester=<学期ID>`、`type=1`（学校默认“最好”）；`type=0` 为首次、空字符串为全部记录。`semester` 空字符串表示所有学期；省略客户端选择表示先解析学校当前学期，不能混淆。不发送 `xs0101id`，只读取登录者自己的成绩。
- 成绩响应 `data[0].achievement[]`：`courseName`、`fraction`、`credit`、`kcbh`、`curriculumAttributes`、`courseNature`、`examinationNature`；学校页面展示的平均学分绩点为 `data[0].pjxfjd`。分数和学分接受数值或文本，包括 0，不能强制转成浮点、猜测 GPA 或把文字成绩变成 0。姓名、学号等无必要的响应字段不保留。
- `/student/examinationArrangement`：query 可带 `semester`；学校页面直接调用此接口。`data[]`：`courseName`、`examinationPlace`、`time`。学校其他模式也有 `ksqssj`、`zssj1`、`zssj2`；这些只作严格识别的辅助格式，不能假设所有学校共用结构。优先主字段，不使用第三方示例猜测的 `examAddress` 取代已核验的 `examinationPlace`。

所有响应先检查成功 code（1 或 "1"）。`data: []` 是有效空结果；缺失/错误结构、HTML、登录过期和失败码不能当作空结果。请求与响应都有现有限额/超时/同源 HTTPS 控制；错误文字不回显凭据或完整私人响应。

## 统一序列化字段

`ScheduleSnapshot/ScheduleResponse` 新增一个可选 `exam_schedule`；旧缓存缺失时为 null，不影响普通课表解码：

```json
{
  "exam_schedule": {
    "term_id": "2026-2027-1",
    "account_key": "existing-platform-account-key",
    "fetched_at": "2026-09-12T00:00:00+08:00",
    "status": "fresh",
    "message": "",
    "items": [{
      "id": "exam-stable-id",
      "name": "示例课程（非真实安排）",
      "date": "2026-12-21",
      "start_time": "09:00",
      "end_time": "11:00",
      "room": "示例考场",
      "seat": "",
      "time_text": "2026-12-21 09:00-11:00"
    }]
  }
}
```

`status` 仅为 `fresh` / `stale` / `failed`；未获取的旧缓存用 null。`account_key` 复用各平台课程删除的账户 key 规则，禁止包含原密码。考试日期或时间未能严格确定时相应字段为空字符串，保留原 `time_text` 并明确待定；无日期的项目只提示待定，不能安排到今天。ID 优先明确上游记录 ID，否则使用已规范化字段的稳定摘要，不使用随机数或数组下标。

Course 的临时投影增加可选 `event_kind`（考试为 `exam`，普通课缺失）、`event_date`、`start_time`、`end_time`，其余旧字段保留。考试 `name` 为原始名称，界面以单独“考试”标记区分；不能把机器标记拼进原始名称或恢复废弃的 `exam_week_numbers` 推断。所有精确时间排序、碰撞、绘制、导出、忙碌节次和支持的提醒/小组件需读取统一时间 helper。未定时间考试在全天/详情区域明确展示，不绘制虚构的 08:00 时间块。

普通课程原始数组不混入考试。有效日期投影顺序：应用普通课本地删除规则 → 计算当日真实考试 → 隐藏与有效考试半开区间 `[start,end)` 重叠的单次普通课 → 合并考试。首尾相接不冲突；未定时间不抑制课程；考试之间不互相删除。课程删除/恢复不能作用到考试，不用考试日期延长教学周推断。考试即使在正常教学周以外仍按真实日期展示。

课表刷新使用同次登录 token 获取课程与考试。成绩/考试使用教务密码，不使用独立教学云密码。考试失败不能使已成功的普通课表不可用；只可保留同账户 key、同学期的已验证考试并标 `stale`。成功空结果必须清除旧考试。拒绝账号切换/密码改变/清除数据后的旧异步回写；未能验证 owner 的旧考试缓存不加载。

成绩响应的跨平台模型使用 `current_term_id` / `terms[{id,name}]`，以及 `term_id` / `record_type` / `fetched_at` / `average_grade_point` / `items[{id,name,score,credits,course_code,course_attribute,course_nature,exam_nature}]`。可选标量缺失表示未公布，不造数。成绩默认只保留当前进程内的有界缓存，key 包含账号凭据版本、学期与记录类型；不写普通课表缓存/日志/截图。切换成绩学期与刷新独立于教学日历动画，支持未登录提示与跳转已有账户设置。

## 验证边界

初始字段来自公开前端与参考路由。2026-09-12 使用现有安全存储中的账号只读验证了学校登录、当前学期、学期列表、当前与全部学期成绩，以及带学期/不带学期的考试查询：当前学期成绩为空，全部学期有成绩，考试成功返回空数组。只记录成功状态和字段类型，不保留私人响应。真实成绩还有 `curSemesterName`（归属学期）、`cjbs`（成绩标识）、`cj0708id`（稳定记录标识）；分别映射到 `semester_name`、`grade_status` 和哈希 ID，额外姓名/学号字段丢弃。

由于账号目前没有非空考试记录，具体考试时间解析、重叠优先级、缓存回退与各视图采用合成样例回归，不能声称已经验证真实考场／座位及非空考试格式。样例明确为合成数据；不将私人分数、姓名、学号、token 或密码写入仓库和测试产物。各平台未知时间均安全降级为待定；Rust 还严格支持同日结束边界 `24:00`，导出为次日零点，不对跨日期字符串猜测。
