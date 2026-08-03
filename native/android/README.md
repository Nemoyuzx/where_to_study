# Android 原生客户端

该目录是独立的 Kotlin + Android Framework Views 工程，不依赖 Tauri、WebView 或 Compose。迁移期使用
`com.nemoyu.wheretostudy.nativeapp` 包名，以便和现有 Tauri Android 测试包并存。

构建、单元测试和 Lint：

```bash
./scripts/native-android-build.sh
```

账号和密码由 Android Keystore 中的 AES-GCM 密钥加密后存入应用私有
`SharedPreferences`；校区等非敏感偏好直接存储。当前原生预览版已接入移动教务的个人课表和当天两校区空教室请求，并使用 `AtomicFile` 分别保存本地课表和空教室缓存。课程联动、原有教学楼限制、三位教室号、双门教室号、日/周/月/年视图和第 17、18 个实际教学周的“试”标记均复用 `contracts/v1` 的脱敏夹具测试。

空教室数据仅查询当天；应用启动时会在已有凭据且当天缓存缺失时刷新一次，并通过 Android `JobScheduler` 在每天北京时间约 07:00、网络可用时自动刷新。该任务是一次性 persisted job，每次完成后安排下一天，设备重启后由系统恢复，不使用常驻轮询。教学日历支持缓存法定节假日、日/周/月/年视图、按课程数量加深的年视图色块和日/周当前时间线。节假日运行时数据通过同一上游仓库的 GitHub Raw HTTPS 地址获取，来源归属和许可证边界见根目录 README。教学日历可在用户授权后，将本地缓存课表展开到 `Asia/Shanghai` 的实际上课日期并写入主可写系统日历；应用使用稳定标识更新已有事件，重复导入不会产生重复日程。通知仍在后续阶段。

生成经过测试和签名校验的通用 APK 与 Play 发布 AAB：

```bash
./scripts/native-android-package.sh vX.Y.Z-preview.N
```

脚本从 `ANDROID_SIGNING_*` 环境变量读取签名配置；未设置时也可以复用仓库已忽略的 `src-tauri/gen/android/keystore.properties`。脚本运行 Release 单元测试与 Lint，验证 APK 签名和 ZIP 对齐，并验证 AAB 的 JAR 签名与 ZIP 完整性。APK、AAB 及各自 SHA-256 文件会写入 `release-artifacts/`，签名文件和密码不会进入仓库或安装包目录。
