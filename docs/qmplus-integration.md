# QMplus 课程接入 / QMplus course integration

QMplus 与北邮移动教务、教学云平台是三条独立的数据与登录链。课程页默认先展示教学云的当前课程目录，再展示 QMplus 中名称去空白后以 `EBU` 开头的英方当前课程及其已发布 Assignment／Quiz；教学云的中文课程目录不受这一筛选影响。成绩、考试安排和原有教学云作业 DDL 仍可在“课程”页各自查询。“查询”页只保留公开的班车和重要事件。

QMplus, BUPT Mobile Academic Services, and BUPT Teaching Cloud use separate data and sign-in flows. The Courses page shows the current Teaching Cloud directory first, then current QMplus courses whose names begin with `EBU` after trimming whitespace, with their published assignments and quizzes. This English-side filter does not change the Chinese Teaching Cloud directory. Grades, exams, and existing Teaching Cloud assignment deadlines remain available as separate Courses tabs. Query contains only public shuttle and important-event information.

## 如何连接 / Connecting

1. 在“设置 → 连接 QMplus”或课程页选择连接，应用会打开自己的[官方 QMplus 页面](https://qmplus.qmul.ac.uk/my/)。仅在该网页完成学校 SSO／Microsoft MFA；不要把 Microsoft 密码填入应用的北邮“教务账号”或“教学云密码”输入框。
2. 登录成功后，用户可在官方网页同步课程。原生业务层只取得经验证的课程与活动快照，不接收或保存 Microsoft 密码、网页 Cookie、Moodle `sesskey`、认证令牌或完整 HTML。官方网页及同源脚本仍在隔离 WebView 内使用自己的登录会话；不读取系统浏览器会话，也不会把北邮学号与密码提交给 QMplus。
3. 断开 QMplus 或清除本地数据，会撤销应用持有的 QMplus 会话并删除其业务快照；这不会删除 QMplus／Microsoft 服务端的账户或学习记录。更换北邮账号、密码或学期不会自动更换独立的 QMplus 身份。

Open Connect QMplus in Settings or Courses, then complete SSO/MFA on the official page in the app's own web view. Never enter a Microsoft password in the BUPT academic or Teaching Cloud fields. The native business layer receives only a validated course/activity snapshot, not the Microsoft password, webpage cookies, Moodle session key, authentication tokens, or full HTML. The official page and same-origin script use their own sign-in session inside the isolated web view; no system-browser session is imported and no BUPT credentials are submitted to QMplus. Disconnecting or clearing local data revokes the app-owned session and snapshot, not records held by QMplus or Microsoft. Changing BUPT account settings does not switch the independent QMplus identity.

## 读取范围与时间 / Read-only scope and dates

- 同步脚本以 [`contracts/qmplus/qmplus-sync.js`](../contracts/qmplus/qmplus-sync.js) 为唯一来源，仅对官方 `https://qmplus.qmul.ac.uk` 的已登记课程目录、当前课程模块目录、Assignment／Quiz `view.php` 详情及其同源 `/lib/ajax/service.php` 进行白名单只读请求；作业和测验时间直接来自这些已发布活动的详情。**不会请求 QMplus 日历或 Timeline**，也不会提交作业、上传附件、开始测验、读取答案／评分反馈，或调用第三方 Worker 代理。
- 课程目录最多 100 门，活动最多 500 项；业务快照上限 512 KiB。单个网页请求最多 20 秒、整次同步最多约 120 秒。客户端再次核对来源、字段、官方链接和大小，旧网页回调不能在断开连接后恢复已清除的数据。
- QMplus 仅保留名称去空白后以 `EBU` 开头的英方课程；活动必须归属这些课程，且默认只展示其中已确认当前学期的活动。课程仍被明确标为 `current`、`other` 或 `unknown`；没有可靠的学年或起止日期证据时保持“学期未确认”，不把历史课或通识课猜成本学期。旧本地快照在展示时也应用同一筛选，不能重新带入非 EBU 活动；教学云目录不受影响。
- 作业可能有截止与最终截止时间；测验可能有开放、关闭和限时。测验开放区间**不是**固定考试时段。同步结果中的结构化时间采用 RFC 3339 UTC；原网页伦敦时间遵循英国夏令时。春季缺失时间或秋季重复时间无法可靠消歧时保留原文，不虚构具体时间；未发布的截止日期也保持未知。
- 某些课程或详情受限是正常权限事实，不等于同步失败。真正的请求失败会标记部分同步：没有旧结果时展示本次已核实的部分数据；已有完整结果时平台可能保留上次成功的资料并标明它不是本次完整更新。请始终以官方课程页为准。

The shared script makes only allowlisted read-only requests to the official enrolled-course directory, current-course module directories, published Assignment/Quiz `view.php` details and the same-origin AJAX endpoint. Assignment and quiz times come directly from those activity details; **it does not request the QMplus calendar or Timeline**. It never submits assignments, uploads files, starts a quiz, reads answers/feedback, or calls a third-party Worker. Limits are 100 courses, 500 activities, a 512 KiB business snapshot, 20 seconds per request and roughly 120 seconds per sync; native clients validate the result again. Only courses whose trimmed names begin with `EBU` and their associated activities are retained; old local snapshots are filtered again before display, while the separate Teaching Cloud directory is unaffected. Courses are classified as current, other or unknown, without guessing from weak term evidence; only verified current EBU activities appear by default. Unknown due dates remain unknown. London wall-clock dates respect daylight saving; nonexistent or ambiguous times retain their original text instead of a fabricated UTC instant. Quiz open/close windows are not fixed exam appointments. Restricted pages do not by themselves mean a failed sync; genuine partial failures keep clearly labelled verified or previously successful information for reference.

## 会话和本地资料 / Sessions and local data

| 平台 / Platform | 应用内官方网页登录会话 / App-owned web session | 业务快照 / Business snapshot |
| --- | --- | --- |
| Windows/Linux Tauri | 独立 incognito 窗口；不复用系统浏览器 Cookie，关闭进程后可能需要重新登录 / Separate incognito window; no system-browser cookie reuse, sign-in may be needed after restart | 当前进程内存 / Process memory |
| iOS/macOS | iOS 17／macOS 14 及以上使用应用专属、可持久的隔离 WebKit data store；更旧系统使用非持久会话 / App-specific isolated persistent WebKit store on iOS 17+/macOS 14+; nonpersistent on older supported systems | 当前进程内存 / Process memory |
| Android | 应用内独立 `:qmplus` 进程及 WebView profile；不读取外部浏览器 Cookie / Separate app-owned `:qmplus` process and WebView profile, no external-browser cookie access | 应用私有的有界缓存 / Bounded app-private cache |
| HarmonyOS | 应用内 incognito ArkWeb，Cookie 和网页存储不写入持久文件 / App-owned incognito ArkWeb; cookies and web storage are not persisted | 当前进程内存 / Process memory |

会话是否跨重启保留因平台和系统版本而异，不能把“曾同步课程”视为“当前仍已登录”。所有平台均只在本机保存业务结果，不向 Where To Study 服务器上传 QMplus 课程、活动或身份信息。官方 QMplus 与 Microsoft 服务可能按照其各自政策处理你主动提交的登录信息及一般网络元数据。见[隐私声明](../PRIVACY.md)。

Session persistence varies by platform and OS version; a previous sync does not prove that the official account is still signed in. Business results remain on the device and are not uploaded to Where To Study servers. QMplus and Microsoft may process sign-in information you provide directly to them and ordinary network metadata under their own policies. See the [Privacy Policy](../PRIVACY.md).
