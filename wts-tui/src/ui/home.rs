use chrono::Datelike;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::widgets::{Borders, Paragraph, Wrap};
use ratatui::Frame;
use where_to_study_lib::config::today_in_app_tz;

use crate::app::App;
use crate::theme::Theme;

pub fn draw(frame: &mut Frame, area: Rect, app: &App, theme: &Theme) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(5),
            Constraint::Min(4),
            Constraint::Length(6),
        ])
        .split(area);

    // Week & date summary
    let week_text = match (app.current_week(), &app.schedule) {
        (Some(week), Some(schedule)) => format!(
            "公历第 {} 周 · 教学第 {week} 周 · 学期 {} · 第一周周一 {}",
            today_in_app_tz().iso_week().week(),
            schedule.term_id,
            schedule.term_start_date
        ),
        (None, Some(schedule)) => format!("学期 {} · 教学周范围外", schedule.term_id),
        _ => "未获取课表".to_string(),
    };
    let title = Paragraph::new(format!("{} · {}", today_date_label(), week_text))
        .block(theme.card_block().borders(Borders::ALL).title("概览"))
        .style(theme.strong_text());

    frame.render_widget(title, chunks[0]);

    // Today courses
    let courses = app.today_courses();
    let mut lines = vec![format!("今天共 {} 项安排", courses.len())];
    for course in &courses {
        let time = if where_to_study_lib::academic::is_exam(course) {
            where_to_study_lib::academic::course_minutes(course).map_or_else(
                || "全天 · 时间待定".into(),
                |(start, end)| {
                    format!(
                        "{:02}:{:02}-{:02}:{:02}",
                        start / 60,
                        start % 60,
                        end / 60,
                        end % 60
                    )
                },
            )
        } else if course.time_range.is_empty() {
            format!("第{}-{}节", course.start_slot + 1, course.end_slot + 1)
        } else {
            course.time_range.clone()
        };
        let room = if course.room.is_empty() {
            "地点未标注".to_string()
        } else {
            course.room.clone()
        };
        lines.push(format!(
            "  {}{}  {time}  {room}",
            if where_to_study_lib::academic::is_exam(course) {
                "考试 · "
            } else {
                ""
            },
            course.name
        ));
    }
    if lines.len() == 1 {
        lines.push("  （今天没有课程）".to_string());
    }
    let courses_para = Paragraph::new(lines.join("\n"))
        .block(theme.card_block().borders(Borders::ALL).title("今天课程"))
        .wrap(Wrap { trim: false });

    frame.render_widget(courses_para, chunks[1]);

    // Quick help
    let help = Paragraph::new(
        "快捷键：Tab/数字键 切换页面 · q 退出 · r 刷新当前页 · ↑↓ 导航 · Enter 选择",
    )
    .block(theme.card_block().borders(Borders::ALL).title("帮助"))
    .style(theme.muted_text());

    frame.render_widget(help, chunks[2]);

    // Holiday today
    let holiday = app.holiday_on(today_in_app_tz());
    let holiday_kind = holiday.as_ref().map(|(kind, _)| *kind);
    let holiday_text = match &holiday {
        Some((kind, name)) => format!("今天：{kind} {name}"),
        None => "今天无节假日安排".to_string(),
    };
    let holiday_para = Paragraph::new(holiday_text)
        .block(theme.card_block().borders(Borders::ALL).title("节假日"))
        .style(if holiday_kind == Some("休") {
            theme.danger_text()
        } else if holiday_kind == Some("班") {
            theme.workday_text()
        } else {
            theme.muted_text()
        });

    frame.render_widget(holiday_para, chunks[3]);
}

fn today_date_label() -> String {
    let today = today_in_app_tz();
    let weekday = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        [today.weekday().num_days_from_monday() as usize];
    format!("{} {}", today.format("%Y-%m-%d"), weekday)
}
