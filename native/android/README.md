# Android 原生客户端

该目录是唯一的 Android 客户端源码，使用 Kotlin + Android Framework Views，
不依赖 Tauri、WebView 或 Compose。应用包名为 `com.nemoyu.wheretostudy.nativeapp`。

构建、单元测试和 Lint：

```bash
./scripts/native-android-build.sh
```

账号和密码由 Android Keystore 中的 AES-GCM 密钥加密后存入应用私有
`SharedPreferences`；校区等非敏感偏好直接存储。当前原生预览版已接入移动教务的个人课表和当天两校区空教室请求，并使用 `AtomicFile` 分别保存本地课表和空教室缓存。课程联动、原有教学楼限制、三位教室号、双门教室号、日/周/月/年视图和第 17、18 个实际教学周的“试”标记均复用 `contracts/v1` 的脱敏夹具测试。

空教室数据仅查询当天；应用启动时会在已有凭据且当天缓存缺失时刷新一次，并通过 Android `JobScheduler` 在每天北京时间约 07:00、网络可用时自动刷新。该任务是一次性 persisted job，每次完成后安排下一天，设备重启后由系统恢复，不使用常驻轮询。教学日历支持缓存法定节假日、日/周/月/年视图、按课程数量加深的年视图色块和日/周当前时间线。节假日运行时数据通过固定版本的 unpkg HTTPS 年度 JSON 地址获取，来源归属和许可证边界见根目录 README。教学日历可在用户授权后，将本地缓存课表展开到 `Asia/Shanghai` 的实际上课日期并写入主可写系统日历；应用使用稳定标识更新已有事件，重复导入不会产生重复日程。

应用提供可调整尺寸的原生“今日课程”桌面小组件，直接读取应用私有课表缓存并展示课程时间与教室。课表刷新、账号清除、日期或时区变化以及应用更新后会立即重绘；当天没有课程或尚未获取课表时统一显示“今日无课”。

每日课程摘要默认关闭。用户在设置中显式开启并授予通知权限后，应用使用持久化 `JobScheduler` 在每天 07:30-08:00 的有效窗口内发送当天摘要；关闭提醒、权限撤销、账号切换或清除本地数据会撤销旧任务，且没有可用 Keystore 凭据时不会继续安排后台刷新。

生成经过测试和签名校验的通用 APK 与 Play 发布 AAB：

```bash
./scripts/native-android-signing-init.sh
./scripts/native-android-package.sh vX.Y.Z
```

签名初始化脚本将本地 keystore 和 `keystore.properties` 写入已忽略的 `native/android/keystore/` 与 `native/android/keystore.properties`。打包脚本优先从 `ANDROID_SIGNING_*` 环境变量读取签名配置，未设置时使用上述本地配置。脚本运行 Release 单元测试与 Lint，验证 APK 签名和 ZIP 对齐，并验证 AAB 的 JAR 签名与 ZIP 完整性。APK、AAB 及各自 SHA-256 文件会写入 `release-artifacts/`，签名文件和密码不会进入仓库或安装包目录。APK/AAB 还会携带并逐字节校验根 `LICENSE`、`THIRD_PARTY_LICENSES.html` 与 `THIRD_PARTY_NOTICES.md`。
