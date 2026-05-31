# Where To Study

一个基于 Tauri 2、React 和 Rust 的 macOS 空教室查询桌面端。功能对齐本地 `agenda_with_empty_classroom` 网站：

- 获取北邮个人课表并解析 XLS 课表文件。
- 查询当天空教室，优先使用微信教务实时接口，失败时回退到 Jraaay 公共实时数据源。
- 按个人空闲节次、教学楼、最少座位数筛选空教室。
- 推荐可以连续待着、不用换教室的候选教室。

## 开发运行

```bash
npm install
npm run tauri dev
```

## 构建 macOS App

```bash
npm run tauri build
```

如果不在界面输入学号和教务密码，也可以在启动前配置环境变量：

```bash
export BUPT_USERNAME=你的学号
export BUPT_PASSWORD=你的教务密码
```

默认学期配置：

- 学期：`2025-2026-2`
- 第一周周一：`2026-03-02`

可通过环境变量 `DEFAULT_TERM_ID` 和 `DEFAULT_TERM_START_DATE` 调整。
