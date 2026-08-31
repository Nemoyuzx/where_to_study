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
        "{}年{}月 · ←→ 切换月份 · 空格 回到今天 · i 班车/重要事件查询",
        year,
        month_index + 1
    ))
    .style(theme.strong_text());

    frame.render_widget(title, header_chunks[0]);

    // Calendar grid: 6 rows x 7 cols
    let first_day = NaiveDate::from_ymd_opt(year, month.month(), 1).unwrap();
    let offset = first_day.weekday().num_days_from_monday() as i64;
    let today = today_in_app_tz();
    let important_events = app.all_query_events();

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
        let holiday = app.holiday_on(date);
        let courses = app.courses_on(date);
        let date_key = date.format("%Y-%m-%d").to_string();
        let (conference_count, other_event_count) = important_events
            .iter()
            .filter(|item| item.primary_deadline.get(..10) == Some(date_key.as_str()))
            .fold((0_usize, 0_usize), |(conference, other), item| {
                if matches!(
                    item.event_type.as_str(),
                    "conference" | "journal_special_issue"
                ) {
                    (conference + 1, other)
                } else {
                    (conference, other + 1)
                }
            });
        let mut content = day.to_string();
        if let Some((kind, _)) = &holiday {
            content = format!("{}{}", kind, content);
        }
        if !courses.is_empty() {
            content = format!("{content}·{}", courses.len());
        }
        if conference_count > 0 {
            content = format!("{content}·会{conference_count}");
        }
        if other_event_count > 0 {
            content = format!("{content}·事{other_event_count}");
        }
        let style = if is_today {
            Style::default()
                .fg(theme.background)
                .bg(theme.primary)
                .add_modifier(Modifier::BOLD)
        } else if holiday.as_ref().is_some_and(|(kind, _)| *kind == "休") {
            theme.danger_text()
        } else if holiday.as_ref().is_some_and(|(kind, _)| *kind == "班") {
            theme.gold_text()
        } else if conference_count > 0 || other_event_count > 0 || !courses.is_empty() {
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
            .title("月历（休=红 班=金 数字=课程数 会=会议 事=重要事件）"),
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

#[cfg(test)]
mod tests {
    use ratatui::backend::TestBackend;
    use ratatui::Terminal;
    use where_to_study_lib::models::{ImportantEventItem, ImportantEventsResponse};

    use super::*;

    fn event(id: &str, event_type: &str) -> ImportantEventItem {
        ImportantEventItem {
            id: id.to_string(),
            name: id.to_string(),
            event_type: event_type.to_string(),
            source_type: "contest_ddl".to_string(),
            primary_deadline: "2026-08-31T23:59:59+08:00".to_string(),
            deadline_label: Some("截止".to_string()),
            organizer: None,
            official_url: None,
            source_name: None,
            source_url: None,
            categories: Vec::new(),
            tags: Vec::new(),
            level: None,
            location: None,
            status: None,
            description: None,
            eligibility: None,
            notes: None,
            region: None,
            mode: None,
            published_at: None,
            stale: false,
            archived: false,
        }
    }

    #[test]
    fn month_calendar_marks_conferences_and_other_important_events() {
        let mut app = App::new(false);
        app.calendar_month = NaiveDate::from_ymd_opt(2026, 8, 1).unwrap();
        app.important_events = Some(ImportantEventsResponse {
            fetched_at: "2026-08-31T00:00:00+08:00".to_string(),
            source: "fixture".to_string(),
            used_backup: false,
            items: vec![
                event("conference", "conference"),
                event("contest", "competition"),
            ],
        });
        let backend = TestBackend::new(140, 18);
        let mut terminal = Terminal::new(backend).unwrap();
        terminal
            .draw(|frame| draw(frame, frame.area(), &app, &crate::theme::LIGHT))
            .unwrap();
        let rendered = terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect::<String>()
            .replace(' ', "");
        assert!(rendered.contains("会1"));
        assert!(rendered.contains("事1"));
        assert!(rendered.contains("会=会议"));
    }
}
