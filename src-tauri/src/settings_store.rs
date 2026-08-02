use std::fs;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};

use crate::credential_store::{self, Credentials};
use crate::error::{ServiceError, ServiceResult};
use crate::models::SavedSettings;

const SETTINGS_FILE_NAME: &str = "settings.json";
const SETTINGS_SCHEMA_VERSION: u32 = 2;

#[derive(Debug, Default, Deserialize)]
struct SettingsFile {
    #[serde(default)]
    account: String,
    #[serde(default)]
    password: String,
    #[serde(default)]
    term_id: String,
    #[serde(default)]
    term_start_date: String,
    #[serde(default)]
    campus_id: String,
    #[serde(default)]
    default_min_seats: usize,
}

#[derive(Debug, Serialize)]
struct PersistedSettings<'a> {
    schema_version: u32,
    term_id: &'a str,
    term_start_date: &'a str,
    campus_id: &'a str,
    default_min_seats: usize,
}

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
        return load_credentials(SavedSettings::with_defaults());
    }

    let bytes =
        fs::read(&path).map_err(|error| ServiceError::new(format!("无法读取本地设置：{error}")))?;
    if bytes.is_empty() {
        return load_credentials(SavedSettings::with_defaults());
    }

    let file: SettingsFile = serde_json::from_slice(&bytes)
        .map_err(|error| ServiceError::new(format!("本地设置格式不正确：{error}")))?;
    let mut settings = SavedSettings {
        account: file.account,
        password: file.password,
        term_id: file.term_id,
        term_start_date: file.term_start_date,
        campus_id: file.campus_id,
        default_min_seats: file.default_min_seats,
    };
    settings.apply_defaults();

    if !settings.account.is_empty() || !settings.password.is_empty() {
        credential_store::save(&credentials_from(&settings))?;
        write_non_sensitive_settings(&path, &settings)?;
        return Ok(settings);
    }

    load_credentials(settings)
}

pub fn save(app: &AppHandle, mut settings: SavedSettings) -> ServiceResult<SavedSettings> {
    settings.apply_defaults();
    let path = settings_path(app)?;
    credential_store::save(&credentials_from(&settings))?;
    write_non_sensitive_settings(&path, &settings)?;
    Ok(settings)
}

fn credentials_from(settings: &SavedSettings) -> Credentials {
    Credentials {
        account: settings.account.clone(),
        password: settings.password.clone(),
    }
}

fn load_credentials(mut settings: SavedSettings) -> ServiceResult<SavedSettings> {
    if let Some(credentials) = credential_store::load()? {
        settings.account = credentials.account;
        settings.password = credentials.password;
    }
    Ok(settings)
}

fn write_non_sensitive_settings(path: &PathBuf, settings: &SavedSettings) -> ServiceResult<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建本地设置目录：{error}")))?;
    }

    let persisted = PersistedSettings {
        schema_version: SETTINGS_SCHEMA_VERSION,
        term_id: &settings.term_id,
        term_start_date: &settings.term_start_date,
        campus_id: &settings.campus_id,
        default_min_seats: settings.default_min_seats,
    };
    let bytes = serde_json::to_vec_pretty(&persisted)
        .map_err(|error| ServiceError::new(format!("无法序列化本地设置：{error}")))?;
    fs::write(path, bytes)
        .map_err(|error| ServiceError::new(format!("无法保存本地设置：{error}")))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{write_non_sensitive_settings, SavedSettings};
    use std::fs;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn settings_file_never_contains_credentials() {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("system clock after epoch")
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "where-to-study-settings-{suffix}-{}.json",
            std::process::id()
        ));
        let settings = SavedSettings {
            account: "fixture-account".to_string(),
            password: "fixture-password".to_string(),
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            campus_id: "01".to_string(),
            default_min_seats: 20,
        };

        write_non_sensitive_settings(&path, &settings).expect("write redacted settings");
        let content = fs::read_to_string(&path).expect("read redacted settings");
        let value: serde_json::Value = serde_json::from_str(&content).expect("valid JSON");

        assert_eq!(value["schema_version"], 2);
        assert!(value.get("account").is_none());
        assert!(value.get("password").is_none());
        assert!(!content.contains("fixture-account"));
        assert!(!content.contains("fixture-password"));

        fs::remove_file(path).expect("remove test settings file");
    }
}
