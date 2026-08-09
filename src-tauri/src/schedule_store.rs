use std::fs;
use std::path::PathBuf;

use tauri::{AppHandle, Manager};

use crate::error::{ServiceError, ServiceResult};
use crate::models::ScheduleResponse;
use crate::scoped_cache;

const SCHEDULE_FILE_NAME: &str = "schedule.json";

fn schedule_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地课表目录：{error}")))?;
    Ok(directory.join(SCHEDULE_FILE_NAME))
}

pub fn load(app: &AppHandle, account_scope: &str) -> ServiceResult<Option<ScheduleResponse>> {
    let path = schedule_path(app)?;
    if !path.exists() {
        return Ok(None);
    }

    let bytes =
        fs::read(&path).map_err(|error| ServiceError::new(format!("无法读取本地课表：{error}")))?;
    if bytes.is_empty() {
        return Ok(None);
    }

    let Some(mut schedule) =
        scoped_cache::decode::<ScheduleResponse>(&bytes, account_scope, "本地课表")?
    else {
        return Ok(None);
    };
    crate::schedule::annotate_exam_weeks(&mut schedule.courses);
    Ok(Some(schedule))
}

pub fn save(
    app: &AppHandle,
    account_scope: &str,
    schedule: &ScheduleResponse,
) -> ServiceResult<()> {
    let path = schedule_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建本地课表目录：{error}")))?;
    }

    let bytes = scoped_cache::encode(account_scope, schedule, "本地课表")?;
    fs::write(&path, bytes)
        .map_err(|error| ServiceError::new(format!("无法保存本地课表：{error}")))?;
    Ok(())
}

pub fn clear(app: &AppHandle) -> ServiceResult<()> {
    let path = schedule_path(app)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(ServiceError::new(format!("无法清除本地课表：{error}"))),
    }
}
