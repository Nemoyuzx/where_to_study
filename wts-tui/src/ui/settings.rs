use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::text::Line;
use ratatui::widgets::{Borders, List, ListItem, Paragraph, Wrap};
use ratatui::Frame;

use crate::app::App;
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, area: Rect, app: &mut App, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(10),
            Constraint::Min(4),
            Constraint::Length(5),
        ])
        .split(area);

    // Login form
    let focus = app.settings_focus;
    let account_style = if focus == 0 && app.settings_editing {
        theme.primary_selected()
    } else {
        theme
            .layer_style(theme.surface_variant)
            .patch(theme.strong_text())
    };
    let password_style = if focus == 1 && app.settings_editing {
        theme.primary_selected()
    } else {
        theme
            .layer_style(theme.surface_variant)
            .patch(theme.strong_text())
    };
    let account_display = if app.login_account.is_empty() {
        "（空）".to_string()
    } else {
        app.login_account.clone()
    };
    let cloud_style = if focus == 2 && app.settings_editing {
        theme.primary_selected()
    } else {
        theme
            .layer_style(theme.surface_variant)
            .patch(theme.strong_text())
    };
    let cloud_display = if !app.teaching_cloud_password.is_empty() {
        "•".repeat(app.teaching_cloud_password.chars().count())
    } else if app.use_academic_password {
        "（保存后改用教务密码）".into()
    } else if app.has_teaching_cloud_password
        && app.login_account.trim() == app.saved_account.trim()
    {
        "（已保存，留空保持不变）".into()
    } else {
        "（使用教务密码）".into()
    };
    let password_display = if app.login_password.is_empty()
        && app.credentials_saved
        && app.login_account.trim() == app.saved_account.trim()
    {
        "（已保存，留空保持不变）".to_string()
    } else if app.login_password.is_empty() {
        "（空）".to_string()
    } else {
        "•".repeat(app.login_password.chars().count())
    };
    let form = Paragraph::new(vec![
        Line::from(format!("账号：{account_display}")).style(account_style),
        Line::from(format!("教务密码：{password_display}")).style(password_style),
        Line::from(format!("教学云平台密码（选填）：{cloud_display}")).style(cloud_style),
        Line::from("同学号，仅作业认证；TUI 暂无作业页，CLI 使用其单独保存的账户。"),
        Line::from(""),
        Line::from(if app.settings_editing {
            "输入模式 · ↑↓/Tab 切换 · Enter 登录 · Esc 结束输入"
        } else {
            "Enter/e 输入 · l 保存 · u 改用教务密码 · m 管理课程 · o 退出 · t 颜色主题"
        }),
    ])
    .block(theme.card_block().borders(Borders::ALL).title("账号设置"))
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
        ListItem::new(format!(
            "公共查询：班车 {} · 重要事件 {} · 收藏 {} 项（按 i 打开）",
            if app.shuttle.is_some() {
                "已缓存"
            } else {
                "未加载"
            },
            if app.important_events.is_some() {
                "已缓存"
            } else {
                "未加载"
            },
            app.favorite_events.len()
        )),
    ];
    let status_list =
        List::new(status_items).block(theme.card_block().borders(Borders::ALL).title("数据状态"));

    frame.render_widget(status_list, chunks[1]);

    // About
    let about = Paragraph::new(format!(
        "Where To Study TUI · 数据源：北邮移动教务 HTTPS 接口\n版本 {} · GPL-3.0",
        env!("CARGO_PKG_VERSION")
    ))
    .block(theme.card_block().borders(Borders::ALL).title("关于"))
    .style(theme.muted_text());

    frame.render_widget(about, chunks[2]);
}
