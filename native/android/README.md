# Android 原生客户端

该目录是独立的 Kotlin + Android Framework Views 工程，不依赖 Tauri、WebView 或 Compose。迁移期使用
`com.nemoyu.wheretostudy.nativeapp` 包名，以便和现有 Tauri Android 测试包并存。

构建、单元测试和 Lint：

```bash
./scripts/native-android-build.sh
```

账号和密码由 Android Keystore 中的 AES-GCM 密钥加密后存入应用私有
`SharedPreferences`；校区等非敏感偏好直接存储。当前基线包含响应式三页导航、14 个节次、教学日历视图和设置页；教务网络层将在下一迭代接入。
