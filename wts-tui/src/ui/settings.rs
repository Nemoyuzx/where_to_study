use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::Style;
use ratatui::text::Line;
use ratatui::widgets::{Block, Borders, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::App;
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, area: Rect, app: &mut App, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(8),
            Constraint::Min(4),
            Constraint::Length(5),
        ])
        .split(area);

    // Login form
    let focus = app.settings_focus;
    let account_style = if focus == 0 && app.settings_editing {
        Style::default().fg(theme.background).bg(theme.primary)
    } else {
        theme.strong_text()
    };
    let password_style = if focus == 1 && app.settings_editing {
        Style::default().fg(theme.background).bg(theme.primary)
    } else {
        theme.strong_text()
    };
    let account_display = if app.login_account.is_empty() {
        "（空）".to_string()
    } else {
        app.login_account.clone()
    };
    let password_display = if app.login_password.is_empty() {
        "（空）".to_string()
    } else {
        "•".repeat(app.login_password.chars().count())
    };
    let form = Paragraph::new(vec![
        Line::from(format!("账号：{account_display}")).style(account_style),
        Line::from(format!("密码：{password_display}")).style(password_style),
        Line::from(""),
        Line::from(if app.settings_editing {
            "输入模式 · ↑↓/Tab 切换 · Enter 登录 · Esc 结束输入"
        } else {
            "Enter/e 开始输入 · l 登录 · o 退出登录 · r 刷新课表"
        }),
    ])
    .block(Block::default().borders(Borders::ALL).title("账号设置"))
    .wrap(Wrap { trim: false });

    frame.render_widget(form, chunks[0]);

    // Credential status
    let status_items = vec![
        ListItem::new(format!(
            "本地凭据文件：{}",
            if app.credentials_saved {
                format!("已保存（{}）", app.saved_account)
            } else {
                "未保存".to_string()
            }
        )),
        ListItem::new(format!(
            "课表：{}",
            if app.schedule.is_some() {
                "已加载"
            } else {
                "未加载"
            }
        )),
        ListItem::new(format!(
            "空教室缓存：{}",
            if app.classrooms.is_some() {
                "已加载"
            } else {
                "未加载"
            }
        )),
        ListItem::new(format!(
            "节假日：{}",
            if !app.holidays.is_empty() {
                "已加载"
            } else {
                "未加载"
            }
        )),
    ];
    let status_list =
        List::new(status_items).block(Block::default().borders(Borders::ALL).title("数据状态"));

    frame.render_widget(status_list, chunks[1]);

    // About
    let about = Paragraph::new(format!(
        "Where To Study TUI · 数据源：北邮移动教务 HTTPS 接口\n版本 {} · GPL-3.0",
        env!("CARGO_PKG_VERSION")
    ))
    .block(Block::default().borders(Borders::ALL).title("关于"))
    .style(theme.muted_text());

    frame.render_widget(about, chunks[2]);
}
