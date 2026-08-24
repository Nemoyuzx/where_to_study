use std::fs::{self, OpenOptions};
use std::io::Write;
#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use tempfile::NamedTempFile;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::credential_store::{self, Credentials};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{SaveSettingsRequest, SavedSettings};

const SETTINGS_FILE_NAME: &str = "settings.json";
const ACCOUNT_ACCESS_REVOKED_FILE_NAME: &str = "account-access-revoked";
const SETTINGS_SCHEMA_VERSION: u32 = 8;

fn default_true() -> bool {
    true
}

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
    #[serde(default)]
    ui_language: String,
    #[serde(default)]
    daily_course_notifications_enabled: bool,
    #[serde(default = "default_true")]
    automatic_term_detection_enabled: bool,
    #[serde(default = "default_true")]
    weather_enabled: bool,
    #[serde(default = "default_true")]
    almanac_enabled: bool,
    #[serde(default = "default_true")]
    competition_deadlines_enabled: bool,
    #[serde(default = "default_true")]
    school_contest_notices_enabled: bool,
    #[serde(default = "default_true")]
    summer_camp_deadlines_enabled: bool,
    #[serde(default = "default_true")]
    hackathon_deadlines_enabled: bool,
    #[serde(default)]
    custom_deadlines_enabled: bool,
    #[serde(default)]
    custom_deadlines_url: String,
}

#[derive(Serialize)]
struct PersistedSettings<'a> {
    schema_version: u32,
    term_id: &'a str,
    term_start_date: &'a str,
    campus_id: &'a str,
    default_min_seats: usize,
    ui_language: &'a str,
    daily_course_notifications_enabled: bool,
    automatic_term_detection_enabled: bool,
    weather_enabled: bool,
    almanac_enabled: bool,
    competition_deadlines_enabled: bool,
    school_contest_notices_enabled: bool,
    summer_camp_deadlines_enabled: bool,
    hackathon_deadlines_enabled: bool,
    custom_deadlines_enabled: bool,
    custom_deadlines_url: &'a str,
}

fn settings_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地设置目录：{error}")))?;
    Ok(directory.join(SETTINGS_FILE_NAME))
}

fn account_access_revoked_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位账号访问状态目录：{error}")))?;
    Ok(directory.join(ACCOUNT_ACCESS_REVOKED_FILE_NAME))
}

pub fn account_access_revoked(app: &AppHandle) -> ServiceResult<bool> {
    Ok(account_access_revoked_path(app)?.exists())
}

pub fn mark_account_access_revoked(app: &AppHandle) -> ServiceResult<()> {
    mark_account_access_revoked_at_path(&account_access_revoked_path(app)?)
}

pub fn clear_account_access_revoked(app: &AppHandle) -> ServiceResult<()> {
    clear_account_access_revoked_at_path(&account_access_revoked_path(app)?)
}

pub fn load(app: &AppHandle) -> ServiceResult<SavedSettings> {
    load_from_path(
        &settings_path(app)?,
        credential_store::load,
        credential_store::save,
    )
}

pub struct SettingsSavePlan {
    settings: SavedSettings,
    credentials: Credentials,
    previous_credentials: Option<Credentials>,
    account_changed: bool,
}

impl SettingsSavePlan {
    pub fn account_changed(&self) -> bool {
        self.account_changed
    }

    pub fn has_account(&self) -> bool {
        !self.credentials.account.trim().is_empty()
    }
}

pub fn prepare_save(request: SaveSettingsRequest) -> ServiceResult<SettingsSavePlan> {
    prepare_save_with(request, credential_store::load)
}

pub fn commit_save(app: &AppHandle, plan: SettingsSavePlan) -> ServiceResult<SavedSettings> {
    commit_save_to_path(&settings_path(app)?, plan, credential_store::save)
}

pub fn clear_local_files_preserving_revocation(app: &AppHandle) -> ServiceResult<()> {
    clear_directory_preserving_revocation(
        &app.path()
            .app_config_dir()
            .map_err(|error| ServiceError::new(format!("无法定位本地数据目录：{error}")))?,
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
        ui_language: file.ui_language.clone(),
        daily_course_notifications_enabled: file.daily_course_notifications_enabled,
        automatic_term_detection_enabled: file.automatic_term_detection_enabled,
        weather_enabled: file.weather_enabled,
        almanac_enabled: file.almanac_enabled,
        competition_deadlines_enabled: file.competition_deadlines_enabled,
        school_contest_notices_enabled: file.school_contest_notices_enabled,
        summer_camp_deadlines_enabled: file.summer_camp_deadlines_enabled,
        hackathon_deadlines_enabled: file.hackathon_deadlines_enabled,
        custom_deadlines_enabled: file.custom_deadlines_enabled,
        custom_deadlines_url: file.custom_deadlines_url.clone(),
    };
    settings.apply_defaults();

    if !file.account.is_empty() || !file.password.is_empty() {
        let credentials = Credentials {
            account: file.account.clone(),
            password: file.password.clone(),
            account_scope: if file.account.trim().is_empty() {
                String::new()
            } else {
                crate::scoped_cache::new_account_scope()?
            },
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

fn prepare_save_with<L>(
    mut request: SaveSettingsRequest,
    load_credentials: L,
) -> ServiceResult<SettingsSavePlan>
where
    L: FnOnce() -> ServiceResult<Option<Credentials>>,
{
    request.apply_defaults();
    if !is_strict_contract_date(&request.term_start_date) {
        return Err(ServiceError::new(
            "第一周周一日期格式不正确，请使用 yyyy-MM-dd。",
        ));
    }
    request.custom_deadlines_url = request.custom_deadlines_url.trim().to_string();
    if request.custom_deadlines_enabled {
        crate::deadlines::validate_custom_feed_endpoint(&request.custom_deadlines_url)?;
    }
    let existing = load_credentials()?;
    let requested_account = request.account.trim();
    let entered_password = request
        .password
        .as_deref()
        .filter(|value| !value.is_empty());
    let password = if requested_account.is_empty() {
        if entered_password.is_some() {
            return Err(ServiceError::new("请输入教务账号。"));
        }
        String::new()
    } else if let Some(entered_password) = entered_password {
        entered_password.to_string()
    } else if let Some(existing) = existing.as_ref().filter(|credentials| {
        credentials.account.trim() == requested_account && !credentials.password.is_empty()
    }) {
        existing.password.clone()
    } else {
        return Err(ServiceError::new("更换教务账号时必须输入新密码。"));
    };
    let preserved_scope = existing
        .as_ref()
        .filter(|credentials| credentials.account.trim() == requested_account)
        .map(|credentials| credentials.account_scope.as_str())
        .filter(|scope| crate::scoped_cache::is_valid_account_scope(scope));
    let account_scope = if requested_account.is_empty() {
        String::new()
    } else if let Some(scope) = preserved_scope {
        scope.to_string()
    } else {
        crate::scoped_cache::new_account_scope()?
    };
    let credentials = Credentials {
        account: requested_account.to_string(),
        password,
        account_scope,
    };
    let settings = SavedSettings {
        account: credentials.account.clone(),
        has_saved_password: !credentials.password.is_empty(),
        term_id: request.term_id.clone(),
        term_start_date: request.term_start_date.clone(),
        campus_id: request.campus_id.clone(),
        default_min_seats: request.default_min_seats,
        ui_language: request.ui_language.clone(),
        daily_course_notifications_enabled: request.daily_course_notifications_enabled,
        automatic_term_detection_enabled: request.automatic_term_detection_enabled,
        weather_enabled: request.weather_enabled,
        almanac_enabled: request.almanac_enabled,
        competition_deadlines_enabled: request.competition_deadlines_enabled,
        school_contest_notices_enabled: request.school_contest_notices_enabled,
        summer_camp_deadlines_enabled: request.summer_camp_deadlines_enabled,
        hackathon_deadlines_enabled: request.hackathon_deadlines_enabled,
        custom_deadlines_enabled: request.custom_deadlines_enabled,
        custom_deadlines_url: request.custom_deadlines_url.clone(),
    };

    let existing_account = existing
        .as_ref()
        .map(|credentials| credentials.account.trim())
        .unwrap_or_default();
    let account_changed = existing_account != requested_account
        || (!requested_account.is_empty()
            && existing
                .as_ref()
                .is_none_or(|previous| previous.account_scope != credentials.account_scope));
    Ok(SettingsSavePlan {
        settings,
        credentials,
        previous_credentials: existing,
        account_changed,
    })
}

fn is_strict_contract_date(value: &str) -> bool {
    value.len() == 10
        && value.as_bytes().get(4) == Some(&b'-')
        && value.as_bytes().get(7) == Some(&b'-')
        && NaiveDate::parse_from_str(value, "%Y-%m-%d")
            .is_ok_and(|date| date.format("%Y-%m-%d").to_string() == value)
}

fn commit_save_to_path<S>(
    path: &Path,
    plan: SettingsSavePlan,
    mut save_credentials: S,
) -> ServiceResult<SavedSettings>
where
    S: FnMut(&Credentials) -> ServiceResult<()>,
{
    save_credentials(&plan.credentials)?;
    if let Err(settings_error) = write_non_sensitive_settings(path, &plan.settings) {
        let rollback_credentials = if plan.account_changed {
            Credentials::default()
        } else {
            plan.previous_credentials.unwrap_or_default()
        };
        return match save_credentials(&rollback_credentials) {
            Ok(()) => Err(settings_error),
            Err(rollback_error) => Err(ServiceError::new(format!(
                "{}；同时无法回滚系统凭据：{}",
                settings_error.message, rollback_error.message
            ))),
        };
    }
    Ok(plan.settings)
}

#[cfg(test)]
fn save_to_path<L, S>(
    path: &Path,
    request: SaveSettingsRequest,
    load_credentials: L,
    save_credentials: S,
) -> ServiceResult<SavedSettings>
where
    L: FnOnce() -> ServiceResult<Option<Credentials>>,
    S: FnMut(&Credentials) -> ServiceResult<()>,
{
    let plan = prepare_save_with(request, load_credentials)?;
    commit_save_to_path(path, plan, save_credentials)
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
        ui_language: &settings.ui_language,
        daily_course_notifications_enabled: settings.daily_course_notifications_enabled,
        automatic_term_detection_enabled: settings.automatic_term_detection_enabled,
        weather_enabled: settings.weather_enabled,
        almanac_enabled: settings.almanac_enabled,
        competition_deadlines_enabled: settings.competition_deadlines_enabled,
        school_contest_notices_enabled: settings.school_contest_notices_enabled,
        summer_camp_deadlines_enabled: settings.summer_camp_deadlines_enabled,
        hackathon_deadlines_enabled: settings.hackathon_deadlines_enabled,
        custom_deadlines_enabled: settings.custom_deadlines_enabled,
        custom_deadlines_url: &settings.custom_deadlines_url,
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

fn mark_account_access_revoked_at_path(path: &Path) -> ServiceResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| ServiceError::new("账号访问状态路径没有父目录。"))?;
    fs::create_dir_all(parent)
        .map_err(|error| ServiceError::new(format!("无法创建账号访问状态目录：{error}")))?;

    let mut file = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(path)
        .map_err(|error| ServiceError::new(format!("无法写入账号访问撤销标记：{error}")))?;

    #[cfg(unix)]
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
        .map_err(|error| ServiceError::new(format!("无法限制账号访问状态文件权限：{error}")))?;

    file.write_all(b"revoked\n")
        .and_then(|_| file.flush())
        .and_then(|_| file.sync_all())
        .map_err(|error| ServiceError::new(format!("无法保存账号访问撤销标记：{error}")))
}

fn clear_account_access_revoked_at_path(path: &Path) -> ServiceResult<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(ServiceError::new(format!(
            "无法清除账号访问撤销标记：{error}"
        ))),
    }
}

fn clear_directory_preserving_revocation(directory: &Path) -> ServiceResult<()> {
    if !directory.exists() {
        return Ok(());
    }

    let entries = fs::read_dir(directory)
        .map_err(|error| ServiceError::new(format!("无法读取本地数据目录：{error}")))?;
    for entry in entries {
        let entry =
            entry.map_err(|error| ServiceError::new(format!("无法读取本地数据项目：{error}")))?;
        if entry.file_name() == ACCOUNT_ACCESS_REVOKED_FILE_NAME {
            continue;
        }
        let file_type = entry
            .file_type()
            .map_err(|error| ServiceError::new(format!("无法检查本地数据项目：{error}")))?;
        let result = if file_type.is_dir() {
            fs::remove_dir_all(entry.path())
        } else {
            fs::remove_file(entry.path())
        };
        result.map_err(|error| {
            ServiceError::new(format!(
                "无法清除本地数据项目 {}：{error}",
                entry.path().display()
            ))
        })?;
    }
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
    use std::cell::{Cell, RefCell};

    const FIXTURE_SCOPE: &str =
        "opaque-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn fixture_credentials(account: &str, password: &str) -> Credentials {
        Credentials {
            account: account.to_string(),
            password: password.to_string(),
            account_scope: if account.is_empty() {
                String::new()
            } else {
                FIXTURE_SCOPE.to_string()
            },
        }
    }

    fn fixture_settings() -> SavedSettings {
        SavedSettings {
            account: "fixture-account".to_string(),
            has_saved_password: true,
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            campus_id: "01".to_string(),
            default_min_seats: 20,
            ui_language: "en".to_string(),
            daily_course_notifications_enabled: true,
            automatic_term_detection_enabled: true,
            weather_enabled: true,
            almanac_enabled: true,
            competition_deadlines_enabled: true,
            school_contest_notices_enabled: true,
            summer_camp_deadlines_enabled: true,
            hackathon_deadlines_enabled: true,
            custom_deadlines_enabled: true,
            custom_deadlines_url: "https://example.com/calendar.json".to_string(),
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
            ui_language: "en".to_string(),
            daily_course_notifications_enabled: true,
            automatic_term_detection_enabled: true,
            weather_enabled: true,
            almanac_enabled: true,
            competition_deadlines_enabled: true,
            school_contest_notices_enabled: true,
            summer_camp_deadlines_enabled: true,
            hackathon_deadlines_enabled: true,
            custom_deadlines_enabled: true,
            custom_deadlines_url: "https://example.com/calendar.json".to_string(),
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
        assert_eq!(value["ui_language"], "en");
        assert_eq!(value["daily_course_notifications_enabled"], true);
        assert_eq!(value["automatic_term_detection_enabled"], true);
        assert_eq!(value["weather_enabled"], true);
        assert_eq!(value["almanac_enabled"], true);
        assert_eq!(value["competition_deadlines_enabled"], true);
        assert_eq!(value["school_contest_notices_enabled"], true);
        assert_eq!(value["summer_camp_deadlines_enabled"], true);
        assert_eq!(value["hackathon_deadlines_enabled"], true);
        assert_eq!(value["custom_deadlines_enabled"], true);
        assert_eq!(
            value["custom_deadlines_url"],
            "https://example.com/calendar.json"
        );
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
        assert!(!loaded.daily_course_notifications_enabled);
        assert!(loaded.automatic_term_detection_enabled);
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
        let stored = fixture_credentials("fixture-account", "existing-secret");

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
        let stored = fixture_credentials("fixture-account", "existing-secret");

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
    fn explicit_password_can_replace_credentials_for_a_changed_account() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = fixture_credentials("fixture-account", "existing-secret");
        let mut request = fixture_request(Some("replacement-secret"));
        request.account = "other-account".to_string();

        let plan = prepare_save_with(request, || Ok(Some(stored.clone())))
            .expect("prepare changed account");
        assert!(plan.account_changed());

        commit_save_to_path(&path, plan, |credentials| {
            assert_eq!(credentials.account, "other-account");
            assert_eq!(credentials.password, "replacement-secret");
            Ok(())
        })
        .expect("replace password");
    }

    #[test]
    fn invalid_term_start_date_is_rejected_before_credentials_are_loaded() {
        for invalid in ["2026-02-30", "2026-13-01", "2026-2-03"] {
            let credentials_loaded = Cell::new(false);
            let mut request = fixture_request(Some("replacement-secret"));
            request.term_start_date = invalid.to_string();

            let result = prepare_save_with(request, || {
                credentials_loaded.set(true);
                Ok(None)
            });
            let error = match result {
                Ok(_) => panic!("invalid date must be rejected"),
                Err(error) => error,
            };

            assert_eq!(
                error.message,
                "第一周周一日期格式不正确，请使用 yyyy-MM-dd。"
            );
            assert!(!credentials_loaded.get());
        }
    }

    #[test]
    fn explicit_password_for_same_account_does_not_change_account_scope() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = fixture_credentials("fixture-account", "existing-secret");
        let plan = prepare_save_with(fixture_request(Some("replacement-secret")), || {
            Ok(Some(stored))
        })
        .expect("prepare same-account password change");

        assert!(!plan.account_changed());
        commit_save_to_path(&path, plan, |credentials| {
            assert_eq!(credentials.account, "fixture-account");
            assert_eq!(credentials.password, "replacement-secret");
            Ok(())
        })
        .expect("save same-account password change");
    }

    #[test]
    fn legacy_secure_credentials_receive_a_new_opaque_scope() {
        let mut legacy = fixture_credentials("fixture-account", "existing-secret");
        legacy.account_scope.clear();

        let plan = prepare_save_with(fixture_request(None), || Ok(Some(legacy)))
            .expect("prepare legacy credential migration");

        assert!(plan.account_changed());
        assert!(crate::scoped_cache::is_valid_account_scope(
            &plan.credentials.account_scope
        ));
        assert!(!plan.credentials.account_scope.contains("fixture-account"));
    }

    #[test]
    fn changed_account_credential_failure_never_persists_identity_or_password() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = fixture_credentials("fixture-account", "existing-secret");
        let mut request = fixture_request(Some("replacement-secret"));
        request.account = "other-account".to_string();
        let plan =
            prepare_save_with(request, || Ok(Some(stored))).expect("prepare changed account");

        let error = commit_save_to_path(&path, plan, |_| {
            Err(ServiceError::new("credential store unavailable"))
        })
        .expect_err("credential save must fail");

        assert_eq!(error.message, "credential store unavailable");
        assert!(!path.exists());
    }

    #[test]
    fn settings_write_failure_rolls_back_same_account_credentials() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let blocking_file = directory.path().join("not-a-directory");
        fs::write(&blocking_file, b"block settings parent").expect("create blocking file");
        let path = blocking_file.join("settings.json");
        let stored = fixture_credentials("fixture-account", "existing-secret");
        let plan = prepare_save_with(fixture_request(Some("replacement-secret")), || {
            Ok(Some(stored.clone()))
        })
        .expect("prepare same-account update");
        let writes = RefCell::new(Vec::new());

        let error = commit_save_to_path(&path, plan, |credentials| {
            writes.borrow_mut().push(credentials.clone());
            Ok(())
        })
        .expect_err("settings write must fail");

        assert!(error.message.contains("无法创建本地设置目录"));
        let writes = writes.into_inner();
        assert_eq!(writes.len(), 2);
        assert_eq!(writes[0].password, "replacement-secret");
        assert_eq!(writes[1], stored);
    }

    #[test]
    fn settings_write_failure_clears_new_changed_account_credentials() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let blocking_file = directory.path().join("not-a-directory");
        fs::write(&blocking_file, b"block settings parent").expect("create blocking file");
        let path = blocking_file.join("settings.json");
        let stored = fixture_credentials("fixture-account", "existing-secret");
        let mut request = fixture_request(Some("replacement-secret"));
        request.account = "other-account".to_string();
        let plan = prepare_save_with(request, || Ok(Some(stored)))
            .expect("prepare changed-account update");
        let writes = RefCell::new(Vec::new());

        commit_save_to_path(&path, plan, |credentials| {
            writes.borrow_mut().push(credentials.clone());
            Ok(())
        })
        .expect_err("settings write must fail");

        let writes = writes.into_inner();
        assert_eq!(writes.len(), 2);
        assert_eq!(writes[0].account, "other-account");
        assert_eq!(writes[0].password, "replacement-secret");
        assert_eq!(writes[1], Credentials::default());
    }

    #[test]
    fn changing_account_without_a_new_password_is_rejected() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = fixture_credentials("fixture-account", "existing-secret");
        let mut request = fixture_request(None);
        request.account = "other-account".to_string();
        let save_called = Cell::new(false);

        let error = save_to_path(
            &path,
            request,
            || Ok(Some(stored)),
            |_| {
                save_called.set(true);
                Ok(())
            },
        )
        .expect_err("changed account must provide a password");

        assert_eq!(error.message, "更换教务账号时必须输入新密码。");
        assert!(!save_called.get());
        assert!(!path.exists());
    }

    #[test]
    fn same_account_without_an_existing_password_is_rejected() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = fixture_credentials("fixture-account", "");

        let error = save_to_path(
            &path,
            fixture_request(None),
            || Ok(Some(stored)),
            |_| Ok(()),
        )
        .expect_err("there is no secure password to preserve");

        assert_eq!(error.message, "更换教务账号时必须输入新密码。");
        assert!(!path.exists());
    }

    #[test]
    fn empty_account_and_password_clear_secure_credentials() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let stored = fixture_credentials("fixture-account", "existing-secret");
        let mut request = fixture_request(Some(""));
        request.account = "  ".to_string();

        let plan =
            prepare_save_with(request, || Ok(Some(stored))).expect("prepare credential clear");
        assert!(plan.account_changed());

        let saved = commit_save_to_path(&path, plan, |credentials| {
            assert!(credentials.account.is_empty());
            assert!(credentials.password.is_empty());
            Ok(())
        })
        .expect("clear secure credentials");

        assert!(saved.account.is_empty());
        assert!(!saved.has_saved_password);
    }

    #[test]
    fn password_without_an_account_is_rejected() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("settings.json");
        let mut request = fixture_request(Some("orphan-secret"));
        request.account = " ".to_string();
        let save_called = Cell::new(false);

        let error = save_to_path(
            &path,
            request,
            || Ok(None),
            |_| {
                save_called.set(true);
                Ok(())
            },
        )
        .expect_err("password requires an account");

        assert_eq!(error.message, "请输入教务账号。");
        assert!(!save_called.get());
        assert!(!path.exists());
    }

    #[test]
    fn stored_password_is_only_merged_for_the_same_account() {
        let stored = fixture_credentials("saved-user", "saved-secret");
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

    #[test]
    fn account_access_revocation_marker_persists_without_sensitive_data() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join(ACCOUNT_ACCESS_REVOKED_FILE_NAME);

        mark_account_access_revoked_at_path(&path).expect("write revocation marker");

        let contents = fs::read_to_string(&path).expect("read revocation marker");
        assert_eq!(contents, "revoked\n");
        assert!(!contents.contains("fixture-account"));
        assert!(!contents.contains("fixture-secret"));

        clear_account_access_revoked_at_path(&path).expect("clear revocation marker");
        assert!(!path.exists());
        clear_account_access_revoked_at_path(&path).expect("repeat marker clear");
    }

    #[test]
    fn local_data_clear_preserves_only_the_revocation_marker() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let marker = directory.path().join(ACCOUNT_ACCESS_REVOKED_FILE_NAME);
        mark_account_access_revoked_at_path(&marker).expect("write revocation marker");
        fs::write(directory.path().join("settings.json"), b"settings")
            .expect("write settings fixture");
        let nested = directory.path().join("nested");
        fs::create_dir(&nested).expect("create nested fixture");
        fs::write(nested.join("cache.json"), b"cache").expect("write cache fixture");

        clear_directory_preserving_revocation(directory.path()).expect("clear local files");

        assert!(marker.exists());
        let entries = fs::read_dir(directory.path())
            .expect("read cleared directory")
            .collect::<Result<Vec<_>, _>>()
            .expect("collect cleared directory");
        assert_eq!(entries.len(), 1);
        assert_eq!(entries[0].file_name(), ACCOUNT_ACCESS_REVOKED_FILE_NAME);
    }
}
