use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use tauri::{AppHandle, Manager};
use tempfile::NamedTempFile;

use crate::error::{ServiceError, ServiceResult};
use crate::models::ScheduleResponse;
use crate::scoped_cache;

const SCHEDULE_FILE_NAME: &str = "schedule.json";

fn schedule_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地课表目录：{error}")))?;
    Ok(directory.join(SCHEDULE_FILE_NAME))
}

const MAX_SCHEDULE_CACHE_BYTES: u64 = 8 * 1024 * 1024;

fn read_limited_cache_bytes(path: &Path, description: &str, max_bytes: u64) -> ServiceResult<Vec<u8>> {
    let metadata = fs::metadata(path)
        .map_err(|error| ServiceError::new(format!("无法读取{description}：{error}")))?;
    if metadata.len() > max_bytes {
        return Err(ServiceError::new(format!("{description}缓存过大。")));
    }
    fs::read(path).map_err(|error| ServiceError::new(format!("无法读取{description}：{error}")))
}

pub fn load(app: &AppHandle, account_scope: &str) -> ServiceResult<Option<ScheduleResponse>> {
    let path = schedule_path(app)?;
    if !path.exists() {
        return Ok(None);
    }

    let bytes = read_limited_cache_bytes(&path, "本地课表", MAX_SCHEDULE_CACHE_BYTES)?;
    if bytes.is_empty() {
        return Ok(None);
    }

    let Some(mut schedule) =
        scoped_cache::decode::<ScheduleResponse>(&bytes, account_scope, "本地课表")?
    else {
        return Ok(None);
    };
    crate::schedule::annotate_exam_weeks(&mut schedule.courses);
    Ok(Some(schedule))
}

pub fn save(
    app: &AppHandle,
    account_scope: &str,
    schedule: &ScheduleResponse,
) -> ServiceResult<()> {
    save_to_path(&schedule_path(app)?, account_scope, schedule)
}

fn save_to_path(
    path: &Path,
    account_scope: &str,
    schedule: &ScheduleResponse,
) -> ServiceResult<()> {
    let bytes = scoped_cache::encode(account_scope, schedule, "本地课表")?;
    write_cache_bytes_to_path(path, &bytes)
}

fn write_cache_bytes_to_path(path: &Path, bytes: &[u8]) -> ServiceResult<()> {
    write_cache_bytes_to_path_with(path, bytes, |temporary, bytes| {
        temporary.write_all(bytes)?;
        temporary.flush()?;
        temporary.as_file().sync_all()
    })
}

fn write_cache_bytes_to_path_with<W>(
    path: &Path,
    bytes: &[u8],
    write_temporary: W,
) -> ServiceResult<()>
where
    W: FnOnce(&mut NamedTempFile, &[u8]) -> io::Result<()>,
{
    let parent = path
        .parent()
        .ok_or_else(|| ServiceError::new("本地课表路径没有父目录。"))?;
    fs::create_dir_all(parent)
        .map_err(|error| ServiceError::new(format!("无法创建本地课表目录：{error}")))?;
    let mut temporary = NamedTempFile::new_in(parent)
        .map_err(|error| ServiceError::new(format!("无法创建临时课表文件：{error}")))?;
    write_temporary(&mut temporary, bytes)
        .map_err(|error| ServiceError::new(format!("无法写入临时课表文件：{error}")))?;
    temporary
        .persist(path)
        .map_err(|error| ServiceError::new(format!("无法原子替换本地课表：{}", error.error)))?;
    Ok(())
}

pub fn clear(app: &AppHandle) -> ServiceResult<()> {
    let path = schedule_path(app)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(ServiceError::new(format!("无法清除本地课表：{error}"))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE_SCOPE: &str =
        "opaque-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn fixture_schedule() -> ScheduleResponse {
        serde_json::from_str(include_str!("../../contracts/v1/fixtures/schedule.json"))
            .expect("valid schedule fixture")
    }

    #[test]
    fn failed_temporary_schedule_write_preserves_existing_cache() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join(SCHEDULE_FILE_NAME);
        let old_cache = b"existing schedule cache";
        fs::write(&path, old_cache).expect("write existing schedule cache");

        let error = write_cache_bytes_to_path_with(&path, b"replacement", |temporary, bytes| {
            temporary.write_all(&bytes[..1])?;
            Err(io::Error::other("injected schedule write failure"))
        })
        .expect_err("temporary write must fail");

        assert!(error.message.contains("injected schedule write failure"));
        assert_eq!(fs::read(&path).unwrap(), old_cache);
    }

    #[test]
    fn successful_schedule_save_atomically_replaces_existing_cache() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join(SCHEDULE_FILE_NAME);
        fs::write(&path, b"existing schedule cache").expect("write existing schedule cache");
        let expected = fixture_schedule();

        save_to_path(&path, FIXTURE_SCOPE, &expected).expect("replace schedule cache");

        let bytes = fs::read(&path).expect("read replaced schedule cache");
        let actual = scoped_cache::decode::<ScheduleResponse>(&bytes, FIXTURE_SCOPE, "本地课表")
            .expect("decode replaced schedule cache")
            .expect("matching schedule cache");
        assert_eq!(
            serde_json::to_value(actual).unwrap(),
            serde_json::to_value(expected).unwrap()
        );
    }

    #[test]
    fn oversized_schedule_cache_is_rejected_before_reading() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join(SCHEDULE_FILE_NAME);
        fs::write(&path, vec![b' '; MAX_SCHEDULE_CACHE_BYTES as usize + 1])
            .expect("write oversized schedule cache");
        let error = read_limited_cache_bytes(&path, "本地课表", MAX_SCHEDULE_CACHE_BYTES)
            .expect_err("oversized schedule cache must be rejected");
        assert_eq!(error.message, "本地课表缓存过大。");
    }
}
