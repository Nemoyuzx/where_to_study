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
- 课程和空教室缓存不得包含密码、token 或完整响应头。
- 课程通知默认关闭且只读取本地课表；用户显式开启后才能调度。关闭提醒、切换账号或清除本地数据时必须先持久撤销后续调度，再清理平台 API 支持撤销的系统任务和已显示摘要。
- Tauri `load_saved_settings` 的响应不得包含密码，只能返回 `has_saved_password`；WebView 中的密码输入仅作为一次性替换值。
- 旧版普通设置中的明文凭据必须先通过同目录临时文件、所有者权限和原子替换完成脱敏，再写入系统凭据存储；后续步骤失败不得把明文写回。

## 网络

- 只向产品所需的北邮教务与节假日数据源发送请求。
- 不记录请求体、密码、token、cookie 或完整响应。
- 错误信息面向用户时不得回显凭据。
- 教务请求只使用 `jwglweixin.bupt.edu.cn` 的 HTTPS 端点；客户端不得为该数据源开放明文传输例外。
- 个人课表请求失败时必须原样返回移动教务链路的错误，不得自动切换到旧教务或其他数据源。
- 节假日数据只通过固定版本的 `unpkg.com/holiday-calendar@1.3.3/data/CN/{year}.json` HTTPS 地址按年份读取，不为其开放明文传输例外；来源说明见根目录 README，MIT 许可文本与归属记录见 `THIRD_PARTY_NOTICES.md`。

## Apple 隐私清单

- 原生 Apple 目标必须把 `native/apple/Resources/PrivacyInfo.xcprivacy` 打入应用资源。
- `UserDefaults` 只保存应用自身可见的普通偏好，对应 `CA92.1`。
- 文件元数据访问只用于应用容器内缓存的大小和状态校验，对应 `C617.1`。
- 应用不接入分析或广告 SDK，不声明跟踪域；账号、课表和教室缓存不会发送给项目维护者。

## 开源发布检查

1. `git status` 中无本地配置和签名文件。
2. tracked-file 扫描无真实凭据。
3. release 产物不包含开发日志、本地路径或未使用调试资源。
4. 生成 SHA-256 校验文件。
5. Android APK 与 AAB 的签名证书必须同时匹配 `native/android/release-certificate.sha256`。
6. 发布说明注明平台、架构、最低系统版本和签名状态。
7. 根目录包含完整 GPL-3.0-only 文本，项目元数据和发布说明使用一致的 SPDX 标识。
