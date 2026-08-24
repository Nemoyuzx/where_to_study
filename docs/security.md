# 安全与隐私基线

## 敏感数据

以下内容不得提交到 Git：

- 教务账号和密码。
- 登录 token、cookie 和抓包内容。
- Android keystore、密码及 `keystore.properties`。
- Apple `.p12`、provisioning profile、导出密码和 Team 私有配置。
- 含真实课程、姓名、教师账号或学号的测试数据与截图。

测试夹具必须使用虚构账号与脱敏课程。提交前应运行 tracked-file 凭据扫描。

## 本地存储

- Windows：账号和密码存入 Windows Credential Manager；普通偏好存入应用配置目录。
- macOS/iOS：账号和密码存入 Keychain；原生客户端普通偏好存入 `UserDefaults`，Tauri 客户端存入应用配置目录。
- Android：账号和密码使用 Android Keystore 保护后存储；原生客户端普通偏好存入 `SharedPreferences`，Tauri 客户端存入应用配置目录。
- 终端 TUI：不调用系统密码库，账号和密码存入用户配置目录下独立的 `credentials.json`；Unix 目录/文件权限必须为 `0700/0600`，保存必须使用同目录临时文件替换，退出登录必须删除文件。该文件是明文敏感数据，不得同步、分享或提交到 Git。
- 课程和空教室缓存不得包含密码、token 或完整响应头。
- 课程通知默认关闭且只读取本地课表；用户显式开启后才能调度。关闭提醒、切换账号或清除本地数据时必须先持久撤销后续调度，再清理平台 API 支持撤销的系统任务和已显示摘要。
- Tauri `load_saved_settings` 的响应不得包含密码，只能返回 `has_saved_password`；WebView 中的密码输入仅作为一次性替换值。
- 旧版普通设置中的明文凭据必须先通过同目录临时文件、所有者权限和原子替换完成脱敏，再写入系统凭据存储；后续步骤失败不得把明文写回。

## 网络

- 只向产品所需的北邮教务、节假日、天气、黄历/宜忌与公开 DDL 数据源发送请求。
- 不记录请求体、密码、token、cookie 或完整响应。
- 错误信息面向用户时不得回显凭据。
- 教务请求只使用 `jwglweixin.bupt.edu.cn` 的 HTTPS 端点；客户端不得为该数据源开放明文传输例外。
- 个人课表请求失败时必须原样返回移动教务链路的错误，不得自动切换到旧教务或其他数据源。
- 节假日数据：Apple 与 Tauri 客户端只通过固定版本的 `unpkg.com/holiday-calendar@1.3.3/data/CN/{year}.json` HTTPS 地址按年份读取权威休息日与调休上班日；Android 在已有系统日历权限时可读取设备“中国（大陆）节假日”日历，并仍用该远端数据补充调休上班日。设备日历中的普通节日不得直接判定为休息日。来源说明见根目录 README，MIT 许可文本与归属记录见 `THIRD_PARTY_NOTICES.md`。
- 天气与黄历数据：只向 `https://uapis.cn` 发送固定 HTTPS 请求；天气仅提交西土城对应海淀区或沙河对应昌平区的公开行政区划代码，基础黄历仅提交所选日期换算的时间戳与 `Asia/Shanghai` 时区。宜忌增强信息只向 `https://api.timelessq.com` 提交所选日期。响应大小受限，不得携带教务凭据、Cookie、token、课表或空教室数据；Timeless 不可用时必须保留 UAPI 基础黄历并降级显示。
- 公开 DDL：主数据只从 `https://nemoyuzx.github.io/contest-ddl/data/competitions.json` 获取并在本地按日期和类型筛选。备用活动地址固定为 `http://101.201.29.29/api/contest-events`，校内竞赛通知地址固定为同主机的 `/api/contest-notices`；明文例外必须固定到该 IP 与默认 80 端口，只能发送不含任何凭据、Cookie、token、课表、教室或作业数据的 `GET`，必须拒绝重定向并限制响应体。校内通知的详情链接只接受 HTTPS。不得因此对教务请求或其他主机开放全局明文传输。
- 自定义日程：只允许用户填写公开 HTTPS JSON 地址，拒绝 URL 用户信息、片段、`localhost`、回环/链路本地/私网/保留 IP 字面量和所有重定向；不得附带凭据、Cookie、token 或其他应用数据。响应体上限 2 MiB、条目上限 5000、单次范围上限 370 天、成功缓存 5 分钟，并在客户端限频。条目原文链接同样只接受 HTTPS。完整契约见 [`custom-schedule-api.md`](custom-schedule-api.md)。
- 收藏日程：仅保存通过验证的完整事件快照到应用本地数据，最多 500 条，不上传、不跨设备同步；关闭来源、请求失败或上游移除条目不删除收藏。取消收藏或清除本地数据时删除对应快照。
- 云课堂作业：客户端只从系统安全存储临时加载已保存凭据，并且只允许将账号密码通过 HTTPS 提交给固定主机 `auth.bupt.edu.cn`；统一认证返回的跳转必须固定为 `https://ucloud.bupt.edu.cn`，令牌与课程/作业接口必须固定为 `https://apiucloud.bupt.edu.cn`。禁止重定向到其他主机，禁止读取或复用浏览器 Cookie/token，禁止把票据、Cookie、访问令牌写入磁盘或日志。解析器只接受已授权响应中的 `records` 或 `undoneList` 契约，限制响应体、课程数和作业数；内存缓存最长 10 分钟且必须在账号切换或清除本地数据时失效。测试夹具必须使用虚构课程与作业。

## Apple 隐私清单

- 原生 Apple 目标必须把 `native/apple/Resources/PrivacyInfo.xcprivacy` 打入应用资源。
- `UserDefaults` 只保存应用自身可见的普通偏好，对应 `CA92.1`。
- 应用不接入分析或广告 SDK，不声明跟踪域；账号、课表和教室缓存不会发送给项目维护者。

## 开源发布检查

1. `git status` 中无本地配置和签名文件。
2. tracked-file 扫描无真实凭据。
3. release 产物不包含开发日志、本地路径或未使用调试资源。
4. 生成 SHA-256 校验文件。
5. Android APK 与 AAB 的签名证书必须同时匹配 `native/android/release-certificate.sha256`。
6. 发布说明注明平台、架构、最低系统版本和签名状态。
7. 根目录包含完整 GPL-3.0-only 文本，项目元数据和发布说明使用一致的 SPDX 标识。
