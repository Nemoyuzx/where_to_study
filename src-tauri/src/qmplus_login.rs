//! Separate, opt-in QM credential record. Commands return status, never secrets.
use crate::credential_store::{self, Credentials};
use serde::{Deserialize, Serialize};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::Manager;
use zeroize::{Zeroize, ZeroizeOnDrop};

const ENTRY: &str = "qmplus-microsoft-v1";
const JOURNAL: &str = "qmplus-autofill-authorization.json";
static GATE: Mutex<LoginGate> = Mutex::new(LoginGate { blocked: false });
static REVISION: AtomicU64 = AtomicU64::new(0);
struct LoginGate {
    blocked: bool,
}

#[derive(Default, Clone, Serialize)]
pub struct LoginStatus {
    pub saved: bool,
    pub enabled: bool,
}
#[derive(Deserialize, Zeroize, ZeroizeOnDrop)]
#[serde(deny_unknown_fields)]
pub struct LoginRequest {
    account: String,
    password: String,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AutofillRequest {
    enabled: bool,
}

fn valid(record: &Credentials) -> bool {
    record.account.len() <= 320
        && record.account.split('@').count() == 2
        && record.account.split('@').all(|part| !part.is_empty())
        && !record.account.chars().any(char::is_whitespace)
        && !record.password.is_empty()
        && record.password.encode_utf16().count() <= 2048
        && record.password.len() <= 4096
        && record.teaching_cloud_password.is_none()
        && crate::scoped_cache::is_valid_account_scope(&record.account_scope)
}

fn journal_path(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    app.path()
        .app_config_dir()
        .map(|p| p.join(JOURNAL))
        .map_err(|_| "QMplus 本地授权不可用。".into())
}
fn marker(app: &tauri::AppHandle) -> Result<Option<String>, String> {
    let path = journal_path(app)?;
    match std::fs::read(path) {
        Ok(bytes) if bytes.len() <= 256 => serde_json::from_slice(&bytes)
            .map(Some)
            .map_err(|_| "QMplus 本地授权格式不正确。".into()),
        Ok(_) => Err("QMplus 本地授权格式不正确。".into()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(None),
        Err(_) => Err("无法读取 QMplus 本地授权。".into()),
    }
}
fn revoke_marker(app: &tauri::AppHandle) -> Result<(), String> {
    match std::fs::remove_file(journal_path(app)?) {
        Ok(()) => Ok(()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err("无法撤销 QMplus 本地授权。".into()),
    }
}
fn authorize(app: &tauri::AppHandle, record_id: &str) -> Result<(), String> {
    use std::io::Write;
    let path = journal_path(app)?;
    let parent = path.parent().ok_or("QMplus 本地授权不可用。")?;
    std::fs::create_dir_all(parent).map_err(|_| "无法保存 QMplus 本地授权。")?;
    let mut file =
        tempfile::NamedTempFile::new_in(parent).map_err(|_| "无法保存 QMplus 本地授权。")?;
    file.write_all(&serde_json::to_vec(record_id).map_err(|_| "QMplus 本地授权格式不正确。")?)
        .and_then(|_| file.as_file().sync_all())
        .map_err(|_| "无法保存 QMplus 本地授权。")?;
    file.persist(path)
        .map_err(|_| "无法保存 QMplus 本地授权。")?;
    if marker(app)?.as_deref() != Some(record_id) {
        return Err("QMplus 本地授权验证失败。".into());
    }
    Ok(())
}
fn load() -> Result<Option<Credentials>, String> {
    let record = credential_store::load_named(ENTRY).map_err(|_| "无法读取 QMplus 安全存储。")?;
    if record.as_ref().is_some_and(|r| !valid(r)) {
        return Err("QMplus 安全记录格式不正确。".into());
    }
    Ok(record)
}
fn status(app: &tauri::AppHandle, blocked: bool) -> Result<LoginStatus, String> {
    let record = load()?;
    Ok(LoginStatus {
        saved: record.is_some(),
        enabled: !blocked
            && record.as_ref().is_some_and(|r| {
                marker(app).ok().flatten().as_deref() == Some(r.account_scope.as_str())
            }),
    })
}

pub fn authorized(app: &tauri::AppHandle) -> Option<Credentials> {
    let gate = GATE.lock().ok()?;
    if gate.blocked {
        return None;
    }
    let record = load().ok()??;
    (marker(app).ok().flatten().as_deref() == Some(record.account_scope.as_str())).then_some(record)
}

pub fn revision() -> u64 {
    REVISION.load(Ordering::SeqCst)
}

pub fn clear(app: &tauri::AppHandle) -> Result<(), String> {
    REVISION.fetch_add(1, Ordering::SeqCst);
    let mut gate = GATE.lock().map_err(|_| "QMplus 安全存储正忙。")?;
    gate.blocked = true;
    let revoke = revoke_marker(app);
    let remove = credential_store::save_named(&Credentials::default(), ENTRY)
        .map_err(|_| "QMplus 安全记录未能删除。".to_string());
    match (revoke, remove) {
        (Ok(_), Ok(_)) => Ok(()),
        (Err(_), Err(_)) => {
            Err("QMplus 已在本次使用中停用，但授权与安全记录均未能删除；下次启动前请重试。".into())
        }
        (_, Err(e)) | (Err(e), _) => Err(e),
    }
}

#[tauri::command]
pub async fn load_qmplus_login(app: tauri::AppHandle) -> Result<LoginStatus, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let gate = GATE.lock().map_err(|_| "QMplus 安全存储正忙。")?;
        status(&app, gate.blocked)
    })
    .await
    .map_err(|_| "QMplus 安全存储不可用。".to_string())?
}

#[tauri::command]
pub async fn save_qmplus_login(
    app: tauri::AppHandle,
    payload: LoginRequest,
) -> Result<LoginStatus, String> {
    // Own the request secrets only until this background transaction finishes.
    let revision = REVISION.fetch_add(1, Ordering::SeqCst) + 1;
    crate::qmplus::disconnect_qmplus(app.clone(), app.state::<crate::qmplus::QmState>());
    tauri::async_runtime::spawn_blocking(move || {
        let mut gate = GATE.lock().map_err(|_| "QMplus 安全存储正忙。")?;
        if REVISION.load(Ordering::SeqCst) != revision {
            return Err("QMplus 保存请求已失效。".into());
        }
        gate.blocked = true;
        revoke_marker(&app)?;
        let record = Credentials {
            account: payload.account.trim().to_string(),
            password: payload.password.clone(),
            teaching_cloud_password: None,
            account_scope: crate::scoped_cache::new_account_scope()
                .map_err(|_| "无法准备 QMplus 安全记录。")?,
        };
        if !valid(&record) {
            return Err("请输入有效的 QMplus 邮箱和密码。".into());
        }
        credential_store::save_named(&record, ENTRY).map_err(|_| "无法保存 QMplus 安全记录。")?;
        if load()?.as_ref() != Some(&record) {
            return Err("QMplus 安全记录验证失败。".into());
        }
        // Saving is not permission to submit credentials. A separate switch authorizes it.
        Ok(LoginStatus {
            saved: true,
            enabled: false,
        })
    })
    .await
    .map_err(|_| "QMplus 安全存储不可用。".to_string())?
}

#[tauri::command]
pub async fn set_qmplus_autofill(
    app: tauri::AppHandle,
    payload: AutofillRequest,
) -> Result<LoginStatus, String> {
    let revision = REVISION.fetch_add(1, Ordering::SeqCst) + 1;
    crate::qmplus::disconnect_qmplus(app.clone(), app.state::<crate::qmplus::QmState>());
    tauri::async_runtime::spawn_blocking(move || {
        let mut gate = GATE.lock().map_err(|_| "QMplus 安全存储正忙。")?;
        if REVISION.load(Ordering::SeqCst) != revision {
            return Err("QMplus 授权请求已失效。".into());
        }
        gate.blocked = true;
        if payload.enabled {
            let record = load()?.ok_or("请先保存 QMplus 账号和密码。")?;
            authorize(&app, &record.account_scope)?;
            gate.blocked = false;
        } else if revoke_marker(&app).is_err() {
            credential_store::save_named(&Credentials::default(), ENTRY)
                .map_err(|_| "本次已停用，永久撤销失败；下次启动前请重试。")?;
        }
        status(&app, gate.blocked)
    })
    .await
    .map_err(|_| "QMplus 安全存储不可用。".to_string())?
}

#[tauri::command]
pub async fn clear_qmplus_login(app: tauri::AppHandle) -> Result<LoginStatus, String> {
    REVISION.fetch_add(1, Ordering::SeqCst);
    crate::qmplus::disconnect_qmplus(app.clone(), app.state::<crate::qmplus::QmState>());
    tauri::async_runtime::spawn_blocking(move || {
        clear(&app)?;
        Ok(LoginStatus::default())
    })
    .await
    .map_err(|_| "QMplus 安全存储不可用。".to_string())?
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn independent_record_requires_an_explicit_opaque_marker_and_bounded_email_password() {
        let mut record = Credentials {
            account: "student@example.org".into(),
            password: "synthetic".into(),
            teaching_cloud_password: None,
            account_scope: format!("opaque-v1:{}", "a".repeat(64)),
        };
        assert!(valid(&record));
        record.password = "x".repeat(2049);
        assert!(!valid(&record));
        record.password = "synthetic".into();
        record.account_scope.clear();
        assert!(!valid(&record));
        record.account_scope = format!("opaque-v1:{}", "a".repeat(64));
        record.teaching_cloud_password = Some("forbidden".into());
        assert!(!valid(&record));
        assert_ne!(ENTRY, "default-account");
    }
    #[test]
    fn ui_metadata_never_serializes_credentials() {
        let json = serde_json::to_string(&LoginStatus {
            saved: true,
            enabled: false,
        })
        .unwrap();
        assert_eq!(json, r#"{"saved":true,"enabled":false}"#);
    }
}
