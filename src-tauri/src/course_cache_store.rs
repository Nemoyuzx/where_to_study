//! Bounded, app-private business DTOs only. No cookie, token, account or password.
use crate::qmplus::Snapshot;
#[cfg(test)]
use crate::{assignments::CourseRef, models::AssignmentDeadlineItem};
use serde::{Deserialize, Serialize};
use std::{
    fs,
    io::{Read, Write},
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, Ordering},
        Mutex,
    },
};
use tauri::Manager;

const DIRECTORY: &str = "course-business-cache";
const LIMIT: usize = 512 * 1024;
const ERROR: &str = "无法保存本地偏好。";
static WRITES: Mutex<()> = Mutex::new(());
static CLOUD_OWNER_BLOCKED: AtomicBool = AtomicBool::new(false);

pub use crate::assignments::CloudCatalogue;
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct CloudOwner {
    schema_version: u8,
    owner_epoch: String,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct CloudEnvelope {
    schema_version: u8,
    account_scope: String,
    owner_epoch: String,
    payload: CloudCatalogue,
}
#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct QmEnvelope {
    schema_version: u8,
    profile_id: String,
    payload: Snapshot,
}

fn root(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let path = app
        .path()
        .app_config_dir()
        .map_err(|_| ERROR)?
        .join(DIRECTORY);
    match fs::symlink_metadata(&path) {
        Ok(value) if value.is_dir() && !value.file_type().is_symlink() => {}
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        _ => return Err(ERROR.into()),
    }
    Ok(path)
}
fn private_directory(path: &Path) -> Result<(), String> {
    fs::create_dir_all(path).map_err(|_| ERROR)?;
    let metadata = fs::symlink_metadata(path).map_err(|_| ERROR)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(ERROR.into());
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o700)).map_err(|_| ERROR)?;
    }
    Ok(())
}
fn read(path: &Path, limit: usize) -> Result<Option<Vec<u8>>, String> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(value) => value,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(_) => return Err(ERROR.into()),
    };
    if !metadata.is_file() || metadata.file_type().is_symlink() || metadata.len() > limit as u64 {
        return Ok(None);
    }
    let mut bytes = Vec::new();
    fs::File::open(path)
        .map_err(|_| ERROR)?
        .take(limit as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| ERROR)?;
    Ok((bytes.len() <= limit).then_some(bytes))
}
fn write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path.parent().ok_or(ERROR)?;
    private_directory(parent)?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent).map_err(|_| ERROR)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        temporary
            .as_file()
            .set_permissions(fs::Permissions::from_mode(0o600))
            .map_err(|_| ERROR)?;
    }
    temporary.write_all(bytes).map_err(|_| ERROR)?;
    temporary.as_file().sync_all().map_err(|_| ERROR)?;
    temporary.persist(path).map_err(|_| ERROR)?;
    #[cfg(unix)]
    {
        fs::File::open(parent)
            .and_then(|file| file.sync_all())
            .map_err(|_| ERROR)?;
    }
    Ok(())
}
fn owner_at(path: &Path) -> Result<String, String> {
    if let Some(bytes) = read(path, 4096)? {
        let owner: CloudOwner = serde_json::from_slice(&bytes).map_err(|_| ERROR)?;
        if owner.schema_version != 1
            || !crate::scoped_cache::is_valid_account_scope(&owner.owner_epoch)
        {
            return Err(ERROR.into());
        }
        return Ok(owner.owner_epoch);
    }
    let owner = CloudOwner {
        schema_version: 1,
        owner_epoch: crate::scoped_cache::new_account_scope().map_err(|_| ERROR)?,
    };
    write(path, &serde_json::to_vec(&owner).map_err(|_| ERROR)?)?;
    Ok(owner.owner_epoch)
}
pub fn cloud_owner(app: &tauri::AppHandle) -> Result<String, String> {
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    if CLOUD_OWNER_BLOCKED.load(Ordering::SeqCst) {
        return Err(ERROR.into());
    }
    owner_at(&root(app)?.join("cloud-owner.json"))
}
pub fn rotate_cloud_owner(app: &tauri::AppHandle) -> Result<(), String> {
    CLOUD_OWNER_BLOCKED.store(true, Ordering::SeqCst);
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    CLOUD_OWNER_BLOCKED.store(true, Ordering::SeqCst);
    let owner = CloudOwner {
        schema_version: 1,
        owner_epoch: crate::scoped_cache::new_account_scope().map_err(|_| ERROR)?,
    };
    write(
        &root(app)?.join("cloud-owner.json"),
        &serde_json::to_vec(&owner).map_err(|_| ERROR)?,
    )?;
    clear_file(&root(app)?.join("cloud.json"))?;
    clear_file(&root(app)?.join("cloud-seen.json"))?;
    CLOUD_OWNER_BLOCKED.store(false, Ordering::SeqCst);
    Ok(())
}
fn clear_file(path: &Path) -> Result<(), String> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(_) => Err(ERROR.into()),
    }
}
fn valid_cloud(value: &CloudCatalogue) -> bool {
    fn plain(value: &str, limit: usize) -> bool {
        let lower = value.trim_start().to_ascii_lowercase();
        value.encode_utf16().count() <= limit
            && !value.chars().any(|c| c.is_control())
            && !["<!doctype", "<html", "<body", "<script", "<form"]
                .iter()
                .any(|prefix| lower.starts_with(prefix))
    }
    fn id(value: &str) -> bool {
        !value.trim().is_empty()
            && plain(value, 256)
            && !value.contains('<')
            && !value.contains('>')
    }
    if value.courses.len() > 100
        || value.assignments.len() > 5000
        || chrono::DateTime::parse_from_rfc3339(&value.fetched_at).is_err()
    {
        return false;
    }
    let mut course_ids = std::collections::BTreeSet::new();
    if !value.courses.iter().all(|course| {
        id(&course.id)
            && course.id.encode_utf16().count() <= 128
            && course_ids.insert(&course.id)
            && course
                .name
                .as_ref()
                .is_none_or(|name| !name.trim().is_empty() && plain(name, 512))
            && course.teacher_names.len() <= 20
            && course
                .teacher_names
                .iter()
                .all(|name| !name.trim().is_empty() && plain(name, 200))
            && course.url == "https://ucloud.bupt.edu.cn/uclass/index.html#/student/homePage"
    }) {
        return false;
    }
    let mut keys = std::collections::BTreeSet::new();
    value.assignments.iter().all(|item| {
        id(&item.id)
            && !item.title.trim().is_empty()
            && plain(&item.title, 2048)
            && keys.insert((&item.id, &item.deadline))
            && crate::assignments::normalized_deadline(&item.deadline).is_some()
            && item.course_id.as_ref().is_none_or(|value| id(value))
            && item
                .course_name
                .as_ref()
                .is_none_or(|value| plain(value, 512))
            && item.status.as_ref().is_none_or(|value| plain(value, 1000))
    })
}
pub fn load_cloud(
    app: &tauri::AppHandle,
    scope: &str,
    epoch: &str,
) -> Result<Option<CloudCatalogue>, String> {
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    if CLOUD_OWNER_BLOCKED.load(Ordering::SeqCst)
        || owner_at(&root(app)?.join("cloud-owner.json"))? != epoch
    {
        return Ok(None);
    }
    let Some(bytes) = read(&root(app)?.join("cloud.json"), LIMIT)? else {
        return Ok(None);
    };
    let raw: serde_json::Value = match serde_json::from_slice(&bytes) {
        Ok(value) => value,
        Err(_) => return Ok(None),
    };
    if raw
        .pointer("/payload/assignments")
        .and_then(|value| value.as_array())
        .is_none_or(|items| {
            items.iter().any(|item| {
                item.as_object().is_none_or(|object| {
                    object.keys().any(|key| {
                        ![
                            "id",
                            "title",
                            "course_name",
                            "course_id",
                            "deadline",
                            "status",
                        ]
                        .contains(&key.as_str())
                    })
                })
            })
        })
    {
        return Ok(None);
    }
    let envelope: CloudEnvelope = match serde_json::from_slice(&bytes) {
        Ok(value) => value,
        Err(_) => return Ok(None),
    };
    let restored = (envelope.schema_version == 1
        && envelope.account_scope == scope
        && envelope.owner_epoch == epoch
        && valid_cloud(&envelope.payload))
    .then_some(envelope.payload);
    if let Some(value) = restored.as_ref() {
        let _ = observe_at(
            &root(app)?.join("cloud-seen.json"),
            &format!("{scope}:{epoch}"),
            &value
                .assignments
                .iter()
                .map(|item| item.id.clone())
                .collect::<Vec<_>>(),
            true,
        );
    }
    Ok(restored)
}
fn observe_at(
    path: &Path,
    owner: &str,
    ids: &[String],
    restore: bool,
) -> Result<Vec<String>, String> {
    let mut seen: crate::assignment_seen::Seen = match read(path, 24 * 1024 * 1024)? {
        Some(bytes) => serde_json::from_slice(&bytes).map_err(|_| ERROR)?,
        None => Default::default(),
    };
    if !seen.valid() {
        return Err(ERROR.into());
    }
    let today = chrono::Utc::now()
        .with_timezone(&chrono::FixedOffset::east_opt(8 * 3600).unwrap())
        .date_naive();
    let term = crate::config::suggested_term_for_date(today).0;
    let fresh = seen.observe(owner, &term, ids, restore);
    write(path, &serde_json::to_vec(&seen).map_err(|_| ERROR)?)?;
    Ok(fresh)
}
pub fn observe_cloud(
    app: &tauri::AppHandle,
    scope: &str,
    epoch: &str,
    value: &CloudCatalogue,
    restore: bool,
) -> Result<Vec<String>, String> {
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    if CLOUD_OWNER_BLOCKED.load(Ordering::SeqCst)
        || owner_at(&root(app)?.join("cloud-owner.json"))? != epoch
        || !valid_cloud(value)
    {
        return Err(ERROR.into());
    }
    observe_at(
        &root(app)?.join("cloud-seen.json"),
        &format!("{scope}:{epoch}"),
        &value
            .assignments
            .iter()
            .map(|item| item.id.clone())
            .collect::<Vec<_>>(),
        restore,
    )
}
fn qm_ids(value: &Snapshot) -> Vec<String> {
    value
        .activities
        .iter()
        .filter(|item| ["assignment", "quiz"].contains(&item.kind.as_str()) && item.is_assessment())
        .filter_map(|item| {
            let course = value.courses.iter().find(|course| {
                course.id == item.course_id
                    && course.current_term_status == "current"
                    && course
                        .name
                        .trim()
                        .get(..3)
                        .is_some_and(|prefix| prefix.eq_ignore_ascii_case("EBU"))
            })?;
            Some(format!("{}:{}:{}", course.id, item.kind, item.id))
        })
        .collect()
}
/// Oversize/write failure keeps last-good disk data without rejecting a legal
/// fresh catalogue. The caller rechecks account/revision before invoking this.
pub fn save_cloud(
    app: &tauri::AppHandle,
    scope: &str,
    epoch: &str,
    value: &CloudCatalogue,
) -> Result<bool, String> {
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    if CLOUD_OWNER_BLOCKED.load(Ordering::SeqCst)
        || owner_at(&root(app)?.join("cloud-owner.json"))? != epoch
    {
        return Err(ERROR.into());
    }
    if !crate::scoped_cache::is_valid_account_scope(scope) || !valid_cloud(value) {
        return Ok(false);
    }
    let mut payload = value.clone();
    payload.new_assignment_ids.clear();
    let envelope = CloudEnvelope {
        schema_version: 1,
        account_scope: scope.into(),
        owner_epoch: epoch.into(),
        payload,
    };
    let bytes = serde_json::to_vec(&envelope).map_err(|_| ERROR)?;
    if bytes.len() > LIMIT {
        return Ok(false);
    }
    Ok(write(&root(app)?.join("cloud.json"), &bytes).is_ok())
}
pub fn load_qm(app: &tauri::AppHandle, profile: &str) -> Result<Option<Snapshot>, String> {
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    if !crate::qmplus_profile::current(app, Some(profile)) {
        return Ok(None);
    }
    let Some(bytes) = read(&root(app)?.join("qmplus.json"), LIMIT)? else {
        return Ok(None);
    };
    let envelope: QmEnvelope = match serde_json::from_slice(&bytes) {
        Ok(value) => value,
        Err(_) => return Ok(None),
    };
    if envelope.schema_version != 1
        || envelope.profile_id != profile
        || !envelope.payload.ok
        || envelope.payload.validate().is_err()
    {
        return Ok(None);
    }
    if !envelope.payload.partial {
        let _ = observe_at(
            &root(app)?.join("qmplus-seen.json"),
            profile,
            &qm_ids(&envelope.payload),
            true,
        );
    }
    Ok(Some(envelope.payload))
}
pub fn save_qm(
    app: &tauri::AppHandle,
    profile: &str,
    value: &Snapshot,
    current: impl FnOnce() -> bool,
) -> Result<(bool, Vec<String>), String> {
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    if !current() || !crate::qmplus_profile::current(app, Some(profile)) {
        return Err(ERROR.into());
    }
    value.validate()?;
    let fresh = if value.partial {
        Vec::new()
    } else {
        observe_at(
            &root(app)?.join("qmplus-seen.json"),
            profile,
            &qm_ids(value),
            false,
        )
        .unwrap_or_default()
    };
    let bytes = serde_json::to_vec(&QmEnvelope {
        schema_version: 1,
        profile_id: profile.into(),
        payload: value.clone(),
    })
    .map_err(|_| ERROR)?;
    if bytes.len() > LIMIT {
        return Ok((false, fresh));
    }
    Ok((
        write(&root(app)?.join("qmplus.json"), &bytes).is_ok(),
        fresh,
    ))
}
pub fn clear_qm(app: &tauri::AppHandle) -> Result<(), String> {
    let _guard = WRITES.lock().map_err(|_| ERROR)?;
    clear_file(&root(app)?.join("qmplus.json"))?;
    clear_file(&root(app)?.join("qmplus-seen.json"))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn fixture() -> CloudCatalogue {
        CloudCatalogue {
            fetched_at: "2026-10-05T00:00:00Z".into(),
            cache_warning: false,
            new_assignment_ids: Vec::new(),
            courses: vec![CourseRef {
                id: "course-fixture".into(),
                name: Some("Fixture course".into()),
                teacher_names: vec!["Fixture teacher".into()],
                url: "https://ucloud.bupt.edu.cn/uclass/index.html#/student/homePage".into(),
            }],
            assignments: vec![AssignmentDeadlineItem {
                id: "work-fixture".into(),
                title: "Fixture task".into(),
                course_name: Some("Fixture course".into()),
                course_id: Some("course-fixture".into()),
                deadline: "2026-10-06 12:00:00".into(),
                status: Some("未提交".into()),
            }],
        }
    }
    #[test]
    fn business_fields_are_validated_without_accepting_html_or_invented_dates() {
        assert!(valid_cloud(&fixture()));
        let mut value = fixture();
        value.assignments[0].deadline = "2026-02-30 10:00:00".into();
        assert!(!valid_cloud(&value));
        let mut value = fixture();
        value.courses[0].name = Some("<html>error</html>".into());
        assert!(!valid_cloud(&value));
        let mut value = fixture();
        value.courses.push(value.courses[0].clone());
        assert!(!valid_cloud(&value));
        let mut value = fixture();
        value.assignments[0].id = "<script>".into();
        assert!(!valid_cloud(&value));
    }
    #[test]
    fn owner_metadata_is_opaque_stable_and_private_and_bounded_reads_do_not_expand() {
        let temp = tempfile::tempdir().unwrap();
        let owner = temp.path().join("business/owner.json");
        let first = owner_at(&owner).unwrap();
        assert_eq!(owner_at(&owner).unwrap(), first);
        assert!(crate::scoped_cache::is_valid_account_scope(&first));
        let value: serde_json::Value =
            serde_json::from_slice(&read(&owner, 4096).unwrap().unwrap()).unwrap();
        assert_eq!(value.as_object().unwrap().len(), 2);
        assert!(read(&owner, 1).unwrap().is_none());
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(
                fs::metadata(&owner).unwrap().permissions().mode() & 0o777,
                0o600
            );
            assert_eq!(
                fs::metadata(owner.parent().unwrap())
                    .unwrap()
                    .permissions()
                    .mode()
                    & 0o777,
                0o700
            );
        }
    }
}
