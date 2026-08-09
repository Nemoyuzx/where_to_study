use std::fs;
use std::path::PathBuf;

use tauri::{AppHandle, Manager};

use crate::error::{ServiceError, ServiceResult};
use crate::models::{ClassroomsCacheResponse, CLASSROOMS_CACHE_VERSION};
use crate::scoped_cache;

const CLASSROOMS_FILE_NAME: &str = "classrooms.json";

fn classrooms_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地空教室目录：{error}")))?;
    Ok(directory.join(CLASSROOMS_FILE_NAME))
}

pub fn load(
    app: &AppHandle,
    account_scope: &str,
) -> ServiceResult<Option<ClassroomsCacheResponse>> {
    let path = classrooms_path(app)?;
    if !path.exists() {
        return Ok(None);
    }

    let bytes = fs::read(&path)
        .map_err(|error| ServiceError::new(format!("无法读取本地空教室信息：{error}")))?;
    if bytes.is_empty() {
        return Ok(None);
    }

    let Some(classrooms) =
        scoped_cache::decode::<ClassroomsCacheResponse>(&bytes, account_scope, "本地空教室信息")?
    else {
        return Ok(None);
    };
    if classrooms.cache_version < CLASSROOMS_CACHE_VERSION {
        return Ok(None);
    }
    Ok(Some(classrooms))
}

pub fn save(
    app: &AppHandle,
    account_scope: &str,
    classrooms: &ClassroomsCacheResponse,
) -> ServiceResult<()> {
    let path = classrooms_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建本地空教室目录：{error}")))?;
    }

    let bytes = scoped_cache::encode(account_scope, classrooms, "本地空教室信息")?;
    fs::write(&path, bytes)
        .map_err(|error| ServiceError::new(format!("无法保存本地空教室信息：{error}")))?;
    Ok(())
}

pub fn clear(app: &AppHandle) -> ServiceResult<()> {
    let path = classrooms_path(app)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(ServiceError::new(format!(
            "无法清除本地空教室信息：{error}"
        ))),
    }
}
