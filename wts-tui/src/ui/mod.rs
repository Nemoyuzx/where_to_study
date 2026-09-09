pub mod calendar;
pub mod home;
pub mod planner;
pub mod query;
pub mod schedule;
pub mod settings;
pub mod theme_editor;

use chrono::Datelike;
use ratatui::layout::{Constraint, Direction, Layout};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::Wrap;
use ratatui::widgets::{Block, Borders, Paragraph, Tabs};
use ratatui::Frame;
use where_to_study_lib::config::today_in_app_tz;

use crate::app::{App, TAB_LABELS};
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, app: &mut App, theme: &Theme) {
    let area = frame.area();
    if let Some(editor) = &app.theme_editor {
        theme_editor::draw(frame, area, editor, theme);
        return;
    }
    if app.color_theme.preset != "default" {
        frame.render_widget(
            Block::default().style(Style::default().bg(theme.background).fg(theme.text)),
            area,
        );
    }

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
            theme
                .control_block()
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
        4 => query::draw(frame, content_area, app, theme),
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
    let hint = if app.selected_tab_index == 4 {
        "←/→ 切换班车/事件 · r 刷新 · ↑↓ 浏览 · Tab/1-6 切换页面 · 事件：/ 搜索 t 类型 c 分类 p 来源 e 已结束 f 收藏"
    } else {
        "q 退出 · r 刷新 · l 登录 · o 退出登录 · Tab/1-6 切换页面"
    };
    let hint_bar = Paragraph::new(Span::styled(hint, theme.muted_text()));
    frame.render_widget(hint_bar, chunks[3]);
}

fn status_line(app: &App) -> String {
    let mut parts: Vec<String> = Vec::new();
    if let Some(error) = &app.error_message {
        parts.push(format!("错误：{error}"));
    } else if let Some(status) = &app.status_message {
        parts.push(status.clone());
    }
    if app.loading {
        parts.push("加载中…".to_string());
    }
    let date = crate::date_today_label();
    let week = app
        .current_week()
        .map(|week| {
            format!(
                "公历第 {} 周 · 教学第 {week} 周",
                today_in_app_tz().iso_week().week()
            )
        })
        .unwrap_or_default();
    parts.push(format!("{date} {week}"));
    if parts.is_empty() {
        "就绪".to_string()
    } else {
        parts.join("  ·  ")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::color_theme::{channels, contrast, ColorTheme};
    use ratatui::{backend::TestBackend, Terminal};

    #[test]
    fn all_real_pages_render_themed_canvas_cards_navigation_and_borders() {
        for dark in [false, true] {
            for preset in ["ocean", "violet", "amber", "rose", "custom"] {
                for page in 0..6 {
                    let mut app = App::new(dark);
                    app.selected_tab_index = page;
                    app.color_theme = ColorTheme {
                        preset: preset.into(),
                        primary: "#FFFFFF".into(),
                        ..ColorTheme::default()
                    };
                    let theme = crate::current_theme(&app);
                    let mut terminal = Terminal::new(TestBackend::new(100, 30)).unwrap();
                    terminal
                        .draw(|frame| draw(frame, &mut app, &theme))
                        .unwrap();
                    let cells = terminal.backend().buffer().content();
                    for surface in [theme.background, theme.surface, theme.surface_variant] {
                        assert!(
                            cells.iter().any(|cell| cell.bg == surface),
                            "missing {surface:?} on page {page}, {preset}, dark={dark}"
                        );
                    }
                    assert!(cells
                        .iter()
                        .any(|cell| cell.symbol() == "┌" && cell.fg == theme.border));
                    for cell in cells.iter().filter(|cell| {
                        cell.fg == theme.text
                            || cell.fg == theme.text_muted
                            || cell.fg == theme.primary
                    }) {
                        if [
                            theme.background,
                            theme.surface,
                            theme.surface_variant,
                            theme.elevated,
                        ]
                        .contains(&cell.bg)
                        {
                            assert!(contrast(channels(cell.fg), channels(cell.bg)) >= 4.5);
                        }
                    }
                }
            }
        }
    }

    #[test]
    fn default_keeps_terminal_surface_behavior_and_unfocused_inputs_use_theme_controls() {
        for custom in [false, true] {
            let mut app = App::new(false);
            app.selected_tab_index = 5;
            app.login_account = "theme-input".into();
            if custom {
                app.color_theme.preset = "rose".into();
            }
            let theme = crate::current_theme(&app);
            let mut terminal = Terminal::new(TestBackend::new(100, 30)).unwrap();
            terminal
                .draw(|frame| draw(frame, &mut app, &theme))
                .unwrap();
            let buffer = terminal.backend().buffer();
            if custom {
                assert_eq!(buffer[(14, 4)].bg, theme.surface_variant);
                assert_eq!(buffer[(0, 0)].bg, theme.surface_variant);
            } else {
                assert_eq!(buffer[(0, 0)].bg, ratatui::style::Color::Reset);
                assert_eq!(buffer[(14, 4)].bg, ratatui::style::Color::Reset);
            }
        }
    }
}
