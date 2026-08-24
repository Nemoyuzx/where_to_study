use chrono::{Datelike, Duration};
use ratatui::layout::{Constraint, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::widgets::{Block, Borders, Cell, Paragraph, Row, Table};
use ratatui::Frame;
use where_to_study_lib::config::{today_in_app_tz, SLOT_TIMES};

use crate::app::App;
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, area: Rect, app: &App, theme: &Theme) {
    let Some(schedule) = &app.schedule else {
        let msg = Paragraph::new("尚未获取课表。请在设置页登录并刷新，或按 r 获取。")
            .block(Block::default().borders(Borders::ALL).title("周课表"))
            .style(theme.muted_text());
        frame.render_widget(msg, area);
        return;
    };

    // Build the week grid: 7 days x 14 slots
    let today = today_in_app_tz();
    let monday = today
        .checked_sub_days(chrono::Days::new(
            today.weekday().num_days_from_monday() as u64
        ))
        .unwrap_or(today);
    let Some(week) = app.schedule_week_on(today) else {
        let msg = Paragraph::new("今天不在已加载课表的学期范围内。").style(theme.muted_text());
        frame.render_widget(msg, area);
        return;
    };

    let mut header = vec![Cell::from("节次").style(theme.strong_text())];
    for offset in 0..7 {
        let day = monday + Duration::days(offset);
        let is_today = day == today;
        let mut label = format!("{}", day.format("%m/%d"));
        if is_today {
            label = format!("▶ {label}");
        }
        header.push(Cell::from(label).style(if is_today {
            Style::default()
                .fg(theme.primary)
                .add_modifier(Modifier::BOLD)
        } else {
            theme.muted_text()
        }));
    }

    let mut rows = vec![Row::new(header).style(theme.strong_text())];
    for (slot_index, (start, end)) in SLOT_TIMES.iter().enumerate() {
        let mut cells = vec![Cell::from(format!("{} {}", start, end)).style(theme.muted_text())];
        for offset in 0..7 {
            let day = monday + Duration::days(offset);
            let weekday = day.weekday().num_days_from_monday() as i64 + 1;
            let courses: Vec<&where_to_study_lib::models::Course> = schedule
                .courses
                .iter()
                .filter(|c| c.weekday == weekday && c.week_numbers.contains(&week))
                .filter(|c| c.start_slot <= slot_index && c.end_slot >= slot_index)
                .collect();
            if courses.is_empty() {
                cells.push(Cell::from(""));
            } else {
                let is_today = day == today;
                let name = courses
                    .iter()
                    .map(|c| c.name.clone())
                    .collect::<Vec<_>>()
                    .join(",");
                cells.push(Cell::from(name).style(if is_today {
                    Style::default().fg(theme.background).bg(theme.primary)
                } else {
                    Style::default().fg(theme.primary)
                }));
            }
        }
        rows.push(Row::new(cells));
    }

    let widths = [
        Constraint::Length(12),
        Constraint::Length(10),
        Constraint::Length(10),
        Constraint::Length(10),
        Constraint::Length(10),
        Constraint::Length(10),
        Constraint::Length(10),
        Constraint::Length(10),
    ];
    let table =
        Table::new(rows, widths).block(Block::default().borders(Borders::ALL).title(format!(
            "本周课表 · 公历第 {} 周 · 教学第 {week} 周",
            today_in_app_tz().iso_week().week()
        )));

    frame.render_widget(table, area);
}
