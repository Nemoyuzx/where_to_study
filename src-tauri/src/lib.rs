mod auth;
mod calendar_export;
mod classrooms;
mod classrooms_store;
mod config;
mod credential_store;
mod error;
mod holidays;
mod models;
#[cfg(not(mobile))]
mod recommender;
mod schedule;
mod schedule_store;
mod settings_store;

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;

#[cfg(not(mobile))]
use std::time::Duration;

#[cfg(not(mobile))]
use chrono::{Duration as ChronoDuration, NaiveDate, NaiveDateTime, NaiveTime};
#[cfg(not(mobile))]
use tauri::image::Image;
#[cfg(not(mobile))]
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
#[cfg(not(mobile))]
use tauri::tray::TrayIconBuilder;
#[cfg(not(mobile))]
use tauri::Emitter;
use tauri::Manager;
#[cfg(not(mobile))]
use tauri_plugin_notification::NotificationExt;

use crate::models::{
    ClassroomsCacheResponse, ClassroomsRequest, HolidaysRequest, HolidaysResponse,
    MetadataResponse, SaveSettingsRequest, SavedSettings, ScheduleRequest, ScheduleResponse,
};

const STALE_LOCAL_DATA_MESSAGE: &str = "本地数据已清除，本次后台结果未保存。";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct LocalDataGeneration(u64);

#[derive(Debug, PartialEq, Eq)]
enum LocalDataAccessError {
    Stale,
    Operation(String),
}

impl LocalDataAccessError {
    fn message(self) -> String {
        match self {
            Self::Stale => STALE_LOCAL_DATA_MESSAGE.to_string(),
            Self::Operation(message) => message,
        }
    }
}

struct LocalDataCoordinator {
    generation: AtomicU64,
    io_lock: Mutex<()>,
}

impl LocalDataCoordinator {
    const fn new() -> Self {
        Self {
            generation: AtomicU64::new(0),
            io_lock: Mutex::new(()),
        }
    }

    fn begin(&self) -> LocalDataGeneration {
        LocalDataGeneration(self.generation.load(Ordering::Acquire))
    }

    fn with_current<T>(
        &self,
        expected: LocalDataGeneration,
        operation: impl FnOnce() -> Result<T, String>,
    ) -> Result<T, LocalDataAccessError> {
        let _guard = self
            .io_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.generation.load(Ordering::Acquire) != expected.0 {
            return Err(LocalDataAccessError::Stale);
        }
        operation().map_err(LocalDataAccessError::Operation)
    }

    fn clear<T>(&self, operation: impl FnOnce() -> Result<T, String>) -> Result<T, String> {
        let _guard = self
            .io_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.generation.fetch_add(1, Ordering::AcqRel);
        operation()
    }
}

static LOCAL_DATA: LocalDataCoordinator = LocalDataCoordinator::new();

#[cfg(test)]
mod local_data_coordination_tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::AtomicUsize;
    use std::sync::{mpsc, Arc};
    use std::thread;

    #[test]
    fn clear_after_write_removes_disk_and_memory_results() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("cache.json");
        let coordinator = Arc::new(LocalDataCoordinator::new());
        let memory_value = Arc::new(AtomicUsize::new(0));
        let generation = coordinator.begin();
        let (write_started_tx, write_started_rx) = mpsc::channel();
        let (release_write_tx, release_write_rx) = mpsc::channel();

        let writer = {
            let coordinator = Arc::clone(&coordinator);
            let path = path.clone();
            let memory_value = Arc::clone(&memory_value);
            thread::spawn(move || {
                coordinator.with_current(generation, || {
                    fs::write(&path, b"old result").map_err(|error| error.to_string())?;
                    memory_value.store(1, Ordering::Release);
                    write_started_tx.send(()).expect("signal write start");
                    release_write_rx.recv().expect("release write");
                    Ok(())
                })
            })
        };

        write_started_rx.recv().expect("wait for active write");
        let clearer = {
            let coordinator = Arc::clone(&coordinator);
            let path = path.clone();
            let memory_value = Arc::clone(&memory_value);
            thread::spawn(move || {
                coordinator.clear(|| {
                    if path.exists() {
                        fs::remove_file(&path).map_err(|error| error.to_string())?;
                    }
                    memory_value.store(0, Ordering::Release);
                    Ok(())
                })
            })
        };

        release_write_tx.send(()).expect("finish write");
        assert_eq!(writer.join().expect("join writer"), Ok(()));
        assert_eq!(clearer.join().expect("join clearer"), Ok(()));
        assert!(!path.exists());
        assert_eq!(memory_value.load(Ordering::Acquire), 0);
    }

    #[test]
    fn clear_before_write_rejects_stale_disk_and_memory_results() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("cache.json");
        let coordinator = LocalDataCoordinator::new();
        let memory_value = AtomicUsize::new(0);
        let generation = coordinator.begin();

        coordinator
            .clear(|| {
                memory_value.store(0, Ordering::Release);
                Ok(())
            })
            .expect("clear local data");
        let result = coordinator.with_current(generation, || {
            fs::write(&path, b"stale result").map_err(|error| error.to_string())?;
            memory_value.store(1, Ordering::Release);
            Ok(())
        });

        assert_eq!(result, Err(LocalDataAccessError::Stale));
        assert!(!path.exists());
        assert_eq!(memory_value.load(Ordering::Acquire), 0);
    }

    #[test]
    fn clear_before_remote_holiday_result_rejects_cache_save() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("holidays_2026.json");
        let coordinator = LocalDataCoordinator::new();
        let generation = coordinator.begin();
        let response = HolidaysResponse {
            year: 2026,
            source: "https://example.invalid/holidays".to_string(),
            fetched_at: "2026-08-04T08:00:00+08:00".to_string(),
            items: Vec::new(),
        };

        coordinator.clear(|| Ok(())).expect("clear local data");
        let result = coordinator.with_current(generation, || {
            holidays::save_cache_to_path(&path, &response).map_err(|error| error.message)
        });

        assert_eq!(result, Err(LocalDataAccessError::Stale));
        assert!(!path.exists());
    }
}

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
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current(generation, || {
            settings_store::load(&app).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
fn save_saved_settings(
    app: tauri::AppHandle,
    payload: SaveSettingsRequest,
) -> Result<SavedSettings, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current(generation, || {
            settings_store::save(&app, payload).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
fn clear_local_data(app: tauri::AppHandle) -> Result<bool, String> {
    LOCAL_DATA.clear(|| {
        let mut errors = Vec::new();
        if let Err(error) = credential_store::save(&credential_store::Credentials::default()) {
            errors.push(error.message);
        }

        match app.path().app_config_dir() {
            Ok(directory) if directory.exists() => {
                if let Err(error) = std::fs::remove_dir_all(&directory) {
                    errors.push(format!("无法清除本地缓存与设置：{error}"));
                }
            }
            Ok(_) => {}
            Err(error) => errors.push(format!("无法定位本地数据目录：{error}")),
        }

        #[cfg(not(mobile))]
        if let Err(error) = set_tray_menu(
            &app,
            TrayCourseContent::Message("暂无本地课表，请先获取/刷新个人课表。".to_string()),
        ) {
            errors.push(format!("无法重置托盘课程信息：{error}"));
        }

        if errors.is_empty() {
            Ok(true)
        } else {
            Err(errors.join("；"))
        }
    })
}

#[tauri::command]
fn load_saved_schedule(app: tauri::AppHandle) -> Result<Option<ScheduleResponse>, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current(generation, || {
            schedule_store::load(&app).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
fn load_saved_classrooms(app: tauri::AppHandle) -> Result<Option<ClassroomsCacheResponse>, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current(generation, || {
            classrooms_store::load(&app).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
async fn fetch_schedule(
    app: tauri::AppHandle,
    mut payload: ScheduleRequest,
) -> Result<ScheduleResponse, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current(generation, || {
            settings_store::apply_saved_credentials(&mut payload.account, &mut payload.password)
                .map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)?;
    let schedule = schedule::fetch_schedule(&payload)
        .await
        .map_err(|error| error.message)?;
    LOCAL_DATA
        .with_current(generation, || {
            schedule_store::save(&app, &schedule).map_err(|error| error.message)?;
            #[cfg(not(mobile))]
            let _ = app.emit("schedule:updated", schedule.clone());
            Ok(())
        })
        .map_err(LocalDataAccessError::message)?;
    Ok(schedule)
}

#[tauri::command]
fn import_schedule_to_calendar(app: tauri::AppHandle) -> Result<String, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current(generation, || {
            let Some(schedule) = schedule_store::load(&app).map_err(|error| error.message)? else {
                return Err("请先获取/刷新个人课表，获取成功后会自动保存到本地。".to_string());
            };
            calendar_export::export_and_open(&app, &schedule)
                .map(|path| path.to_string_lossy().to_string())
                .map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
async fn fetch_classrooms(
    app: tauri::AppHandle,
    mut payload: ClassroomsRequest,
) -> Result<ClassroomsCacheResponse, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current(generation, || {
            settings_store::apply_saved_credentials(&mut payload.account, &mut payload.password)
                .map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)?;
    payload.target_date = Some(config::today_in_app_tz().to_string());
    let classrooms = classrooms::fetch_all_classrooms(&payload)
        .await
        .map_err(|error| error.message)?;
    LOCAL_DATA
        .with_current(generation, || {
            classrooms_store::save(&app, &classrooms).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)?;
    Ok(classrooms)
}

#[tauri::command]
async fn fetch_holidays(
    app: tauri::AppHandle,
    payload: HolidaysRequest,
) -> Result<HolidaysResponse, String> {
    holidays::validate_fetch_year(payload.year).map_err(|error| error.message)?;
    let generation = LOCAL_DATA.begin();

    match holidays::fetch_remote(payload.year).await {
        Ok(response) => {
            LOCAL_DATA
                .with_current(generation, || {
                    holidays::save_cache(&app, &response).map_err(|error| error.message)
                })
                .map_err(LocalDataAccessError::message)?;
            Ok(response)
        }
        Err(_) => {
            let cached = LOCAL_DATA
                .with_current(generation, || {
                    Ok(holidays::load_cache(&app, payload.year).ok().flatten())
                })
                .map_err(LocalDataAccessError::message)?;
            if let Some(cached) = cached {
                return Ok(cached);
            }

            LOCAL_DATA
                .with_current(generation, || {
                    holidays::offline_response(payload.year).map_err(|error| error.message)
                })
                .map_err(LocalDataAccessError::message)
        }
    }
}

#[tauri::command]
async fn show_desktop_widget(app: tauri::AppHandle) -> Result<bool, String> {
    #[cfg(not(mobile))]
    {
        show_course_widget(&app).map_err(|error| error.to_string())?;
        Ok(true)
    }

    #[cfg(mobile)]
    {
        let _ = app;
        Err("桌面课程小组件仅支持 macOS、Windows 和 Linux。".to_string())
    }
}

#[tauri::command]
async fn hide_desktop_widget(app: tauri::AppHandle) -> Result<bool, String> {
    #[cfg(not(mobile))]
    {
        if let Some(window) = app.get_webview_window("course-widget") {
            window.close().map_err(|error| error.to_string())?;
        }
        Ok(true)
    }

    #[cfg(mobile)]
    {
        let _ = app;
        Err("桌面课程小组件仅支持 macOS、Windows 和 Linux。".to_string())
    }
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
fn show_course_widget(app: &tauri::AppHandle) -> tauri::Result<()> {
    if let Some(window) = app.get_webview_window("course-widget") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
        return Ok(());
    }

    let window = tauri::WebviewWindowBuilder::new(
        app,
        "course-widget",
        tauri::WebviewUrl::App("index.html?widget=course".into()),
    )
    .title("今日课程")
    .inner_size(320.0, 420.0)
    .min_inner_size(280.0, 320.0)
    .max_inner_size(420.0, 620.0)
    .position(24.0, 80.0)
    .decorations(false)
    .resizable(false)
    .always_on_top(true)
    .visible_on_all_workspaces(true)
    .focused(false)
    .shadow(true)
    .build()?;
    let _ = window.show();
    Ok(())
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
fn classrooms_request_from_settings(settings: SavedSettings) -> ClassroomsRequest {
    ClassroomsRequest {
        account: non_empty_option(settings.account),
        password: None,
        campus_id: None,
        target_date: Some(config::today_in_app_tz().to_string()),
    }
}

#[cfg(not(mobile))]
#[derive(Debug, PartialEq, Eq)]
enum ScheduledClassroomRefreshError {
    MissingCredentials(String),
    Cancelled,
    Retryable(String),
}

#[cfg(not(mobile))]
impl ScheduledClassroomRefreshError {
    fn from_local_data(error: LocalDataAccessError) -> Self {
        match error {
            LocalDataAccessError::Stale => Self::Cancelled,
            LocalDataAccessError::Operation(message) => Self::Retryable(message),
        }
    }

    fn message(&self) -> Option<&str> {
        match self {
            Self::MissingCredentials(message) | Self::Retryable(message) => Some(message),
            Self::Cancelled => None,
        }
    }

    fn task_outcome(&self) -> DesktopTaskOutcome {
        match self {
            Self::Retryable(_) => DesktopTaskOutcome::RetryableFailure,
            Self::MissingCredentials(_) | Self::Cancelled => DesktopTaskOutcome::PermanentFailure,
        }
    }
}

#[cfg(not(mobile))]
async fn fetch_today_classrooms_from_saved_settings(
    app: tauri::AppHandle,
) -> Result<ClassroomsCacheResponse, ScheduledClassroomRefreshError> {
    let generation = LOCAL_DATA.begin();
    let request = LOCAL_DATA
        .with_current(generation, || {
            let settings = settings_store::load(&app).map_err(|error| error.message)?;
            let mut request = classrooms_request_from_settings(settings);
            settings_store::apply_saved_credentials(&mut request.account, &mut request.password)
                .map_err(|error| error.message)?;
            Ok(request)
        })
        .map_err(ScheduledClassroomRefreshError::from_local_data)?;
    auth::resolve_credentials(&request.account, &request.password)
        .map_err(|error| ScheduledClassroomRefreshError::MissingCredentials(error.message))?;
    let classrooms = classrooms::fetch_all_classrooms(&request)
        .await
        .map_err(|error| ScheduledClassroomRefreshError::Retryable(error.message))?;
    LOCAL_DATA
        .with_current(generation, || {
            classrooms_store::save(&app, &classrooms).map_err(|error| error.message)?;
            let _ = app.emit("classrooms:auto-fetched", classrooms.clone());
            Ok(())
        })
        .map_err(ScheduledClassroomRefreshError::from_local_data)?;
    Ok(classrooms)
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
fn format_course_menu_line(course: &crate::models::Course, week_number: i64) -> String {
    let room = if course.room.trim().is_empty() {
        "地点未标注".to_string()
    } else {
        course.room.clone()
    };
    let course_name = if course.exam_week_numbers.contains(&week_number) {
        format!("试 {}", course.name)
    } else {
        course.name.clone()
    };
    truncate_menu_label(
        format!("{}  {}  @ {}", course_time_label(course), course_name, room),
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
    let widget = MenuItem::with_id(app, "show_widget", "显示课程小组件", true, None::<&str>)?;
    let planner = MenuItem::with_id(app, "planner", "查看空教室", true, None::<&str>)?;
    let calendar = MenuItem::with_id(app, "calendar", "教学日历", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "设置", true, Some("CmdOrCtrl+,"))?;
    let refresh = MenuItem::with_id(app, "refresh_today", "刷新课程", true, Some("CmdOrCtrl+R"))?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, Some("CmdOrCtrl+Q"))?;
    menu.append_items(&[&open, &widget, &planner, &calendar, &settings])?;
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
        courses: state
            .courses
            .iter()
            .map(|course| format_course_menu_line(course, state.week_number))
            .collect(),
    }
}

#[cfg(not(mobile))]
async fn load_today_course_content(
    app: tauri::AppHandle,
    generation: LocalDataGeneration,
    prefer_saved_schedule: bool,
) -> TrayCourseContent {
    if prefer_saved_schedule {
        match LOCAL_DATA.with_current(generation, || {
            schedule_store::load(&app).map_err(|error| error.message)
        }) {
            Ok(Some(schedule)) => return schedule_to_tray_content(schedule),
            Ok(None) => {}
            Err(error) => return TrayCourseContent::Message(error.message()),
        }
    }

    let request = match LOCAL_DATA.with_current(generation, || {
        let settings = settings_store::load(&app).map_err(|error| error.message)?;
        let mut request = ScheduleRequest {
            account: non_empty_option(settings.account),
            password: None,
            term_id: non_empty_option(settings.term_id),
            term_start_date: non_empty_option(settings.term_start_date),
        };
        settings_store::apply_saved_credentials(&mut request.account, &mut request.password)
            .map_err(|error| error.message)?;
        Ok(request)
    }) {
        Ok(request) => request,
        Err(error) => return TrayCourseContent::Message(error.message()),
    };
    let schedule = match schedule::fetch_schedule(&request).await {
        Ok(schedule) => {
            if let Err(error) = LOCAL_DATA.with_current(generation, || {
                schedule_store::save(&app, &schedule).map_err(|error| error.message)
            }) {
                return TrayCourseContent::Message(error.message());
            }
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
    let generation = LOCAL_DATA.begin();
    if LOCAL_DATA
        .with_current(generation, || {
            set_tray_menu(&app, TrayCourseContent::Loading).map_err(|error| error.to_string())
        })
        .is_err()
    {
        return;
    }
    tauri::async_runtime::spawn(async move {
        let content =
            load_today_course_content(app.clone(), generation, prefer_saved_schedule).await;
        let _ = LOCAL_DATA.with_current(generation, || {
            set_tray_menu(&app, content).map_err(|error| error.to_string())
        });
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
            "show_widget" => {
                let _ = show_course_widget(app);
            }
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

#[cfg(not(mobile))]
fn next_daily_trigger_after(now: NaiveDateTime, hour: u32, minute: u32) -> NaiveDateTime {
    let time = NaiveTime::from_hms_opt(hour, minute, 0).expect("valid daily trigger time");
    let today_trigger = now.date().and_time(time);
    if now < today_trigger {
        today_trigger
    } else {
        today_trigger + ChronoDuration::days(1)
    }
}

#[cfg(not(mobile))]
fn desktop_now() -> NaiveDateTime {
    chrono::Utc::now()
        .with_timezone(&chrono_tz::Asia::Shanghai)
        .naive_local()
}

#[cfg(not(mobile))]
const MAX_SCHEDULER_SLEEP: Duration = Duration::from_secs(5 * 60);
#[cfg(not(mobile))]
const CLASSROOM_REFRESH_RETRY_DELAY: ChronoDuration = ChronoDuration::minutes(15);
#[cfg(not(mobile))]
const MAX_CLASSROOM_REFRESH_RETRIES: u8 = 2;

#[cfg(not(mobile))]
fn next_desktop_schedule_boundary(
    now: NaiveDateTime,
    state: DesktopScheduleState,
) -> NaiveDateTime {
    let mut boundaries = vec![
        next_daily_trigger_after(now, 0, 0),
        next_daily_trigger_after(now, 7, 0),
        next_daily_trigger_after(now, 7, 30),
    ];
    if let Some(retry) = state
        .classroom_retry
        .filter(|retry| retry.next_attempt_at > now)
    {
        boundaries.push(retry.next_attempt_at);
    }
    boundaries
        .into_iter()
        .min()
        .expect("desktop schedule always has a boundary")
}

#[cfg(not(mobile))]
fn scheduler_sleep_duration(now: NaiveDateTime, boundary: NaiveDateTime) -> Duration {
    let wait = (boundary - now)
        .to_std()
        .unwrap_or_else(|_| Duration::from_secs(1));
    wait.clamp(Duration::from_secs(1), MAX_SCHEDULER_SLEEP)
}

#[cfg(not(mobile))]
fn sleep_until(boundary: NaiveDateTime) {
    std::thread::sleep(scheduler_sleep_duration(desktop_now(), boundary));
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DesktopScheduledTask {
    RebuildTrayForDate,
    RefreshClassroomsAndTray,
    SendCourseNotification,
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DesktopTaskOutcome {
    Completed,
    PermanentFailure,
    RetryableFailure,
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DesktopTaskRetry {
    date: NaiveDate,
    attempts: u8,
    next_attempt_at: NaiveDateTime,
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DesktopScheduleState {
    tray_date: NaiveDate,
    classroom_refresh_date: Option<NaiveDate>,
    notification_date: Option<NaiveDate>,
    classroom_retry: Option<DesktopTaskRetry>,
}

#[cfg(not(mobile))]
impl DesktopScheduleState {
    fn after_startup(now: NaiveDateTime) -> Self {
        let today = now.date();
        let seven = NaiveTime::from_hms_opt(7, 0, 0).expect("valid refresh time");
        let seven_thirty = NaiveTime::from_hms_opt(7, 30, 0).expect("valid notification time");
        Self {
            tray_date: today,
            classroom_refresh_date: (now.time() >= seven).then_some(today),
            notification_date: (now.time() >= seven_thirty).then_some(today),
            classroom_retry: None,
        }
    }

    fn mark_completed(&mut self, task: DesktopScheduledTask, date: NaiveDate) {
        match task {
            DesktopScheduledTask::RebuildTrayForDate => self.tray_date = date,
            DesktopScheduledTask::RefreshClassroomsAndTray => {
                self.tray_date = date;
                self.classroom_refresh_date = Some(date);
                self.classroom_retry = None;
            }
            DesktopScheduledTask::SendCourseNotification => {
                self.notification_date = Some(date);
            }
        }
    }

    fn record_result(
        &mut self,
        task: DesktopScheduledTask,
        date: NaiveDate,
        completed_at: NaiveDateTime,
        outcome: DesktopTaskOutcome,
    ) {
        if task != DesktopScheduledTask::RefreshClassroomsAndTray
            || outcome != DesktopTaskOutcome::RetryableFailure
        {
            self.mark_completed(task, date);
            return;
        }

        let attempts = self
            .classroom_retry
            .filter(|retry| retry.date == date)
            .map(|retry| retry.attempts.saturating_add(1))
            .unwrap_or(1);
        if attempts > MAX_CLASSROOM_REFRESH_RETRIES {
            self.mark_completed(task, date);
            return;
        }

        self.classroom_retry = Some(DesktopTaskRetry {
            date,
            attempts,
            next_attempt_at: completed_at + CLASSROOM_REFRESH_RETRY_DELAY,
        });
    }
}

#[cfg(not(mobile))]
fn due_desktop_tasks(now: NaiveDateTime, state: DesktopScheduleState) -> Vec<DesktopScheduledTask> {
    let today = now.date();
    let classroom_due = state.classroom_refresh_date != Some(today)
        && match state.classroom_retry.filter(|retry| retry.date == today) {
            Some(retry) => now >= retry.next_attempt_at,
            None => now.time() >= NaiveTime::from_hms_opt(7, 0, 0).expect("valid refresh time"),
        };
    let notification_due = now.time()
        >= NaiveTime::from_hms_opt(7, 30, 0).expect("valid notification time")
        && state.notification_date != Some(today);

    let mut tasks = Vec::with_capacity(2);
    if classroom_due {
        tasks.push(DesktopScheduledTask::RefreshClassroomsAndTray);
    } else if state.tray_date != today {
        tasks.push(DesktopScheduledTask::RebuildTrayForDate);
    }
    if notification_due {
        tasks.push(DesktopScheduledTask::SendCourseNotification);
    }
    tasks
}

#[cfg(not(mobile))]
fn refresh_today_classrooms_and_emit(app: &tauri::AppHandle) -> DesktopTaskOutcome {
    match tauri::async_runtime::block_on(fetch_today_classrooms_from_saved_settings(app.clone())) {
        Ok(_) => DesktopTaskOutcome::Completed,
        Err(error) => {
            if let Some(message) = error.message() {
                let _ = app.emit(
                    "classrooms:auto-fetch-error",
                    format!("自动获取当天空教室失败：{message}"),
                );
            }
            error.task_outcome()
        }
    }
}

#[cfg(not(mobile))]
fn daily_course_notification_content(
    app: &tauri::AppHandle,
    today: NaiveDate,
    generation: LocalDataGeneration,
) -> Result<(String, String), String> {
    let Some(schedule) = (match LOCAL_DATA.with_current(generation, || {
        schedule_store::load(app).map_err(|error| error.message)
    }) {
        Ok(schedule) => schedule,
        Err(LocalDataAccessError::Stale) => return Err(STALE_LOCAL_DATA_MESSAGE.to_string()),
        Err(LocalDataAccessError::Operation(message)) => {
            return Ok(("今日课程提醒".to_string(), message));
        }
    }) else {
        return Ok((
            "今日课程提醒".to_string(),
            "还没有保存课表，打开应用刷新个人课表后会在这里提醒。".to_string(),
        ));
    };
    let term_start_date = match NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d") {
        Ok(date) => date,
        Err(_) => {
            return Ok((
                "今日课程提醒".to_string(),
                "第一周周一日期格式不正确，请在设置里修正。".to_string(),
            ));
        }
    };
    let state = recommender::date_state(&schedule.courses, today, term_start_date);
    if state.courses.is_empty() {
        return Ok((
            "今日暂无课程".to_string(),
            format!("{} · 第 {} 周", today, state.week_number),
        ));
    }

    let mut lines: Vec<String> = state
        .courses
        .iter()
        .take(4)
        .map(|course| format_course_menu_line(course, state.week_number))
        .collect();
    if state.courses.len() > lines.len() {
        lines.push(format!(
            "还有 {} 门课，打开应用查看完整日程。",
            state.courses.len() - lines.len()
        ));
    }
    Ok((
        format!("今日有 {} 门课", state.courses.len()),
        lines.join("\n"),
    ))
}

#[cfg(not(mobile))]
fn send_daily_course_notification(app: &tauri::AppHandle, today: NaiveDate) -> Result<(), String> {
    let generation = LOCAL_DATA.begin();
    let (title, body) = daily_course_notification_content(app, today, generation)?;
    let notification = app.notification();
    notification
        .request_permission()
        .map_err(|error| format!("无法确认系统通知权限：{error}"))?;
    LOCAL_DATA
        .with_current(generation, || {
            notification
                .builder()
                .title(title)
                .body(body)
                .group("daily-courses")
                .auto_cancel()
                .show()
                .map_err(|error| error.to_string())
        })
        .map_err(LocalDataAccessError::message)
}

#[cfg(not(mobile))]
fn run_desktop_scheduled_task(
    app: &tauri::AppHandle,
    task: DesktopScheduledTask,
    today: NaiveDate,
) -> DesktopTaskOutcome {
    match task {
        DesktopScheduledTask::RebuildTrayForDate => {
            refresh_tray_courses(app.clone(), true);
            DesktopTaskOutcome::Completed
        }
        DesktopScheduledTask::RefreshClassroomsAndTray => {
            let outcome = refresh_today_classrooms_and_emit(app);
            refresh_tray_courses(app.clone(), true);
            outcome
        }
        DesktopScheduledTask::SendCourseNotification => {
            if let Err(error) = send_daily_course_notification(app, today) {
                eprintln!("daily course notification failed: {error}");
                let _ = app.emit(
                    "schedule:daily-notification-error",
                    format!("发送今日课程提醒失败：{error}"),
                );
            }
            DesktopTaskOutcome::Completed
        }
    }
}

#[cfg(not(mobile))]
fn schedule_desktop_background_tasks(app: tauri::AppHandle) {
    std::thread::spawn(move || {
        let started_at = desktop_now();
        let mut state = DesktopScheduleState::after_startup(started_at);

        loop {
            let now = desktop_now();
            for task in due_desktop_tasks(now, state) {
                let outcome = run_desktop_scheduled_task(&app, task, now.date());
                state.record_result(task, now.date(), now, outcome);
            }
            let now = desktop_now();
            sleep_until(next_desktop_schedule_boundary(now, state));
        }
    });
}

#[cfg(all(test, not(mobile)))]
mod background_schedule_tests {
    use super::*;

    fn date_time(hour: u32, minute: u32, second: u32) -> NaiveDateTime {
        NaiveDate::from_ymd_opt(2026, 8, 3)
            .unwrap()
            .and_hms_opt(hour, minute, second)
            .unwrap()
    }

    #[test]
    fn daily_trigger_is_strictly_after_now() {
        assert_eq!(
            next_daily_trigger_after(date_time(6, 59, 59), 7, 0),
            date_time(7, 0, 0)
        );
        assert_eq!(
            next_daily_trigger_after(date_time(7, 0, 0), 7, 0),
            date_time(7, 0, 0) + ChronoDuration::days(1)
        );
    }

    #[test]
    fn scheduler_uses_daily_boundaries_when_no_retry_is_pending() {
        let state = DesktopScheduleState::after_startup(date_time(6, 0, 0));
        assert_eq!(
            next_desktop_schedule_boundary(date_time(6, 59, 59), state),
            date_time(7, 0, 0)
        );
        assert_eq!(
            next_desktop_schedule_boundary(date_time(7, 0, 0), state),
            date_time(7, 30, 0)
        );
        assert_eq!(
            next_desktop_schedule_boundary(date_time(7, 30, 0), state),
            date_time(0, 0, 0) + ChronoDuration::days(1)
        );
    }

    #[test]
    fn midnight_rebuilds_tray_without_network_refresh() {
        let yesterday = date_time(0, 0, 0).date() - ChronoDuration::days(1);
        let state = DesktopScheduleState {
            tray_date: yesterday,
            classroom_refresh_date: Some(yesterday),
            notification_date: Some(yesterday),
            classroom_retry: None,
        };

        assert_eq!(
            due_desktop_tasks(date_time(0, 0, 1), state),
            vec![DesktopScheduledTask::RebuildTrayForDate]
        );
    }

    #[test]
    fn delayed_wake_refreshes_classrooms_tray_and_notification_once() {
        let yesterday = date_time(0, 0, 0).date() - ChronoDuration::days(1);
        let mut state = DesktopScheduleState {
            tray_date: yesterday,
            classroom_refresh_date: Some(yesterday),
            notification_date: Some(yesterday),
            classroom_retry: None,
        };
        let now = date_time(8, 0, 0);
        let tasks = due_desktop_tasks(now, state);
        assert_eq!(
            tasks,
            vec![
                DesktopScheduledTask::RefreshClassroomsAndTray,
                DesktopScheduledTask::SendCourseNotification,
            ]
        );

        for task in tasks {
            state.record_result(task, now.date(), now, DesktopTaskOutcome::Completed);
        }
        assert!(due_desktop_tasks(now, state).is_empty());
    }

    #[test]
    fn startup_before_seven_keeps_the_seven_oclock_refresh_due() {
        let state = DesktopScheduleState::after_startup(date_time(6, 0, 0));
        assert!(due_desktop_tasks(date_time(6, 59, 59), state).is_empty());
        assert_eq!(
            due_desktop_tasks(date_time(7, 0, 0), state),
            vec![DesktopScheduledTask::RefreshClassroomsAndTray]
        );
    }

    #[test]
    fn transient_classroom_failures_retry_twice_at_low_frequency() {
        let mut state = DesktopScheduleState::after_startup(date_time(6, 0, 0));
        let task = DesktopScheduledTask::RefreshClassroomsAndTray;

        state.record_result(
            task,
            date_time(7, 0, 0).date(),
            date_time(7, 0, 0),
            DesktopTaskOutcome::RetryableFailure,
        );
        assert!(due_desktop_tasks(date_time(7, 14, 59), state).is_empty());
        assert_eq!(
            next_desktop_schedule_boundary(date_time(7, 0, 1), state),
            date_time(7, 15, 0)
        );
        assert_eq!(due_desktop_tasks(date_time(7, 15, 0), state), vec![task]);

        state.record_result(
            task,
            date_time(7, 15, 0).date(),
            date_time(7, 15, 0),
            DesktopTaskOutcome::RetryableFailure,
        );
        assert_eq!(state.classroom_retry.unwrap().attempts, 2);
        assert!(due_desktop_tasks(date_time(7, 29, 59), state).is_empty());

        state.record_result(
            task,
            date_time(7, 30, 0).date(),
            date_time(7, 30, 0),
            DesktopTaskOutcome::RetryableFailure,
        );
        assert_eq!(
            state.classroom_refresh_date,
            Some(date_time(7, 30, 0).date())
        );
        assert!(state.classroom_retry.is_none());
    }

    #[test]
    fn missing_credentials_do_not_schedule_retries() {
        let mut state = DesktopScheduleState::after_startup(date_time(6, 0, 0));
        let task = DesktopScheduledTask::RefreshClassroomsAndTray;
        let outcome =
            ScheduledClassroomRefreshError::MissingCredentials("missing credentials".to_string())
                .task_outcome();
        assert_eq!(outcome, DesktopTaskOutcome::PermanentFailure);

        state.record_result(task, date_time(7, 0, 0).date(), date_time(7, 0, 0), outcome);

        assert!(state.classroom_retry.is_none());
        assert!(!due_desktop_tasks(date_time(8, 0, 0), state).contains(&task));
    }

    #[test]
    fn scheduler_sleep_is_capped_and_rechecks_after_clock_changes() {
        assert_eq!(
            scheduler_sleep_duration(date_time(7, 0, 0), date_time(8, 0, 0)),
            MAX_SCHEDULER_SLEEP
        );
        assert_eq!(
            scheduler_sleep_duration(date_time(8, 0, 0), date_time(7, 0, 0)),
            Duration::from_secs(1)
        );
    }
}

fn setup_app(app: &mut tauri::App) -> tauri::Result<()> {
    #[cfg(not(mobile))]
    {
        setup_tray(app)?;
        schedule_desktop_background_tasks(app.app_handle().clone());
    }

    #[cfg(mobile)]
    let _ = app;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();
    #[cfg(not(mobile))]
    let builder = builder.plugin(tauri_plugin_notification::init());

    builder
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
            clear_local_data,
            load_saved_schedule,
            load_saved_classrooms,
            fetch_schedule,
            import_schedule_to_calendar,
            fetch_classrooms,
            fetch_holidays,
            show_desktop_widget,
            hide_desktop_widget
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
