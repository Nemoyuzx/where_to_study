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

## 网络

- 只向产品所需的北邮教务与节假日数据源发送请求。
- 不记录请求体、密码、token、cookie 或完整响应。
- 错误信息面向用户时不得回显凭据。
- 现有教务部分端点仍使用 HTTP；客户端必须明确限制目标 host，后续评估可用的 HTTPS 替代端点。

## 开源发布检查

1. `git status` 中无本地配置和签名文件。
2. tracked-file 扫描无真实凭据。
3. release 产物不包含开发日志、本地路径或未使用调试资源。
4. 生成 SHA-256 校验文件。
5. 发布说明注明平台、架构、最低系统版本和签名状态。
6. 许可证由仓库所有者明确选择后加入根目录。
