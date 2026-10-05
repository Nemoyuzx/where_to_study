//! App-owned browser profiles. The journal holds opaque IDs only, never cookies or credentials.
use serde::{Deserialize, Serialize};
use std::{
    io::Write,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};
use tauri::Manager;

pub const JOURNAL_DIRECTORY: &str = "qmplus-web-session";
pub const PROFILE_DIRECTORY: &str = "qmplus-web-profiles";
pub const RESTART_REQUIRED: &str = "QMplus 网页会话需要清理，请重新启动应用。";
const ERROR: &str = "QMplus 网页会话尚未清除或保存失败，请重试。";
static WRITES: Mutex<()> = Mutex::new(());
static UNSAVED_REVOCATION: AtomicBool = AtomicBool::new(false);
static USED_DIRECTORIES: Mutex<Vec<String>> = Mutex::new(Vec::new());

#[derive(Clone, Copy, Deserialize, Serialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum Backend {
    Directory,
    Webkit,
    Ephemeral,
}
#[derive(Clone, Deserialize, Serialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
struct Profile {
    id: String,
    backend: Backend,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Journal {
    schema_version: u8,
    active: Option<Profile>,
    pending: Vec<Profile>,
}
impl Default for Journal {
    fn default() -> Self {
        Self {
            schema_version: 1,
            active: None,
            pending: Vec::new(),
        }
    }
}
pub struct Lease {
    profile: Profile,
    directory: PathBuf,
}
impl Lease {
    pub fn id(&self) -> &str {
        &self.profile.id
    }
    pub fn persistent(&self) -> bool {
        self.profile.backend != Backend::Ephemeral
    }
    pub fn configure<'a, R: tauri::Runtime, M: tauri::Manager<R>>(
        &self,
        builder: tauri::WebviewWindowBuilder<'a, R, M>,
    ) -> tauri::WebviewWindowBuilder<'a, R, M> {
        match self.profile.backend {
            Backend::Directory => {
                // Runtime WebContexts/network processes can outlive their last
                // window. Never unlink a directory used by this live process.
                USED_DIRECTORIES
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .push(self.profile.id.clone());
                builder
                    .incognito(false)
                    .data_directory(self.directory.clone())
            }
            Backend::Webkit => {
                #[cfg(target_os = "macos")]
                {
                    builder.incognito(false).data_store_identifier(
                        identifier(&self.profile.id).expect("validated profile ID"),
                    )
                }
                #[cfg(not(target_os = "macos"))]
                {
                    builder.incognito(true)
                }
            }
            Backend::Ephemeral => builder.incognito(true),
        }
    }
}
fn identifier(id: &str) -> Option<[u8; 16]> {
    if id.len() != 32
        || !id
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c))
    {
        return None;
    }
    let mut bytes = [0; 16];
    for (index, value) in bytes.iter_mut().enumerate() {
        *value = u8::from_str_radix(&id[index * 2..index * 2 + 2], 16).ok()?;
    }
    Some(bytes)
}
fn new_profile(backend: Backend) -> Result<Profile, String> {
    let mut bytes = [0; 16];
    getrandom::fill(&mut bytes).map_err(|_| ERROR)?;
    Ok(Profile {
        id: bytes.iter().map(|b| format!("{b:02x}")).collect(),
        backend,
    })
}
fn backend() -> Backend {
    #[cfg(any(target_os = "windows", target_os = "linux"))]
    {
        return Backend::Directory;
    }
    #[cfg(target_os = "macos")]
    {
        if objc2_foundation::NSProcessInfo::processInfo()
            .operatingSystemVersion()
            .majorVersion
            >= 14
        {
            return Backend::Webkit;
        }
    }
    Backend::Ephemeral
}
fn private_directory(path: &Path) -> Result<(), String> {
    std::fs::create_dir_all(path).map_err(|_| ERROR)?;
    let metadata = std::fs::symlink_metadata(path).map_err(|_| ERROR)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(ERROR.into());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))
            .map_err(|_| ERROR)?;
    }
    Ok(())
}
fn journal_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    Ok(app
        .path()
        .app_config_dir()
        .map_err(|_| ERROR)?
        .join(JOURNAL_DIRECTORY)
        .join("state.json"))
}
fn profiles_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    Ok(app
        .path()
        .app_local_data_dir()
        .map_err(|_| ERROR)?
        .join(PROFILE_DIRECTORY))
}
fn load(path: &Path) -> Result<Journal, String> {
    let bytes = match std::fs::read(path) {
        Ok(bytes) if bytes.len() <= 16 * 1024 => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Journal::default()),
        _ => return Err(ERROR.into()),
    };
    let journal: Journal = serde_json::from_slice(&bytes).map_err(|_| ERROR)?;
    if journal.schema_version != 1
        || journal.pending.len() > 64
        || journal
            .active
            .iter()
            .chain(journal.pending.iter())
            .any(|profile| identifier(&profile.id).is_none())
        || journal.active.as_ref().is_some_and(|profile| {
            journal
                .pending
                .iter()
                .any(|pending| pending.id == profile.id)
        })
    {
        return Err(ERROR.into());
    }
    Ok(journal)
}
fn save(path: &Path, journal: &Journal) -> Result<(), String> {
    let parent = path.parent().ok_or(ERROR)?;
    private_directory(parent)?;
    let mut file = tempfile::NamedTempFile::new_in(parent).map_err(|_| ERROR)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        file.as_file()
            .set_permissions(std::fs::Permissions::from_mode(0o600))
            .map_err(|_| ERROR)?;
    }
    file.write_all(&serde_json::to_vec(journal).map_err(|_| ERROR)?)
        .and_then(|_| file.as_file().sync_all())
        .map_err(|_| ERROR)?;
    file.persist(path).map_err(|_| ERROR)?;
    #[cfg(unix)]
    {
        std::fs::File::open(parent)
            .and_then(|directory| directory.sync_all())
            .map_err(|_| ERROR)?;
    }
    Ok(())
}
pub fn prepare(app: &tauri::AppHandle) -> Result<Lease, String> {
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    if UNSAVED_REVOCATION.load(Ordering::SeqCst) {
        return Err(ERROR.into());
    }
    let path = journal_path(app)?;
    let mut journal = load(&path)?;
    if !journal.pending.is_empty() {
        return Err(ERROR.into());
    }
    if journal.active.as_ref().is_some_and(|profile| {
        profile.backend == Backend::Ephemeral && backend() != Backend::Ephemeral
    }) {
        // A terminated ephemeral context has no browser data to migrate.
        journal.active = None;
    }
    if journal.active.is_none() {
        journal.active = Some(new_profile(backend())?);
        save(&path, &journal)?;
    }
    let profile = journal.active.ok_or(ERROR)?;
    if profile.backend != backend() {
        return Err(ERROR.into());
    }
    let root = profiles_path(app)?;
    let directory = root.join(&profile.id);
    if profile.backend == Backend::Directory {
        private_directory(&root)?;
        private_directory(&directory)?;
    }
    Ok(Lease { profile, directory })
}
pub fn current(app: &tauri::AppHandle, id: Option<&str>) -> bool {
    let Ok(_guard) = WRITES.lock() else {
        return false;
    };
    if UNSAVED_REVOCATION.load(Ordering::SeqCst) {
        return false;
    }
    journal_path(app)
        .and_then(|path| load(&path))
        .ok()
        .is_some_and(|journal| {
            journal.pending.is_empty()
                && journal.active.as_ref().is_some_and(|profile| {
                    Some(profile.id.as_str()) == id && profile.backend == backend()
                })
        })
}
pub fn authorization_ready(app: &tauri::AppHandle) -> bool {
    let Ok(_guard) = WRITES.lock() else {
        return false;
    };
    !UNSAVED_REVOCATION.load(Ordering::SeqCst)
        && journal_path(app)
            .and_then(|path| load(&path))
            .ok()
            .is_some_and(|journal| journal.pending.is_empty())
}
pub fn active_profile_ready(app: &tauri::AppHandle) -> bool {
    let Ok(_guard) = WRITES.lock() else {
        return false;
    };
    !UNSAVED_REVOCATION.load(Ordering::SeqCst)
        && journal_path(app)
            .and_then(|path| load(&path))
            .ok()
            .is_some_and(|journal| {
                journal.pending.is_empty()
                    && journal
                        .active
                        .as_ref()
                        .is_some_and(|profile| profile.backend == backend())
            })
}
pub fn mark_for_removal(app: &tauri::AppHandle) -> Result<(), String> {
    UNSAVED_REVOCATION.store(true, Ordering::SeqCst);
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    UNSAVED_REVOCATION.store(true, Ordering::SeqCst);
    let path = journal_path(app)?;
    let mut journal = load(&path)?;
    if let Some(profile) = journal.active.take() {
        journal.pending.push(profile);
    }
    save(&path, &journal)?;
    UNSAVED_REVOCATION.store(false, Ordering::SeqCst);
    Ok(())
}
fn remove_directory(root: &Path, profile: &Profile) -> Result<(), String> {
    identifier(&profile.id).ok_or(ERROR)?;
    match std::fs::symlink_metadata(root) {
        Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        _ => return Err(ERROR.into()),
    }
    let target = root.join(&profile.id);
    match std::fs::remove_dir_all(target) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(ERROR.into()),
    }
}
#[cfg(target_os = "macos")]
async fn remove_webkit_store(app: &tauri::AppHandle, id: &str) -> Result<(), String> {
    use wry::{WebView, WebViewExtDarwin};
    if backend() != Backend::Webkit {
        return Err(ERROR.into());
    }
    let bytes = identifier(id).ok_or(ERROR)?;
    let (sent, received) = tokio::sync::oneshot::channel();
    app.run_on_main_thread(move || {
        if WebView::fetch_data_store_identifiers(move |identifiers| {
            let _ = sent.send(identifiers);
        })
        .is_err()
        { /* receiver fails closed */ }
    })
    .map_err(|_| ERROR)?;
    let identifiers = tokio::time::timeout(std::time::Duration::from_secs(10), received)
        .await
        .map_err(|_| ERROR)?
        .map_err(|_| ERROR)?;
    if !identifiers.contains(&bytes) {
        return Ok(());
    }
    let (sent, received) = tokio::sync::oneshot::channel();
    app.run_on_main_thread(move || {
        WebView::remove_data_store(&bytes, move |result| {
            let _ = sent.send(result.is_ok());
        });
    })
    .map_err(|_| ERROR)?;
    if tokio::time::timeout(std::time::Duration::from_secs(10), received)
        .await
        .map_err(|_| ERROR)?
        .map_err(|_| ERROR)?
    {
        Ok(())
    } else {
        Err(ERROR.into())
    }
}
pub async fn recover_pending(app: &tauri::AppHandle) -> Result<(), String> {
    let pending = {
        let _guard = WRITES.lock().map_err(|_| ERROR)?;
        let journal = load(&journal_path(app)?)?;
        if UNSAVED_REVOCATION.load(Ordering::SeqCst) {
            return Err(ERROR.into());
        }
        journal.pending
    };
    for profile in pending {
        match profile.backend {
            Backend::Directory => {
                if USED_DIRECTORIES
                    .lock()
                    .map_err(|_| ERROR)?
                    .contains(&profile.id)
                {
                    return Err(RESTART_REQUIRED.into());
                }
                let root = profiles_path(app)?;
                let removing = profile.clone();
                tauri::async_runtime::spawn_blocking(move || remove_directory(&root, &removing))
                    .await
                    .map_err(|_| ERROR)??;
            }
            Backend::Webkit => {
                #[cfg(target_os = "macos")]
                {
                    remove_webkit_store(app, &profile.id).await?;
                }
                #[cfg(not(target_os = "macos"))]
                {
                    return Err(ERROR.into());
                }
            }
            Backend::Ephemeral => {}
        }
        let _guard = WRITES.lock().map_err(|_| ERROR)?;
        let path = journal_path(app)?;
        let mut journal = load(&path)?;
        journal.pending.retain(|pending| pending != &profile);
        save(&path, &journal)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn pending_profiles_are_never_active_and_private_metadata_has_no_session_values() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("session/state.json");
        let profile = new_profile(Backend::Directory).unwrap();
        let mut journal = Journal {
            active: Some(profile.clone()),
            ..Journal::default()
        };
        save(&path, &journal).unwrap();
        journal.pending.push(journal.active.take().unwrap());
        save(&path, &journal).unwrap();
        let restored = load(&path).unwrap();
        assert!(restored.active.is_none());
        assert_eq!(restored.pending[0].id, profile.id);
        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        assert!(
            value.get("cookie").is_none()
                && value.get("password").is_none()
                && value.get("token").is_none()
        );
    }
    #[test]
    fn only_owned_fixed_ids_can_select_a_profile_directory() {
        for value in [
            "",
            "..",
            "../other",
            "/",
            "ABCDEF0123456789ABCDEF0123456789",
        ] {
            assert!(identifier(value).is_none());
        }
        assert!(identifier("0123456789abcdef0123456789abcdef").is_some());
    }
}
