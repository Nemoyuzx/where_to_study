mod app;
mod theme;
mod ui;

use std::io;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use app::{App, Tab, TAB_LABELS};
use chrono::Datelike;
use crossterm::event::{self, Event, KeyCode, KeyEventKind};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::{backend::CrosstermBackend, Terminal};
use theme::Theme;
use where_to_study_lib::config::today_in_app_tz;
use where_to_study_lib::error::ServiceResult;

/// Run an async future on a fresh Tokio runtime (reqwest requires a reactor).
fn block_on<T>(future: impl std::future::Future<Output = T>) -> T {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("failed to build tokio runtime")
        .block_on(future)
}

enum Message {
    Schedule(ServiceResult<where_to_study_lib::models::ScheduleResponse>),
    Classrooms(ServiceResult<where_to_study_lib::models::ClassroomsCacheResponse>),
    Holidays(ServiceResult<where_to_study_lib::models::HolidaysResponse>),
    CredentialsSaved(bool, String),
}

fn main() -> io::Result<()> {
    let theme_dark = theme::prefers_dark();
    let mut app = App::new(theme_dark);
    app.credentials_saved = credentials_have_account();
    if let Ok(Some(credentials)) = where_to_study_lib::credential_store::load() {
        app.saved_account = credentials.account.clone();
    }

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let (tx, rx) = mpsc::channel::<Message>();

    load_holidays(&tx, today_in_app_tz().year());

    let result = run(&mut terminal, &mut app, &rx, &tx);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    if let Err(error) = result {
        eprintln!("错误：{error}");
        std::process::exit(1);
    }
    Ok(())
}

/// Human-readable today label used by the status bar.
pub fn date_today_label() -> String {
    let today = today_in_app_tz();
    let weekday = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        [today.weekday().num_days_from_monday() as usize];
    format!("{} {}", today.format("%Y-%m-%d"), weekday)
}

fn credentials_have_account() -> bool {
    where_to_study_lib::credential_store::load()
        .ok()
        .flatten()
        .map(|c| !c.account.trim().is_empty() && !c.password.is_empty())
        .unwrap_or(false)
}

fn load_holidays(tx: &mpsc::Sender<Message>, year: i32) {
    let tx = tx.clone();
    thread::spawn(move || {
        let result = match block_on(where_to_study_lib::holidays::fetch_remote(year)) {
            Ok(response) => Ok(response),
            Err(_) => where_to_study_lib::holidays::offline_response(year),
        };
        let _ = tx.send(Message::Holidays(result));
    });
}

fn run(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
    rx: &mpsc::Receiver<Message>,
    tx: &mpsc::Sender<Message>,
) -> io::Result<()> {
    loop {
        let theme = current_theme(app);
        terminal.draw(|frame| ui::draw(frame, app, &theme))?;

        // Batch-consume all queued events so fast key sequences are not lost.
        if event::poll(Duration::from_millis(120))? {
            loop {
                if !event::poll(Duration::ZERO)? {
                    break;
                }
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press {
                        if key.code == KeyCode::Char('q') && key.modifiers.is_empty() {
                            return Ok(());
                        }
                        handle_key(app, key, tx);
                    }
                }
            }
        }

        while let Ok(message) = rx.try_recv() {
            match message {
                Message::Schedule(result) => {
                    app.loading = false;
                    match result {
                        Ok(schedule) => {
                            app.schedule = Some(schedule);
                            app.set_status("课表已刷新".to_string());
                        }
                        Err(error) => app.set_error(error.message),
                    }
                }
                Message::Classrooms(result) => {
                    app.loading = false;
                    match result {
                        Ok(cache) => {
                            app.classrooms = Some(cache);
                            app.available_buildings = collect_buildings(app);
                            app.set_status("空教室已刷新".to_string());
                        }
                        Err(error) => app.set_error(error.message),
                    }
                }
                Message::Holidays(result) => match result {
                    Ok(response) => app.holidays = Some(response),
                    Err(error) => app.set_error(error.message),
                },
                Message::CredentialsSaved(ok, account) => {
                    if ok {
                        app.credentials_saved = true;
                        app.saved_account = account;
                        app.login_password.clear();
                        app.set_status("凭据已保存".to_string());
                    }
                }
            }
        }
    }
}

fn current_theme(app: &App) -> Theme {
    if app.theme_dark {
        theme::DARK
    } else {
        theme::LIGHT
    }
}

fn collect_buildings(app: &App) -> Vec<String> {
    app.building_names()
}

fn handle_key(app: &mut App, key: crossterm::event::KeyEvent, tx: &mpsc::Sender<Message>) {
    match key.code {
        KeyCode::Char('r') => {
            app.clear_error();
            refresh_schedule(app, tx);
            if app.selected_tab_index == 2 {
                refresh_classrooms(app, tx);
            }
        }
        KeyCode::Char('l') => login_with_form(app, tx),
        KeyCode::Char('o') => {
            let _ = where_to_study_lib::credential_store::save(
                &where_to_study_lib::credential_store::Credentials::default(),
            );
            app.credentials_saved = false;
            app.saved_account.clear();
            app.set_status("已退出登录".to_string());
        }
        // Text input has priority on the settings tab (digits are part of accounts).
        KeyCode::Char(ch) if app.selected_tab_index == 4 => {
            let focus = app.settings_focus;
            if focus == 0 {
                app.login_account.push(ch);
            } else if focus == 1 {
                app.login_password.push(ch);
            }
        }
        KeyCode::Backspace if app.selected_tab_index == 4 => {
            let focus = app.settings_focus;
            if focus == 0 {
                app.login_account.pop();
            } else if focus == 1 {
                app.login_password.pop();
            }
        }
        KeyCode::Char('1') => switch_tab(app, 0),
        KeyCode::Char('2') => switch_tab(app, 1),
        KeyCode::Char('3') => switch_tab(app, 2),
        KeyCode::Char('4') => switch_tab(app, 3),
        KeyCode::Char('5') => switch_tab(app, 4),
        KeyCode::Tab => {
            let next = (app.selected_tab_index + 1) % TAB_LABELS.len();
            switch_tab(app, next);
        }
        KeyCode::Char('a') if app.selected_tab_index == 2 => {
            app.all_slots_selected = true;
            app.selected_slots = (0..14).collect();
        }
        KeyCode::Char('c') if app.selected_tab_index == 2 => {
            app.all_slots_selected = false;
            app.selected_slots.clear();
        }
        KeyCode::Char(ch) if app.selected_tab_index == 2 && ch.is_ascii_digit() => {
            if let Some(slot) = ch.to_digit(10) {
                if (1..=9).contains(&slot) {
                    toggle_slot(app, (slot - 1) as usize);
                }
            }
        }
        KeyCode::Char('0') if app.selected_tab_index == 2 => {
            toggle_slot(app, 9);
        }
        KeyCode::Char(' ') => match app.selected_tab_index {
            2 => {
                if app.selected_buildings.is_empty() {
                    app.selected_buildings = app.available_buildings.clone();
                } else {
                    app.selected_buildings.clear();
                }
            }
            3 => {
                app.calendar_month = today_in_app_tz();
            }
            _ => {}
        },
        KeyCode::Enter if app.selected_tab_index == 4 => {
            if app.settings_focus == 0 {
                app.settings_focus = 1;
            } else if app.settings_focus == 1 {
                login_with_form(app, tx);
            }
        }
        KeyCode::Up if app.selected_tab_index == 4 => {
            app.settings_focus = app.settings_focus.saturating_sub(1);
        }
        KeyCode::Down if app.selected_tab_index == 4 => {
            app.settings_focus = (app.settings_focus + 1).min(1);
        }
        KeyCode::Left => match app.selected_tab_index {
            2 => {
                if app.campus_id == "04" {
                    app.campus_id = "01".to_string();
                    app.selected_buildings.clear();
                    app.available_buildings = collect_buildings(app);
                }
            }
            3 => {
                let month = app.calendar_month;
                let (y, m) = if month.month() == 1 {
                    (month.year() - 1, 12)
                } else {
                    (month.year(), month.month() - 1)
                };
                app.calendar_month = chrono::NaiveDate::from_ymd_opt(y, m, 1).unwrap();
            }
            _ => {}
        },
        KeyCode::Right => match app.selected_tab_index {
            2 => {
                if app.campus_id == "01" {
                    app.campus_id = "04".to_string();
                    app.selected_buildings.clear();
                    app.available_buildings = collect_buildings(app);
                }
            }
            3 => {
                let month = app.calendar_month;
                let (y, m) = if month.month() == 12 {
                    (month.year() + 1, 1)
                } else {
                    (month.year(), month.month() + 1)
                };
                app.calendar_month = chrono::NaiveDate::from_ymd_opt(y, m, 1).unwrap();
            }
            _ => {}
        },
        _ => {}
    }
}

fn toggle_slot(app: &mut App, slot: usize) {
    app.all_slots_selected = false;
    if let Some(index) = app.selected_slots.iter().position(|s| *s == slot) {
        app.selected_slots.remove(index);
    } else {
        app.selected_slots.push(slot);
        app.selected_slots.sort_unstable();
    }
    if app.selected_slots.len() == 14 {
        app.all_slots_selected = true;
    }
}

fn login_with_form(app: &mut App, tx: &mpsc::Sender<Message>) {
    let account = app.login_account.clone();
    let password = app.login_password.clone();
    if account.trim().is_empty() {
        app.set_error("请输入账号。".to_string());
        return;
    }
    if password.is_empty() {
        app.set_error("请输入密码。".to_string());
        return;
    }
    let tx = tx.clone();
    thread::spawn(move || {
        let credentials = where_to_study_lib::credential_store::Credentials {
            account: account.trim().to_string(),
            password,
            account_scope: String::new(),
        };
        let saved = where_to_study_lib::credential_store::save(&credentials).is_ok();
        let _ = tx.send(Message::CredentialsSaved(saved, account));
    });
}

fn refresh_schedule(app: &mut App, tx: &mpsc::Sender<Message>) {
    let (account, password) = match load_credentials() {
        Ok(Some(creds)) => creds,
        Ok(None) => {
            app.set_error("尚未保存凭据，请先在设置页登录（l 登录）。".to_string());
            return;
        }
        Err(error) => {
            app.set_error(error.message.clone());
            return;
        }
    };
    app.loading = true;
    let tx = tx.clone();
    thread::spawn(move || {
        let request = where_to_study_lib::models::ScheduleRequest {
            account: Some(account),
            password: Some(password),
            term_id: None,
            term_start_date: None,
        };
        let result = block_on(where_to_study_lib::schedule::fetch_schedule(&request));
        let _ = tx.send(Message::Schedule(result));
    });
}

fn refresh_classrooms(app: &mut App, tx: &mpsc::Sender<Message>) {
    let (account, password) = match load_credentials() {
        Ok(Some(creds)) => creds,
        Ok(None) => {
            app.set_error("尚未保存凭据，请先在设置页登录（l 登录）。".to_string());
            return;
        }
        Err(error) => {
            app.set_error(error.message.clone());
            return;
        }
    };
    app.loading = true;
    let campus_id = app.campus_id.clone();
    let tx = tx.clone();
    thread::spawn(move || {
        let request = where_to_study_lib::models::ClassroomsRequest {
            account: Some(account),
            password: Some(password),
            campus_id: Some(campus_id),
            target_date: Some(today_in_app_tz().format("%Y-%m-%d").to_string()),
        };
        let result = block_on(where_to_study_lib::classrooms::fetch_all_classrooms(
            &request,
        ));
        let _ = tx.send(Message::Classrooms(result));
    });
}

fn load_credentials() -> ServiceResult<Option<(String, String)>> {
    let Some(credentials) = where_to_study_lib::credential_store::load()? else {
        return Ok(None);
    };
    let account = credentials.account.clone();
    let password = credentials.password.clone();
    Ok(Some((account, password)))
}

fn switch_tab(app: &mut App, index: usize) {
    app.selected_tab_index = index;
    app.tab = match index {
        0 => Tab::Home,
        1 => Tab::Schedule,
        2 => Tab::Planner,
        3 => Tab::Calendar,
        _ => Tab::Settings,
    };
}
