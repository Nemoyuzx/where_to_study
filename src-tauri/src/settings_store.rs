use std::fs;
use std::path::PathBuf;

use tauri::{AppHandle, Manager};

use crate::error::{ServiceError, ServiceResult};
use crate::models::SavedSettings;

const SETTINGS_FILE_NAME: &str = "settings.json";

fn settings_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地设置目录：{error}")))?;
    Ok(directory.join(SETTINGS_FILE_NAME))
}

pub fn load(app: &AppHandle) -> ServiceResult<SavedSettings> {
    let path = settings_path(app)?;
    if !path.exists() {
        return Ok(SavedSettings::with_defaults());
    }

    let bytes =
        fs::read(&path).map_err(|error| ServiceError::new(format!("无法读取本地设置：{error}")))?;
    if bytes.is_empty() {
        return Ok(SavedSettings::with_defaults());
    }

    let mut settings: SavedSettings = serde_json::from_slice(&bytes)
        .map_err(|error| ServiceError::new(format!("本地设置格式不正确：{error}")))?;
    settings.apply_defaults();
    Ok(settings)
}

pub fn save(app: &AppHandle, mut settings: SavedSettings) -> ServiceResult<SavedSettings> {
    settings.apply_defaults();
    let path = settings_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建本地设置目录：{error}")))?;
    }

    let bytes = serde_json::to_vec_pretty(&settings)
        .map_err(|error| ServiceError::new(format!("无法序列化本地设置：{error}")))?;
    fs::write(&path, bytes)
        .map_err(|error| ServiceError::new(format!("无法保存本地设置：{error}")))?;
    Ok(settings)
}
