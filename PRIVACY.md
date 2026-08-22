# 隐私声明 / Privacy Policy

生效日期 / Effective date: 2026-08-23

Where To Study 是用于查看北京邮电大学个人课表、空教室及相关学习信息的独立非官方客户端，不由北京邮电大学运营，也不代表学校官方立场。

Where To Study is an independent, unofficial client for viewing BUPT schedules, empty classrooms, and related study information. It is not operated by or affiliated with Beijing University of Posts and Telecommunications.

## 账户与教务请求 / Account and academic requests

你输入的学号和密码保存在操作系统的受保护凭据存储中。应用在你主动获取课表、空教室或课程作业时，才会按下述用途通过 HTTPS 使用这些凭据。课表和空教室请求会发送到 `jwglweixin.bupt.edu.cn`；保存有效凭据后，应用还可能在启动、回到前台，或平台允许的每日约 07:00 后台任务中自动刷新当天空教室。项目维护者无法读取这些凭据，设置接口也不会返回已保存的密码。

The account and password you enter are stored in the operating system's protected credential storage. The app uses them over HTTPS only when you request schedules, empty classrooms, or assignments as described below. Schedule and classroom requests are sent to `jwglweixin.bupt.edu.cn`. After valid credentials are saved, the app may also refresh the current day's classroom availability at launch, on returning to the foreground, or around 07:00 where the platform permits background work. The maintainer cannot read these credentials, and settings APIs never return a saved password.

## 本地数据 / Local data

个人课表、空教室结果、校区、学期和功能开关会缓存在设备上，以减少重复请求。受支持系统上的课程小组件只读取本地课表快照。你可以在设置中使用“清除本地数据”删除应用保存的凭据、课表、空教室和节假日缓存、偏好设置及应用管理的提醒任务。

Schedules, classroom results, campus, term, and feature preferences are cached on your device to reduce repeated requests. Course widgets on supported systems read only a local schedule snapshot. You can use “Clear local data” in Settings to remove saved credentials, schedule, classroom and holiday caches, preferences, and app-managed reminder tasks.

## 节假日数据 / Holiday data

应用可能通过 unpkg 获取固定版本 `holiday-calendar@1.3.3` 中的中国法定节假日与调休数据；Android 在已获得日历权限时也可能读取系统提供的“中国节假日”日历。远程请求仅包含 `CN` 地区和年份，不包含凭据、课表或空教室数据。iOS 不会仅因日期名称像节日就将其标记为休息日，只有权威休息日数据才显示“休”。

The app may retrieve Chinese statutory holiday and transfer-workday data from the pinned `holiday-calendar@1.3.3` dataset through unpkg. Android may also read the OS-provided “Chinese holidays” calendar when calendar permission has already been granted. Remote requests contain only the `CN` region and year, never credentials, schedules, or classroom data. On iOS, a festival-like date name alone does not mark a day as a rest day; only authoritative rest-day data does.

## 天气、黄历与公开活动 / Weather, almanac, and public events

天气功能通过 UAPI 按所选校区对应的海淀或昌平行政区获取今日、明日天气，不读取 GPS 或精确位置。黄历功能通过 UAPI 获取基础农历信息，并可能通过 Timeless API 补充“宜/忌”。Contest DDL 的 GitHub Pages 主源提供学科竞赛、夏令营和黑客松数据，主源不可用时可能访问固定的 HTTP 备用接口。校内竞赛通知由服务器脚本从学校内部网站的公开通知页提取整理，再由固定的校内通知 API 提供。天气、黄历、学科竞赛、校内竞赛通知、夏令营和黑客松均有独立开关。

Weather uses UAPI to request today and tomorrow for the Haidian or Changping administrative district associated with the selected campus; it does not read GPS or precise location. Almanac data comes from UAPI, with optional `宜`/`忌` advice from the Timeless API. Contest DDL's GitHub Pages source provides competition, summer-camp, and hackathon data, with a fixed HTTP backup when the primary source is unavailable. School competition notices are extracted and organized by a server-side script from public notice pages on the university's internal website, then exposed through the fixed school-notice API. Weather, almanac, competitions, school notices, summer camps, and hackathons each have a separate switch.

对 `http://101.201.29.29/api/contest-events` 和 `http://101.201.29.29/api/contest-notices` 的明文请求仅为发往固定主机、不接受重定向且限制响应大小的无凭据 `GET`；请求不包含 Cookie、token、课表、教室、作业或其他个人数据。卡片中的所有天气、民俗和截止日期信息均仅供参考，请以实际官方信息为准。

Plaintext requests to `http://101.201.29.29/api/contest-events` and `http://101.201.29.29/api/contest-notices` are credential-free `GET` requests to the fixed host, reject redirects, and enforce response-size limits. They contain no cookies, tokens, schedules, classrooms, assignments, or other personal data. All weather, folklore, and deadline information shown in cards is for reference only; rely on actual official information.

## 云课堂作业 / UCloud assignments

日期详情请求课程作业时，应用会从安全存储临时读取已保存的教务账号和密码，只将其通过 HTTPS 提交给 `auth.bupt.edu.cn` 完成统一认证，再用一次性票据换取仅存于内存的云课堂令牌，并从 `apiucloud.bupt.edu.cn` 读取课程与作业。应用不读取浏览器 Cookie 或 token，不向 `ucloud.bupt.edu.cn` 或 `apiucloud.bupt.edu.cn` 发送密码，也不把认证票据、Cookie、令牌或作业写入磁盘。跨日期查询结果最多在内存复用 10 分钟，并在切换账号或清除本地数据时失效。

When date details request assignments, the app temporarily reads saved credentials from protected storage and submits them only to `auth.bupt.edu.cn` over HTTPS for unified authentication. It exchanges the one-time ticket for an in-memory UCloud token and reads courses and assignments from `apiucloud.bupt.edu.cn`. The app does not read browser cookies or tokens, does not send the password to `ucloud.bupt.edu.cn` or `apiucloud.bupt.edu.cn`, and does not persist authentication tickets, cookies, tokens, or assignments. Cross-date results may be reused in memory for up to ten minutes and are invalidated when the account changes or local data is cleared.

## 系统日历、通知与小组件 / System calendar, notifications, and widgets

只有在你主动操作并授予相应系统权限后，应用才会写入系统日历或安排本地课程摘要通知。应用仅管理带有 Where To Study 标记的日历事件；课程小组件只在支持该能力的平台提供。相关数据不会上传给项目维护者。

The app writes to the system calendar or schedules local course-summary notifications only after your action and the applicable system permission. It manages only calendar events marked by Where To Study, and course widgets are available only on platforms that support them. This data is not uploaded to the maintainer.

## 不收集的数据与第三方元数据 / Data not collected and third-party metadata

本项目不运营应用后端，不包含广告、分析或行为跟踪 SDK，也不收集 GPS 位置、联系人、广告标识符、诊断或使用行为。北邮服务、unpkg、UAPI、Timeless、GitHub Pages 和固定活动 API 可能依据各自政策处理 IP 地址、请求时间等普通网络元数据。

The project operates no application backend and includes no advertising, analytics, or behavioral-tracking SDK. It does not collect GPS location, contacts, advertising identifiers, diagnostics, or usage behavior. BUPT services, unpkg, UAPI, Timeless, GitHub Pages, and the fixed event APIs may process ordinary network metadata such as IP address and request time under their own policies.

## 保留与删除 / Retention and deletion

凭据和缓存保留在你的设备上，直到被替换、在设置中清除或随卸载移除。清除本地数据不会删除北京邮电大学或其他第三方服务持有的记录。

Credentials and caches remain on your device until replaced, cleared in Settings, or removed with the app. Clearing local data does not delete records held by BUPT or other third-party services.

## 安全与联系 / Security and contact

安全报告请遵循 [SECURITY.md](SECURITY.md)。隐私问题可在 [GitHub Issues](https://github.com/Nemoyuzx/where_to_study/issues) 中提交不含敏感信息的讨论。请勿在公开内容中提供账号、密码、令牌、个人课表或其他敏感数据。重大变更会在本仓库更新生效日期。

Follow [SECURITY.md](SECURITY.md) for security reports. Privacy questions may be opened as a non-sensitive discussion in [GitHub Issues](https://github.com/Nemoyuzx/where_to_study/issues). Never include accounts, passwords, tokens, personal schedules, or other sensitive data in public content. Material changes will be published in this repository with an updated effective date.
