use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};

use serde::{Deserialize, Serialize};
use where_to_study_lib::error::{ServiceError, ServiceResult};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

const CREDENTIALS_FILE_NAME: &str = "credentials.json";
static TEMP_FILE_SEQUENCE: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct Credentials {
    pub account: String,
    pub password: String,
    #[serde(default)]
    pub account_scope: String,
}

pub fn load() -> ServiceResult<Option<Credentials>> {
    load_from(&credentials_path()?)
}

pub fn save(credentials: &Credentials) -> ServiceResult<()> {
    save_to(&credentials_path()?, credentials)
}

pub fn clear() -> ServiceResult<()> {
    clear_from(&credentials_path()?)
}

fn credentials_path() -> ServiceResult<PathBuf> {
    default_config_root()
        .map(|root| {
            root.join("where-to-study")
                .join("wts-tui")
                .join(CREDENTIALS_FILE_NAME)
        })
        .ok_or_else(|| ServiceError::new("无法确定 TUI 本地凭据文件目录"))
}

#[cfg(target_os = "windows")]
fn default_config_root() -> Option<PathBuf> {
    env::var_os("LOCALAPPDATA")
        .or_else(|| env::var_os("APPDATA"))
        .or_else(|| {
            env::var_os("USERPROFILE").map(|home| {
                PathBuf::from(home)
                    .join("AppData")
                    .join("Local")
                    .into_os_string()
            })
        })
        .map(PathBuf::from)
}

#[cfg(target_os = "macos")]
fn default_config_root() -> Option<PathBuf> {
    env::var_os("HOME").map(|home| {
        PathBuf::from(home)
            .join("Library")
            .join("Application Support")
    })
}

#[cfg(all(not(target_os = "windows"), not(target_os = "macos")))]
fn default_config_root() -> Option<PathBuf> {
    env::var_os("XDG_CONFIG_HOME")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
}

fn load_from(path: &Path) -> ServiceResult<Option<Credentials>> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(file_error("无法检查 TUI 本地凭据文件", path, error)),
    };
    validate_credential_file(path, &metadata)?;
    tighten_file_permissions(path)?;

    let payload = Zeroizing::new(
        fs::read(path).map_err(|error| file_error("无法读取 TUI 本地凭据文件", path, error))?,
    );
    serde_json::from_slice(&payload).map(Some).map_err(|error| {
        ServiceError::new(format!(
            "TUI 本地凭据文件格式不正确（{}）：{error}",
            path.display()
        ))
    })
}

fn save_to(path: &Path, credentials: &Credentials) -> ServiceResult<()> {
    if credentials.account.is_empty() && credentials.password.is_empty() {
        return clear_from(path);
    }

    let parent = parent_directory(path);
    create_private_directory(parent)?;
    match fs::symlink_metadata(path) {
        Ok(metadata) => validate_credential_file(path, &metadata)?,
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => return Err(file_error("无法检查 TUI 本地凭据文件", path, error)),
    }

    let payload = Zeroizing::new(
        serde_json::to_vec(credentials)
            .map_err(|error| ServiceError::new(format!("无法序列化 TUI 本地账户凭据：{error}")))?,
    );
    let (temporary_path, mut temporary_file) = create_private_temp_file(path, parent)?;
    let write_result = (|| -> ServiceResult<()> {
        temporary_file
            .write_all(&payload)
            .map_err(|error| file_error("无法写入 TUI 临时凭据文件", &temporary_path, error))?;
        temporary_file
            .flush()
            .map_err(|error| file_error("无法刷新 TUI 临时凭据文件", &temporary_path, error))?;
        temporary_file
            .sync_all()
            .map_err(|error| file_error("无法同步 TUI 临时凭据文件", &temporary_path, error))?;
        drop(temporary_file);
        replace_file(&temporary_path, path)?;
        tighten_file_permissions(path)?;
        sync_directory(parent);
        Ok(())
    })();

    if write_result.is_err() {
        let _ = fs::remove_file(&temporary_path);
    }
    write_result
}

fn clear_from(path: &Path) -> ServiceResult<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) => {
            validate_credential_file(path, &metadata)?;
            fs::remove_file(path)
                .map_err(|error| file_error("无法清除 TUI 本地凭据文件", path, error))?;
            sync_directory(parent_directory(path));
            Ok(())
        }
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(file_error("无法检查 TUI 本地凭据文件", path, error)),
    }
}

fn parent_directory(path: &Path) -> &Path {
    path.parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .unwrap_or_else(|| Path::new("."))
}

fn create_private_directory(path: &Path) -> ServiceResult<()> {
    fs::create_dir_all(path)
        .map_err(|error| file_error("无法创建 TUI 本地凭据目录", path, error))?;
    let metadata = fs::symlink_metadata(path)
        .map_err(|error| file_error("无法检查 TUI 本地凭据目录", path, error))?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(ServiceError::new(format!(
            "TUI 本地凭据目录必须是普通目录：{}",
            path.display()
        )));
    }
    tighten_directory_permissions(path)
}

fn create_private_temp_file(path: &Path, parent: &Path) -> ServiceResult<(PathBuf, File)> {
    let file_name = path
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(CREDENTIALS_FILE_NAME);
    for _ in 0..16 {
        let sequence = TEMP_FILE_SEQUENCE.fetch_add(1, Ordering::Relaxed);
        let temporary_path = parent.join(format!(
            ".{file_name}.{}.{}.tmp",
            std::process::id(),
            sequence
        ));
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)]
        {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        match options.open(&temporary_path) {
            Ok(file) => return Ok((temporary_path, file)),
            Err(error) if error.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(error) => {
                return Err(file_error(
                    "无法创建 TUI 临时凭据文件",
                    &temporary_path,
                    error,
                ));
            }
        }
    }
    Err(ServiceError::new("无法分配 TUI 临时凭据文件名"))
}

fn replace_file(source: &Path, destination: &Path) -> ServiceResult<()> {
    #[cfg(target_os = "windows")]
    if destination.exists() {
        fs::remove_file(destination)
            .map_err(|error| file_error("无法替换旧的 TUI 本地凭据文件", destination, error))?;
    }

    fs::rename(source, destination)
        .map_err(|error| file_error("无法提交 TUI 本地凭据文件", destination, error))
}

fn validate_credential_file(path: &Path, metadata: &fs::Metadata) -> ServiceResult<()> {
    if metadata.file_type().is_symlink() {
        return Err(ServiceError::new(format!(
            "拒绝使用符号链接作为 TUI 本地凭据文件：{}",
            path.display()
        )));
    }
    if !metadata.is_file() {
        return Err(ServiceError::new(format!(
            "TUI 本地凭据路径不是普通文件：{}",
            path.display()
        )));
    }
    Ok(())
}

#[cfg(unix)]
fn tighten_directory_permissions(path: &Path) -> ServiceResult<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
        .map_err(|error| file_error("无法限制 TUI 本地凭据目录权限", path, error))
}

#[cfg(not(unix))]
fn tighten_directory_permissions(_path: &Path) -> ServiceResult<()> {
    Ok(())
}

#[cfg(unix)]
fn tighten_file_permissions(path: &Path) -> ServiceResult<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
        .map_err(|error| file_error("无法限制 TUI 本地凭据文件权限", path, error))
}

#[cfg(not(unix))]
fn tighten_file_permissions(_path: &Path) -> ServiceResult<()> {
    Ok(())
}

#[cfg(unix)]
fn sync_directory(path: &Path) {
    let _ = File::open(path).and_then(|directory| directory.sync_all());
}

#[cfg(not(unix))]
fn sync_directory(_path: &Path) {}

fn file_error(context: &str, path: &Path, error: io::Error) -> ServiceError {
    ServiceError::new(format!("{context}（{}）：{error}", path.display()))
}

#[cfg(test)]
mod tests {
    use super::*;

    static TEST_SEQUENCE: AtomicU64 = AtomicU64::new(0);

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new(name: &str) -> Self {
            let sequence = TEST_SEQUENCE.fetch_add(1, Ordering::Relaxed);
            let path =
                env::temp_dir().join(format!("wts-tui-{name}-{}-{sequence}", std::process::id()));
            fs::create_dir_all(&path).expect("create test directory");
            Self(path)
        }

        fn credentials_path(&self) -> PathBuf {
            self.0.join("private").join(CREDENTIALS_FILE_NAME)
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn fixture(account: &str, password: &str) -> Credentials {
        Credentials {
            account: account.to_string(),
            password: password.to_string(),
            account_scope:
                "opaque-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                    .to_string(),
        }
    }

    fn temporary_password(label: &str) -> String {
        format!("{label}-{}", std::process::id())
    }

    #[test]
    fn credentials_round_trip_overwrite_and_clear() {
        let directory = TestDirectory::new("round-trip");
        let path = directory.credentials_path();
        let first_password = temporary_password("first");
        let second_password = temporary_password("second");
        assert_eq!(load_from(&path).unwrap(), None);

        save_to(&path, &fixture("2023000000", &first_password)).unwrap();
        assert_eq!(
            load_from(&path).unwrap().unwrap(),
            fixture("2023000000", &first_password)
        );

        save_to(&path, &fixture("2023000001", &second_password)).unwrap();
        assert_eq!(
            load_from(&path).unwrap().unwrap(),
            fixture("2023000001", &second_password)
        );

        clear_from(&path).unwrap();
        assert_eq!(load_from(&path).unwrap(), None);
        clear_from(&path).unwrap();
    }

    #[test]
    fn malformed_payload_is_rejected() {
        let directory = TestDirectory::new("malformed");
        let path = directory.credentials_path();
        create_private_directory(parent_directory(&path)).unwrap();
        fs::write(&path, b"not-json").unwrap();

        let error = load_from(&path).unwrap_err();
        assert!(error.message.contains("格式不正确"));
    }

    #[cfg(unix)]
    #[test]
    fn unix_permissions_are_private() {
        use std::os::unix::fs::PermissionsExt;

        let directory = TestDirectory::new("permissions");
        let path = directory.credentials_path();
        let password = temporary_password("permissions");
        save_to(&path, &fixture("2023000000", &password)).unwrap();

        assert_eq!(
            fs::metadata(parent_directory(&path))
                .unwrap()
                .permissions()
                .mode()
                & 0o777,
            0o700
        );
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }

    #[cfg(unix)]
    #[test]
    fn symbolic_link_is_rejected() {
        use std::os::unix::fs::symlink;

        let directory = TestDirectory::new("symlink");
        let path = directory.credentials_path();
        create_private_directory(parent_directory(&path)).unwrap();
        let target = directory.0.join("target.json");
        fs::write(&target, b"{}").unwrap();
        symlink(&target, &path).unwrap();

        let error = load_from(&path).unwrap_err();
        assert!(error.message.contains("符号链接"));
    }
}
