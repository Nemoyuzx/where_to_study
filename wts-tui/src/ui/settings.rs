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
    let account_style = if focus == 0 {
        Style::default().fg(theme.background).bg(theme.primary)
    } else {
        theme.strong_text()
    };
    let password_style = if focus == 1 {
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
        "•".repeat(app.login_password.len())
    };
    let form = Paragraph::new(vec![
        Line::from(format!("账号：{account_display}")).style(account_style),
        Line::from(format!("密码：{password_display}")).style(password_style),
        Line::from(""),
        Line::from("↑↓ 切换输入框 · 输入账号/密码 · Enter 登录 · o 退出登录 · r 刷新课表"),
    ])
    .block(Block::default().borders(Borders::ALL).title("账号设置"))
    .wrap(Wrap { trim: false });

    frame.render_widget(form, chunks[0]);

    // Credential status
    let status_items = vec![
        ListItem::new(format!(
            "凭据状态：{}",
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
            if app.holidays.is_some() {
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
    let about = Paragraph::new(
        "Where To Study TUI · 数据源：北邮移动教务 HTTPS 接口
版本 0.1.6 · GPL-3.0",
    )
    .block(Block::default().borders(Borders::ALL).title("关于"))
    .style(theme.muted_text());

    frame.render_widget(about, chunks[2]);
}
