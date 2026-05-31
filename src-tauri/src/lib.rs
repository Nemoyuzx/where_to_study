mod auth;
mod classrooms;
mod config;
mod error;
mod models;
mod recommender;
mod schedule;

use chrono::NaiveDate;

use crate::models::{
    ClassroomsRequest, ClassroomsResponse, MetadataResponse, RecommendationRequest,
    RecommendationResponse, ScheduleRequest, ScheduleResponse,
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
    ))
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .invoke_handler(tauri::generate_handler![
            get_metadata,
            fetch_schedule,
            fetch_classrooms,
            fetch_recommendations
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
