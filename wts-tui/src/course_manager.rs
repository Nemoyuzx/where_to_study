use crate::{app::App, theme::Theme};
use chrono::{Duration, NaiveDate};
use crossterm::event::{KeyCode, KeyEvent};
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    text::Line,
    widgets::{Borders, List, ListItem, ListState, Paragraph, Wrap},
    Frame,
};
use where_to_study_lib::{
    config::today_in_app_tz,
    course_deletions::{self, CourseDeletion},
    error::{ServiceError, ServiceResult},
};

pub struct CourseManager {
    pub date: NaiveDate,
    pub cursor: usize,
    pub showing_deleted: bool,
    pub pending: Option<CourseDeletion>,
}

impl CourseManager {
    pub fn new() -> Self {
        Self {
            date: today_in_app_tz(),
            cursor: 0,
            showing_deleted: false,
            pending: None,
        }
    }
}

pub fn persist(app: &mut App, records: Vec<CourseDeletion>) -> ServiceResult<()> {
    let path = app
        .course_deletion_path
        .as_ref()
        .ok_or_else(|| ServiceError::new("请先保存账号；课程删除记录尚未准备好。"))?;
    course_deletions::save(path, &app.account_scope, &records)?;
    app.course_deletions = records;
    app.recompute_schedule();
    Ok(())
}

pub fn handle_key(app: &mut App, key: KeyEvent) {
    let Some(mut manager) = app.course_manager.take() else {
        return;
    };
    if let Some(rule) = manager.pending.take() {
        match key.code {
            KeyCode::Char('y') | KeyCode::Char('Y') => {
                let mut records = app.course_deletions.clone();
                if !records.iter().any(|existing| existing.id == rule.id) {
                    records.push(rule);
                }
                match persist(app, records) {
                    Ok(()) => app.set_status("课程已从本地课表删除；按 u 查看记录并恢复".into()),
                    Err(error) => app.set_error(error.message),
                }
            }
            KeyCode::Esc | KeyCode::Char('n') => {}
            _ => manager.pending = Some(rule),
        }
        app.course_manager = Some(manager);
        return;
    }
    let count = if manager.showing_deleted {
        app.course_deletions.len()
    } else {
        app.courses_on(manager.date).len()
    };
    match key.code {
        KeyCode::Esc => return,
        KeyCode::Char('u') => {
            manager.showing_deleted = !manager.showing_deleted;
            manager.cursor = 0;
        }
        KeyCode::Up => manager.cursor = manager.cursor.saturating_sub(1),
        KeyCode::Down => manager.cursor = (manager.cursor + 1).min(count.saturating_sub(1)),
        KeyCode::Left | KeyCode::Right | KeyCode::PageUp | KeyCode::PageDown
            if !manager.showing_deleted =>
        {
            let delta = match key.code {
                KeyCode::Left => -1,
                KeyCode::Right => 1,
                KeyCode::PageUp => -7,
                _ => 7,
            };
            if let Some(date) = manager.date.checked_add_signed(Duration::days(delta)) {
                manager.date = date;
            }
            manager.cursor = 0;
        }
        KeyCode::Char('t') => {
            manager.date = today_in_app_tz();
            manager.cursor = 0;
        }
        KeyCode::Enter if manager.showing_deleted => {
            if let Some(rule) = app.course_deletions.get(manager.cursor) {
                let records = app
                    .course_deletions
                    .iter()
                    .filter(|item| item.id != rule.id)
                    .cloned()
                    .collect();
                match persist(app, records) {
                    Ok(()) => app.set_status("已恢复课程删除记录".into()),
                    Err(error) => app.set_error(error.message),
                }
                manager.cursor = manager
                    .cursor
                    .min(app.course_deletions.len().saturating_sub(1));
            }
        }
        KeyCode::Char('x') | KeyCode::Char('d') if !manager.showing_deleted => {
            if let (Some(raw), Some(course)) = (
                app.raw_schedule.as_ref(),
                app.courses_on(manager.date).get(manager.cursor),
            ) {
                let day = manager.date.to_string();
                let date = if key.code == KeyCode::Char('x') {
                    Some(day.as_str())
                } else {
                    None
                };
                match CourseDeletion::create(raw, &course.id, date) {
                    Ok(rule) => manager.pending = Some(rule),
                    Err(error) => app.set_error(error.message),
                }
            }
        }
        _ => {}
    }
    app.course_manager = Some(manager);
}

pub fn draw(frame: &mut Frame, area: Rect, app: &App, theme: &Theme) {
    let Some(manager) = app.course_manager.as_ref() else {
        return;
    };
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(4),
            Constraint::Min(2),
            Constraint::Length(6),
        ])
        .split(area);
    let title = if manager.showing_deleted {
        "已删除课程 / Deleted courses".to_string()
    } else {
        format!("课程管理 / Manage courses · {}", manager.date)
    };
    frame.render_widget(
        Paragraph::new(
            "↑↓ 选择 · ←/→ 切换日期 · PgUp/PgDn 切换周 · t 今天 · u 删除记录 · Esc 关闭",
        )
        .block(theme.card_block().borders(Borders::ALL).title(title))
        .wrap(Wrap { trim: false }),
        chunks[0],
    );
    let rows: Vec<ListItem> = if manager.showing_deleted {
        app.course_deletions
            .iter()
            .map(|rule| {
                ListItem::new(vec![
                    Line::from(format!(
                        "{} · {} · {}",
                        rule.name, rule.teacher, rule.term_id
                    )),
                    Line::from(
                        rule.date
                            .as_ref()
                            .map(|day| {
                                format!("{day} · {}–{} 节", rule.start_slot + 1, rule.end_slot + 1)
                            })
                            .unwrap_or("本学期整门课程".into()),
                    ),
                ])
            })
            .collect()
    } else {
        app.courses_on(manager.date)
            .into_iter()
            .map(|course| {
                ListItem::new(vec![
                    Line::from(format!(
                        "{} · {} · {}",
                        course.name, course.time_range, course.teacher
                    )),
                    Line::from(course.room.clone()),
                ])
            })
            .collect()
    };
    let mut state = ListState::default().with_selected(Some(manager.cursor));
    frame.render_stateful_widget(
        List::new(rows)
            .block(theme.card_block().borders(Borders::ALL))
            .highlight_style(theme.primary_selected())
            .highlight_symbol("▶ "),
        chunks[1],
        &mut state,
    );
    let help = if let Some(rule) = &manager.pending {
        format!("确认删除「{}」· {}？\ny 确认 · n/Esc 取消\n仅修改本账号本地课表，刷新后仍生效，可恢复。学校选课、作业和已导出日历事件保持不变。", rule.name, rule.date.as_deref().unwrap_or("本学期整门课程"))
    } else if manager.showing_deleted {
        "Enter 恢复选中记录 · u 返回课表\n恢复后立即更新本地课程与空闲节次；尚未加载课表时，下次刷新生效。".into()
    } else {
        "x 仅删除本次 · d 删除本学期整门课程（均需确认）\n先按 r 刷新课表，再从主页、周课表、月历或设置页按 m 打开。\n按 u 可查看当前账号的删除记录并恢复。".into()
    };
    let help = if let Some(error) = &app.error_message {
        format!("错误：{error}\n{help}")
    } else if let Some(status) = &app.status_message {
        format!("{status}\n{help}")
    } else {
        help
    };
    frame.render_widget(
        Paragraph::new(help)
            .wrap(Wrap { trim: false })
            .block(theme.card_block().borders(Borders::ALL)),
        chunks[2],
    );
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::KeyModifiers;
    use ratatui::{backend::TestBackend, Terminal};

    fn key(character: char) -> KeyEvent {
        KeyEvent::new(KeyCode::Char(character), KeyModifiers::NONE)
    }

    fn fixture() -> App {
        let mut app = App::new(false);
        let mut raw: where_to_study_lib::models::ScheduleResponse =
            serde_json::from_str(include_str!("../../contracts/v1/fixtures/schedule.json"))
                .unwrap();
        raw.term_start_date = "2026-03-02".into();
        raw.courses.truncate(1);
        raw.courses[0].weekday = 1;
        raw.courses[0].week_numbers = vec![1, 2, 3];
        app.set_raw_schedule(raw);
        app.account_scope = where_to_study_lib::scoped_cache::new_account_scope().unwrap();
        let mut manager = CourseManager::new();
        manager.date = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        app.course_manager = Some(manager);
        app
    }

    #[test]
    fn keyboard_deletion_requires_confirmation_persists_refresh_and_restores_both_scopes() {
        let directory = crate::color_theme::tests::TestDirectory::new();
        let mut app = fixture();
        app.course_deletion_path = Some(directory.0.join("deletions.json"));
        let raw = app.raw_schedule.clone().unwrap();
        handle_key(&mut app, key('x'));
        assert!(app.course_manager.as_ref().unwrap().pending.is_some());
        assert_eq!(
            app.schedule.as_ref().unwrap().courses[0].week_numbers,
            vec![1, 2, 3]
        );
        handle_key(&mut app, key('y'));
        assert_eq!(
            app.schedule.as_ref().unwrap().courses[0].week_numbers,
            vec![2, 3]
        );
        app.set_raw_schedule(raw.clone());
        assert_eq!(
            app.schedule.as_ref().unwrap().courses[0].week_numbers,
            vec![2, 3]
        );
        assert_eq!(
            course_deletions::load(
                app.course_deletion_path.as_ref().unwrap(),
                &app.account_scope
            )
            .unwrap()
            .len(),
            1
        );
        handle_key(&mut app, key('u'));
        handle_key(&mut app, KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        assert_eq!(
            app.schedule.as_ref().unwrap().courses[0].week_numbers,
            vec![1, 2, 3]
        );
        handle_key(&mut app, key('u'));
        handle_key(&mut app, key('d'));
        handle_key(&mut app, key('n'));
        assert_eq!(app.schedule.as_ref().unwrap().courses.len(), 1);
        handle_key(&mut app, key('d'));
        handle_key(&mut app, key('y'));
        assert!(app.schedule.as_ref().unwrap().courses.is_empty());
        app.set_raw_schedule(raw);
        assert!(app.schedule.as_ref().unwrap().courses.is_empty());
        handle_key(&mut app, key('u'));
        handle_key(&mut app, KeyEvent::new(KeyCode::Enter, KeyModifiers::NONE));
        assert_eq!(app.schedule.as_ref().unwrap().courses.len(), 1);
    }

    #[test]
    fn failed_write_keeps_courses_and_shows_error_in_manager() {
        let directory = crate::color_theme::tests::TestDirectory::new();
        let mut app = fixture();
        app.course_deletion_path = Some(directory.0.clone());
        handle_key(&mut app, key('d'));
        handle_key(&mut app, key('y'));
        assert!(app.error_message.is_some());
        assert!(app.course_deletions.is_empty());
        assert_eq!(app.schedule.as_ref().unwrap().courses.len(), 1);
        let mut terminal = Terminal::new(TestBackend::new(100, 24)).unwrap();
        terminal
            .draw(|frame| draw(frame, frame.area(), &app, &crate::theme::LIGHT))
            .unwrap();
        let text: String = terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect();
        assert!(text.replace(' ', "").contains("错误"));
    }
}
