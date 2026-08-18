use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use tauri::{AppHandle, Manager};
use tempfile::NamedTempFile;

use crate::error::{ServiceError, ServiceResult};
use crate::models::{ClassroomsCacheResponse, CLASSROOMS_CACHE_VERSION};
use crate::scoped_cache;

const CLASSROOMS_FILE_NAME: &str = "classrooms.json";

fn classrooms_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地空教室目录：{error}")))?;
    Ok(directory.join(CLASSROOMS_FILE_NAME))
}

const MAX_CLASSROOMS_CACHE_BYTES: u64 = 8 * 1024 * 1024;

fn read_limited_cache_bytes(
    path: &Path,
    description: &str,
    max_bytes: u64,
) -> ServiceResult<Vec<u8>> {
    let metadata = fs::metadata(path)
        .map_err(|error| ServiceError::new(format!("无法读取{description}：{error}")))?;
    if metadata.len() > max_bytes {
        return Err(ServiceError::new(format!("{description}缓存过大。")));
    }
    fs::read(path).map_err(|error| ServiceError::new(format!("无法读取{description}：{error}")))
}

pub fn load(
    app: &AppHandle,
    account_scope: &str,
) -> ServiceResult<Option<ClassroomsCacheResponse>> {
    let path = classrooms_path(app)?;
    if !path.exists() {
        return Ok(None);
    }

    let bytes = read_limited_cache_bytes(&path, "本地空教室信息", MAX_CLASSROOMS_CACHE_BYTES)?;
    if bytes.is_empty() {
        return Ok(None);
    }

    let Some(classrooms) =
        scoped_cache::decode::<ClassroomsCacheResponse>(&bytes, account_scope, "本地空教室信息")?
    else {
        return Ok(None);
    };
    if classrooms.cache_version < CLASSROOMS_CACHE_VERSION {
        return Ok(None);
    }
    Ok(Some(classrooms))
}

pub fn save(
    app: &AppHandle,
    account_scope: &str,
    classrooms: &ClassroomsCacheResponse,
) -> ServiceResult<()> {
    save_to_path(&classrooms_path(app)?, account_scope, classrooms)
}

fn save_to_path(
    path: &Path,
    account_scope: &str,
    classrooms: &ClassroomsCacheResponse,
) -> ServiceResult<()> {
    let bytes = scoped_cache::encode(account_scope, classrooms, "本地空教室信息")?;
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
        .ok_or_else(|| ServiceError::new("本地空教室路径没有父目录。"))?;
    fs::create_dir_all(parent)
        .map_err(|error| ServiceError::new(format!("无法创建本地空教室目录：{error}")))?;
    let mut temporary = NamedTempFile::new_in(parent)
        .map_err(|error| ServiceError::new(format!("无法创建临时空教室文件：{error}")))?;
    write_temporary(&mut temporary, bytes)
        .map_err(|error| ServiceError::new(format!("无法写入临时空教室文件：{error}")))?;
    temporary.persist(path).map_err(|error| {
        ServiceError::new(format!("无法原子替换本地空教室信息：{}", error.error))
    })?;
    Ok(())
}

pub fn clear(app: &AppHandle) -> ServiceResult<()> {
    let path = classrooms_path(app)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(ServiceError::new(format!(
            "无法清除本地空教室信息：{error}"
        ))),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE_SCOPE: &str =
        "opaque-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn fixture_classrooms() -> ClassroomsCacheResponse {
        serde_json::from_str(include_str!("../../contracts/v1/fixtures/classrooms.json"))
            .expect("valid classrooms fixture")
    }

    #[test]
    fn failed_temporary_classrooms_write_preserves_existing_cache() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join(CLASSROOMS_FILE_NAME);
        let old_cache = b"existing classrooms cache";
        fs::write(&path, old_cache).expect("write existing classrooms cache");

        let error = write_cache_bytes_to_path_with(&path, b"replacement", |temporary, bytes| {
            temporary.write_all(&bytes[..1])?;
            Err(io::Error::other("injected classrooms write failure"))
        })
        .expect_err("temporary write must fail");

        assert!(error.message.contains("injected classrooms write failure"));
        assert_eq!(fs::read(&path).unwrap(), old_cache);
    }

    #[test]
    fn successful_classrooms_save_atomically_replaces_existing_cache() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join(CLASSROOMS_FILE_NAME);
        fs::write(&path, b"existing classrooms cache").expect("write existing classrooms cache");
        let expected = fixture_classrooms();

        save_to_path(&path, FIXTURE_SCOPE, &expected).expect("replace classrooms cache");

        let bytes = fs::read(&path).expect("read replaced classrooms cache");
        let actual = scoped_cache::decode::<ClassroomsCacheResponse>(
            &bytes,
            FIXTURE_SCOPE,
            "本地空教室信息",
        )
        .expect("decode replaced classrooms cache")
        .expect("matching classrooms cache");
        assert_eq!(
            serde_json::to_value(actual).unwrap(),
            serde_json::to_value(expected).unwrap()
        );
    }

    #[test]
    fn oversized_classrooms_cache_is_rejected_before_reading() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join(CLASSROOMS_FILE_NAME);
        fs::write(&path, vec![b' '; MAX_CLASSROOMS_CACHE_BYTES as usize + 1])
            .expect("write oversized classrooms cache");
        let error = read_limited_cache_bytes(&path, "本地空教室信息", MAX_CLASSROOMS_CACHE_BYTES)
            .expect_err("oversized classrooms cache must be rejected");
        assert_eq!(error.message, "本地空教室信息缓存过大。");
    }
}
