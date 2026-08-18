pub mod calendar;
pub mod home;
pub mod planner;
pub mod schedule;
pub mod settings;

use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Wrap;
use ratatui::widgets::{Block, Borders, Paragraph, Tabs};
use ratatui::Frame;

use crate::app::{App, TAB_LABELS};
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, app: &mut App, theme: &Theme) {
    let area = frame.area();

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(0),
            Constraint::Length(3),
            Constraint::Length(1),
        ])
        .split(area);

    // Tab bar
    let titles: Vec<Line> = TAB_LABELS
        .iter()
        .enumerate()
        .map(|(index, label)| {
            if index == app.selected_tab_index {
                Line::from(format!("● {label}"))
            } else {
                Line::from(format!("  {label}"))
            }
        })
        .collect();
    let tabs = Tabs::new(titles)
        .select(app.selected_tab_index)
        .highlight_style(
            Style::default()
                .fg(theme.primary)
                .add_modifier(Modifier::BOLD),
        )
        .block(
            Block::default()
                .borders(Borders::ALL)
                .title("Where To Study"),
        );
    frame.render_widget(tabs, chunks[0]);

    // Content area
    let content_area = chunks[1];
    match app.selected_tab_index {
        0 => home::draw(frame, content_area, app, theme),
        1 => schedule::draw(frame, content_area, app, theme),
        2 => planner::draw(frame, content_area, app, theme),
        3 => calendar::draw(frame, content_area, app, theme),
        _ => settings::draw(frame, content_area, app, theme),
    }

    // Status bar
    let status = status_line(app);
    let status_style = if app.error_message.is_some() {
        theme.danger_text()
    } else {
        theme.muted_text()
    };
    let status_bar = Paragraph::new(status)
        .style(status_style)
        .block(Block::default().borders(Borders::NONE))
        .wrap(Wrap { trim: false });
    frame.render_widget(status_bar, chunks[2]);

    // Key hint bar
    let hint = "q 退出 · r 刷新 · l 登录 · o 退出登录 · Tab 切换页 · ↑↓←→ 导航";
    let hint_bar = Paragraph::new(Span::styled(hint, theme.muted_text()));
    frame.render_widget(hint_bar, chunks[3]);
}

fn status_line(app: &App) -> String {
    let mut parts: Vec<String> = Vec::new();
    if let Some(error) = &app.error_message {
        parts.push(format!("错误：{error}"));
    }
    if let Some(status) = &app.status_message {
        parts.push(status.clone());
    }
    if app.loading {
        parts.push("加载中…".to_string());
    }
    let date = crate::date_today_label();
    let week = app
        .current_week()
        .map(|week| format!("第 {week} 周"))
        .unwrap_or_default();
    parts.push(format!("{date} {week}"));
    if parts.is_empty() {
        "就绪".to_string()
    } else {
        parts.join("  ·  ")
    }
}
