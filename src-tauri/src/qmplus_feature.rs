//! Public feature preference, independent of credentials and ordinary settings saves.
use serde::{Deserialize, Serialize};
use std::io::Write;
use std::path::Path;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use tauri::Manager;

pub const FILE_NAME: &str = "qmplus-feature.json";
static WRITES: Mutex<()> = Mutex::new(());
static SESSION: SessionPreference = SessionPreference::new();

// One atomic value binds a request generation to its immediate Off fence.
// A completed older On cannot clear an Off request that arrived during I/O.
struct SessionPreference {
    state: AtomicU64,
}
impl SessionPreference {
    const fn new() -> Self {
        Self {
            state: AtomicU64::new(0),
        }
    }
    fn disabled(&self) -> bool {
        self.state.load(Ordering::SeqCst) & 1 != 0
    }
    fn begin(&self, enabled: bool) -> u64 {
        let previous = self
            .state
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |value| {
                Some(value.wrapping_add(2) | if enabled { value & 1 } else { 1 })
            })
            .expect("feature state update always produces a value");
        previous.wrapping_add(2) | if enabled { previous & 1 } else { 1 }
    }
    fn current(&self, request: u64) -> bool {
        self.state.load(Ordering::SeqCst) == request
    }
    fn complete_enable(&self, request: u64) -> Result<(), String> {
        self.state
            .compare_exchange(request, request & !1, Ordering::SeqCst, Ordering::SeqCst)
            .map(|_| ())
            .map_err(|_| "无法保存本地偏好。".into())
    }
}
#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Preference {
    enabled: bool,
}

fn path(app: &tauri::AppHandle) -> Result<std::path::PathBuf, String> {
    app.path()
        .app_config_dir()
        .map(|p| p.join(FILE_NAME))
        .map_err(|_| "无法保存本地偏好。".into())
}
fn write_at(path: &Path, enabled: bool) -> Result<(), String> {
    let directory = path.parent().ok_or("无法保存本地偏好。")?;
    std::fs::create_dir_all(directory).map_err(|_| "无法保存本地偏好。")?;
    let mut temporary =
        tempfile::NamedTempFile::new_in(directory).map_err(|_| "无法保存本地偏好。")?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        temporary
            .as_file()
            .set_permissions(std::fs::Permissions::from_mode(0o600))
            .map_err(|_| "无法保存本地偏好。")?;
    }
    temporary
        .write_all(&serde_json::to_vec(&Preference { enabled }).map_err(|_| "无法保存本地偏好。")?)
        .and_then(|_| temporary.as_file().sync_all())
        .map_err(|_| "无法保存本地偏好。")?;
    temporary.persist(path).map_err(|_| "无法保存本地偏好。")?;
    Ok(())
}
fn load_at(path: &Path) -> Result<bool, String> {
    match std::fs::read(path) {
        Ok(data) if data.len() <= 128 => serde_json::from_slice::<Preference>(&data)
            .map(|p| p.enabled)
            .map_err(|_| "无法保存本地偏好。".into()),
        Ok(_) => Err("无法保存本地偏好。".into()),
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            // An opaque bounded marker is migration evidence; no secret reads.
            let legacy = path.with_file_name("qmplus-autofill-authorization.json");
            let enabled = std::fs::read(legacy)
                .ok()
                .filter(|d| d.len() <= 256)
                .and_then(|d| serde_json::from_slice::<String>(&d).ok())
                .is_some_and(|id| crate::scoped_cache::is_valid_account_scope(&id));
            write_at(path, enabled)?;
            Ok(enabled)
        }
        Err(_) => Err("无法保存本地偏好。".into()),
    }
}
pub fn enabled(app: &tauri::AppHandle) -> Result<bool, String> {
    if SESSION.disabled() {
        return Ok(false);
    }
    let _guard = WRITES.lock().map_err(|_| "无法保存本地偏好。")?;
    if SESSION.disabled() {
        return Ok(false);
    }
    let saved = load_at(&path(app)?)?;
    Ok(saved && !SESSION.disabled())
}
pub fn disable_for_session() {
    SESSION.begin(false);
}
pub fn set(app: &tauri::AppHandle, enabled: bool) -> Result<(), String> {
    let request = SESSION.begin(enabled);
    set_at(&path(app)?, enabled, &SESSION, &WRITES, request)
}
fn set_at(
    path: &Path,
    enabled: bool,
    session: &SessionPreference,
    writes: &Mutex<()>,
    request: u64,
) -> Result<(), String> {
    let _guard = writes.lock().map_err(|_| "无法保存本地偏好。")?;
    if !session.current(request) {
        return Err("无法保存本地偏好。".into());
    }
    write_at(path, enabled)?;
    if enabled {
        session.complete_enable(request)?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn old_enable_completion_cannot_clear_a_newer_immediate_off_fence() {
        let session = SessionPreference::new();
        session.begin(false);
        let on = session.begin(true);
        assert!(
            session.disabled(),
            "On remains fenced until its durable write succeeds"
        );
        session.begin(false);
        assert!(session.complete_enable(on).is_err());
        assert!(session.disabled());
        let current_on = session.begin(true);
        session.complete_enable(current_on).unwrap();
        assert!(!session.disabled());
    }

    #[test]
    fn queued_old_on_write_cannot_overwrite_a_newer_off_request() {
        use std::sync::{mpsc, Arc};
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join(FILE_NAME);
        write_at(&path, false).unwrap();
        let session = Arc::new(SessionPreference::new());
        let writes = Arc::new(Mutex::new(()));
        let held = writes.lock().unwrap();
        let old_on = session.begin(true);
        let (ready, received) = mpsc::channel();
        let worker_session = session.clone();
        let worker_writes = writes.clone();
        let worker_path = path.clone();
        let worker = std::thread::spawn(move || {
            ready.send(()).unwrap();
            set_at(&worker_path, true, &worker_session, &worker_writes, old_on)
        });
        received
            .recv_timeout(std::time::Duration::from_secs(5))
            .unwrap();
        let off = session.begin(false);
        assert!(session.disabled());
        drop(held);
        assert!(worker.join().unwrap().is_err());
        set_at(&path, false, &session, &writes, off).unwrap();
        assert!(!load_at(&path).unwrap());
        assert!(session.disabled());
    }

    #[test]
    fn concurrent_requests_leave_the_latest_atomic_file_preference_and_fence() {
        use std::sync::Arc;
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join(FILE_NAME);
        write_at(&path, false).unwrap();
        let session = Arc::new(SessionPreference::new());
        let writes = Arc::new(Mutex::new(()));
        let workers: Vec<_> = (0..24)
            .map(|index| {
                let session = session.clone();
                let writes = writes.clone();
                let path = path.clone();
                std::thread::spawn(move || {
                    let enabled = index % 2 == 0;
                    let request = session.begin(enabled);
                    let result = set_at(&path, enabled, &session, &writes, request);
                    (request, enabled, result)
                })
            })
            .collect();
        let results: Vec<_> = workers
            .into_iter()
            .map(|worker| worker.join().unwrap())
            .collect();
        let (_, enabled, result) = results
            .iter()
            .max_by_key(|(request, _, _)| request >> 1)
            .unwrap();
        assert!(result.is_ok());
        assert_eq!(load_at(&path).unwrap(), *enabled);
        assert_eq!(session.disabled(), !enabled);
        let value: serde_json::Value =
            serde_json::from_slice(&std::fs::read(path).unwrap()).unwrap();
        assert_eq!(
            value.as_object().unwrap().len(),
            1,
            "File contains only the public bool"
        );
    }

    #[test]
    fn failed_on_write_keeps_off_and_the_last_good_preference() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join(FILE_NAME);
        let session = SessionPreference::new();
        let writes = Mutex::new(());
        let off = session.begin(false);
        set_at(&path, false, &session, &writes, off).unwrap();
        let blocker = directory.path().join("synthetic-file");
        std::fs::write(&blocker, b"synthetic").unwrap();
        let on = session.begin(true);
        assert!(set_at(&blocker.join(FILE_NAME), true, &session, &writes, on).is_err());
        assert!(session.disabled());
        assert!(!load_at(&path).unwrap());
    }

    #[test]
    fn new_default_off_and_opaque_legacy_metadata_migrates_once() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join(FILE_NAME);
        assert!(!load_at(&p).unwrap());
        let id = crate::scoped_cache::new_account_scope().unwrap();
        std::fs::write(
            p.with_file_name("qmplus-autofill-authorization.json"),
            serde_json::to_vec(&id).unwrap(),
        )
        .unwrap();
        assert!(
            !load_at(&p).unwrap(),
            "Explicit Off wins over later metadata"
        );
        std::fs::remove_file(&p).unwrap();
        assert!(load_at(&p).unwrap());
        write_at(&p, false).unwrap();
        assert!(!load_at(&p).unwrap());
    }
    #[test]
    fn invalid_preference_never_enables_and_clear_off_overrides_legacy_marker() {
        let d = tempfile::tempdir().unwrap();
        let p = d.path().join(FILE_NAME);
        std::fs::write(&p, b"{\"enabled\":true,\"account\":\"not-allowed\"}").unwrap();
        assert!(load_at(&p).is_err());
        write_at(&p, false).unwrap();
        assert!(!load_at(&p).unwrap());
    }
}
