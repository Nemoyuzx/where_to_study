use std::fs::{self, OpenOptions};
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use tempfile::NamedTempFile;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::credential_store::{self, Credentials};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{SaveSettingsRequest, SavedSettings};

const SETTINGS_FILE_NAME: &str = "settings.json";
const SETTINGS_SCHEMA_VERSION: u32 = 2;

#[derive(Default, Deserialize, Zeroize, ZeroizeOnDrop)]
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

#[derive(Serialize)]
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
    load_from_path(
        &settings_path(app)?,
        credential_store::load,
        credential_store::save,
    )
}

pub fn save(app: &AppHandle, request: SaveSettingsRequest) -> ServiceResult<SavedSettings> {
    save_to_path(
        &settings_path(app)?,
        request,
        credential_store::load,
        credential_store::save,
    )
}

pub fn apply_saved_credentials(
    account: &mut Option<String>,
    password: &mut Option<String>,
) -> ServiceResult<()> {
    let account_present = account
        .as_deref()
        .map(str::trim)
        .is_some_and(|value| !value.is_empty());
    let password_present = password.as_deref().is_some_and(|value| !value.is_empty());
    if account_present && password_present {
        return Ok(());
    }

    let stored = credential_store::load()?;
    merge_saved_credentials(account, password, stored.as_ref());
    Ok(())
}

fn load_from_path<L, S>(
    path: &Path,
    load_credentials: L,
    save_credentials: S,
) -> ServiceResult<SavedSettings>
where
    L: FnOnce() -> ServiceResult<Option<Credentials>>,
    S: FnOnce(&Credentials) -> ServiceResult<()>,
{
    if !path.exists() {
        return settings_with_credentials(SavedSettings::with_defaults(), load_credentials()?);
    }

    let bytes = Zeroizing::new(match fs::read(path) {
        Ok(bytes) => bytes,
        Err(error) => {
            return Err(fail_closed_after_redaction_error(
                path,
                ServiceError::new(format!("无法读取本地设置：{error}")),
            ));
        }
    });
    if bytes.is_empty() {
        return settings_with_credentials(SavedSettings::with_defaults(), load_credentials()?);
    }

    let mut file: SettingsFile = match serde_json::from_slice(&bytes) {
        Ok(file) => file,
        Err(error) => {
            return Err(fail_closed_after_redaction_error(
                path,
                ServiceError::new(format!("本地设置格式不正确：{error}")),
            ));
        }
    };
    let mut settings = SavedSettings {
        account: String::new(),
        has_saved_password: false,
        term_id: file.term_id.clone(),
        term_start_date: file.term_start_date.clone(),
        campus_id: file.campus_id.clone(),
        default_min_seats: file.default_min_seats,
    };
    settings.apply_defaults();

    if !file.account.is_empty() || !file.password.is_empty() {
        let credentials = Credentials {
            account: file.account.clone(),
            password: file.password.clone(),
        };
        if let Err(error) = write_non_sensitive_settings(path, &settings) {
            return Err(fail_closed_after_redaction_error(path, error));
        }

        file.zeroize();
        drop(bytes);
        save_credentials(&credentials)?;
        return settings_with_credentials(settings, Some(credentials));
    }

    settings_with_credentials(settings, load_credentials()?)
}

fn save_to_path<L, S>(
    path: &Path,
    mut request: SaveSettingsRequest,
    load_credentials: L,
    save_credentials: S,
) -> ServiceResult<SavedSettings>
where
    L: FnOnce() -> ServiceResult<Option<Credentials>>,
    S: FnOnce(&Credentials) -> ServiceResult<()>,
{
    request.apply_defaults();
    let existing = load_credentials()?;
    let requested_account = request.account.trim();
    let password = request
        .password
        .as_ref()
        .filter(|value| !value.is_empty())
        .cloned()
        .or_else(|| {
            existing
                .as_ref()
                .filter(|credentials| credentials.account.trim() == requested_account)
                .map(|credentials| credentials.password.clone())
        })
        .unwrap_or_default();
    let credentials = Credentials {
        account: requested_account.to_string(),
        password,
    };
    let settings = SavedSettings {
        account: credentials.account.clone(),
        has_saved_password: !credentials.password.is_empty(),
        term_id: request.term_id.clone(),
        term_start_date: request.term_start_date.clone(),
        campus_id: request.campus_id.clone(),
        default_min_seats: request.default_min_seats,
    };

    write_non_sensitive_settings(path, &settings)?;
    save_credentials(&credentials)?;
    Ok(settings)
}

fn settings_with_credentials(
    mut settings: SavedSettings,
    credentials: Option<Credentials>,
) -> ServiceResult<SavedSettings> {
    if let Some(credentials) = credentials {
        settings.account = credentials.account.clone();
        settings.has_saved_password = !credentials.password.is_empty();
    }
    Ok(settings)
}

fn merge_saved_credentials(
    account: &mut Option<String>,
    password: &mut Option<String>,
    stored: Option<&Credentials>,
) {
    let Some(stored) = stored else {
        return;
    };

    if account
        .as_deref()
        .map(str::trim)
        .is_none_or(|value| value.is_empty())
    {
        *account = non_empty_string(stored.account.clone());
    }

    let effective_account = account.as_deref().unwrap_or_default().trim();
    let password_missing = password.as_deref().is_none_or(|value| value.is_empty());
    if password_missing && effective_account == stored.account.trim() {
        *password = non_empty_string(stored.password.clone());
    }
}

fn non_empty_string(value: String) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

fn write_non_sensitive_settings(path: &Path, settings: &SavedSettings) -> ServiceResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| ServiceError::new("本地设置路径没有父目录。"))?;
    fs::create_dir_all(parent)
        .map_err(|error| ServiceError::new(format!("无法创建本地设置目录：{error}")))?;

    let persisted = PersistedSettings {
        schema_version: SETTINGS_SCHEMA_VERSION,
        term_id: &settings.term_id,
        term_start_date: &settings.term_start_date,
        campus_id: &settings.campus_id,
        default_min_seats: settings.default_min_seats,
    };
    let bytes = Zeroizing::new(
        serde_json::to_vec_pretty(&persisted)
            .map_err(|error| ServiceError::new(format!("无法序列化本地设置：{error}")))?,
    );
    let mut temporary = NamedTempFile::new_in(parent)
        .map_err(|error| ServiceError::new(format!("无法创建临时设置文件：{error}")))?;

    #[cfg(unix)]
    fs::set_permissions(temporary.path(), fs::Permissions::from_mode(0o600))
        .map_err(|error| ServiceError::new(format!("无法限制临时设置文件权限：{error}")))?;

    temporary
        .write_all(&bytes)
        .and_then(|_| temporary.flush())
        .and_then(|_| temporary.as_file().sync_all())
        .map_err(|error| ServiceError::new(format!("无法写入临时设置文件：{error}")))?;
    temporary
        .persist(path)
        .map_err(|error| ServiceError::new(format!("无法原子替换本地设置：{}", error.error)))?;

    #[cfg(unix)]
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
        .map_err(|error| ServiceError::new(format!("无法限制本地设置文件权限：{error}")))?;

    Ok(())
}

fn fail_closed_after_redaction_error(path: &Path, write_error: ServiceError) -> ServiceError {
    if fs::remove_file(path).is_ok() {
        return ServiceError::new(format!(
            "{}；为避免保留明文凭据，旧设置文件已删除。",
            write_error.message
        ));
    }

    let truncated = OpenOptions::new()
        .write(true)
        .truncate(true)
        .open(path)
        .and_then(|file| file.sync_all())
        .is_ok();
    if truncated {
        ServiceError::new(format!(
            "{}；为避免保留明文凭据，旧设置文件已清空。",
            write_error.message
        ))
    } else {
        ServiceError::new(format!(
            "{}；无法自动删除含旧凭据的设置文件，请立即删除 {}。",
            write_error.message,
            path.display()
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::Cell;

    fn fixture_settings() -> SavedSettings {
        SavedSettings {
            account: "fixture-account".to_string(),
            has_saved_password: true,
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            campus_id: "01".to_string(),
            default_min_seats: 20,
        }
    }

    fn fixture_request(password: Option<&str>) -> SaveSettingsRequest {
        SaveSettingsRequest {
            account: "fixture-account".to_string(),
            password: password.map(ToOwned::to_owned),
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            campus_id: "01".to_string(),
            default_min_seats: 20,
        }
    }

    #[test]
    fn settings_file_never_contains_credentials_and_is_owner_only() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");

        write_non_sensitive_settings(&path, &fixture_settings()).expect("write redacted settings");
        let content = fs::read_to_string(&path).expect("read redacted settings");
        let value: serde_json::Value = serde_json::from_str(&content).expect("valid JSON");

        assert_eq!(value["schema_version"], SETTINGS_SCHEMA_VERSION);
        assert!(value.get("account").is_none());
        assert!(value.get("password").is_none());
        assert!(!content.contains("fixture-account"));

        #[cfg(unix)]
        assert_eq!(
            fs::metadata(path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }

    #[test]
    fn legacy_plaintext_is_redacted_before_credentials_are_saved() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        fs::write(
            &path,
            r#"{"account":"legacy-user","password":"legacy-secret","term_id":"2025-2026-2","term_start_date":"2026-03-02","campus_id":"01"}"#,
        )
        .unwrap();
        let save_called = Cell::new(false);

        let loaded = load_from_path(
            &path,
            || Ok(None),
            |credentials| {
                let redacted = fs::read_to_string(&path).unwrap();
                assert!(!redacted.contains("legacy-user"));
                assert!(!redacted.contains("legacy-secret"));
                assert_eq!(credentials.account, "legacy-user");
                assert_eq!(credentials.password, "legacy-secret");
                save_called.set(true);
                Ok(())
            },
        )
        .expect("migrate legacy settings");

        assert!(save_called.get());
        assert_eq!(loaded.account, "legacy-user");
        assert!(loaded.has_saved_password);
    }

    #[test]
    fn credential_save_failure_cannot_restore_plaintext_file() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        fs::write(
            &path,
            r#"{"account":"legacy-user","password":"legacy-secret"}"#,
        )
        .unwrap();

        let result = load_from_path(
            &path,
            || Ok(None),
            |_| Err(ServiceError::new("credential store unavailable")),
        );

        assert!(result.is_err());
        let redacted = fs::read_to_string(path).unwrap();
        assert!(!redacted.contains("legacy-user"));
        assert!(!redacted.contains("legacy-secret"));
    }

    #[test]
    fn malformed_legacy_file_is_removed_instead_of_retaining_plaintext() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        fs::write(&path, r#"{"password":"legacy-secret""#).unwrap();

        let result = load_from_path(&path, || Ok(None), |_| Ok(()));

        assert!(result.is_err());
        assert!(!path.exists() || fs::read_to_string(path).unwrap().is_empty());
    }

    #[test]
    fn missing_password_preserves_existing_secure_password() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = Credentials {
            account: "fixture-account".to_string(),
            password: "existing-secret".to_string(),
        };

        let saved = save_to_path(
            &path,
            fixture_request(None),
            || Ok(Some(stored.clone())),
            |credentials| {
                assert_eq!(credentials.password, "existing-secret");
                Ok(())
            },
        )
        .expect("save without replacing password");

        assert!(saved.has_saved_password);
        assert!(!fs::read_to_string(path)
            .unwrap()
            .contains("existing-secret"));
    }

    #[test]
    fn empty_password_preserves_existing_secure_password() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = Credentials {
            account: "fixture-account".to_string(),
            password: "existing-secret".to_string(),
        };

        let saved = save_to_path(
            &path,
            fixture_request(Some("")),
            || Ok(Some(stored.clone())),
            |credentials| {
                assert_eq!(credentials.password, "existing-secret");
                Ok(())
            },
        )
        .expect("save empty replacement password");

        assert!(saved.has_saved_password);
    }

    #[test]
    fn explicit_password_replaces_existing_secure_password() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = Credentials {
            account: "fixture-account".to_string(),
            password: "existing-secret".to_string(),
        };

        save_to_path(
            &path,
            fixture_request(Some("replacement-secret")),
            || Ok(Some(stored.clone())),
            |credentials| {
                assert_eq!(credentials.password, "replacement-secret");
                Ok(())
            },
        )
        .expect("replace password");
    }

    #[test]
    fn changing_account_does_not_reuse_previous_accounts_password() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = Credentials {
            account: "fixture-account".to_string(),
            password: "existing-secret".to_string(),
        };
        let mut request = fixture_request(None);
        request.account = "other-account".to_string();

        let saved = save_to_path(
            &path,
            request,
            || Ok(Some(stored)),
            |credentials| {
                assert_eq!(credentials.account, "other-account");
                assert!(credentials.password.is_empty());
                Ok(())
            },
        )
        .expect("save changed account");

        assert!(!saved.has_saved_password);
    }

    #[test]
    fn stored_password_is_only_merged_for_the_same_account() {
        let stored = Credentials {
            account: "saved-user".to_string(),
            password: "saved-secret".to_string(),
        };
        let mut matching_account = Some("saved-user".to_string());
        let mut matching_password = None;
        merge_saved_credentials(&mut matching_account, &mut matching_password, Some(&stored));
        assert_eq!(matching_password.as_deref(), Some("saved-secret"));

        let mut different_account = Some("other-user".to_string());
        let mut different_password = None;
        merge_saved_credentials(
            &mut different_account,
            &mut different_password,
            Some(&stored),
        );
        assert!(different_password.is_none());
    }

    #[test]
    fn public_settings_response_contains_only_password_presence() {
        let serialized = serde_json::to_value(fixture_settings()).expect("serialize settings");

        assert_eq!(serialized["has_saved_password"], true);
        assert!(serialized.get("password").is_none());
    }
}
