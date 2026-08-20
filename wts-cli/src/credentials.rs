use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use where_to_study_lib::credential_store::Credentials;
use where_to_study_lib::error::{ServiceError, ServiceResult};
use zeroize::Zeroizing;

#[cfg(target_os = "macos")]
const APP_DIRECTORY: &str = "Where To Study";
#[cfg(not(target_os = "macos"))]
const CONFIG_DIRECTORY: &str = "where-to-study";
const CREDENTIALS_FILE: &str = "cli-credentials.json";

/// Interactive password prompt that does not echo input.
pub fn prompt_password(prompt: &str) -> ServiceResult<Zeroizing<String>> {
    print!("{prompt}");
    io::stdout().flush().map_err(|error| {
        where_to_study_lib::error::ServiceError::new(format!("无法刷新终端输出：{error}"))
    })?;
    let password = rpassword::read_password().map_err(|error| {
        where_to_study_lib::error::ServiceError::new(format!("无法读取密码输入：{error}"))
    })?;
    Ok(Zeroizing::new(password))
}

/// Interactive account prompt kept out of process arguments and terminal echo.
pub fn prompt_account() -> ServiceResult<Zeroizing<String>> {
    prompt_password("教务账号（输入不可见）：")
}

/// Save credentials to a user-only local file.
pub fn save(account: &str, password: String) -> ServiceResult<()> {
    let account = account.trim();
    let path = credential_file_path()?;
    let existing = load_from_path(&path)?;
    let account_scope = account_scope_for(existing.as_ref(), account)?;
    let credentials = Credentials {
        account: account.to_string(),
        password,
        account_scope,
    };
    save_to_path(&path, &credentials)
}

fn account_scope_for(existing: Option<&Credentials>, account: &str) -> ServiceResult<String> {
    let preserved_scope = existing
        .filter(|credentials| credentials.account.trim() == account)
        .map(|credentials| credentials.account_scope.as_str())
        .filter(|scope| where_to_study_lib::scoped_cache::is_valid_account_scope(scope));
    if let Some(scope) = preserved_scope {
        Ok(scope.to_string())
    } else {
        where_to_study_lib::scoped_cache::new_account_scope()
    }
}

/// Load credentials from the user-only local file.
pub fn load() -> ServiceResult<Option<Credentials>> {
    load_from_path(&credential_file_path()?)
}

/// Clear credentials from the user-only local file.
pub fn clear() -> ServiceResult<()> {
    clear_path(&credential_file_path()?)
}

pub fn storage_description() -> ServiceResult<String> {
    Ok(credential_file_path()?.display().to_string())
}

fn credential_file_path() -> ServiceResult<PathBuf> {
    #[cfg(target_os = "macos")]
    {
        home_directory().map(|home| {
            home.join("Library")
                .join("Application Support")
                .join(APP_DIRECTORY)
                .join(CREDENTIALS_FILE)
        })
    }

    #[cfg(not(target_os = "macos"))]
    {
        if let Some(config_home) = env::var_os("XDG_CONFIG_HOME").filter(|value| !value.is_empty())
        {
            return Ok(PathBuf::from(config_home)
                .join(CONFIG_DIRECTORY)
                .join(CREDENTIALS_FILE));
        }
        home_directory().map(|home| {
            home.join(".config")
                .join(CONFIG_DIRECTORY)
                .join(CREDENTIALS_FILE)
        })
    }
}

fn home_directory() -> ServiceResult<PathBuf> {
    env::var_os("HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .ok_or_else(|| ServiceError::new("无法确定当前用户主目录（HOME 未设置）。"))
}

fn load_from_path(path: &Path) -> ServiceResult<Option<Credentials>> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => {
            return Err(ServiceError::new(format!(
                "无法检查本地凭据文件 {}：{error}",
                path.display()
            )))
        }
    };
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(ServiceError::new(format!(
            "本地凭据路径不是普通文件：{}",
            path.display()
        )));
    }
    ensure_private_file_permissions(path, &metadata)?;

    let mut file = File::open(path).map_err(|error| {
        ServiceError::new(format!("无法读取本地凭据文件 {}：{error}", path.display()))
    })?;
    let mut payload = Zeroizing::new(Vec::new());
    file.read_to_end(&mut payload).map_err(|error| {
        ServiceError::new(format!("无法读取本地凭据文件 {}：{error}", path.display()))
    })?;
    serde_json::from_slice(&payload)
        .map(Some)
        .map_err(|error| ServiceError::new(format!("本地凭据文件格式不正确：{error}")))
}

fn save_to_path(path: &Path, credentials: &Credentials) -> ServiceResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| ServiceError::new("本地凭据文件路径缺少父目录。"))?;
    ensure_private_directory(parent)?;

    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => {
            return Err(ServiceError::new(format!(
                "本地凭据路径不是普通文件：{}",
                path.display()
            )));
        }
        Ok(_) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => {
            return Err(ServiceError::new(format!(
                "无法检查本地凭据文件 {}：{error}",
                path.display()
            )))
        }
    }

    let payload = Zeroizing::new(
        serde_json::to_vec(credentials)
            .map_err(|error| ServiceError::new(format!("无法序列化账户凭据：{error}")))?,
    );
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let temporary = parent.join(format!(
        ".{CREDENTIALS_FILE}.{}.{}.tmp",
        std::process::id(),
        nonce
    ));

    let result = (|| -> ServiceResult<()> {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        set_private_create_mode(&mut options);
        let mut file = options
            .open(&temporary)
            .map_err(|error| ServiceError::new(format!("无法创建临时凭据文件：{error}")))?;
        file.write_all(&payload)
            .and_then(|_| file.sync_all())
            .map_err(|error| ServiceError::new(format!("无法写入本地凭据文件：{error}")))?;
        fs::rename(&temporary, path)
            .map_err(|error| ServiceError::new(format!("无法保存本地凭据文件：{error}")))?;
        set_private_file_permissions(path)?;
        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

fn clear_path(path: &Path) -> ServiceResult<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_file() => Err(
            ServiceError::new(format!("本地凭据路径不是普通文件：{}", path.display())),
        ),
        Ok(_) => fs::remove_file(path).map_err(|error| {
            ServiceError::new(format!("无法清除本地凭据文件 {}：{error}", path.display()))
        }),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(ServiceError::new(format!(
            "无法检查本地凭据文件 {}：{error}",
            path.display()
        ))),
    }
}

fn ensure_private_directory(path: &Path) -> ServiceResult<()> {
    fs::create_dir_all(path).map_err(|error| {
        ServiceError::new(format!("无法创建凭据目录 {}：{error}", path.display()))
    })?;
    set_private_directory_permissions(path)
}

#[cfg(unix)]
fn set_private_create_mode(options: &mut OpenOptions) {
    use std::os::unix::fs::OpenOptionsExt;
    options.mode(0o600);
}

#[cfg(not(unix))]
fn set_private_create_mode(_options: &mut OpenOptions) {}

#[cfg(unix)]
fn set_private_directory_permissions(path: &Path) -> ServiceResult<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(|error| {
        ServiceError::new(format!("无法设置凭据目录权限 {}：{error}", path.display()))
    })
}

#[cfg(not(unix))]
fn set_private_directory_permissions(_path: &Path) -> ServiceResult<()> {
    Ok(())
}

#[cfg(unix)]
fn set_private_file_permissions(path: &Path) -> ServiceResult<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600)).map_err(|error| {
        ServiceError::new(format!("无法设置凭据文件权限 {}：{error}", path.display()))
    })
}

#[cfg(not(unix))]
fn set_private_file_permissions(_path: &Path) -> ServiceResult<()> {
    Ok(())
}

#[cfg(unix)]
fn ensure_private_file_permissions(path: &Path, metadata: &fs::Metadata) -> ServiceResult<()> {
    use std::os::unix::fs::PermissionsExt;
    if metadata.permissions().mode() & 0o077 != 0 {
        return Err(ServiceError::new(format!(
            "本地凭据文件权限过宽：{}。请运行 chmod 600 后重试。",
            path.display()
        )));
    }
    Ok(())
}

#[cfg(not(unix))]
fn ensure_private_file_permissions(_path: &Path, _metadata: &fs::Metadata) -> ServiceResult<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};

    const VALID_SCOPE: &str =
        "opaque-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    static TEST_ID: AtomicU64 = AtomicU64::new(0);

    fn fixture(account: &str, scope: &str) -> Credentials {
        Credentials {
            account: account.to_string(),
            password: "fixture-password".to_string(),
            account_scope: scope.to_string(),
        }
    }

    fn test_path(name: &str) -> PathBuf {
        let id = TEST_ID.fetch_add(1, Ordering::Relaxed);
        env::temp_dir().join(format!(
            "where-to-study-cli-test-{}-{id}-{name}",
            std::process::id()
        ))
    }

    #[test]
    fn same_account_preserves_valid_desktop_cache_scope() {
        let existing = fixture("2023000000", VALID_SCOPE);
        assert_eq!(
            account_scope_for(Some(&existing), "2023000000").unwrap(),
            VALID_SCOPE
        );
    }

    #[test]
    fn changed_account_or_invalid_scope_gets_new_opaque_scope() {
        let existing = fixture("2023000000", VALID_SCOPE);
        let changed = account_scope_for(Some(&existing), "2023000001").unwrap();
        assert!(where_to_study_lib::scoped_cache::is_valid_account_scope(
            &changed
        ));
        assert_ne!(changed, VALID_SCOPE);

        let invalid = fixture("2023000000", "legacy-scope");
        let repaired = account_scope_for(Some(&invalid), "2023000000").unwrap();
        assert!(where_to_study_lib::scoped_cache::is_valid_account_scope(
            &repaired
        ));
        assert_ne!(repaired, "legacy-scope");
    }

    #[test]
    fn local_file_round_trip_and_clear() {
        let directory = test_path("round-trip");
        let path = directory.join(CREDENTIALS_FILE);
        let credentials = fixture("2023000000", VALID_SCOPE);

        save_to_path(&path, &credentials).unwrap();
        assert_eq!(load_from_path(&path).unwrap(), Some(credentials));

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&directory).unwrap().permissions().mode() & 0o777,
                0o700
            );
            assert_eq!(
                fs::metadata(&path).unwrap().permissions().mode() & 0o777,
                0o600
            );
        }

        clear_path(&path).unwrap();
        assert_eq!(load_from_path(&path).unwrap(), None);
        let _ = fs::remove_dir_all(directory);
    }

    #[cfg(unix)]
    #[test]
    fn rejects_credentials_readable_by_other_users() {
        use std::os::unix::fs::PermissionsExt;

        let directory = test_path("permissions");
        let path = directory.join(CREDENTIALS_FILE);
        save_to_path(&path, &fixture("2023000000", VALID_SCOPE)).unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();

        let error = load_from_path(&path).unwrap_err();
        assert!(error.message.contains("chmod 600"));
        let _ = fs::remove_dir_all(directory);
    }

    #[cfg(unix)]
    #[test]
    fn rejects_symbolic_link_credentials_path() {
        use std::os::unix::fs::symlink;

        let directory = test_path("symlink");
        fs::create_dir_all(&directory).unwrap();
        let target = directory.join("target.json");
        fs::write(&target, b"{}").unwrap();
        let path = directory.join(CREDENTIALS_FILE);
        symlink(&target, &path).unwrap();

        assert!(load_from_path(&path)
            .unwrap_err()
            .message
            .contains("普通文件"));
        assert!(save_to_path(&path, &fixture("2023000000", VALID_SCOPE))
            .unwrap_err()
            .message
            .contains("普通文件"));
        let _ = fs::remove_dir_all(directory);
    }
}
