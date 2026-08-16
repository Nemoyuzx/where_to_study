# 贡献指南

感谢你对 **Where To Study** 的关注！这是一个基于 Tauri 2、React 和 Rust 的跨平台空教室查询应用。无论是提交 bug、改进文档，还是开发新功能，都非常欢迎。

在开始之前，建议先阅读项目根目录的 [README.md](./README.md)，了解项目结构、开发命令和各平台的构建方式。

## 目录

- [行为准则](#行为准则)
- [许可证状态](#许可证状态)
- [我可以贡献什么](#我可以贡献什么)
- [提交 Issue](#提交-issue)
- [开发环境准备](#开发环境准备)
- [本地开发流程](#本地开发流程)
- [代码风格约定](#代码风格约定)
- [使用 AI 进行 vibe coding](#使用-ai-进行-vibe-coding)
- [提交 Pull Request](#提交-pull-request)
- [Commit 信息规范](#commit-信息规范)
- [项目结构速览](#项目结构速览)

## 行为准则

请保持友善、尊重和包容。讨论问题时对事不对人，欢迎新人提问，乐于分享知识。

## 许可证状态

项目代码按 [GNU General Public License v3.0 only](./LICENSE)（SPDX：`GPL-3.0-only`）发布。提交贡献即表示你有权提交相关代码、素材和数据，并同意该贡献按项目的 GPL-3.0-only 条款分发；第三方材料必须另外记录来源和许可证。

## 我可以贡献什么

- **报告 Bug**：发现问题就提 issue，附上复现步骤。
- **修复 Bug**：认领 issue 并提交 PR。
- **新功能**：例如完善教学楼过滤、改进日历交互、优化 UI 等。
- **文档**：完善 README、注释或本指南。
- **平台支持**：补充 Windows / Linux 桌面端打包验证，或完善 iOS 签名流程。

如果想做较大的改动，建议先开一个 issue 讨论方案，避免重复劳动。

## 提交 Issue

提交 issue 时请尽量包含：

- 运行平台和版本（macOS / Android / Windows / Linux，应用版本号）。
- 复现步骤、期望行为和实际行为。
- 相关日志、截图或错误信息。
- 如果是构建/打包问题，附上完整命令和报错输出。

> 注意：请不要在 issue、PR 或代码中提交学号、教务密码、签名证书、keystore 等敏感信息。

## 开发环境准备

基础依赖：

- [Node.js](https://nodejs.org/)（建议 LTS 版本）和 npm
- [Rust](https://www.rust-lang.org/)（通过 rustup 安装）
- Tauri 2 所需的系统依赖，详见 [Tauri 官方文档](https://tauri.app/start/prerequisites/)

按平台额外所需：

- **macOS 桌面端**：Xcode Command Line Tools。
- **Android**：Android Studio / Android SDK、Command-line Tools、NDK，以及 rustup 管理的 Android target。
- **iOS**：Xcode、CocoaPods，以及 rustup 管理的 iOS target；真机/发布构建还需 Apple 签名配置。
- **Windows**：Rust MSVC toolchain、Microsoft C++ Build Tools、WebView2 Runtime。

各平台的初始化与构建命令详见 [README.md](./README.md)。

## 本地开发流程

1. Fork 本仓库并 clone 到本地。
2. 安装依赖：

   ```bash
   npm install
   ```

3. 启动开发环境（桌面端）：

   ```bash
   npm run tauri dev
   ```

4. 验证构建可以通过：

   ```bash
   npm run tauri build
   ```

5. 如果改动涉及移动端，按需在对应平台上验证：

   ```bash
   ./scripts/native-android-build.sh
   ./scripts/native-apple-build.sh
   ```

运行前若不想在界面输入学号和教务密码，可通过环境变量配置（仅用于本地调试，切勿提交）：

```bash
export BUPT_USERNAME=你的学号
export BUPT_PASSWORD=你的教务密码
```

## 代码风格约定

- **前端（React / JS）**：组件位于 `src/`，遵循现有的命名和文件组织风格，保持函数式组件写法。
- **后端（Rust）**：源码位于 `src-tauri/src/`，提交前请运行：

  ```bash
  cargo fmt --manifest-path src-tauri/Cargo.toml --all -- --check
  cargo test --manifest-path src-tauri/Cargo.toml --lib --locked
  cargo clippy --manifest-path src-tauri/Cargo.toml --locked --all-targets -- -D warnings
  ```

  尽量消除 clippy 警告，保持模块职责清晰（如 `classrooms.rs`、`schedule.rs`、`holidays.rs` 等已有划分）。
- 保持改动聚焦：一个 PR 只解决一个问题，避免无关的格式化或重构混入。
- 不要提交本地生成的产物和敏感文件（构建输出、keystore、签名证书等，仓库已通过 `.gitignore` 忽略）。

## 使用 AI 进行 vibe coding

我们欢迎使用 AI 辅助编写的代码（vibe coding）！借助 AI 可以更快地实现功能、修复问题。但为了保证代码质量，请遵守以下约定：

- **务必人工审查**：AI 生成的功能或内容必须经过你本人的检查和测试，确保逻辑正确、符合项目风格，且没有引入安全隐患或冗余代码。你需要对自己提交的代码负责，而不是把责任推给 AI。
- **使用代码能力强的模型**：请尽量使用代码效果较好的模型进行开发，例如 ChatGPT 5.5、Claude Sonnet 4.6、Opus 4.7 等。
- **打开较高的思考等级**：在支持的模型上，尽量开启「高」或更高的思考（reasoning）等级，让模型更充分地推理，减少低级错误。
- **理解你提交的代码**：在发起 PR 前，确保你能解释清楚每一处改动的作用。无法解释的 AI 代码不应直接提交。

## 提交 Pull Request

1. 从 `main` 切出一个有意义的分支名，例如 `fix/classroom-filter` 或 `feat/shahe-building`。
2. 完成改动并在本地验证通过（构建 + 相关平台运行）。
3. 保持 commit 历史清晰，必要时 rebase 整理。
4. 推送分支并发起 PR，描述中说明：
   - 解决了什么问题 / 新增了什么功能。
   - 关联的 issue 编号（如 `Closes #12`）。
   - 在哪些平台上做了验证。
   - 如有 UI 改动，附上截图或录屏。
5. 等待 review，并根据反馈更新。

## Commit 信息规范

推荐使用简洁清晰的提交信息，建议遵循 [Conventional Commits](https://www.conventionalcommits.org/) 风格：

```
feat: 支持沙河智慧教学楼空教室查询
fix: 修复跨校区缓存覆盖问题
docs: 补充 Android 签名构建说明
refactor: 拆分日期节次计算逻辑
```

## 项目结构速览

```
src/                前端 React 应用（UI、交互）
src-tauri/src/      Rust 后端（教务认证、课表、空教室、日期节次计算、通知等）
src-tauri/gen/      各平台原生工程（android / apple）
scripts/            移动端构建与签名脚本
release-artifacts/  发布产物的校验文件
```

后端核心模块：

- `auth.rs`：教务系统认证。
- `schedule.rs` / `schedule_store.rs`：课表获取与缓存。
- `classrooms.rs` / `classrooms_store.rs`：空教室数据与缓存。
- `recommender.rs`：按日期计算课程及忙碌/空闲节次。
- `calendar_export.rs`：课程日历导出。
- `holidays.rs`：节假日处理。

---

再次感谢你的贡献！如果有任何疑问，欢迎在 issue 区交流。
