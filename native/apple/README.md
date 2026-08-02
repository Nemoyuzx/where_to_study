# Apple 原生客户端

该目录包含共享 SwiftUI 源码，并通过 XcodeGen 生成两个独立原生 target：

- `WhereToStudyMac`：macOS 13+
- `WhereToStudyiOS`：iOS 16+

生成工程并构建：

```bash
./scripts/native-apple-generate.sh
./scripts/native-apple-build.sh
```

账号和密码由 Apple Keychain 保存，普通偏好使用 `UserDefaults`。当前基线已包含统一导航、空教室、教学日历和设置页面，以及与共享契约一致的课程模型；联网数据服务在后续迭代接入。
