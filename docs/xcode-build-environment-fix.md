# Xcode 构建环境问题诊断与修复指引

## 问题现象

运行 `xcodebuild build` 时崩溃（SIGABRT / exit 134），日志显示：

```
DVTPlugInLoading: Failed to load code for plug-in com.apple.dt.IDESimulatorFoundation
Symbol not found: _$s12DVTDownloads17DownloadUtilitiesC16downloadedAssets9assetType15attributesQuerySayAA25DownloadableAssetProtocol_pGAA0jkG0O_SDySSypGtYaKFZ
Referenced from: /Applications/Xcode.app/Contents/Frameworks/IDESimulatorFoundation.framework
Expected in:     /Library/Developer/PrivateFrameworks/DVTDownloads.framework/Versions/A/DVTDownloads
A required plugin failed to load. Please ensure system content is up-to-date — try running 'xcodebuild -runFirstLaunch'.
```

## 根因分析

| 组件 | 版本 | 说明 |
|------|------|------|
| 操作系统 | macOS 27.0 Beta (26A5388g) | 系统运行 Beta 系统 |
| Xcode | 16.4 (16F6) | IDESimulatorFoundation 期望 DVTDownloads 23225.0.0 |
| /Library/Developer/PrivateFrameworks/DVTDownloads.framework | 16.1.0 (23060) | 由 com.apple.pkg.XcodeSystemResources 16.1.0 安装于 2024-10 |

**根本原因**：Xcode 从 16.1 升级到 16.4 后，`/Library/Developer/PrivateFrameworks` 中的系统组件
（XcodeSystemResources 包）未随 Xcode 同步更新。Xcode 16.4 的 IDESimulatorFoundation 插件
需要 DVTDownloads.framework 中新增的 `downloadedAssets` 符号（版本 23225），但系统上的
DVTDownloads 仍是旧版（23060），符号缺失导致插件加载失败，xcodebuild 在插件初始化阶段
`loadAssertingOnError` 断言崩溃。

崩溃栈关键帧：
```
-[DVTPlugIn loadAssertingOnError:error:]
-[DVTExtension _fireExtensionFaultAssertingOnBundleLoadError:error:]
_IDEInitializePlugIns
```

## 修复步骤（需要管理员权限，任选其一）

### 方法 1：重新运行 Xcode 首次启动安装（推荐先试）
```bash
sudo xcodebuild -runFirstLaunch
sudo xcodebuild -runFirstLaunch -checkForNewerComponents
```

### 方法 2：通过 App Store 更新 Xcode
打开 App Store → 更新页 → 检查 Xcode 是否有可用更新。
Xcode 更新会重新安装配套的 XcodeSystemResources 包（包含匹配版本的 DVTDownloads.framework）。

### 方法 3：重新安装 Xcode
1. 删除 /Applications/Xcode.app
2. 从 App Store 重新下载安装 Xcode 16.4
3. 首次启动 Xcode 完成组件安装

### 方法 4：手动替换 DVTDownloads.framework（仅高级用户）
从另一台安装有 Xcode 16.4 的 Mac 上复制匹配版本：
```bash
sudo rm -rf /Library/Developer/PrivateFrameworks/DVTDownloads.framework
# 复制新版本到 /Library/Developer/PrivateFrameworks/ 并修正权限
sudo chown -R root:wheel /Library/Developer/PrivateFrameworks/DVTDownloads.framework
```

## 验证修复

```bash
# 确认版本匹配
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  /Library/Developer/PrivateFrameworks/DVTDownloads.framework/Versions/A/Resources/Info.plist
# 期望输出: 23225（与 Xcode 16.4 匹配）

# 确认构建成功
cd /Users/apple/Desktop/code/whereToStudy
./scripts/native-apple-generate.sh
xcodebuild -project native/apple/WhereToStudyNative.xcodeproj \
  -scheme WhereToStudyMac -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO build
```

## 当前会话中的替代验证

由于本机无管理员权限，已使用 swiftc 完成等效验证：
- `swiftc -parse`：所有修改文件语法通过
- `swiftc -typecheck`（完整类型检查，所有源文件）：修改文件零错误；
  唯一残留错误为 AppModel.swift:199 的 MainActor 默认参数问题（原有代码，与本次修改无关）
