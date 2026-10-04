# QMplus 只读课程快照（0.4.0）

`qmplus-sync.js` 由各平台加载到自己的官方 QMplus 登录 WebView，随后调用 `WTSQmSync()`。业务调用仅在 `https://qmplus.qmul.ac.uk`；用户在官方网页完成 SSO／MFA，不采集微软密码。Microsoft 页面不能调用业务桥。退出时调用 `WTSQmCancel()` 并撤销 native 的请求代际。

仅白名单只读课程、模块 AJAX 及 Assignment/Quiz `view.php` GET。**不请求日历或 Timeline**；活动时间直接来自各自详情页。不会提交作业、开始 Quiz、访问答案或评分反馈。Cookie、sesskey、用户身份字段和完整 HTML 均不能返回 native。

返回：`schema_version:1, source:"qmplus", fetched_at, ok, partial, courses, activities, warnings`；失败有固定 `error_code`。最大 UTF-8 **512 KiB**，100 课程、500 活动、40 警告，每请求20秒、总120秒、串行单飞。native 必须再次校验来源、schema、字段数量、长度和官方业务 URL，不能信任网页输入。

课程：`id,name,short_name,url,start_at,end_at,current_term_status`。**仅保留完整课程名去空白后以 EBU 开头的 QMplus 课程及其所属活动**，大小写不敏感；其他课程既不显示，也不读取模块详情。状态为 `current/other/unknown`，依实际起止时间与课程学年标记判定；没有可靠学期证据时标注未知，不把历史课程强算成本学期。教学云平台课程不适用此筛选。

活动：`id,course_id,title,kind,url,due_at,opens_at,closes_at,cutoff_at,time_limit_seconds,status,detail_status,raw_time_text`。kind=`assignment/quiz`；detail_status=`available/restricted/unavailable`。日期 nullable UTC RFC3339；原网页的伦敦日期遵守夏令时，原始时间说明最多1000字符。未验证个人延期/截止不能捏造；未发布截止的活动仍展示“未公布”。Quiz 开放区间不是固定考试时段。

默认仅同步本学期课程详情，课程目录保留其它与未知条目用于明确展示。先发现完整课程模块目录，再读取活动详情。受限模块保留并标记 restricted；请求失败返回 partial，本次 partial 不覆盖已有完整快照及其原时间，首次则展示已获取部分。不能以接口失败推断已完成/已删除。账号退出或全部清除需清会话、业务缓存和晚回调，语言切换不得触发重新登录。
