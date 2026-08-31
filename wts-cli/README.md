# Where To Study 命令行客户端 (`where-to-study-cli`)

纯命令行版本的北邮课表、空教室与校园信息查询工具，与桌面版共享 Rust 核心逻辑。

## 功能

- `login` / `logout`：通过隐藏终端输入保存/清除 CLI 独立凭据，支持无
  Secret Service 桌面会话的 Linux 服务器
- `schedule`：显示服务返回学期内的指定日期（默认今天，上海时区）个人课程
- `week`：显示本周课程
- `classrooms`：按校区、教学楼、节次筛选查询当天空教室（实时接口不支持其他日期）
- `holidays`：显示中国法定节假日与调休（支持离线兜底数据）
- `shuttle`：显示当天班车状态和当前生效时刻表
- `events`：查询、搜索、分类筛选公开活动和校内竞赛通知，默认按 DDL 升序并隐藏
  已截止事件；支持共享本地收藏（不包含作业和自定义日程）
- 所有查询命令支持 `--json` 输出，方便脚本消费

## 构建

```bash
cd wts-cli
cargo build --release
# 产物：target/release/where-to-study-cli
```

需要 Rust 1.89+。支持 macOS 与 Linux；共享核心使用 Rustls 发起 HTTPS 请求，
CLI 不依赖正在运行的 Secret Service、GNOME Keyring 或 macOS Keychain。

### Linux 拉取与安装

从 GitHub Release 安装（以 x86_64 为例）：

```bash
mkdir -p ~/.local/bin
curl -L -o where-to-study-cli.tar.gz \
  https://github.com/Nemoyuzx/where_to_study/releases/download/v0.2.8/where-to-study-cli-linux-x86_64.tar.gz
tar -xzf where-to-study-cli.tar.gz
install -m 0755 where-to-study-cli ~/.local/bin/where-to-study-cli
where-to-study-cli --version
```

ARM64 Linux 将文件名中的 `x86_64` 改为 `aarch64`。

从源码安装时，先安装 Rust 1.89+、Git 和系统 C/C++ 构建工具：

```bash
git clone https://github.com/Nemoyuzx/where_to_study.git
cd where_to_study
cargo install --path wts-cli --locked
where-to-study-cli --version
```

更新已有安装：

```bash
cd where_to_study
git pull --ff-only
cargo install --path wts-cli --locked --force
```

默认安装到 `~/.cargo/bin/where-to-study-cli`。若命令不可用，请将
`$HOME/.cargo/bin` 加入 `PATH`。

## 使用示例

```bash
# 保存账号（账号和密码均交互输入且不回显）
where-to-study-cli login

# 查看今天的课
where-to-study-cli schedule

# 查看指定日期的课
where-to-study-cli schedule --date 2026-06-01

# 查看本周课程（JSON 输出）
where-to-study-cli week --json

# 查询西土城 教1 楼 1-4 节的空教室
where-to-study-cli classrooms --campus 01 --building 教1 --slots 1-4

# 查询沙河 3-5,7 节的所有空教室（JSON 输出）
where-to-study-cli classrooms --campus 04 --slots 3-5,7 --json

# 查看 2026 年节假日
where-to-study-cli holidays --year 2026

# 查看今天当前生效的班车时刻表
where-to-study-cli shuttle

# 搜索人工智能会议，按 DDL 升序输出 JSON
where-to-study-cli events --search 人工智能 --type conference --json

# 查看 API 返回的真实分类，并按类别筛选
where-to-study-cli events --category 人工智能

# 收藏/取消收藏（使用查询结果中稳定的 favorite_key）
where-to-study-cli events --favorite contest_ddl:conference-example
where-to-study-cli events --unfavorite contest_ddl:conference-example
where-to-study-cli events --favorites-only --include-ended

# 清除本地保存的凭据
where-to-study-cli logout
```

`login` 不带参数时会依次提示输入账号和密码，二者均不回显；同账号留空密码会保留
已保存密码。为避免凭据出现在 shell 历史、进程参数或程序日志中，不提供命令行密码
选项。`logout` 只清除 CLI 自己的凭据文件，不会改动桌面端账号。

凭据以 JSON 保存在当前用户专属的配置目录中，并通过目录 `0700`、文件 `0600`
限制为当前用户可读写。CLI 会拒绝符号链接或权限过宽的凭据文件：

- macOS：`~/Library/Application Support/Where To Study/cli-credentials.json`
- Linux：`${XDG_CONFIG_HOME:-~/.config}/where-to-study/cli-credentials.json`

该文件包含明文教务密码，不应同步、备份到公共位置或提交到版本控制。多人共用主机
应为每位用户使用独立系统账号；不再需要凭据时运行 `where-to-study-cli logout`。

## 设计

- 复用 `src-tauri/src` 的纯逻辑模块（`schedule`、`classrooms`、
  `holidays`、`auth`、`config`、`models`、`error`），与桌面版使用相同的数据源、
  解析、校验和账号缓存作用域
- CLI 凭据独立存放在用户配置目录，不依赖图形桌面密码库
- 节假日离线兜底与桌面版相同（2026 年内置数据）
- 班车和重要事件使用固定 HTTPS 接口、禁用重定向并限制响应大小；CLI 不接受用户
  指定的替代 URL。公开活动主源不可用时才使用 `where-to-study.cn` 备用接口。
- 重要事件收藏保存完整本地快照，因此远程项目下线后仍可查看。收藏文件由 CLI/TUI
  共享：`${XDG_CONFIG_HOME:-~/.config}/where-to-study/favorite-events.json`（macOS
  位于 `~/Library/Application Support/where-to-study/`）。
- 输出支持人类可读表格与 `--json` 两种格式

## 测试

```bash
cd wts-cli
cargo test
```
