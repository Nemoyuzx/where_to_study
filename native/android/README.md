# Android 原生客户端

该目录是独立的 Kotlin + Android Framework Views 工程，不依赖 Tauri、WebView 或 Compose。迁移期使用
`com.nemoyu.wheretostudy.nativeapp` 包名，以便和现有 Tauri Android 测试包并存。

构建、单元测试和 Lint：

```bash
./scripts/native-android-build.sh
```

账号和密码由 Android Keystore 中的 AES-GCM 密钥加密后存入应用私有
`SharedPreferences`；校区等非敏感偏好直接存储。当前原生预览版已接入移动教务的只读个人课表请求，并使用 `AtomicFile` 保存本地课表。日、周、月、年视图和第 17、18 个实际教学周的“试”标记均复用 `contracts/v1` 的脱敏夹具测试。

空教室实时请求、节假日、当前时间线、通知和系统日历导入仍在后续阶段；需要这些功能时应继续使用 Tauri 客户端。

生成经过测试和签名校验的通用 APK：

```bash
./scripts/native-android-package.sh vX.Y.Z-preview.N
```

脚本从 `ANDROID_SIGNING_*` 环境变量读取签名配置；未设置时也可以复用仓库已忽略的 `src-tauri/gen/android/keystore.properties`。APK 与 SHA-256 文件会写入 `release-artifacts/`，签名文件和密码不会进入仓库或安装包目录。
