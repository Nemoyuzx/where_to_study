use std::fs;
use std::path::PathBuf;

use tauri::{AppHandle, Manager};

use crate::error::{ServiceError, ServiceResult};
use crate::models::{ClassroomsCacheResponse, CLASSROOMS_CACHE_VERSION};

const CLASSROOMS_FILE_NAME: &str = "classrooms.json";

fn classrooms_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地空教室目录：{error}")))?;
    Ok(directory.join(CLASSROOMS_FILE_NAME))
}

pub fn load(app: &AppHandle) -> ServiceResult<Option<ClassroomsCacheResponse>> {
    let path = classrooms_path(app)?;
    if !path.exists() {
        return Ok(None);
    }

    let bytes = fs::read(&path)
        .map_err(|error| ServiceError::new(format!("无法读取本地空教室信息：{error}")))?;
    if bytes.is_empty() {
        return Ok(None);
    }

    let classrooms: ClassroomsCacheResponse = serde_json::from_slice(&bytes)
        .map_err(|error| ServiceError::new(format!("本地空教室信息格式不正确：{error}")))?;
    if classrooms.cache_version < CLASSROOMS_CACHE_VERSION {
        return Ok(None);
    }
    Ok(Some(classrooms))
}

pub fn save(app: &AppHandle, classrooms: &ClassroomsCacheResponse) -> ServiceResult<()> {
    let path = classrooms_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建本地空教室目录：{error}")))?;
    }

    let bytes = serde_json::to_vec_pretty(classrooms)
        .map_err(|error| ServiceError::new(format!("无法序列化本地空教室信息：{error}")))?;
    fs::write(&path, bytes)
        .map_err(|error| ServiceError::new(format!("无法保存本地空教室信息：{error}")))?;
    Ok(())
}
