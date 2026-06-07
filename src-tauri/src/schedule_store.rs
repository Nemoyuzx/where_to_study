use std::fs;
use std::path::PathBuf;

use tauri::{AppHandle, Manager};

use crate::error::{ServiceError, ServiceResult};
use crate::models::ScheduleResponse;

const SCHEDULE_FILE_NAME: &str = "schedule.json";

fn schedule_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地课表目录：{error}")))?;
    Ok(directory.join(SCHEDULE_FILE_NAME))
}

pub fn load(app: &AppHandle) -> ServiceResult<Option<ScheduleResponse>> {
    let path = schedule_path(app)?;
    if !path.exists() {
        return Ok(None);
    }

    let bytes =
        fs::read(&path).map_err(|error| ServiceError::new(format!("无法读取本地课表：{error}")))?;
    if bytes.is_empty() {
        return Ok(None);
    }

    let mut schedule: ScheduleResponse = serde_json::from_slice(&bytes)
        .map_err(|error| ServiceError::new(format!("本地课表格式不正确：{error}")))?;
    crate::schedule::annotate_exam_weeks(&mut schedule.courses);
    Ok(Some(schedule))
}

pub fn save(app: &AppHandle, schedule: &ScheduleResponse) -> ServiceResult<()> {
    let path = schedule_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建本地课表目录：{error}")))?;
    }

    let bytes = serde_json::to_vec_pretty(schedule)
        .map_err(|error| ServiceError::new(format!("无法序列化本地课表：{error}")))?;
    fs::write(&path, bytes)
        .map_err(|error| ServiceError::new(format!("无法保存本地课表：{error}")))?;
    Ok(())
}
