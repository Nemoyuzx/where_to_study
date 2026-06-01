mod auth;
mod classrooms;
mod config;
mod error;
mod models;
mod recommender;
mod schedule;
mod settings_store;

use chrono::NaiveDate;
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
async fn fetch_schedule(payload: ScheduleRequest) -> Result<ScheduleResponse, String> {
    schedule::fetch_schedule(&payload)
        .await
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
fn setup_tray(app: &mut tauri::App) -> tauri::Result<()> {
    let title = MenuItem::with_id(app, "tray_title", "Where To Study", false, None::<&str>)?;
    let status = MenuItem::with_id(
        app,
        "tray_status",
        "空教室、教学日历与本地账号设置",
        false,
        None::<&str>,
    )?;
    let open = MenuItem::with_id(app, "open", "打开主窗口", true, None::<&str>)?;
    let planner = MenuItem::with_id(app, "planner", "查看空教室", true, None::<&str>)?;
    let calendar = MenuItem::with_id(app, "calendar", "教学日历", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "设置", true, Some("CmdOrCtrl+,"))?;
    let refresh = MenuItem::with_id(app, "refresh", "刷新当前页面", true, Some("CmdOrCtrl+R"))?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, Some("CmdOrCtrl+Q"))?;
    let first_separator = PredefinedMenuItem::separator(app)?;
    let second_separator = PredefinedMenuItem::separator(app)?;
    let menu = Menu::with_items(
        app,
        &[
            &title,
            &status,
            &first_separator,
            &open,
            &planner,
            &calendar,
            &settings,
            &second_separator,
            &refresh,
            &quit,
        ],
    )?;

    let mut tray = TrayIconBuilder::with_id("where-to-study-tray")
        .tooltip("Where To Study")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" => show_main_window(app),
            "planner" => {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "planner");
            }
            "calendar" => {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "calendar");
            }
            "settings" => {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "settings");
            }
            "refresh" => {
                if let Some(window) = app.get_webview_window("main") {
                    let _ = window.eval("window.location.reload()");
                }
            }
            "quit" => app.exit(0),
            _ => {}
        });

    if let Some(icon) = app.default_window_icon().cloned() {
        tray = tray.icon(icon).icon_as_template(true);
    }
    tray.build(app)?;
    Ok(())
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
        .invoke_handler(tauri::generate_handler![
            get_metadata,
            load_saved_settings,
            save_saved_settings,
            fetch_schedule,
            fetch_classrooms,
            fetch_recommendations
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
