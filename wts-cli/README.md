# Where To Study 命令行客户端 (wts-cli)

纯命令行版本的北邮课表与空教室查询工具，与桌面版共享同一套 Rust 核心逻辑和
数据源（移动教务 HTTPS 接口）。

## 功能

- `login` / `logout`：通过隐藏终端输入保存/清除教务凭据；当前发布的 macOS
  构建与桌面端共享同一个 Keychain 条目和账号缓存作用域
- `schedule`：显示服务返回学期内的指定日期（默认今天，上海时区）个人课程
- `week`：显示本周课程
- `classrooms`：按校区、教学楼、节次筛选查询当天空教室（实时接口不支持其他日期）
- `holidays`：显示中国法定节假日与调休（支持离线兜底数据）
- 所有查询命令支持 `--json` 输出，方便脚本消费

## 构建

```bash
cd wts-cli
cargo build --release
# 产物：target/release/wts-cli
```

需要 Rust 1.89+。当前 CI 与发布产物面向 macOS，需要 Xcode Command Line
Tools 提供系统 WebKit。

## 使用示例

```bash
# 保存账号（密码交互输入，不回显）
wts-cli login 2023xxxxx

# 查看今天的课
wts-cli schedule

# 查看指定日期的课
wts-cli schedule --date 2026-06-01

# 查看本周课程（JSON 输出）
wts-cli week --json

# 查询西土城 教1 楼 1-4 节的空教室
wts-cli classrooms --campus 01 --building 教1 --slots 1-4

# 查询沙河 3-5,7 节的所有空教室（JSON 输出）
wts-cli classrooms --campus 04 --slots 3-5,7 --json

# 查看 2026 年节假日
wts-cli holidays --year 2026

# 清除本地保存的凭据
wts-cli logout
```

`login` 会提示输入密码且不回显；同账号留空会保留已保存密码。为避免密码出现在
shell 历史与进程参数中，不提供命令行密码选项。`logout` 会同时清除桌面端共享的
Keychain 凭据。

## 设计

- 复用 `src-tauri/src` 的纯逻辑模块（`schedule`、`classrooms`、
  `holidays`、`auth`、`config`、`models`、`error`、`credential_store`），
  与桌面版行为完全一致（同样的解析、校验、缓存作用域与安全处理）
- 凭据通过 `credential_store` 写入系统安全存储，不落盘明文
- 节假日离线兜底与桌面版相同（2026 年内置数据）
- 输出支持人类可读表格与 `--json` 两种格式

## 测试

```bash
cd wts-cli
cargo test
```
