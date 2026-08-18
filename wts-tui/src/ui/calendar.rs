use chrono::{Datelike, Duration, NaiveDate};
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::widgets::{Block, Borders, Cell, Paragraph, Row, Table};
use ratatui::Frame;
use where_to_study_lib::config::today_in_app_tz;

use crate::app::App;
use crate::theme::Theme;

const WEEKDAY_HEADERS: [&str; 7] = ["一", "二", "三", "四", "五", "六", "日"];

pub fn draw(frame: &mut Frame, area: Rect, app: &App, theme: &Theme) {
    let month = app.calendar_month;
    let year = month.year();
    let month_index = month.month() - 1;

    // Header
    let header_chunks = Layout::default()
        .vertical_margin(0)
        .constraints([Constraint::Length(1), Constraint::Min(6)])
        .split(area);

    let title = Paragraph::new(format!(
        "{}年{}月 ·  ←→ 切换月份 · 空格 回到今天",
        year,
        month_index + 1
    ))
    .style(theme.strong_text());

    frame.render_widget(title, header_chunks[0]);

    // Calendar grid: 6 rows x 7 cols
    let first_day = NaiveDate::from_ymd_opt(year, month.month(), 1).unwrap();
    let offset = first_day.weekday().num_days_from_monday() as i64;
    let today = today_in_app_tz();

    let mut header = vec![];
    for label in WEEKDAY_HEADERS {
        header.push(Cell::from(label).style(theme.muted_text()));
    }

    let mut rows = vec![Row::new(header)];
    let mut cells: Vec<Cell> = Vec::new();
    // Fill leading blanks
    for _ in 0..offset {
        cells.push(Cell::from(""));
    }
    let days_in_month = days_in_month(year, month_index + 1);
    for day in 1..=days_in_month {
        let date = NaiveDate::from_ymd_opt(year, month.month(), day).unwrap();
        let is_today = date == today;
        let has_holiday = app.holiday_on(date).is_some();
        let courses = app.courses_on(date);
        let mut content = day.to_string();
        if let Some((kind, _)) = app.holiday_on(date) {
            content = format!("{}{}", kind, content);
        }
        if !courses.is_empty() {
            content = format!("{content}·{}", courses.len());
        }
        let style = if is_today {
            Style::default()
                .fg(theme.background)
                .bg(theme.primary)
                .add_modifier(Modifier::BOLD)
        } else if has_holiday {
            theme.danger_text()
        } else if !courses.is_empty() {
            theme.primary_text()
        } else {
            theme.muted_text()
        };
        cells.push(Cell::from(content).style(style));
    }
    // Pad to full weeks
    while !cells.len().is_multiple_of(7) {
        cells.push(Cell::from(""));
    }
    for chunk in cells.chunks(7) {
        rows.push(Row::new(chunk.to_vec()));
    }

    let widths = [Constraint::Percentage(14); 7];
    let table = Table::new(rows, widths).block(
        Block::default()
            .borders(Borders::ALL)
            .title("月历（休=红 班=金 数字=课程数）"),
    );

    frame.render_widget(table, header_chunks[1]);
}

fn days_in_month(year: i32, month: u32) -> u32 {
    let (next_year, next_month) = if month == 12 {
        (year + 1, 1)
    } else {
        (year, month + 1)
    };
    let first_next = NaiveDate::from_ymd_opt(next_year, next_month, 1).unwrap();
    (first_next - Duration::days(1)).day()
}
