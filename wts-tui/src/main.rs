mod app;
mod theme;
mod ui;

use std::io::{self, Stdout};
use std::panic;
use std::sync::mpsc;
use std::thread;
use std::time::Duration;

use app::{App, Tab, TAB_LABELS};
use chrono::Datelike;
use crossterm::cursor::Show;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers};
use crossterm::execute;
use crossterm::terminal::{
    disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen,
};
use ratatui::{backend::CrosstermBackend, Terminal};
use theme::Theme;
use where_to_study_lib::config::today_in_app_tz;
use where_to_study_lib::error::{ServiceError, ServiceResult};
use zeroize::{Zeroize, Zeroizing};

type AppTerminal = Terminal<CrosstermBackend<Stdout>>;

fn block_on<T>(future: impl std::future::Future<Output = T>) -> T {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("failed to build tokio runtime")
        .block_on(future)
}

enum Message {
    Schedule {
        request_id: u64,
        result: ServiceResult<where_to_study_lib::models::ScheduleResponse>,
    },
    Classrooms {
        request_id: u64,
        result: ServiceResult<where_to_study_lib::models::ClassroomsCacheResponse>,
    },
    Holidays {
        year: i32,
        result: ServiceResult<where_to_study_lib::models::HolidaysResponse>,
    },
    CredentialsSaved(Result<String, String>),
    CredentialsCleared(Result<(), String>),
}

struct TerminalSession {
    terminal: AppTerminal,
}

impl TerminalSession {
    fn new() -> io::Result<Self> {
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        if let Err(error) = execute!(stdout, EnterAlternateScreen) {
            let _ = disable_raw_mode();
            return Err(error);
        }
        let backend = CrosstermBackend::new(stdout);
        match Terminal::new(backend) {
            Ok(terminal) => Ok(Self { terminal }),
            Err(error) => {
                restore_terminal();
                Err(error)
            }
        }
    }
}

impl Drop for TerminalSession {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(self.terminal.backend_mut(), LeaveAlternateScreen, Show);
        let _ = self.terminal.show_cursor();
    }
}

fn restore_terminal() {
    let _ = disable_raw_mode();
    let _ = execute!(io::stdout(), LeaveAlternateScreen, Show);
}

fn install_terminal_recovery() -> io::Result<()> {
    let default_hook = panic::take_hook();
    panic::set_hook(Box::new(move |info| {
        restore_terminal();
        default_hook(info);
    }));
    ctrlc::set_handler(|| {
        restore_terminal();
        std::process::exit(130);
    })
    .map_err(io::Error::other)
}

fn main() -> io::Result<()> {
    if handle_meta_args() {
        return Ok(());
    }
    install_terminal_recovery()?;

    let theme_dark = theme::prefers_dark();
    let mut app = App::new(theme_dark);
    app.credentials_saved = credentials_have_account();
    if let Ok(Some(credentials)) = where_to_study_lib::credential_store::load() {
        app.saved_account = credentials.account.clone();
    }

    let (tx, rx) = mpsc::channel::<Message>();
    ensure_holidays(&mut app, &tx, today_in_app_tz().year());

    let mut session = TerminalSession::new()?;
    let result = run(&mut session.terminal, &mut app, &rx, &tx);
    drop(session);

    if let Err(error) = result {
        eprintln!("错误：{error}");
        return Err(error);
    }
    Ok(())
}

fn handle_meta_args() -> bool {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("--version" | "-V") => {
            println!("wts-tui {}", env!("CARGO_PKG_VERSION"));
            true
        }
        Some("--help" | "-h") => {
            println!("Where To Study TUI\n\n用法: wts-tui\n\n快捷键说明见 wts-tui/README.md");
            true
        }
        Some(argument) => {
            eprintln!("未知参数：{argument}。使用 --help 查看用法。");
            true
        }
        None => false,
    }
}

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
        .map(|credentials| {
            !credentials.account.trim().is_empty() && !credentials.password.is_empty()
        })
        .unwrap_or(false)
}

fn ensure_holidays(app: &mut App, tx: &mpsc::Sender<Message>, year: i32) {
    if !app.request_holidays_for(year) {
        return;
    }
    let tx = tx.clone();
    thread::spawn(move || {
        let result = match block_on(where_to_study_lib::holidays::fetch_remote(year)) {
            Ok(response) => Ok(response),
            Err(_) => where_to_study_lib::holidays::offline_response(year),
        };
        let _ = tx.send(Message::Holidays { year, result });
    });
}

fn run(
    terminal: &mut AppTerminal,
    app: &mut App,
    rx: &mpsc::Receiver<Message>,
    tx: &mpsc::Sender<Message>,
) -> io::Result<()> {
    loop {
        let theme = current_theme(app);
        terminal.draw(|frame| ui::draw(frame, app, &theme))?;

        if event::poll(Duration::from_millis(120))? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press && handle_key(app, key, tx) {
                    return Ok(());
                }
            }
            while event::poll(Duration::ZERO)? {
                if let Event::Key(key) = event::read()? {
                    if key.kind == KeyEventKind::Press && handle_key(app, key, tx) {
                        return Ok(());
                    }
                }
            }
        }

        while let Ok(message) = rx.try_recv() {
            match message {
                Message::Schedule { request_id, result } => {
                    if !app.finish_schedule_request(request_id) {
                        continue;
                    }
                    match result {
                        Ok(schedule) => {
                            app.schedule = Some(schedule);
                            app.set_status("课表已刷新".to_string());
                        }
                        Err(error) => app.set_error(error.message),
                    }
                }
                Message::Classrooms { request_id, result } => {
                    if !app.finish_classrooms_request(request_id) {
                        continue;
                    }
                    match result {
                        Ok(cache) => {
                            app.classrooms = Some(cache);
                            app.available_buildings = app.building_names();
                            app.select_all_buildings();
                            app.set_status("空教室已刷新".to_string());
                        }
                        Err(error) => app.set_error(error.message),
                    }
                }
                Message::Holidays { year, result } => match result {
                    Ok(response) => app.finish_holidays(year, Some(response)),
                    Err(error) => {
                        app.finish_holidays(year, None);
                        app.set_error(error.message);
                    }
                },
                Message::CredentialsSaved(result) => match result {
                    Ok(account) => {
                        app.invalidate_data_requests();
                        app.credentials_saved = true;
                        app.saved_account = account;
                        app.login_password.clear();
                        app.settings_editing = false;
                        app.set_status("凭据已保存".to_string());
                    }
                    Err(message) => app.set_error(message),
                },
                Message::CredentialsCleared(result) => match result {
                    Ok(()) => {
                        app.invalidate_data_requests();
                        app.credentials_saved = false;
                        app.saved_account.clear();
                        app.login_password.clear();
                        app.set_status("已退出登录".to_string());
                    }
                    Err(message) => app.set_error(message),
                },
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

fn handle_key(app: &mut App, key: KeyEvent, tx: &mpsc::Sender<Message>) -> bool {
    if app.selected_tab_index == 4 && app.settings_editing {
        return handle_settings_input(app, key, tx);
    }

    match key.code {
        KeyCode::Char('q') if key.modifiers.is_empty() => return true,
        KeyCode::Char('r') if key.modifiers.is_empty() => {
            app.clear_error();
            refresh_schedule(app, tx);
            if app.selected_tab_index == 2 {
                refresh_classrooms(app, tx);
            }
        }
        KeyCode::Char('l') if key.modifiers.is_empty() => login_with_form(app, tx),
        KeyCode::Char('o') if key.modifiers.is_empty() => clear_credentials(app, tx),
        KeyCode::Tab => {
            let next = (app.selected_tab_index + 1) % TAB_LABELS.len();
            switch_tab(app, next);
        }
        KeyCode::Char(ch) if app.selected_tab_index == 2 => {
            if let Some(slot) = slot_key_index(ch) {
                toggle_slot(app, slot);
            } else {
                match ch {
                    'a' => {
                        app.all_slots_selected = true;
                        app.selected_slots = (0..14).collect();
                        app.room_scroll = 0;
                    }
                    'c' => {
                        app.all_slots_selected = false;
                        app.selected_slots.clear();
                        app.room_scroll = 0;
                    }
                    _ => {}
                }
            }
        }
        KeyCode::Char(ch @ '1'..='5') => {
            switch_tab(app, ch.to_digit(10).unwrap_or(1) as usize - 1);
        }
        KeyCode::Char('e') if app.selected_tab_index == 4 => {
            app.settings_editing = true;
        }
        KeyCode::Enter if app.selected_tab_index == 4 => {
            app.settings_editing = true;
        }
        KeyCode::Char(' ') => match app.selected_tab_index {
            2 => app.toggle_current_building(),
            3 => {
                let today = today_in_app_tz();
                app.calendar_month =
                    chrono::NaiveDate::from_ymd_opt(today.year(), today.month(), 1)
                        .unwrap_or(today);
                ensure_holidays(app, tx, today.year());
            }
            _ => {}
        },
        KeyCode::Up => match app.selected_tab_index {
            2 => app.move_building_cursor(-1),
            4 => app.settings_focus = app.settings_focus.saturating_sub(1),
            _ => {}
        },
        KeyCode::Down => match app.selected_tab_index {
            2 => app.move_building_cursor(1),
            4 => app.settings_focus = (app.settings_focus + 1).min(1),
            _ => {}
        },
        KeyCode::PageUp if app.selected_tab_index == 2 => {
            app.room_scroll = app.room_scroll.saturating_sub(5);
        }
        KeyCode::PageDown if app.selected_tab_index == 2 => {
            app.room_scroll = app.room_scroll.saturating_add(5);
        }
        KeyCode::Left => match app.selected_tab_index {
            2 => switch_campus(app, "01"),
            3 => shift_calendar_month(app, tx, -1),
            _ => {}
        },
        KeyCode::Right => match app.selected_tab_index {
            2 => switch_campus(app, "04"),
            3 => shift_calendar_month(app, tx, 1),
            _ => {}
        },
        _ => {}
    }
    false
}

fn handle_settings_input(app: &mut App, key: KeyEvent, tx: &mpsc::Sender<Message>) -> bool {
    match key.code {
        KeyCode::Esc => app.settings_editing = false,
        KeyCode::Tab => app.settings_focus = (app.settings_focus + 1) % 2,
        KeyCode::Up => app.settings_focus = app.settings_focus.saturating_sub(1),
        KeyCode::Down => app.settings_focus = (app.settings_focus + 1).min(1),
        KeyCode::Enter if app.settings_focus == 0 => app.settings_focus = 1,
        KeyCode::Enter => login_with_form(app, tx),
        KeyCode::Backspace if app.settings_focus == 0 => {
            app.login_account.pop();
        }
        KeyCode::Backspace => {
            app.login_password.pop();
        }
        KeyCode::Char(ch) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
            if app.settings_focus == 0 {
                app.login_account.push(ch);
            } else {
                app.login_password.push(ch);
            }
        }
        _ => {}
    }
    false
}

fn slot_key_index(ch: char) -> Option<usize> {
    match ch {
        '1'..='9' => Some(ch.to_digit(10)? as usize - 1),
        '0' => Some(9),
        '-' => Some(10),
        '=' => Some(11),
        '[' => Some(12),
        ']' => Some(13),
        _ => None,
    }
}

fn switch_campus(app: &mut App, campus_id: &str) {
    if app.campus_id == campus_id {
        return;
    }
    app.campus_id = campus_id.to_string();
    app.available_buildings = app.building_names();
    app.building_cursor = 0;
    app.select_all_buildings();
}

fn shift_calendar_month(app: &mut App, tx: &mpsc::Sender<Message>, delta: i32) {
    let month = app.calendar_month;
    let zero_based = month.year() * 12 + month.month0() as i32 + delta;
    let year = zero_based.div_euclid(12);
    let month_number = zero_based.rem_euclid(12) as u32 + 1;
    if let Some(next) = chrono::NaiveDate::from_ymd_opt(year, month_number, 1) {
        app.calendar_month = next;
        ensure_holidays(app, tx, year);
    }
}

fn toggle_slot(app: &mut App, slot: usize) {
    app.all_slots_selected = false;
    if let Some(index) = app
        .selected_slots
        .iter()
        .position(|selected| *selected == slot)
    {
        app.selected_slots.remove(index);
    } else {
        app.selected_slots.push(slot);
        app.selected_slots.sort_unstable();
    }
    if app.selected_slots.len() == 14 {
        app.all_slots_selected = true;
    }
    app.room_scroll = 0;
}

fn login_with_form(app: &mut App, tx: &mpsc::Sender<Message>) {
    let account = app.login_account.trim().to_string();
    if account.is_empty() {
        app.set_error("请输入账号。".to_string());
        return;
    }
    if app.login_password.is_empty() {
        app.set_error("请输入密码。".to_string());
        return;
    }

    let password = Zeroizing::new(std::mem::take(&mut *app.login_password));
    app.settings_editing = false;
    let tx = tx.clone();
    thread::spawn(move || {
        let result = save_credentials(account, password).map_err(|error| error.message);
        let _ = tx.send(Message::CredentialsSaved(result));
    });
}

fn save_credentials(account: String, mut password: Zeroizing<String>) -> ServiceResult<String> {
    let existing = where_to_study_lib::credential_store::load()?;
    let account_scope = existing
        .as_ref()
        .filter(|credentials| credentials.account.trim() == account)
        .map(|credentials| credentials.account_scope.as_str())
        .filter(|scope| where_to_study_lib::scoped_cache::is_valid_account_scope(scope))
        .map(str::to_string)
        .map(Ok)
        .unwrap_or_else(where_to_study_lib::scoped_cache::new_account_scope)?;

    let mut credentials = where_to_study_lib::credential_store::Credentials {
        account: account.clone(),
        password: std::mem::take(&mut *password),
        account_scope,
    };
    let result = where_to_study_lib::credential_store::save(&credentials);
    credentials.password.zeroize();
    result?;
    Ok(account)
}

fn clear_credentials(app: &mut App, tx: &mpsc::Sender<Message>) {
    app.settings_editing = false;
    let tx = tx.clone();
    thread::spawn(move || {
        let result = where_to_study_lib::credential_store::save(
            &where_to_study_lib::credential_store::Credentials::default(),
        )
        .map_err(|error| error.message);
        let _ = tx.send(Message::CredentialsCleared(result));
    });
}

fn refresh_schedule(app: &mut App, tx: &mpsc::Sender<Message>) {
    let credentials = match require_credentials() {
        Ok(credentials) => credentials,
        Err(error) => {
            app.set_error(error.message);
            return;
        }
    };
    let request_id = app.start_schedule_request();
    let tx = tx.clone();
    thread::spawn(move || {
        let mut credentials = credentials;
        let mut request = where_to_study_lib::models::ScheduleRequest {
            account: Some(std::mem::take(&mut credentials.account)),
            password: Some(std::mem::take(&mut credentials.password)),
            term_id: None,
            term_start_date: None,
        };
        let result = block_on(where_to_study_lib::schedule::fetch_schedule(&request));
        if let Some(password) = request.password.as_mut() {
            password.zeroize();
        }
        let _ = tx.send(Message::Schedule { request_id, result });
    });
}

fn refresh_classrooms(app: &mut App, tx: &mpsc::Sender<Message>) {
    let credentials = match require_credentials() {
        Ok(credentials) => credentials,
        Err(error) => {
            app.set_error(error.message);
            return;
        }
    };
    let request_id = app.start_classrooms_request();
    let campus_id = app.campus_id.clone();
    let tx = tx.clone();
    thread::spawn(move || {
        let mut credentials = credentials;
        let mut request = where_to_study_lib::models::ClassroomsRequest {
            account: Some(std::mem::take(&mut credentials.account)),
            password: Some(std::mem::take(&mut credentials.password)),
            campus_id: Some(campus_id),
            target_date: Some(today_in_app_tz().format("%Y-%m-%d").to_string()),
        };
        let result = block_on(where_to_study_lib::classrooms::fetch_all_classrooms(
            &request,
        ));
        if let Some(password) = request.password.as_mut() {
            password.zeroize();
        }
        let _ = tx.send(Message::Classrooms { request_id, result });
    });
}

fn require_credentials() -> ServiceResult<where_to_study_lib::credential_store::Credentials> {
    let Some(credentials) = where_to_study_lib::credential_store::load()? else {
        return Err(ServiceError::new(
            "尚未保存凭据，请先在设置页输入账号和密码。",
        ));
    };
    if credentials.account.trim().is_empty() || credentials.password.is_empty() {
        return Err(ServiceError::new(
            "已保存的凭据不完整，请在设置页重新输入。",
        ));
    }
    Ok(credentials)
}

fn switch_tab(app: &mut App, index: usize) {
    app.settings_editing = false;
    app.selected_tab_index = index;
    app.tab = match index {
        0 => Tab::Home,
        1 => Tab::Schedule,
        2 => Tab::Planner,
        3 => Tab::Calendar,
        _ => Tab::Settings,
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn settings_input_does_not_trigger_global_shortcuts() {
        let (tx, _rx) = mpsc::channel();
        let mut app = App::new(false);
        switch_tab(&mut app, 4);
        app.settings_editing = true;
        assert!(!handle_key(&mut app, key(KeyCode::Char('q')), &tx));
        assert_eq!(app.login_account, "q");
        assert!(!handle_key(&mut app, key(KeyCode::Char('o')), &tx));
        assert_eq!(app.login_account, "qo");
    }

    #[test]
    fn all_fourteen_slot_shortcuts_are_reachable() {
        let keys = [
            '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '[', ']',
        ];
        let slots: Vec<usize> = keys.into_iter().filter_map(slot_key_index).collect();
        assert_eq!(slots, (0..14).collect::<Vec<_>>());
    }

    #[test]
    fn month_shift_crosses_year_boundary() {
        let (tx, _rx) = mpsc::channel();
        let mut app = App::new(false);
        app.calendar_month = chrono::NaiveDate::from_ymd_opt(2026, 1, 1).unwrap();
        shift_calendar_month(&mut app, &tx, -1);
        assert_eq!(
            app.calendar_month,
            chrono::NaiveDate::from_ymd_opt(2025, 12, 1).unwrap()
        );
        assert!(app.holiday_requests.contains(&2025));
    }
}
