# QMplus 课程接入 / QMplus course integration

QMplus 与北邮移动教务、教学云平台是三条独立的数据与登录链。课程页默认先展示教学云的当前课程目录，再展示 QMplus 中名称去空白后以 `EBU` 开头的英方当前课程及其已发布 Assignment／Quiz；教学云的中文课程目录不受这一筛选影响。成绩、考试安排和原有教学云作业 DDL 仍可在“课程”页各自查询。“查询”页只保留公开的班车和重要事件。

QMplus, BUPT Mobile Academic Services, and BUPT Teaching Cloud use separate data and sign-in flows. The Courses page shows the current Teaching Cloud directory first, then current QMplus courses whose names begin with `EBU` after trimming whitespace, with their published assignments and quizzes. This English-side filter does not change the Chinese Teaching Cloud directory. Grades, exams, and existing Teaching Cloud assignment deadlines remain available as separate Courses tabs. Query contains only public shuttle and important-event information.

## 如何连接 / Connecting

1. 在“设置 → 连接 QMplus”或课程页选择连接，应用会打开自己的[官方 QMplus 页面](https://qmplus.qmul.ac.uk/my/)。仅在该网页完成学校 SSO／Microsoft MFA；不要把 Microsoft 密码填入应用的北邮“教务账号”或“教学云密码”输入框。
2. 登录成功后自动只读同步课程；仅经验证的课程和活动进入业务快照，不包含密码、Cookie、Moodle `sesskey`、认证令牌或完整 HTML。官方网页及同源脚本在隔离 WebView 内使用自己的登录会话，不读取系统浏览器会话，也不会把北邮凭据提交给 QMplus。
3. 断开 QMplus 或清除本地数据，会撤销应用持有的 QMplus 连接并删除其业务快照；网页区清理未完成时保持锁定，HarmonyOS 可能要求重启后完成清理。这不会删除 QMplus／Microsoft 服务端的账户或学习记录。更换北邮账号、密码或学期不会自动更换独立的 QMplus 身份。

Open Connect QMplus in Settings or Courses and complete SSO/MFA in the app-owned official web view. Never enter a Microsoft password in BUPT academic or Teaching Cloud fields. A validated sign-in automatically starts read-only synchronization; only validated course/activity information enters the business snapshot, never passwords, webpage cookies, Moodle session keys, authentication tokens or full HTML. No system-browser session is imported and no BUPT credentials are submitted to QMplus. Disconnect-and-clear or clearing local data retires the connection and snapshot; the web store stays blocked until cleanup finishes, and HarmonyOS may require a restart. This does not remove records held by QMplus or Microsoft. BUPT settings do not switch the independent QMplus identity.

### 可选安全保存与自动填写 / Optional secure saving and autofill

默认关闭。在独立 QMplus 设置保存账号和密码，再明确授权本机自动填写。密码使用各平台系统安全存储，与北邮凭据分开，不进入普通设置文件。有效会话优先同步；需要登录时仅在已核验的官方 Microsoft 主文档表单提交普通 Next／Sign in 各一次。精确匹配已保存账号的已核验账户选择页可自动选择一次。验证码、MFA、未匹配的账号选择、保持登录、风险、协议或未知页面显露同一个官方窗口，必须用户处理；不会自动重试密码或绕过验证。网页改版、跨文档步骤或系统限制可能需要完整手动登录，不能保证所有分支静默完成。[辅助契约](../contracts/qmplus/AUTH.md)

Off by default. Save separate QMplus credentials and explicitly authorize local autofill in QMplus settings. Passwords use OS secure storage separate from BUPT credentials, not ordinary settings files. Valid sessions synchronize first; verified official Microsoft main-document forms may receive one ordinary Next and Sign in submission each. A verified account chooser may select an exact match for the saved account once. CAPTCHA, MFA, unmatched account choices, staying signed in, risk, terms or unknown pages reveal the same official window for user action, with no automatic password retries or verification bypass. Changed pages, cross-document steps or OS restrictions may require fully manual sign-in; silence cannot be guaranteed for every branch. [Helper contract](../contracts/qmplus/AUTH.md)

关闭“启用 QMplus”只暂停连接和同步，保留登录资料、官方网页会话与课程缓存；它不执行删除。关闭自动填写会撤销自动填写授权；Apple 的“关闭自动填写并删除 QMplus 登录信息”为组合删除操作。删除登录资料、退出并清除数据或清除本地数据，会按所选操作移除对应记录。

Turning off “Enable QMplus” only pauses connection and sync, retaining saved credentials, the official web session and the course cache. It does not delete data. Turning autofill off revokes autofill authorization; Apple’s “Disable autofill and delete QMplus sign-in details” combines this with credential deletion. Deleting credentials, disconnecting and clearing data, or clearing local data removes the corresponding records.

Apple、Android、HarmonyOS 和 Tauri 对同一已授权记录重新核验后，相同账号和密码的重复保存可保留会话。Apple 要求当前授权、安全记录 marker 和 revision 一致，并精确比较去首尾空白的账号与未改动的密码；Tauri 还要求 active profile 当前可用。不能仅凭普通设置中的账号判断相同，不能用读取失败的记录保留旧身份。更换资料仍撤销旧连接；重复保存不会取消待清理屏障。

Apple, Android, HarmonyOS and Tauri may preserve the session when saving the same account/password after revalidating the same authorized record. Apple requires current authorization, matching secure-record markers and revision, and exact equality of the trimmed account and unchanged password; Tauri also requires a currently usable active profile. A settings account name or an unreadable secure record cannot authorize preserving the old identity. Changed credentials still retire the old connection; repeated saving never cancels pending cleanup.

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
| Windows/Linux Tauri | 应用私有的专用持久 WebEngine 目录，不复用系统浏览器 Cookie / Dedicated app-private persistent WebEngine directory, no system-browser cookie reuse | 当前进程内存 / Process memory |
| macOS Tauri | macOS 14 及以上使用独立命名的持久 WebKit store；更旧系统使用 incognito / Separate named persistent WebKit store on macOS 14+; incognito on older systems | 当前进程内存 / Process memory |
| 原生 iOS/macOS / Native iOS/macOS | iOS 17／macOS 14 及以上使用应用专属、可持久的隔离 WebKit data store；更旧系统使用非持久会话 / App-specific isolated persistent WebKit store on iOS 17+/macOS 14+; nonpersistent on older supported systems | 当前进程内存 / Process memory |
| Android | 应用内独立 `:qmplus` 进程及 WebView profile，成功同步时刷新引擎 Cookie 保存；不读取外部浏览器 Cookie / Separate app-owned `:qmplus` process/profile with engine cookie flush after successful sync, no external-browser cookie access | 应用私有的有界缓存 / Bounded app-private cache |
| HarmonyOS | 应用普通 ArkWeb 持久区仅供 QMplus 使用，不是独立命名 profile / Application normal persistent ArkWeb area exclusively for QMplus, not a named profile | 当前进程内存 / Process memory |

Cookie 与网页存储由系统 WebEngine 在应用私有区管理，不导出到普通设置、业务 DTO、日志或 Where To Study 服务器。Tauri 的会话 journal 只记录随机 profile ID、后端模式及清理状态，保存在单独的 `qmplus-web-session` 目录；Windows／Linux 的引擎区位于应用本地数据目录下的 `qmplus-web-profiles/<随机 ID>`。HarmonyOS API24 没有命名 profile API，应用当前唯一的 `Web` 为 QMplus；以后其它 `Web` 必须使用 incognito，不能共享普通区。旧 Tauri／HarmonyOS incognito 会话不导出、不迁移，首次使用新持久区需重新完成官方登录。

The system WebEngine manages cookies and web storage in app-private storage, never exported into ordinary settings, business DTOs, logs or Where To Study servers. Tauri's separate `qmplus-web-session` journal contains only opaque profile IDs, backend mode and cleanup state; Windows/Linux engine stores live under the app-local `qmplus-web-profiles/<random ID>` directory. HarmonyOS API24 has no named-profile API; QMplus is currently the app's only `Web`, and future unrelated views must use incognito rather than share the normal area. Old Tauri/HarmonyOS incognito sessions are not exported or migrated; the new persistent store requires a fresh official sign-in.

Tauri／HarmonyOS 在退出、清除或更换资料前先持久记录清理意图，旧 owner 和回调随即退休。待清理状态不随普通设置清除而删除，也不会在重启后被当作已清理。Tauri Windows／Linux 的已用目录仍可能被进程内 WebContext 持有，必须真正重启，再在下一次显式连接时确认目录删除成功，才允许新 profile；macOS 命名区则须等待旧窗口销毁并确认 WebKit 删除回调成功或标识已不存在。HarmonyOS 当前进程已用过普通区时必须重启；冷启动先加载 `about:blank`，确认 Cookie 删除、网页存储用量归零及引擎保存成功后，才允许官方固定 GET。Tauri／HarmonyOS 可在持久清理屏障建立后先安全保存新登录资料，不开启新网页身份；保存成功不等于网页区已清理，用户仍须按提示完成清理。清理或状态保存失败时保持阻断，不拿旧身份尝试新连接。

Tauri/HarmonyOS persist cleanup intent before logout, clearing or credential replacement and retire the old owner/callbacks. Ordinary settings clearing preserves pending cleanup, and restart does not turn it into success. Tauri Windows/Linux directories may remain held by the process WebContext: a genuine restart and confirmed directory deletion at the next explicit connection are required before a new profile. macOS named stores wait for the old window's destruction and a successful WebKit removal callback or confirmation that the identifier is absent. A used HarmonyOS normal store requires restart; cold startup first loads `about:blank` and verifies cookie deletion, zero web-storage usage and engine save completion before the fixed official GET. Tauri/HarmonyOS may securely save new credentials after establishing the durable barrier without opening a new web identity; saving is not proof of store cleanup. Cleanup or metadata-write failure blocks the connection instead of trying the old identity.

持久区不会改变官方 Cookie 的有效期、SameSite 或 MFA 策略。HarmonyOS 的 session-only Cookie 在 PC、二合一设备和平板上也可能不跨重启保留；见 [ArkWeb Cookie 文档](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebCookieManager.md)。应用级共享存储的范围见 [ArkWeb WebStorage 文档](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebStorage.md)。不能承诺永久登录或免 MFA。

Persistent storage does not change official cookie expiry, SameSite or MFA policy. HarmonyOS session-only cookies may not survive restart on PCs, 2-in-1 devices or tablets; see the [ArkWeb cookie documentation](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebCookieManager.md). Application-wide storage scope is documented in [ArkWeb WebStorage](https://raw.githubusercontent.com/openharmony/docs/master/en/application-dev/reference/apis-arkweb/arkts-apis-webview-WebStorage.md). Permanent sign-in or exemption from MFA is not guaranteed.

会话是否跨重启保留因平台和系统版本而异，不能把“曾同步课程”视为“当前仍已登录”。所有平台均只在本机保存业务结果，不向 Where To Study 服务器上传 QMplus 课程、活动或身份信息。官方 QMplus 与 Microsoft 服务可能按照其各自政策处理你主动提交的登录信息及一般网络元数据。见[隐私声明](../PRIVACY.md)。

Session persistence varies by platform and OS version; a previous sync does not prove that the official account is still signed in. Business results remain on the device and are not uploaded to Where To Study servers. QMplus and Microsoft may process sign-in information you provide directly to them and ordinary network metadata under their own policies. See the [Privacy Policy](../PRIVACY.md).
