mod auth;
mod calendar_export;
mod classrooms;
mod config;
mod error;
mod models;
mod recommender;
mod schedule;
mod schedule_store;
mod settings_store;

use chrono::{Duration as ChronoDuration, NaiveDate};
#[cfg(not(mobile))]
use tauri::image::Image;
#[cfg(not(mobile))]
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
#[cfg(not(mobile))]
use tauri::tray::TrayIconBuilder;
#[cfg(not(mobile))]
use tauri::{Emitter, Manager};

use crate::models::{
    ClassroomsRequest, ClassroomsResponse, MetadataResponse, RecommendationRequest,
    RecommendationResponse, SavedSettings, ScheduleRequest, ScheduleResponse,
};

#[tauri::command]
fn get_metadata() -> MetadataResponse {
    MetadataResponse {
        campuses: config::campuses_payload(),
        slots: config::slot_payload(),
        default_term_id: config::default_term_id(),
        default_term_start_date: config::default_term_start_date(),
    }
}

#[tauri::command]
fn load_saved_settings(app: tauri::AppHandle) -> Result<SavedSettings, String> {
    settings_store::load(&app).map_err(|error| error.message)
}

#[tauri::command]
fn save_saved_settings(
    app: tauri::AppHandle,
    payload: SavedSettings,
) -> Result<SavedSettings, String> {
    settings_store::save(&app, payload).map_err(|error| error.message)
}

#[tauri::command]
fn load_saved_schedule(app: tauri::AppHandle) -> Result<Option<ScheduleResponse>, String> {
    schedule_store::load(&app).map_err(|error| error.message)
}

#[tauri::command]
async fn fetch_schedule(
    app: tauri::AppHandle,
    payload: ScheduleRequest,
) -> Result<ScheduleResponse, String> {
    let schedule = schedule::fetch_schedule(&payload)
        .await
        .map_err(|error| error.message)?;
    schedule_store::save(&app, &schedule).map_err(|error| error.message)?;
    Ok(schedule)
}

#[tauri::command]
fn import_schedule_to_calendar(app: tauri::AppHandle) -> Result<String, String> {
    let Some(schedule) = schedule_store::load(&app).map_err(|error| error.message)? else {
        return Err("请先获取个人课表，获取成功后会自动保存到本地。".to_string());
    };
    calendar_export::export_and_open(&app, &schedule)
        .map(|path| path.to_string_lossy().to_string())
        .map_err(|error| error.message)
}

#[tauri::command]
async fn fetch_classrooms(payload: ClassroomsRequest) -> Result<ClassroomsResponse, String> {
    classrooms::fetch_classrooms(&payload)
        .await
        .map_err(|error| error.message)
}

#[tauri::command]
async fn fetch_recommendations(
    app: tauri::AppHandle,
    payload: RecommendationRequest,
) -> Result<RecommendationResponse, String> {
    let schedule_request = ScheduleRequest {
        account: payload.account.clone(),
        password: payload.password.clone(),
        term_id: payload.term_id.clone(),
        term_start_date: payload.term_start_date.clone(),
    };
    let classrooms_request = ClassroomsRequest {
        account: payload.account.clone(),
        password: payload.password.clone(),
        campus_id: payload.campus_id.clone(),
        target_date: payload.target_date.clone(),
    };

    let schedule = schedule::fetch_schedule(&schedule_request)
        .await
        .map_err(|error| error.message)?;
    schedule_store::save(&app, &schedule).map_err(|error| error.message)?;
    let classrooms = classrooms::fetch_classrooms(&classrooms_request)
        .await
        .map_err(|error| error.message)?;

    let term_start_date = NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d")
        .map_err(|_| "第一周周一日期格式不正确。".to_string())?;
    let target_date = recommender::parse_optional_date(payload.target_date.as_deref(), "查询日期")
        .map_err(|error| error.message)?;

    Ok(recommender::recommend(
        &schedule.courses,
        term_start_date,
        classrooms,
        target_date,
        payload.selected_slots,
        payload.buildings,
        payload.min_seats,
        payload.use_schedule_filter,
    ))
}

#[cfg(not(mobile))]
fn show_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

#[cfg(not(mobile))]
enum TrayCourseContent {
    Loading,
    Message(String),
    Courses {
        today: TrayDayCourses,
        tomorrow: TrayDayCourses,
    },
}

#[cfg(not(mobile))]
struct TrayDayCourses {
    label: String,
    date: String,
    week_number: i64,
    courses: Vec<String>,
}

#[cfg(not(mobile))]
fn non_empty_option(value: String) -> Option<String> {
    let trimmed = value.trim().to_string();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

#[cfg(not(mobile))]
fn truncate_menu_label(value: String, limit: usize) -> String {
    let mut output = String::new();
    for (index, character) in value.chars().enumerate() {
        if index >= limit {
            output.push('…');
            return output;
        }
        output.push(character);
    }
    output
}

#[cfg(not(mobile))]
fn course_time_label(course: &crate::models::Course) -> String {
    if !course.time_range.trim().is_empty() {
        return course.time_range.clone();
    }
    let start = config::SLOT_TIMES
        .get(course.start_slot)
        .map(|slot| slot.0)
        .unwrap_or("--:--");
    let end = config::SLOT_TIMES
        .get(course.end_slot)
        .map(|slot| slot.1)
        .unwrap_or("--:--");
    format!("{start}-{end}")
}

#[cfg(not(mobile))]
fn format_course_menu_line(course: &crate::models::Course) -> String {
    let room = if course.room.trim().is_empty() {
        "地点未标注".to_string()
    } else {
        course.room.clone()
    };
    truncate_menu_label(
        format!("{}  {}  @ {}", course_time_label(course), course.name, room),
        42,
    )
}

#[cfg(not(mobile))]
fn append_menu_item<M: Manager<tauri::Wry>>(
    menu: &Menu<tauri::Wry>,
    app: &M,
    id: impl Into<String>,
    text: impl AsRef<str>,
    enabled: bool,
) -> tauri::Result<()> {
    let item = MenuItem::with_id(app, id.into(), text, enabled, None::<&str>)?;
    menu.append(&item)
}

#[cfg(not(mobile))]
fn append_separator<M: Manager<tauri::Wry>>(menu: &Menu<tauri::Wry>, app: &M) -> tauri::Result<()> {
    let separator = PredefinedMenuItem::separator(app)?;
    menu.append(&separator)
}

#[cfg(not(mobile))]
fn append_course_section<M: Manager<tauri::Wry>>(
    menu: &Menu<tauri::Wry>,
    app: &M,
    id_prefix: &str,
    day: &TrayDayCourses,
) -> tauri::Result<()> {
    append_menu_item(
        menu,
        app,
        format!("{id_prefix}_title"),
        format!(
            "{}课程 · {} · 第 {} 周",
            day.label, day.date, day.week_number
        ),
        true,
    )?;
    if day.courses.is_empty() {
        append_menu_item(
            menu,
            app,
            format!("{id_prefix}_empty"),
            format!("{}暂无课程", day.label),
            true,
        )?;
    } else {
        for (index, course) in day.courses.iter().enumerate() {
            append_menu_item(
                menu,
                app,
                format!("{id_prefix}_course_{index}"),
                course,
                true,
            )?;
        }
    }
    Ok(())
}

#[cfg(not(mobile))]
fn build_tray_menu<M: Manager<tauri::Wry>>(
    app: &M,
    content: TrayCourseContent,
) -> tauri::Result<Menu<tauri::Wry>> {
    let menu = Menu::new(app)?;
    append_menu_item(&menu, app, "tray_title", "Where To Study", true)?;
    append_menu_item(
        &menu,
        app,
        "tray_status",
        "空教室、教学日历与本地账号设置",
        true,
    )?;
    append_separator(&menu, app)?;

    match &content {
        TrayCourseContent::Loading => {
            append_menu_item(&menu, app, "loading_title", "课程 · 正在更新", false)?;
            append_menu_item(
                &menu,
                app,
                "loading_message",
                "正在读取本地账号并获取课表…",
                false,
            )?;
        }
        TrayCourseContent::Message(message) => {
            append_menu_item(&menu, app, "course_message_title", "课程", true)?;
            append_menu_item(
                &menu,
                app,
                "course_message",
                truncate_menu_label(message.clone(), 42),
                true,
            )?;
        }
        TrayCourseContent::Courses { today, tomorrow } => {
            append_course_section(&menu, app, "today", today)?;
            append_separator(&menu, app)?;
            append_course_section(&menu, app, "tomorrow", tomorrow)?;
        }
    }

    append_separator(&menu, app)?;
    let open = MenuItem::with_id(app, "open", "打开主窗口", true, None::<&str>)?;
    let planner = MenuItem::with_id(app, "planner", "查看空教室", true, None::<&str>)?;
    let calendar = MenuItem::with_id(app, "calendar", "教学日历", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "设置", true, Some("CmdOrCtrl+,"))?;
    let refresh = MenuItem::with_id(app, "refresh_today", "刷新课程", true, Some("CmdOrCtrl+R"))?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, Some("CmdOrCtrl+Q"))?;
    menu.append_items(&[&open, &planner, &calendar, &settings])?;
    append_separator(&menu, app)?;
    menu.append_items(&[&refresh, &quit])?;
    Ok(menu)
}

#[cfg(not(mobile))]
fn build_tray_day_courses(
    label: &str,
    courses: &[crate::models::Course],
    target_date: NaiveDate,
    term_start_date: NaiveDate,
) -> TrayDayCourses {
    let state = recommender::date_state(courses, target_date, term_start_date);
    TrayDayCourses {
        label: label.to_string(),
        date: target_date.to_string(),
        week_number: state.week_number,
        courses: state.courses.iter().map(format_course_menu_line).collect(),
    }
}

#[cfg(not(mobile))]
async fn load_today_course_content(
    app: tauri::AppHandle,
    prefer_saved_schedule: bool,
) -> TrayCourseContent {
    if prefer_saved_schedule {
        match schedule_store::load(&app) {
            Ok(Some(schedule)) => return schedule_to_tray_content(schedule),
            Ok(None) => {}
            Err(error) => return TrayCourseContent::Message(error.message),
        }
    }

    let settings = match settings_store::load(&app) {
        Ok(settings) => settings,
        Err(error) => return TrayCourseContent::Message(error.message),
    };
    let request = ScheduleRequest {
        account: non_empty_option(settings.account),
        password: non_empty_option(settings.password),
        term_id: non_empty_option(settings.term_id),
        term_start_date: non_empty_option(settings.term_start_date),
    };
    let schedule = match schedule::fetch_schedule(&request).await {
        Ok(schedule) => {
            let _ = schedule_store::save(&app, &schedule);
            schedule
        }
        Err(error) => return TrayCourseContent::Message(error.message),
    };
    schedule_to_tray_content(schedule)
}

#[cfg(not(mobile))]
fn schedule_to_tray_content(schedule: ScheduleResponse) -> TrayCourseContent {
    let term_start_date = match NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d") {
        Ok(date) => date,
        Err(_) => {
            return TrayCourseContent::Message("第一周周一日期格式不正确。".to_string());
        }
    };
    let today_date = config::today_in_app_tz();
    let tomorrow_date = today_date + ChronoDuration::days(1);
    TrayCourseContent::Courses {
        today: build_tray_day_courses("今日", &schedule.courses, today_date, term_start_date),
        tomorrow: build_tray_day_courses("明日", &schedule.courses, tomorrow_date, term_start_date),
    }
}

#[cfg(not(mobile))]
fn set_tray_menu(app: &tauri::AppHandle, content: TrayCourseContent) -> tauri::Result<()> {
    if let Some(tray) = app.tray_by_id("where-to-study-tray") {
        let menu = build_tray_menu(app, content)?;
        tray.set_menu(Some(menu))?;
    }
    Ok(())
}

#[cfg(not(mobile))]
fn refresh_tray_courses(app: tauri::AppHandle, prefer_saved_schedule: bool) {
    let _ = set_tray_menu(&app, TrayCourseContent::Loading);
    tauri::async_runtime::spawn(async move {
        let content = load_today_course_content(app.clone(), prefer_saved_schedule).await;
        let _ = set_tray_menu(&app, content);
    });
}

#[cfg(not(mobile))]
fn setup_tray(app: &mut tauri::App) -> tauri::Result<()> {
    let menu = build_tray_menu(app, TrayCourseContent::Loading)?;

    let mut tray = TrayIconBuilder::with_id("where-to-study-tray")
        .tooltip("Where To Study")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" | "tray_title" | "tray_status" => show_main_window(app),
            "planner" => {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "planner");
            }
            id if id == "calendar"
                || id == "course_message_title"
                || id == "course_message"
                || id.starts_with("today_")
                || id.starts_with("tomorrow_") =>
            {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "calendar");
            }
            "settings" => {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "settings");
            }
            "refresh_today" => refresh_tray_courses(app.clone(), false),
            "quit" => app.exit(0),
            _ => {}
        });

    if let Ok(icon) = Image::from_bytes(include_bytes!("../icons/tray-icon.png")) {
        tray = tray.icon(icon).icon_as_template(true);
    } else if let Some(icon) = app.default_window_icon().cloned() {
        tray = tray.icon(icon).icon_as_template(false);
    }
    tray.build(app)?;
    refresh_tray_courses(app.app_handle().clone(), true);
    Ok(())
}

#[cfg(not(mobile))]
fn keep_main_window_in_tray(window: &tauri::Window, event: &tauri::WindowEvent) {
    if window.label() != "main" {
        return;
    }
    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
        api.prevent_close();
        let _ = window.hide();
    }
}

fn setup_app(app: &mut tauri::App) -> tauri::Result<()> {
    #[cfg(not(mobile))]
    setup_tray(app)?;

    #[cfg(mobile)]
    let _ = app;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            setup_app(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            #[cfg(not(mobile))]
            keep_main_window_in_tray(window, event);

            #[cfg(mobile)]
            let _ = (window, event);
        })
        .invoke_handler(tauri::generate_handler![
            get_metadata,
            load_saved_settings,
            save_saved_settings,
            load_saved_schedule,
            fetch_schedule,
            import_schedule_to_calendar,
            fetch_classrooms,
            fetch_recommendations
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
