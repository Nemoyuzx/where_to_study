# Where To Study 可视化终端

功能丰富的终端界面（TUI）客户端，用 ratatui + crossterm 构建，复用桌面版的
Rust 核心逻辑与数据源（北邮移动教务 HTTPS 接口）。

## 功能

### 5 个标签页

| 标签页 | 功能 |
|--------|------|
| 概览 | 今天课程、教学周、节假日状态、快捷键帮助 |
| 课表 | 本周 7x14 节次时间网格，今天高亮，有课格子着色 |
| 空教室 | 校区切换、教学楼逐项多选、14 节筛选、可滚动结果列表 |
| 日历 | 月历视图；“会/事”标记会议与其它重要事件；按 `i` 进入班车/重要事件查询 |
| 设置 | 账号登录与数据状态；按 `i` 进入同一查询子视图 |

### 快捷键

| 按键 | 功能 |
|------|------|
| q | 退出（设置输入模式中作为普通字符） |
| r | 刷新当前页数据；日历页同时刷新课表与重要事件 |
| l | 用表单中的账号密码登录 |
| o | 退出登录（清除凭据） |
| Tab / 1-5 | 切换标签页 |
| 上下箭头 | 设置输入模式切换输入框 / 空教室移动教学楼光标 |
| 左右箭头 | 空教室页切换校区 / 日历页切换月份 |
| 空格 | 空教室页切换当前教学楼 / 日历页回到今天 |
| a / c | 全选 / 清空节次 |
| 1-9、0、-、=、[、] | 依次切换第 1-14 节 |
| PgUp / PgDn | 滚动空教室结果 |
| Enter / e | 设置页进入输入模式；Esc 结束输入 |
| i | 从日历或设置进入/退出查询子视图 |
| 查询页 1 / 2 / Tab | 顶部切换班车查询 / 重要事件查询 |
| 查询页 /、x | 输入/清空重要事件搜索字段 |
| 查询页 t / c / p | 依次切换事件类型 / API 真实分类 / 公开或校内来源 |
| 查询页 e / v / f | 显示已结束 / 仅看收藏 / 收藏当前事件 |

### 其他特性

- 主题：浅色/深色自动（WTS_TUI_THEME=light|dark 可强制），配色与桌面版一致
- 状态栏：当前日期、教学周、加载状态、错误/状态消息
- 凭据存储：账号与密码保存在 TUI 专用本地文件，输入不回显；不会调用系统密码库
- 数据缓存：课表/空教室/节假日内存缓存，切换页面不重复请求
- 公共查询缓存：班车与重要事件在后台独立获取并缓存 5 分钟，切换班车/事件视图
  不触发同步网络请求；`r` 可主动刷新当前查询
- 重要事件仅包含 Contest DDL 公开活动与校内竞赛通知，不读取作业或自定义日程；
  默认隐藏已结束条目并按 DDL 升序，收藏会保存完整本地快照；启动时即在后台预热，
  月历使用“会/事”标记会议与其它重要事件
- 节假日离线兜底：与桌面版相同的 2026 年内置数据

## 构建

```bash
cd wts-tui
cargo build --release
```

需要 Rust 1.89+。TUI 直接复用 Rust 核心库，不依赖图形桌面环境。

### Linux 从 Release 安装

以 x86_64 为例：

```bash
curl -L -o where-to-study-tui.tar.gz \
  https://github.com/Nemoyuzx/where_to_study/releases/download/v0.2.8/where-to-study-tui-linux-x86_64.tar.gz
tar -xzf where-to-study-tui.tar.gz
install -m 0755 where-to-study-tui ~/.local/bin/where-to-study-tui
```

ARM64 Linux 将文件名中的 `x86_64` 改为 `aarch64`。请确保 `~/.local/bin`
已加入 `PATH`。

## 使用

```bash
where-to-study-tui
```

启动后进入设置页，按 Enter 或 e 进入输入模式，输入账号密码并再次按 Enter
登录；Esc 可退出输入模式。凭据保存成功后，密码框会显示“已保存，留空保持不变”，
同一账号无需重复输入密码。随后按 r 刷新课表和空教室。错误与成功状态互斥显示，
不会同时出现“请输入密码”和“凭据已保存”。

TUI 不读取或迁移图形客户端保存在 Keychain、Credential Manager 或 Secret Service
中的凭据。默认文件位置如下，Unix 系统会把目录和文件权限分别限制为 `0700` 与
`0600`：

- macOS：`~/Library/Application Support/where-to-study/wts-tui/credentials.json`
- Linux：`${XDG_CONFIG_HOME:-~/.config}/where-to-study/wts-tui/credentials.json`
- Windows：`%LOCALAPPDATA%\where-to-study\wts-tui\credentials.json`

该文件包含明文账号和密码，不得同步、分享或提交到 Git；退出登录会删除该文件。

重要事件收藏不含账号密码，并由 CLI/TUI 共享：
`${XDG_CONFIG_HOME:-~/.config}/where-to-study/favorite-events.json`；macOS 位于
`~/Library/Application Support/where-to-study/favorite-events.json`。公共查询只连接
内置 HTTPS 数据源，禁用重定向并限制响应大小，不支持通过终端参数替换接口。

## 测试

```bash
cd wts-tui
cargo test
```
