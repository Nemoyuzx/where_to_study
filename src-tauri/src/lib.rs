mod auth;
mod calendar_export;
mod classrooms;
mod classrooms_store;
mod config;
mod credential_store;
mod error;
mod holidays;
mod models;
#[cfg(not(mobile))]
mod recommender;
mod schedule;
mod schedule_store;
mod scoped_cache;
mod settings_store;

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Mutex;

#[cfg(not(mobile))]
use std::fs;
#[cfg(not(mobile))]
use std::io::Write;
#[cfg(not(mobile))]
use std::path::PathBuf;
#[cfg(not(mobile))]
use std::time::Duration;
#[cfg(not(mobile))]
use tempfile::NamedTempFile;

#[cfg(not(mobile))]
use chrono::{Duration as ChronoDuration, NaiveDate, NaiveDateTime, NaiveTime};
#[cfg(not(mobile))]
use tauri::image::Image;
#[cfg(not(mobile))]
use tauri::menu::{Menu, MenuItem, PredefinedMenuItem};
#[cfg(not(mobile))]
use tauri::tray::TrayIconBuilder;
use tauri::{Emitter, Manager};
#[cfg(not(mobile))]
use tauri_plugin_notification::NotificationExt;

use crate::models::{
    ClassroomsCacheResponse, ClassroomsRequest, HolidaysRequest, HolidaysResponse,
    MetadataResponse, SaveSettingsRequest, SavedSettings, ScheduleRequest, ScheduleResponse,
};

const STALE_LOCAL_DATA_MESSAGE: &str = "本地数据已清除，本次后台结果未保存。";
const ACCOUNT_SCOPE_CLEARED_EVENT: &str = "account-scope:cleared";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct LocalDataGeneration(u64);

#[derive(Debug, PartialEq, Eq)]
enum LocalDataAccessError {
    Stale,
    AccountAccessRevoked,
    Operation(String),
}

impl LocalDataAccessError {
    fn message(self) -> String {
        match self {
            Self::Stale => STALE_LOCAL_DATA_MESSAGE.to_string(),
            Self::AccountAccessRevoked => {
                "本地账号访问已撤销，请先在设置中重新保存账号。".to_string()
            }
            Self::Operation(message) => message,
        }
    }
}

fn finish_remote_holiday_fetch(
    response: HolidaysResponse,
    cache_attempt: Result<(), LocalDataAccessError>,
) -> Result<HolidaysResponse, String> {
    match cache_attempt {
        Ok(()) | Err(LocalDataAccessError::Operation(_)) => Ok(response),
        Err(error) => Err(error.message()),
    }
}

#[derive(Debug, PartialEq, Eq, serde::Serialize)]
struct AccountScopeUpdateError {
    message: String,
    account_scope_cleared: bool,
}

#[derive(Debug, serde::Deserialize)]
struct AccountScopeRequest {
    account_scope: String,
}

#[derive(Clone, serde::Serialize)]
struct ScheduleUpdatedEvent {
    account_scope: String,
}

#[derive(Clone, serde::Serialize)]
struct ClassroomsUpdatedEvent {
    account_scope: String,
}

impl AccountScopeUpdateError {
    fn new(message: String, account_scope_cleared: bool) -> Self {
        Self {
            message,
            account_scope_cleared,
        }
    }
}

struct LocalDataCoordinator {
    generation: AtomicU64,
    account_access_revoked: AtomicBool,
    io_lock: Mutex<()>,
}

impl LocalDataCoordinator {
    const fn new() -> Self {
        Self {
            generation: AtomicU64::new(0),
            account_access_revoked: AtomicBool::new(false),
            io_lock: Mutex::new(()),
        }
    }

    fn begin(&self) -> LocalDataGeneration {
        LocalDataGeneration(self.generation.load(Ordering::Acquire))
    }

    fn with_current<T>(
        &self,
        expected: LocalDataGeneration,
        operation: impl FnOnce() -> Result<T, String>,
    ) -> Result<T, LocalDataAccessError> {
        let _guard = self
            .io_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.generation.load(Ordering::Acquire) != expected.0 {
            return Err(LocalDataAccessError::Stale);
        }
        operation().map_err(LocalDataAccessError::Operation)
    }

    fn with_current_account<T>(
        &self,
        expected: LocalDataGeneration,
        operation: impl FnOnce() -> Result<T, String>,
    ) -> Result<T, LocalDataAccessError> {
        let _guard = self
            .io_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.generation.load(Ordering::Acquire) != expected.0 {
            return Err(LocalDataAccessError::Stale);
        }
        if self.account_access_revoked.load(Ordering::Acquire) {
            return Err(LocalDataAccessError::AccountAccessRevoked);
        }
        operation().map_err(LocalDataAccessError::Operation)
    }

    fn revoke_and_clear<T>(
        &self,
        persist_revocation: impl FnOnce() -> Result<(), String>,
        operation: impl FnOnce() -> Result<T, String>,
    ) -> Result<T, String> {
        let _guard = self
            .io_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        persist_revocation()?;
        self.generation.fetch_add(1, Ordering::AcqRel);
        self.account_access_revoked.store(true, Ordering::Release);
        operation()
    }

    fn set_account_access_revoked(&self, revoked: bool) {
        let _guard = self
            .io_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.account_access_revoked
            .store(revoked, Ordering::Release);
    }

    fn account_access_revoked(&self) -> bool {
        self.account_access_revoked.load(Ordering::Acquire)
    }

    fn update_account_scope<P, T>(
        &self,
        prepare: impl FnOnce() -> Result<P, String>,
        scope_state: impl FnOnce(&P) -> (bool, bool),
        persist_revocation: impl FnOnce() -> Result<(), String>,
        revoke_existing_account: impl FnOnce() -> Result<(), String>,
        clear_account_scope: impl FnOnce() -> Result<(), String>,
        commit: impl FnOnce(P) -> Result<T, String>,
    ) -> Result<(T, bool), AccountScopeUpdateError> {
        let _guard = self
            .io_lock
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let plan = prepare().map_err(|message| AccountScopeUpdateError::new(message, false))?;
        let (changed, account_available) = scope_state(&plan);
        if changed {
            persist_revocation().map_err(|message| AccountScopeUpdateError::new(message, false))?;
            self.generation.fetch_add(1, Ordering::AcqRel);
            self.account_access_revoked.store(true, Ordering::Release);
            revoke_existing_account()
                .map_err(|message| AccountScopeUpdateError::new(message, true))?;
            clear_account_scope().map_err(|message| AccountScopeUpdateError::new(message, true))?;
        }
        match commit(plan) {
            Ok(result) => {
                self.account_access_revoked
                    .store(!account_available, Ordering::Release);
                Ok((result, changed))
            }
            Err(message) => Err(AccountScopeUpdateError::new(
                message,
                changed || self.account_access_revoked.load(Ordering::Acquire),
            )),
        }
    }
}

fn finalize_account_scope_update<T>(
    update: Result<(T, bool), AccountScopeUpdateError>,
    on_account_scope_cleared: impl FnOnce(),
) -> Result<T, AccountScopeUpdateError> {
    let account_scope_cleared = match &update {
        Ok((_, changed)) => *changed,
        Err(error) => error.account_scope_cleared,
    };
    if account_scope_cleared {
        on_account_scope_cleared();
    }
    update.map(|(result, _)| result)
}

fn finalize_local_data_clear<T>(
    result: Result<T, String>,
    on_account_data_cleared: impl FnOnce(),
) -> Result<T, String> {
    on_account_data_cleared();
    result
}

#[cfg(not(mobile))]
fn reset_account_scope_surfaces<EmitError, TrayError>(
    emit_clear: impl FnOnce() -> Result<(), EmitError>,
    hide_widget: impl FnOnce(),
    reset_tray: impl FnOnce() -> Result<(), TrayError>,
    hide_tray: impl FnOnce(),
) {
    let _ = emit_clear();
    hide_widget();
    if reset_tray().is_err() {
        hide_tray();
    }
}

fn notify_account_scope_cleared(app: &tauri::AppHandle) {
    #[cfg(not(mobile))]
    reset_account_scope_surfaces(
        || app.emit(ACCOUNT_SCOPE_CLEARED_EVENT, ()),
        || {
            if let Some(window) = app.get_webview_window("course-widget") {
                let _ = window.hide();
                let _ = window.close();
            }
        },
        || {
            set_tray_menu(
                app,
                TrayCourseContent::Message("暂无本地课表，请先获取/刷新个人课表。".to_string()),
            )
        },
        || {
            if let Some(tray) = app.tray_by_id("where-to-study-tray") {
                let _ = tray.set_visible(false);
            }
        },
    );

    #[cfg(mobile)]
    let _ = app.emit(ACCOUNT_SCOPE_CLEARED_EVENT, ());
}

static LOCAL_DATA: LocalDataCoordinator = LocalDataCoordinator::new();
#[cfg(not(mobile))]
static DESKTOP_SCHEDULER_THREAD: Mutex<Option<std::thread::Thread>> = Mutex::new(None);
#[cfg(not(mobile))]
static DESKTOP_NOTIFICATIONS_ENABLED: AtomicBool = AtomicBool::new(false);

#[cfg(test)]
mod local_data_coordination_tests {
    use super::*;
    use std::fs;
    use std::sync::atomic::AtomicUsize;
    use std::sync::{mpsc, Arc};
    use std::thread;

    fn write_account_caches(
        directory: &std::path::Path,
    ) -> (std::path::PathBuf, std::path::PathBuf) {
        let schedule = directory.join("schedule.json");
        let classrooms = directory.join("classrooms.json");
        fs::write(&schedule, b"account-a schedule").expect("write schedule cache");
        fs::write(&classrooms, b"account-a classrooms").expect("write classrooms cache");
        (schedule, classrooms)
    }

    fn clear_cache_paths(paths: &[&std::path::Path]) -> Result<(), String> {
        for path in paths {
            if let Err(error) = fs::remove_file(path) {
                if error.kind() != std::io::ErrorKind::NotFound {
                    return Err(error.to_string());
                }
            }
        }
        Ok(())
    }

    fn sample_holiday_response() -> HolidaysResponse {
        HolidaysResponse {
            year: 2026,
            source: "remote".to_string(),
            fetched_at: "2026-01-01T00:00:00+08:00".to_string(),
            items: Vec::new(),
        }
    }

    #[test]
    fn remote_holiday_result_survives_cache_write_failure() {
        let response = sample_holiday_response();
        let result = finish_remote_holiday_fetch(
            response.clone(),
            Err(LocalDataAccessError::Operation(
                "cache unavailable".to_string(),
            )),
        );

        assert_eq!(result.expect("return valid remote response"), response);
    }

    #[test]
    fn stale_remote_holiday_result_is_still_rejected() {
        let result = finish_remote_holiday_fetch(
            sample_holiday_response(),
            Err(LocalDataAccessError::Stale),
        );

        assert_eq!(
            result.expect_err("reject stale response"),
            STALE_LOCAL_DATA_MESSAGE
        );
    }

    #[test]
    fn clear_after_write_removes_disk_and_memory_results() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("cache.json");
        let coordinator = Arc::new(LocalDataCoordinator::new());
        let memory_value = Arc::new(AtomicUsize::new(0));
        let generation = coordinator.begin();
        let (write_started_tx, write_started_rx) = mpsc::channel();
        let (release_write_tx, release_write_rx) = mpsc::channel();

        let writer = {
            let coordinator = Arc::clone(&coordinator);
            let path = path.clone();
            let memory_value = Arc::clone(&memory_value);
            thread::spawn(move || {
                coordinator.with_current(generation, || {
                    fs::write(&path, b"old result").map_err(|error| error.to_string())?;
                    memory_value.store(1, Ordering::Release);
                    write_started_tx.send(()).expect("signal write start");
                    release_write_rx.recv().expect("release write");
                    Ok(())
                })
            })
        };

        write_started_rx.recv().expect("wait for active write");
        let clearer = {
            let coordinator = Arc::clone(&coordinator);
            let path = path.clone();
            let memory_value = Arc::clone(&memory_value);
            thread::spawn(move || {
                coordinator.revoke_and_clear(
                    || Ok(()),
                    || {
                        if path.exists() {
                            fs::remove_file(&path).map_err(|error| error.to_string())?;
                        }
                        memory_value.store(0, Ordering::Release);
                        Ok(())
                    },
                )
            })
        };

        release_write_tx.send(()).expect("finish write");
        assert_eq!(writer.join().expect("join writer"), Ok(()));
        assert_eq!(clearer.join().expect("join clearer"), Ok(()));
        assert!(!path.exists());
        assert_eq!(memory_value.load(Ordering::Acquire), 0);
    }

    #[test]
    fn clear_before_write_rejects_stale_disk_and_memory_results() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("cache.json");
        let coordinator = LocalDataCoordinator::new();
        let memory_value = AtomicUsize::new(0);
        let generation = coordinator.begin();

        coordinator
            .revoke_and_clear(
                || Ok(()),
                || {
                    memory_value.store(0, Ordering::Release);
                    Ok(())
                },
            )
            .expect("clear local data");
        let result = coordinator.with_current(generation, || {
            fs::write(&path, b"stale result").map_err(|error| error.to_string())?;
            memory_value.store(1, Ordering::Release);
            Ok(())
        });

        assert_eq!(result, Err(LocalDataAccessError::Stale));
        assert!(!path.exists());
        assert_eq!(memory_value.load(Ordering::Acquire), 0);
    }

    #[test]
    fn clear_before_remote_holiday_result_rejects_cache_save() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let path = directory.path().join("holidays_2026.json");
        let coordinator = LocalDataCoordinator::new();
        let generation = coordinator.begin();
        let response = HolidaysResponse {
            year: 2026,
            source: "https://example.invalid/holidays".to_string(),
            fetched_at: "2026-08-04T08:00:00+08:00".to_string(),
            items: Vec::new(),
        };

        coordinator
            .revoke_and_clear(|| Ok(()), || Ok(()))
            .expect("clear local data");
        let result = coordinator.with_current(generation, || {
            holidays::save_cache_to_path(&path, &response).map_err(|error| error.message)
        });

        assert_eq!(result, Err(LocalDataAccessError::Stale));
        assert!(!path.exists());
    }

    #[test]
    fn account_a_to_b_clears_caches_and_invalidates_old_generation() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let (schedule, classrooms) = write_account_caches(directory.path());
        let coordinator = LocalDataCoordinator::new();
        let account_a_request = coordinator.begin();

        let (saved_account, changed) = coordinator
            .update_account_scope(
                || Ok(("account-a", "account-b")),
                |(old, new)| (old != new, !new.is_empty()),
                || Ok(()),
                || Ok(()),
                || clear_cache_paths(&[&schedule, &classrooms]),
                |(_, new)| Ok(new),
            )
            .expect("switch account");

        assert_eq!(saved_account, "account-b");
        assert!(changed);
        assert!(!schedule.exists());
        assert!(!classrooms.exists());
        assert_eq!(
            coordinator.with_current(account_a_request, || Ok(())),
            Err(LocalDataAccessError::Stale)
        );
    }

    #[test]
    fn account_a_to_empty_clears_caches_and_invalidates_old_generation() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let (schedule, classrooms) = write_account_caches(directory.path());
        let coordinator = LocalDataCoordinator::new();
        let account_a_request = coordinator.begin();

        let (saved_account, changed) = coordinator
            .update_account_scope(
                || Ok(("account-a", "")),
                |(old, new)| (old != new, !new.is_empty()),
                || Ok(()),
                || Ok(()),
                || clear_cache_paths(&[&schedule, &classrooms]),
                |(_, new)| Ok(new),
            )
            .expect("clear account");

        assert_eq!(saved_account, "");
        assert!(changed);
        assert!(!schedule.exists());
        assert!(!classrooms.exists());
        assert_eq!(
            coordinator.with_current(account_a_request, || Ok(())),
            Err(LocalDataAccessError::Stale)
        );
    }

    #[test]
    fn same_account_password_change_preserves_caches_and_generation() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let (schedule, classrooms) = write_account_caches(directory.path());
        let coordinator = LocalDataCoordinator::new();
        let account_a_request = coordinator.begin();
        let clear_called = AtomicUsize::new(0);

        let (_, changed) = coordinator
            .update_account_scope(
                || Ok(("account-a", "account-a")),
                |(old, new)| (old != new, !new.is_empty()),
                || Ok(()),
                || Ok(()),
                || {
                    clear_called.fetch_add(1, Ordering::Relaxed);
                    Ok(())
                },
                |_| Ok(()),
            )
            .expect("change password for same account");

        assert!(!changed);
        assert_eq!(clear_called.load(Ordering::Relaxed), 0);
        assert!(schedule.exists());
        assert!(classrooms.exists());
        assert_eq!(
            coordinator.with_current(account_a_request, || Ok("current")),
            Ok("current")
        );
    }

    #[test]
    fn in_flight_account_a_result_cannot_write_after_account_switch() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let stale_path = directory.path().join("schedule.json");
        let coordinator = Arc::new(LocalDataCoordinator::new());
        let account_a_request = coordinator.begin();
        let (remote_started_tx, remote_started_rx) = mpsc::channel();
        let (release_remote_tx, release_remote_rx) = mpsc::channel();

        let writer = {
            let coordinator = Arc::clone(&coordinator);
            let stale_path = stale_path.clone();
            thread::spawn(move || {
                remote_started_tx.send(()).expect("signal remote request");
                release_remote_rx.recv().expect("release remote response");
                coordinator.with_current(account_a_request, || {
                    fs::write(&stale_path, b"stale account-a response")
                        .map_err(|error| error.to_string())
                })
            })
        };

        remote_started_rx.recv().expect("wait for remote request");
        coordinator
            .update_account_scope(
                || Ok(true),
                |changed| (*changed, true),
                || Ok(()),
                || Ok(()),
                || Ok(()),
                |_| Ok(()),
            )
            .expect("switch account while request is active");
        release_remote_tx.send(()).expect("release stale response");

        assert_eq!(
            writer.join().expect("join stale writer"),
            Err(LocalDataAccessError::Stale)
        );
        assert!(!stale_path.exists());
    }

    #[test]
    fn failed_changed_account_commit_remains_fail_closed() {
        let directory = tempfile::tempdir().expect("create temporary directory");
        let (schedule, classrooms) = write_account_caches(directory.path());
        let coordinator = LocalDataCoordinator::new();
        let account_a_request = coordinator.begin();
        let clear_notifications = AtomicUsize::new(0);

        let update = coordinator.update_account_scope(
            || Ok(true),
            |changed| (*changed, true),
            || Ok(()),
            || Ok(()),
            || clear_cache_paths(&[&schedule, &classrooms]),
            |_| Err::<(), _>("credential store unavailable".to_string()),
        );
        let error = finalize_account_scope_update(update, || {
            clear_notifications.fetch_add(1, Ordering::Relaxed);
        })
        .expect_err("changed account commit must fail");

        assert_eq!(error.message, "credential store unavailable");
        assert!(error.account_scope_cleared);
        assert_eq!(clear_notifications.load(Ordering::Relaxed), 1);
        assert!(!schedule.exists());
        assert!(!classrooms.exists());
        assert_eq!(
            coordinator.with_current_account(coordinator.begin(), || Ok(())),
            Err(LocalDataAccessError::AccountAccessRevoked)
        );
        assert_eq!(
            coordinator.with_current(account_a_request, || Ok(())),
            Err(LocalDataAccessError::Stale)
        );
    }

    #[test]
    fn partial_cache_clear_failure_revokes_old_account_until_a_save_succeeds() {
        let coordinator = LocalDataCoordinator::new();
        let revoked_credentials = AtomicBool::new(false);

        let error = coordinator
            .update_account_scope(
                || Ok(true),
                |changed| (*changed, true),
                || Ok(()),
                || {
                    revoked_credentials.store(true, Ordering::Release);
                    Ok(())
                },
                || Err("无法删除旧课表缓存".to_string()),
                |_| Ok(()),
            )
            .expect_err("partial cache clear must fail");

        assert!(error.account_scope_cleared);
        assert!(revoked_credentials.load(Ordering::Acquire));
        assert_eq!(
            coordinator.with_current_account(coordinator.begin(), || Ok("old account data")),
            Err(LocalDataAccessError::AccountAccessRevoked)
        );
    }

    #[test]
    fn failed_local_clear_disables_all_future_account_operations() {
        let coordinator = LocalDataCoordinator::new();

        let error = coordinator
            .revoke_and_clear(
                || Ok(()),
                || Err::<(), _>("credential deletion failed".to_string()),
            )
            .expect_err("clear operation must report the storage failure");

        assert_eq!(error, "credential deletion failed");
        assert_eq!(
            coordinator.with_current_account(coordinator.begin(), || Ok(())),
            Err(LocalDataAccessError::AccountAccessRevoked)
        );
    }

    #[test]
    fn failed_local_clear_still_notifies_all_account_surfaces() {
        let notifications = AtomicUsize::new(0);

        let error =
            finalize_local_data_clear(Err::<(), _>("partial storage failure".to_string()), || {
                notifications.fetch_add(1, Ordering::Relaxed);
            })
            .expect_err("partial clear must remain visible to the caller");

        assert_eq!(error, "partial storage failure");
        assert_eq!(notifications.load(Ordering::Relaxed), 1);
    }

    #[test]
    fn persistent_revocation_failure_keeps_the_existing_account_active() {
        let coordinator = LocalDataCoordinator::new();
        let generation = coordinator.begin();

        let error = coordinator
            .update_account_scope(
                || Ok(true),
                |changed| (*changed, true),
                || Err("revocation marker unavailable".to_string()),
                || panic!("credential deletion must not run"),
                || panic!("cache clear must not run"),
                |_| -> Result<(), String> { panic!("commit must not run") },
            )
            .expect_err("revocation must fail before the transition starts");

        assert!(!error.account_scope_cleared);
        assert_eq!(
            coordinator.with_current_account(generation, || Ok("account-a")),
            Ok("account-a")
        );
    }

    #[test]
    fn successful_saved_account_reenables_access_after_a_local_clear() {
        let coordinator = LocalDataCoordinator::new();
        coordinator
            .revoke_and_clear(|| Ok(()), || Ok(()))
            .expect("clear local data");
        assert!(coordinator.account_access_revoked());

        coordinator
            .update_account_scope(
                || Ok("account-a"),
                |account| (false, !account.is_empty()),
                || panic!("same account recovery does not revoke twice"),
                || panic!("same account recovery does not delete credentials"),
                || panic!("same account recovery does not clear twice"),
                |_| Ok(()),
            )
            .expect("save account after local clear");

        assert_eq!(
            coordinator.with_current_account(coordinator.begin(), || Ok("available")),
            Ok("available")
        );
    }

    #[test]
    fn account_scope_validation_rejects_unsaved_accounts_and_event_is_scope_only() {
        let saved_scope = scoped_cache::new_account_scope().expect("saved scope");
        let other_scope = scoped_cache::new_account_scope().expect("other scope");

        assert!(validate_account_scope_match(&saved_scope, &saved_scope).is_ok());
        assert!(validate_account_scope_match(&other_scope, &saved_scope).is_err());

        let event = serde_json::to_value(ScheduleUpdatedEvent {
            account_scope: saved_scope.clone(),
        })
        .expect("serialize schedule event");
        assert_eq!(event["account_scope"], saved_scope);
        assert!(event.get("schedule").is_none());
        assert!(event.get("courses").is_none());

        let classrooms_event = serde_json::to_value(ClassroomsUpdatedEvent {
            account_scope: saved_scope,
        })
        .expect("serialize classrooms event");
        assert!(classrooms_event.get("classrooms").is_none());
        assert!(classrooms_event.get("campuses").is_none());
    }

    #[cfg(not(mobile))]
    #[test]
    fn account_scope_surface_failures_hide_stale_widget_and_tray_content() {
        let widget_hides = AtomicUsize::new(0);
        let tray_hides = AtomicUsize::new(0);

        reset_account_scope_surfaces(
            || Err::<(), _>("event unavailable"),
            || {
                widget_hides.fetch_add(1, Ordering::Relaxed);
            },
            || Err::<(), _>("tray menu unavailable"),
            || {
                tray_hides.fetch_add(1, Ordering::Relaxed);
            },
        );

        assert_eq!(widget_hides.load(Ordering::Relaxed), 1);
        assert_eq!(tray_hides.load(Ordering::Relaxed), 1);
    }

    #[cfg(not(mobile))]
    #[test]
    fn successful_clear_event_also_hides_the_widget_immediately() {
        let widget_hides = AtomicUsize::new(0);

        reset_account_scope_surfaces(
            || Ok::<(), ()>(()),
            || {
                widget_hides.fetch_add(1, Ordering::Relaxed);
            },
            || Ok::<(), ()>(()),
            || panic!("successful tray reset must not hide the tray"),
        );

        assert_eq!(widget_hides.load(Ordering::Relaxed), 1);
    }
}

#[tauri::command]
fn get_metadata() -> MetadataResponse {
    MetadataResponse {
        campuses: config::campuses_payload(),
        slots: config::slot_payload(),
        default_term_id: config::default_term_id(),
        default_term_start_date: config::default_term_start_date(),
        supports_calendar_import: calendar_export::is_supported(),
    }
}

#[tauri::command]
fn load_saved_settings(app: tauri::AppHandle) -> Result<SavedSettings, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current(generation, || {
            if LOCAL_DATA.account_access_revoked()
                || settings_store::account_access_revoked(&app).map_err(|error| error.message)?
            {
                return Ok(SavedSettings::with_defaults());
            }
            settings_store::load(&app).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
fn save_saved_settings(
    app: tauri::AppHandle,
    payload: SaveSettingsRequest,
) -> Result<SavedSettings, AccountScopeUpdateError> {
    let update = LOCAL_DATA.update_account_scope(
        || settings_store::prepare_save(payload).map_err(|error| error.message),
        |plan| (plan.account_changed(), plan.has_account()),
        || settings_store::mark_account_access_revoked(&app).map_err(|error| error.message),
        || {
            credential_store::save(&credential_store::Credentials::default())
                .map_err(|error| error.message)
        },
        || clear_account_scoped_caches(&app),
        |plan| {
            let saved = settings_store::commit_save(&app, plan).map_err(|error| error.message)?;
            settings_store::clear_account_access_revoked(&app).map_err(|error| error.message)?;
            Ok(saved)
        },
    );

    let result = finalize_account_scope_update(update, || notify_account_scope_cleared(&app));
    #[cfg(not(mobile))]
    match &result {
        Ok(settings) => {
            DESKTOP_NOTIFICATIONS_ENABLED.store(
                settings.daily_course_notifications_enabled,
                Ordering::Release,
            );
            wake_desktop_scheduler();
        }
        Err(error) if error.account_scope_cleared => {
            DESKTOP_NOTIFICATIONS_ENABLED.store(false, Ordering::Release);
            wake_desktop_scheduler();
        }
        Err(_) => {}
    }
    result
}

fn clear_account_scoped_caches(app: &tauri::AppHandle) -> Result<(), String> {
    let mut errors = Vec::new();
    if let Err(error) = schedule_store::clear(app) {
        errors.push(error.message);
    }
    if let Err(error) = classrooms_store::clear(app) {
        errors.push(error.message);
    }
    if let Err(error) = calendar_export::clear(app) {
        errors.push(error.message);
    }
    #[cfg(not(mobile))]
    if let Err(error) = clear_desktop_task_state(app) {
        errors.push(error);
    }
    if errors.is_empty() {
        Ok(())
    } else {
        Err(errors.join("；"))
    }
}

#[tauri::command]
fn clear_local_data(app: tauri::AppHandle) -> Result<bool, String> {
    let result = LOCAL_DATA.revoke_and_clear(
        || settings_store::mark_account_access_revoked(&app).map_err(|error| error.message),
        || {
            let mut errors = Vec::new();
            if let Err(error) = credential_store::save(&credential_store::Credentials::default()) {
                errors.push(error.message);
            }
            if let Err(error) = calendar_export::clear(&app) {
                errors.push(error.message);
            }
            #[cfg(not(mobile))]
            if let Err(error) = clear_desktop_task_state(&app) {
                errors.push(error);
            }
            if let Err(error) = settings_store::clear_local_files_preserving_revocation(&app) {
                errors.push(error.message);
            }

            if errors.is_empty() {
                Ok(true)
            } else {
                Err(errors.join("；"))
            }
        },
    );
    let result = finalize_local_data_clear(result, || notify_account_scope_cleared(&app));
    #[cfg(not(mobile))]
    {
        DESKTOP_NOTIFICATIONS_ENABLED.store(false, Ordering::Release);
        wake_desktop_scheduler();
    }
    result
}

#[tauri::command]
fn load_saved_schedule(app: tauri::AppHandle) -> Result<Option<ScheduleResponse>, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current_account(generation, || load_current_schedule(&app))
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
fn load_saved_schedule_for_scope(
    app: tauri::AppHandle,
    payload: AccountScopeRequest,
) -> Result<Option<ScheduleResponse>, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current_account(generation, || {
            let current_scope = require_saved_account_scope()?;
            validate_account_scope_match(&payload.account_scope, &current_scope)?;
            schedule_store::load(&app, &current_scope).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
fn load_saved_classrooms(app: tauri::AppHandle) -> Result<Option<ClassroomsCacheResponse>, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current_account(generation, || load_current_classrooms(&app))
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
fn load_saved_classrooms_for_scope(
    app: tauri::AppHandle,
    payload: AccountScopeRequest,
) -> Result<Option<ClassroomsCacheResponse>, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current_account(generation, || {
            let current_scope = require_saved_account_scope()?;
            validate_account_scope_match(&payload.account_scope, &current_scope)?;
            classrooms_store::load(&app, &current_scope).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
async fn fetch_schedule(
    app: tauri::AppHandle,
    mut payload: ScheduleRequest,
) -> Result<ScheduleResponse, String> {
    let generation = LOCAL_DATA.begin();
    let account_scope = LOCAL_DATA
        .with_current_account(generation, || {
            settings_store::apply_saved_credentials(&mut payload.account, &mut payload.password)
                .map_err(|error| error.message)?;
            let request_scope = request_account_scope(&payload.account)?;
            let saved_scope = require_saved_account_scope()?;
            validate_account_scope_match(&request_scope, &saved_scope)?;
            Ok(request_scope)
        })
        .map_err(LocalDataAccessError::message)?;
    let schedule = schedule::fetch_schedule(&payload)
        .await
        .map_err(|error| error.message)?;
    LOCAL_DATA
        .with_current_account(generation, || {
            schedule_store::save(&app, &account_scope, &schedule).map_err(|error| error.message)?;
            #[cfg(not(mobile))]
            let _ = app.emit(
                "schedule:updated",
                ScheduleUpdatedEvent {
                    account_scope: account_scope.clone(),
                },
            );
            Ok(())
        })
        .map_err(LocalDataAccessError::message)?;
    Ok(schedule)
}

#[tauri::command]
fn import_schedule_to_calendar(app: tauri::AppHandle) -> Result<String, String> {
    let generation = LOCAL_DATA.begin();
    LOCAL_DATA
        .with_current_account(generation, || {
            let Some(schedule) = load_current_schedule(&app)? else {
                return Err("请先获取/刷新个人课表，获取成功后会自动保存到本地。".to_string());
            };
            calendar_export::export_and_open(&app, &schedule)
                .map(|path| path.to_string_lossy().to_string())
                .map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)
}

#[tauri::command]
async fn fetch_classrooms(
    app: tauri::AppHandle,
    mut payload: ClassroomsRequest,
) -> Result<ClassroomsCacheResponse, String> {
    let generation = LOCAL_DATA.begin();
    let account_scope = LOCAL_DATA
        .with_current_account(generation, || {
            settings_store::apply_saved_credentials(&mut payload.account, &mut payload.password)
                .map_err(|error| error.message)?;
            let request_scope = request_account_scope(&payload.account)?;
            let saved_scope = require_saved_account_scope()?;
            validate_account_scope_match(&request_scope, &saved_scope)?;
            Ok(request_scope)
        })
        .map_err(LocalDataAccessError::message)?;
    payload.target_date = Some(config::today_in_app_tz().to_string());
    let classrooms = classrooms::fetch_all_classrooms(&payload)
        .await
        .map_err(|error| error.message)?;
    LOCAL_DATA
        .with_current_account(generation, || {
            classrooms_store::save(&app, &account_scope, &classrooms).map_err(|error| error.message)
        })
        .map_err(LocalDataAccessError::message)?;
    Ok(classrooms)
}

#[tauri::command]
async fn fetch_holidays(
    app: tauri::AppHandle,
    payload: HolidaysRequest,
) -> Result<HolidaysResponse, String> {
    holidays::validate_fetch_year(payload.year).map_err(|error| error.message)?;
    let generation = LOCAL_DATA.begin();

    match holidays::fetch_remote(payload.year).await {
        Ok(response) => {
            let cache_attempt = LOCAL_DATA.with_current(generation, || {
                holidays::save_cache(&app, &response).map_err(|error| error.message)
            });
            finish_remote_holiday_fetch(response, cache_attempt)
        }
        Err(_) => {
            let cached = LOCAL_DATA
                .with_current(generation, || {
                    Ok(holidays::load_cache(&app, payload.year).ok().flatten())
                })
                .map_err(LocalDataAccessError::message)?;
            if let Some(cached) = cached {
                return Ok(cached);
            }

            LOCAL_DATA
                .with_current(generation, || {
                    holidays::offline_response(payload.year).map_err(|error| error.message)
                })
                .map_err(LocalDataAccessError::message)
        }
    }
}

#[tauri::command]
async fn show_desktop_widget(app: tauri::AppHandle) -> Result<bool, String> {
    #[cfg(not(mobile))]
    {
        show_course_widget(&app).map_err(|error| error.to_string())?;
        Ok(true)
    }

    #[cfg(mobile)]
    {
        let _ = app;
        Err("桌面课程小组件仅支持 macOS、Windows 和 Linux。".to_string())
    }
}

#[tauri::command]
async fn hide_desktop_widget(app: tauri::AppHandle) -> Result<bool, String> {
    #[cfg(not(mobile))]
    {
        if let Some(window) = app.get_webview_window("course-widget") {
            window.close().map_err(|error| error.to_string())?;
        }
        Ok(true)
    }

    #[cfg(mobile)]
    {
        let _ = app;
        Err("桌面课程小组件仅支持 macOS、Windows 和 Linux。".to_string())
    }
}

#[cfg(not(mobile))]
fn show_main_window(app: &tauri::AppHandle) {
    if let Some(window) = app.get_webview_window("main") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
    }
}

#[cfg(not(mobile))]
fn show_course_widget(app: &tauri::AppHandle) -> tauri::Result<()> {
    if let Some(window) = app.get_webview_window("course-widget") {
        let _ = window.show();
        let _ = window.unminimize();
        let _ = window.set_focus();
        return Ok(());
    }

    let builder = tauri::WebviewWindowBuilder::new(
        app,
        "course-widget",
        tauri::WebviewUrl::App("index.html?widget=course".into()),
    )
    .title("今日课程")
    .inner_size(320.0, 420.0)
    .min_inner_size(280.0, 320.0)
    .max_inner_size(420.0, 620.0)
    .position(24.0, 80.0)
    .decorations(false)
    .resizable(false)
    .always_on_top(true);
    // tao's visible_on_all_workspaces is macOS/Linux-only; calling it on
    // Windows is a silent no-op, so keep it off that platform.
    #[cfg(not(target_os = "windows"))]
    let builder = builder.visible_on_all_workspaces(true);
    let window = builder
        .focused(false)
        .shadow(true)
        .build()?;
    let _ = window.show();
    Ok(())
}

#[cfg(not(mobile))]
enum TrayCourseContent {
    Loading,
    Message(String),
    Courses {
        today: TrayDayCourses,
        tomorrow: TrayDayCourses,
    },
}

#[cfg(not(mobile))]
struct TrayDayCourses {
    label: String,
    date: String,
    week_number: i64,
    courses: Vec<String>,
}

#[cfg(not(mobile))]
fn non_empty_option(value: String) -> Option<String> {
    let trimmed = value.trim().to_string();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed)
    }
}

fn request_account_scope(account: &Option<String>) -> Result<String, String> {
    let requested_account = account
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .ok_or_else(|| "请输入教务账号。".to_string())?;
    let credentials = load_saved_credentials_with_scope()?
        .ok_or_else(|| "请先在设置中保存教务账号。".to_string())?;
    if credentials.account.trim() != requested_account {
        return Err("当前查询账号尚未保存，请先在设置中保存后再获取数据。".to_string());
    }
    Ok(credentials.account_scope.clone())
}

fn saved_account_scope() -> Result<Option<String>, String> {
    Ok(load_saved_credentials_with_scope()?.map(|credentials| credentials.account_scope.clone()))
}

fn load_saved_credentials_with_scope() -> Result<Option<credential_store::Credentials>, String> {
    let Some(mut credentials) = credential_store::load().map_err(|error| error.message)? else {
        return Ok(None);
    };
    if credentials.account.trim().is_empty() {
        return Ok(None);
    }
    if !scoped_cache::is_valid_account_scope(&credentials.account_scope) {
        credentials.account_scope =
            scoped_cache::new_account_scope().map_err(|error| error.message)?;
        credential_store::save(&credentials).map_err(|error| error.message)?;
    }
    Ok(Some(credentials))
}

fn require_saved_account_scope() -> Result<String, String> {
    saved_account_scope()?.ok_or_else(|| "请先在设置中保存教务账号。".to_string())
}

fn validate_account_scope_match(request_scope: &str, saved_scope: &str) -> Result<(), String> {
    if request_scope == saved_scope {
        Ok(())
    } else {
        Err("当前查询账号尚未保存，请先在设置中保存后再获取数据。".to_string())
    }
}

fn load_current_schedule(app: &tauri::AppHandle) -> Result<Option<ScheduleResponse>, String> {
    let Some(account_scope) = saved_account_scope()? else {
        return Ok(None);
    };
    schedule_store::load(app, &account_scope).map_err(|error| error.message)
}

fn load_current_classrooms(
    app: &tauri::AppHandle,
) -> Result<Option<ClassroomsCacheResponse>, String> {
    let Some(account_scope) = saved_account_scope()? else {
        return Ok(None);
    };
    classrooms_store::load(app, &account_scope).map_err(|error| error.message)
}

#[cfg(not(mobile))]
fn classrooms_request_from_settings(settings: SavedSettings) -> ClassroomsRequest {
    ClassroomsRequest {
        account: non_empty_option(settings.account),
        password: None,
        campus_id: None,
        target_date: Some(config::today_in_app_tz().to_string()),
    }
}

#[cfg(not(mobile))]
#[derive(Debug, PartialEq, Eq)]
enum ScheduledClassroomRefreshError {
    MissingCredentials(String),
    Cancelled,
    Retryable(String),
}

#[cfg(not(mobile))]
impl ScheduledClassroomRefreshError {
    fn from_local_data(error: LocalDataAccessError) -> Self {
        match error {
            LocalDataAccessError::Stale | LocalDataAccessError::AccountAccessRevoked => {
                Self::Cancelled
            }
            LocalDataAccessError::Operation(message) => Self::Retryable(message),
        }
    }

    fn message(&self) -> Option<&str> {
        match self {
            Self::MissingCredentials(message) | Self::Retryable(message) => Some(message),
            Self::Cancelled => None,
        }
    }

    fn task_outcome(&self) -> DesktopTaskOutcome {
        match self {
            Self::Retryable(_) => DesktopTaskOutcome::RetryableFailure,
            Self::MissingCredentials(_) | Self::Cancelled => DesktopTaskOutcome::PermanentFailure,
        }
    }
}

#[cfg(not(mobile))]
async fn fetch_today_classrooms_from_saved_settings(
    app: tauri::AppHandle,
) -> Result<ClassroomsCacheResponse, ScheduledClassroomRefreshError> {
    let generation = LOCAL_DATA.begin();
    let (request, account_scope) = LOCAL_DATA
        .with_current_account(generation, || {
            let settings = settings_store::load(&app).map_err(|error| error.message)?;
            let mut request = classrooms_request_from_settings(settings);
            settings_store::apply_saved_credentials(&mut request.account, &mut request.password)
                .map_err(|error| error.message)?;
            let account_scope = request_account_scope(&request.account)?;
            Ok((request, account_scope))
        })
        .map_err(ScheduledClassroomRefreshError::from_local_data)?;
    auth::resolve_credentials(&request.account, &request.password)
        .map_err(|error| ScheduledClassroomRefreshError::MissingCredentials(error.message))?;
    let classrooms = classrooms::fetch_all_classrooms(&request)
        .await
        .map_err(|error| ScheduledClassroomRefreshError::Retryable(error.message))?;
    LOCAL_DATA
        .with_current_account(generation, || {
            classrooms_store::save(&app, &account_scope, &classrooms)
                .map_err(|error| error.message)?;
            let _ = app.emit(
                "classrooms:auto-fetched",
                ClassroomsUpdatedEvent {
                    account_scope: account_scope.clone(),
                },
            );
            Ok(())
        })
        .map_err(ScheduledClassroomRefreshError::from_local_data)?;
    Ok(classrooms)
}

#[cfg(not(mobile))]
fn truncate_menu_label(value: String, limit: usize) -> String {
    let mut output = String::new();
    for (index, character) in value.chars().enumerate() {
        if index >= limit {
            output.push('…');
            return output;
        }
        output.push(character);
    }
    output
}

#[cfg(not(mobile))]
fn course_time_label(course: &crate::models::Course) -> String {
    if !course.time_range.trim().is_empty() {
        return course.time_range.clone();
    }
    let start = config::SLOT_TIMES
        .get(course.start_slot)
        .map(|slot| slot.0)
        .unwrap_or("--:--");
    let end = config::SLOT_TIMES
        .get(course.end_slot)
        .map(|slot| slot.1)
        .unwrap_or("--:--");
    format!("{start}-{end}")
}

#[cfg(not(mobile))]
fn format_course_menu_line(course: &crate::models::Course, week_number: i64) -> String {
    let room = if course.room.trim().is_empty() {
        "地点未标注".to_string()
    } else {
        course.room.clone()
    };
    let course_name = if course.exam_week_numbers.contains(&week_number) {
        format!("试 {}", course.name)
    } else {
        course.name.clone()
    };
    truncate_menu_label(
        format!("{}  {}  @ {}", course_time_label(course), course_name, room),
        42,
    )
}

#[cfg(not(mobile))]
fn append_menu_item<M: Manager<tauri::Wry>>(
    menu: &Menu<tauri::Wry>,
    app: &M,
    id: impl Into<String>,
    text: impl AsRef<str>,
    enabled: bool,
) -> tauri::Result<()> {
    let item = MenuItem::with_id(app, id.into(), text, enabled, None::<&str>)?;
    menu.append(&item)
}

#[cfg(not(mobile))]
fn append_separator<M: Manager<tauri::Wry>>(menu: &Menu<tauri::Wry>, app: &M) -> tauri::Result<()> {
    let separator = PredefinedMenuItem::separator(app)?;
    menu.append(&separator)
}

#[cfg(not(mobile))]
fn append_course_section<M: Manager<tauri::Wry>>(
    menu: &Menu<tauri::Wry>,
    app: &M,
    id_prefix: &str,
    day: &TrayDayCourses,
) -> tauri::Result<()> {
    append_menu_item(
        menu,
        app,
        format!("{id_prefix}_title"),
        format!(
            "{}课程 · {} · 第 {} 周",
            day.label, day.date, day.week_number
        ),
        true,
    )?;
    if day.courses.is_empty() {
        append_menu_item(
            menu,
            app,
            format!("{id_prefix}_empty"),
            format!("{}暂无课程", day.label),
            true,
        )?;
    } else {
        for (index, course) in day.courses.iter().enumerate() {
            append_menu_item(
                menu,
                app,
                format!("{id_prefix}_course_{index}"),
                course,
                true,
            )?;
        }
    }
    Ok(())
}

#[cfg(not(mobile))]
fn build_tray_menu<M: Manager<tauri::Wry>>(
    app: &M,
    content: TrayCourseContent,
) -> tauri::Result<Menu<tauri::Wry>> {
    let menu = Menu::new(app)?;
    append_menu_item(&menu, app, "tray_title", "Where To Study", true)?;
    append_menu_item(
        &menu,
        app,
        "tray_status",
        "空教室、教学日历与本地账号设置",
        true,
    )?;
    append_separator(&menu, app)?;

    match &content {
        TrayCourseContent::Loading => {
            append_menu_item(&menu, app, "loading_title", "课程 · 正在更新", false)?;
            append_menu_item(
                &menu,
                app,
                "loading_message",
                "正在读取本地账号并获取课表…",
                false,
            )?;
        }
        TrayCourseContent::Message(message) => {
            append_menu_item(&menu, app, "course_message_title", "课程", true)?;
            append_menu_item(
                &menu,
                app,
                "course_message",
                truncate_menu_label(message.clone(), 42),
                true,
            )?;
        }
        TrayCourseContent::Courses { today, tomorrow } => {
            append_course_section(&menu, app, "today", today)?;
            append_separator(&menu, app)?;
            append_course_section(&menu, app, "tomorrow", tomorrow)?;
        }
    }

    append_separator(&menu, app)?;
    let open = MenuItem::with_id(app, "open", "打开主窗口", true, None::<&str>)?;
    let widget = MenuItem::with_id(app, "show_widget", "显示课程小组件", true, None::<&str>)?;
    let planner = MenuItem::with_id(app, "planner", "查看空教室", true, None::<&str>)?;
    let calendar = MenuItem::with_id(app, "calendar", "教学日历", true, None::<&str>)?;
    let settings = MenuItem::with_id(app, "settings", "设置", true, Some("CmdOrCtrl+,"))?;
    let refresh = MenuItem::with_id(app, "refresh_today", "刷新课程", true, Some("CmdOrCtrl+R"))?;
    let quit = MenuItem::with_id(app, "quit", "退出", true, Some("CmdOrCtrl+Q"))?;
    menu.append_items(&[&open, &widget, &planner, &calendar, &settings])?;
    append_separator(&menu, app)?;
    menu.append_items(&[&refresh, &quit])?;
    Ok(menu)
}

#[cfg(not(mobile))]
fn build_tray_day_courses(
    label: &str,
    courses: &[crate::models::Course],
    target_date: NaiveDate,
    term_start_date: NaiveDate,
) -> TrayDayCourses {
    let state = recommender::date_state(courses, target_date, term_start_date);
    TrayDayCourses {
        label: label.to_string(),
        date: target_date.to_string(),
        week_number: state.week_number,
        courses: state
            .courses
            .iter()
            .map(|course| format_course_menu_line(course, state.week_number))
            .collect(),
    }
}

#[cfg(not(mobile))]
async fn load_today_course_content(
    app: tauri::AppHandle,
    generation: LocalDataGeneration,
    prefer_saved_schedule: bool,
) -> TrayCourseContent {
    if prefer_saved_schedule {
        match LOCAL_DATA.with_current_account(generation, || load_current_schedule(&app)) {
            Ok(Some(schedule)) => return schedule_to_tray_content(schedule),
            Ok(None) => {}
            Err(error) => return TrayCourseContent::Message(error.message()),
        }
    }

    let (request, account_scope) = match LOCAL_DATA.with_current_account(generation, || {
        let settings = settings_store::load(&app).map_err(|error| error.message)?;
        let mut request = ScheduleRequest {
            account: non_empty_option(settings.account),
            password: None,
            term_id: non_empty_option(settings.term_id),
            term_start_date: non_empty_option(settings.term_start_date),
        };
        settings_store::apply_saved_credentials(&mut request.account, &mut request.password)
            .map_err(|error| error.message)?;
        let account_scope = request_account_scope(&request.account)?;
        Ok((request, account_scope))
    }) {
        Ok(request) => request,
        Err(error) => return TrayCourseContent::Message(error.message()),
    };
    let schedule = match schedule::fetch_schedule(&request).await {
        Ok(schedule) => {
            if let Err(error) = LOCAL_DATA.with_current_account(generation, || {
                schedule_store::save(&app, &account_scope, &schedule).map_err(|error| error.message)
            }) {
                return TrayCourseContent::Message(error.message());
            }
            schedule
        }
        Err(error) => return TrayCourseContent::Message(error.message),
    };
    schedule_to_tray_content(schedule)
}

#[cfg(not(mobile))]
fn schedule_to_tray_content(schedule: ScheduleResponse) -> TrayCourseContent {
    let term_start_date = match NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d") {
        Ok(date) => date,
        Err(_) => {
            return TrayCourseContent::Message("第一周周一日期格式不正确。".to_string());
        }
    };
    let today_date = config::today_in_app_tz();
    let tomorrow_date = today_date + ChronoDuration::days(1);
    TrayCourseContent::Courses {
        today: build_tray_day_courses("今日", &schedule.courses, today_date, term_start_date),
        tomorrow: build_tray_day_courses("明日", &schedule.courses, tomorrow_date, term_start_date),
    }
}

#[cfg(not(mobile))]
fn set_tray_menu(app: &tauri::AppHandle, content: TrayCourseContent) -> tauri::Result<()> {
    if let Some(tray) = app.tray_by_id("where-to-study-tray") {
        let menu = build_tray_menu(app, content)?;
        tray.set_menu(Some(menu))?;
        tray.set_visible(true)?;
    }
    Ok(())
}

#[cfg(not(mobile))]
fn refresh_tray_courses(app: tauri::AppHandle, prefer_saved_schedule: bool) {
    let generation = LOCAL_DATA.begin();
    if let Err(error) = LOCAL_DATA.with_current_account(generation, || {
        set_tray_menu(&app, TrayCourseContent::Loading).map_err(|error| error.to_string())
    }) {
        if error == LocalDataAccessError::AccountAccessRevoked {
            let _ = LOCAL_DATA.with_current(generation, || {
                set_tray_menu(
                    &app,
                    TrayCourseContent::Message(
                        "暂无本地课表，请先在设置中重新保存账号。".to_string(),
                    ),
                )
                .map_err(|error| error.to_string())
            });
        }
        return;
    }
    tauri::async_runtime::spawn(async move {
        let content =
            load_today_course_content(app.clone(), generation, prefer_saved_schedule).await;
        let _ = LOCAL_DATA.with_current_account(generation, || {
            set_tray_menu(&app, content).map_err(|error| error.to_string())
        });
    });
}

#[cfg(not(mobile))]
fn setup_tray(app: &mut tauri::App) -> tauri::Result<()> {
    let menu = build_tray_menu(app, TrayCourseContent::Loading)?;

    let mut tray = TrayIconBuilder::with_id("where-to-study-tray")
        .tooltip("Where To Study")
        .menu(&menu)
        .show_menu_on_left_click(true)
        .on_menu_event(|app, event| match event.id().as_ref() {
            "open" | "tray_title" | "tray_status" => show_main_window(app),
            "show_widget" => {
                let _ = show_course_widget(app);
            }
            "planner" => {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "planner");
            }
            id if id == "calendar"
                || id == "course_message_title"
                || id == "course_message"
                || id.starts_with("today_")
                || id.starts_with("tomorrow_") =>
            {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "calendar");
            }
            "settings" => {
                show_main_window(app);
                let _ = app.emit("tray:navigate", "settings");
            }
            "refresh_today" => refresh_tray_courses(app.clone(), false),
            "quit" => app.exit(0),
            _ => {}
        });

    if let Ok(icon) = Image::from_bytes(include_bytes!("../icons/tray-icon.png")) {
        tray = tray.icon(icon).icon_as_template(true);
    } else if let Some(icon) = app.default_window_icon().cloned() {
        tray = tray.icon(icon).icon_as_template(false);
    }
    tray.build(app)?;
    refresh_tray_courses(app.app_handle().clone(), true);
    Ok(())
}

#[cfg(not(mobile))]
fn keep_main_window_in_tray(window: &tauri::Window, event: &tauri::WindowEvent) {
    if window.label() != "main" {
        return;
    }
    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
        api.prevent_close();
        let _ = window.hide();
    }
}

#[cfg(not(mobile))]
fn next_daily_trigger_after(now: NaiveDateTime, hour: u32, minute: u32) -> NaiveDateTime {
    let time = NaiveTime::from_hms_opt(hour, minute, 0).expect("valid daily trigger time");
    let today_trigger = now.date().and_time(time);
    if now < today_trigger {
        today_trigger
    } else {
        today_trigger + ChronoDuration::days(1)
    }
}

#[cfg(not(mobile))]
fn desktop_now() -> NaiveDateTime {
    chrono::Utc::now()
        .with_timezone(&chrono_tz::Asia::Shanghai)
        .naive_local()
}

#[cfg(not(mobile))]
const CLASSROOM_REFRESH_RETRY_DELAY: ChronoDuration = ChronoDuration::minutes(15);
#[cfg(not(mobile))]
const MAX_CLASSROOM_REFRESH_RETRIES: u8 = 2;

#[cfg(not(mobile))]
fn next_desktop_schedule_boundary(
    now: NaiveDateTime,
    state: DesktopScheduleState,
    notifications_enabled: bool,
) -> NaiveDateTime {
    let mut boundaries = vec![
        next_daily_trigger_after(now, 0, 0),
        next_daily_trigger_after(now, 7, 0),
    ];
    if notifications_enabled {
        boundaries.push(next_daily_trigger_after(now, 7, 30));
    }
    if let Some(retry) = state
        .classroom_retry
        .filter(|retry| retry.next_attempt_at > now)
    {
        boundaries.push(retry.next_attempt_at);
    }
    boundaries
        .into_iter()
        .min()
        .expect("desktop schedule always has a boundary")
}

#[cfg(not(mobile))]
fn scheduler_sleep_duration(now: NaiveDateTime, boundary: NaiveDateTime) -> Duration {
    let wait = (boundary - now)
        .to_std()
        .unwrap_or_else(|_| Duration::from_secs(1));
    wait.max(Duration::from_secs(1))
}

#[cfg(not(mobile))]
fn sleep_until(boundary: NaiveDateTime) {
    std::thread::park_timeout(scheduler_sleep_duration(desktop_now(), boundary));
}

#[cfg(not(mobile))]
fn wake_desktop_scheduler() {
    let scheduler = DESKTOP_SCHEDULER_THREAD
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone();
    if let Some(scheduler) = scheduler {
        scheduler.unpark();
    }
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DesktopScheduledTask {
    RebuildTrayForDate,
    RefreshClassroomsAndTray,
    SendCourseNotification,
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DesktopTaskOutcome {
    Completed,
    PermanentFailure,
    RetryableFailure,
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DesktopTaskRetry {
    date: NaiveDate,
    attempts: u8,
    next_attempt_at: NaiveDateTime,
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PersistedDesktopTaskDates {
    classroom_refresh_date: Option<NaiveDate>,
    notification_date: Option<NaiveDate>,
}

#[cfg(not(mobile))]
#[derive(Debug, serde::Serialize, serde::Deserialize)]
struct PersistedDesktopTaskDatesFile {
    #[serde(default)]
    classroom_refresh_date: Option<String>,
    #[serde(default)]
    notification_date: Option<String>,
}

#[cfg(not(mobile))]
const DESKTOP_TASK_STATE_FILE_NAME: &str = "scheduler-state.json";

#[cfg(not(mobile))]
fn desktop_task_state_path(app: &tauri::AppHandle) -> Option<PathBuf> {
    app.path()
        .app_config_dir()
        .ok()
        .map(|directory| directory.join(DESKTOP_TASK_STATE_FILE_NAME))
}

#[cfg(not(mobile))]
fn load_persisted_desktop_task_dates(app: &tauri::AppHandle) -> PersistedDesktopTaskDates {
    let parse_date = |value: Option<String>| {
        value.and_then(|value| NaiveDate::parse_from_str(&value, "%Y-%m-%d").ok())
    };
    let empty = PersistedDesktopTaskDates {
        classroom_refresh_date: None,
        notification_date: None,
    };
    let Some(path) = desktop_task_state_path(app) else {
        return empty;
    };
    let Ok(bytes) = fs::read(&path) else {
        return empty;
    };
    let Ok(file) = serde_json::from_slice::<PersistedDesktopTaskDatesFile>(&bytes) else {
        return empty;
    };
    PersistedDesktopTaskDates {
        classroom_refresh_date: parse_date(file.classroom_refresh_date),
        notification_date: parse_date(file.notification_date),
    }
}

#[cfg(not(mobile))]
fn persist_desktop_task_dates(app: &tauri::AppHandle, state: &DesktopScheduleState) {
    let Some(path) = desktop_task_state_path(app) else {
        return;
    };
    let Some(parent) = path.parent() else {
        return;
    };
    if fs::create_dir_all(parent).is_err() {
        return;
    }
    let file = PersistedDesktopTaskDatesFile {
        classroom_refresh_date: state
            .classroom_refresh_date
            .map(|date| date.format("%Y-%m-%d").to_string()),
        notification_date: state
            .notification_date
            .map(|date| date.format("%Y-%m-%d").to_string()),
    };
    let Ok(bytes) = serde_json::to_vec(&file) else {
        return;
    };
    let Ok(mut temp) = NamedTempFile::new_in(parent) else {
        return;
    };
    let _ = temp.write_all(&bytes).is_err() || temp.persist(&path).is_err();
}

#[cfg(not(mobile))]
fn clear_desktop_task_state(app: &tauri::AppHandle) -> Result<(), String> {
    let Some(path) = desktop_task_state_path(app) else {
        return Ok(());
    };
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(format!("无法清除桌面任务状态：{error}")),
    }
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DesktopScheduleState {
    tray_date: NaiveDate,
    classroom_refresh_date: Option<NaiveDate>,
    notification_date: Option<NaiveDate>,
    classroom_retry: Option<DesktopTaskRetry>,
}

#[cfg(not(mobile))]
impl DesktopScheduleState {
    fn after_startup(now: NaiveDateTime, persisted: PersistedDesktopTaskDates) -> Self {
        let today = now.date();
        Self {
            tray_date: today,
            classroom_refresh_date: (persisted.classroom_refresh_date == Some(today))
                .then_some(today),
            notification_date: (persisted.notification_date == Some(today)).then_some(today),
            classroom_retry: None,
        }
    }

    fn mark_completed(&mut self, task: DesktopScheduledTask, date: NaiveDate) {
        match task {
            DesktopScheduledTask::RebuildTrayForDate => self.tray_date = date,
            DesktopScheduledTask::RefreshClassroomsAndTray => {
                self.tray_date = date;
                self.classroom_refresh_date = Some(date);
                self.classroom_retry = None;
            }
            DesktopScheduledTask::SendCourseNotification => {
                self.notification_date = Some(date);
            }
        }
    }

    fn record_result(
        &mut self,
        task: DesktopScheduledTask,
        date: NaiveDate,
        completed_at: NaiveDateTime,
        outcome: DesktopTaskOutcome,
    ) {
        if task != DesktopScheduledTask::RefreshClassroomsAndTray
            || outcome != DesktopTaskOutcome::RetryableFailure
        {
            self.mark_completed(task, date);
            return;
        }

        let attempts = self
            .classroom_retry
            .filter(|retry| retry.date == date)
            .map(|retry| retry.attempts.saturating_add(1))
            .unwrap_or(1);
        if attempts > MAX_CLASSROOM_REFRESH_RETRIES {
            self.mark_completed(task, date);
            return;
        }

        self.classroom_retry = Some(DesktopTaskRetry {
            date,
            attempts,
            next_attempt_at: completed_at + CLASSROOM_REFRESH_RETRY_DELAY,
        });
    }
}

#[cfg(not(mobile))]
fn due_desktop_tasks(
    now: NaiveDateTime,
    state: DesktopScheduleState,
    notifications_enabled: bool,
) -> Vec<DesktopScheduledTask> {
    let today = now.date();
    let classroom_due = state.classroom_refresh_date != Some(today)
        && match state.classroom_retry.filter(|retry| retry.date == today) {
            Some(retry) => now >= retry.next_attempt_at,
            None => now.time() >= NaiveTime::from_hms_opt(7, 0, 0).expect("valid refresh time"),
        };
    let notification_due = notifications_enabled
        && now.time() >= NaiveTime::from_hms_opt(7, 30, 0).expect("valid notification time")
        && state.notification_date != Some(today);

    let mut tasks = Vec::with_capacity(2);
    if classroom_due {
        tasks.push(DesktopScheduledTask::RefreshClassroomsAndTray);
    } else if state.tray_date != today {
        tasks.push(DesktopScheduledTask::RebuildTrayForDate);
    }
    if notification_due {
        tasks.push(DesktopScheduledTask::SendCourseNotification);
    }
    tasks
}

#[cfg(not(mobile))]
fn refresh_today_classrooms_and_emit(app: &tauri::AppHandle) -> DesktopTaskOutcome {
    match tauri::async_runtime::block_on(fetch_today_classrooms_from_saved_settings(app.clone())) {
        Ok(_) => DesktopTaskOutcome::Completed,
        Err(error) => {
            if let Some(message) = error.message() {
                let _ = app.emit(
                    "classrooms:auto-fetch-error",
                    format!("自动获取当天空教室失败：{message}"),
                );
            }
            error.task_outcome()
        }
    }
}

#[cfg(not(mobile))]
fn daily_course_notification_content(
    app: &tauri::AppHandle,
    today: NaiveDate,
    generation: LocalDataGeneration,
) -> Result<(String, String), String> {
    let Some(schedule) =
        (match LOCAL_DATA.with_current_account(generation, || load_current_schedule(app)) {
            Ok(schedule) => schedule,
            Err(LocalDataAccessError::Stale) => return Err(STALE_LOCAL_DATA_MESSAGE.to_string()),
            Err(LocalDataAccessError::AccountAccessRevoked) => {
                return Err("本地账号访问已撤销。".to_string());
            }
            Err(LocalDataAccessError::Operation(message)) => {
                return Ok(("今日课程提醒".to_string(), message));
            }
        })
    else {
        return Ok((
            "今日课程提醒".to_string(),
            "还没有保存课表，打开应用刷新个人课表后会在这里提醒。".to_string(),
        ));
    };
    let term_start_date = match NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d") {
        Ok(date) => date,
        Err(_) => {
            return Ok((
                "今日课程提醒".to_string(),
                "第一周周一日期格式不正确，请在设置里修正。".to_string(),
            ));
        }
    };
    let state = recommender::date_state(&schedule.courses, today, term_start_date);
    if state.courses.is_empty() {
        return Ok((
            "今日暂无课程".to_string(),
            format!("{} · 第 {} 周", today, state.week_number),
        ));
    }

    let mut lines: Vec<String> = state
        .courses
        .iter()
        .take(4)
        .map(|course| format_course_menu_line(course, state.week_number))
        .collect();
    if state.courses.len() > lines.len() {
        lines.push(format!(
            "还有 {} 门课，打开应用查看完整日程。",
            state.courses.len() - lines.len()
        ));
    }
    Ok((
        format!("今日有 {} 门课", state.courses.len()),
        lines.join("\n"),
    ))
}

#[cfg(not(mobile))]
fn send_daily_course_notification(app: &tauri::AppHandle, today: NaiveDate) -> Result<(), String> {
    if !DESKTOP_NOTIFICATIONS_ENABLED.load(Ordering::Acquire) {
        return Ok(());
    }
    let generation = LOCAL_DATA.begin();
    let (title, body) = daily_course_notification_content(app, today, generation)?;
    let notification = app.notification();
    LOCAL_DATA
        .with_current_account(generation, || {
            notification
                .builder()
                .title(title)
                .body(body)
                .group("daily-courses")
                .auto_cancel()
                .show()
                .map_err(|error| error.to_string())
        })
        .map_err(LocalDataAccessError::message)
}

#[cfg(not(mobile))]
fn run_desktop_scheduled_task(
    app: &tauri::AppHandle,
    task: DesktopScheduledTask,
    today: NaiveDate,
) -> DesktopTaskOutcome {
    match task {
        DesktopScheduledTask::RebuildTrayForDate => {
            refresh_tray_courses(app.clone(), true);
            DesktopTaskOutcome::Completed
        }
        DesktopScheduledTask::RefreshClassroomsAndTray => {
            let outcome = refresh_today_classrooms_and_emit(app);
            refresh_tray_courses(app.clone(), true);
            outcome
        }
        DesktopScheduledTask::SendCourseNotification => {
            if let Err(error) = send_daily_course_notification(app, today) {
                eprintln!("daily course notification failed: {error}");
                let _ = app.emit(
                    "schedule:daily-notification-error",
                    format!("发送今日课程提醒失败：{error}"),
                );
            }
            DesktopTaskOutcome::Completed
        }
    }
}

#[cfg(not(mobile))]
fn schedule_desktop_background_tasks(app: tauri::AppHandle) {
    std::thread::spawn(move || {
        *DESKTOP_SCHEDULER_THREAD
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(std::thread::current());
        let started_at = desktop_now();
        let persisted = load_persisted_desktop_task_dates(&app);
        let mut state = DesktopScheduleState::after_startup(started_at, persisted);

        loop {
            let now = desktop_now();
            let notifications_enabled = DESKTOP_NOTIFICATIONS_ENABLED.load(Ordering::Acquire);
            let mut completed = false;
            for task in due_desktop_tasks(now, state, notifications_enabled) {
                let outcome = run_desktop_scheduled_task(&app, task, now.date());
                state.record_result(task, now.date(), now, outcome);
                completed = true;
            }
            if completed {
                persist_desktop_task_dates(&app, &state);
            }
            let now = desktop_now();
            let notifications_enabled = DESKTOP_NOTIFICATIONS_ENABLED.load(Ordering::Acquire);
            sleep_until(next_desktop_schedule_boundary(
                now,
                state,
                notifications_enabled,
            ));
        }
    });
}

#[cfg(all(test, not(mobile)))]
mod background_schedule_tests {
    use super::*;

    fn date_time(hour: u32, minute: u32, second: u32) -> NaiveDateTime {
        NaiveDate::from_ymd_opt(2026, 8, 3)
            .unwrap()
            .and_hms_opt(hour, minute, second)
            .unwrap()
    }

    #[test]
    fn daily_trigger_is_strictly_after_now() {
        assert_eq!(
            next_daily_trigger_after(date_time(6, 59, 59), 7, 0),
            date_time(7, 0, 0)
        );
        assert_eq!(
            next_daily_trigger_after(date_time(7, 0, 0), 7, 0),
            date_time(7, 0, 0) + ChronoDuration::days(1)
        );
    }

    #[test]
    fn scheduler_uses_daily_boundaries_when_no_retry_is_pending() {
        let state = DesktopScheduleState::after_startup(
            date_time(6, 0, 0),
            PersistedDesktopTaskDates {
                classroom_refresh_date: None,
                notification_date: None,
            },
        );
        assert_eq!(
            next_desktop_schedule_boundary(date_time(6, 59, 59), state, true),
            date_time(7, 0, 0)
        );
        assert_eq!(
            next_desktop_schedule_boundary(date_time(7, 0, 0), state, true),
            date_time(7, 30, 0)
        );
        assert_eq!(
            next_desktop_schedule_boundary(date_time(7, 30, 0), state, true),
            date_time(0, 0, 0) + ChronoDuration::days(1)
        );
    }

    #[test]
    fn midnight_rebuilds_tray_without_network_refresh() {
        let yesterday = date_time(0, 0, 0).date() - ChronoDuration::days(1);
        let state = DesktopScheduleState {
            tray_date: yesterday,
            classroom_refresh_date: Some(yesterday),
            notification_date: Some(yesterday),
            classroom_retry: None,
        };

        assert_eq!(
            due_desktop_tasks(date_time(0, 0, 1), state, true),
            vec![DesktopScheduledTask::RebuildTrayForDate]
        );
    }

    #[test]
    fn delayed_wake_refreshes_classrooms_tray_and_notification_once() {
        let yesterday = date_time(0, 0, 0).date() - ChronoDuration::days(1);
        let mut state = DesktopScheduleState {
            tray_date: yesterday,
            classroom_refresh_date: Some(yesterday),
            notification_date: Some(yesterday),
            classroom_retry: None,
        };
        let now = date_time(8, 0, 0);
        let tasks = due_desktop_tasks(now, state, true);
        assert_eq!(
            tasks,
            vec![
                DesktopScheduledTask::RefreshClassroomsAndTray,
                DesktopScheduledTask::SendCourseNotification,
            ]
        );

        for task in tasks {
            state.record_result(task, now.date(), now, DesktopTaskOutcome::Completed);
        }
        assert!(due_desktop_tasks(now, state, true).is_empty());
    }

    #[test]
    fn startup_without_persisted_state_runs_todays_tasks_once() {
        let state = DesktopScheduleState::after_startup(
            date_time(8, 30, 0),
            PersistedDesktopTaskDates {
                classroom_refresh_date: None,
                notification_date: None,
            },
        );
        assert_eq!(
            due_desktop_tasks(date_time(8, 30, 0), state, true),
            vec![
                DesktopScheduledTask::RefreshClassroomsAndTray,
                DesktopScheduledTask::SendCourseNotification,
            ]
        );
    }

    #[test]
    fn startup_reloads_persisted_completed_dates() {
        let today = date_time(8, 30, 0).date();
        let state = DesktopScheduleState::after_startup(
            date_time(8, 30, 0),
            PersistedDesktopTaskDates {
                classroom_refresh_date: Some(today),
                notification_date: Some(today),
            },
        );
        assert!(due_desktop_tasks(date_time(8, 30, 0), state, true).is_empty());
    }

    #[test]
    fn startup_before_seven_keeps_the_seven_oclock_refresh_due() {
        let state = DesktopScheduleState::after_startup(
            date_time(6, 0, 0),
            PersistedDesktopTaskDates {
                classroom_refresh_date: None,
                notification_date: None,
            },
        );
        assert!(due_desktop_tasks(date_time(6, 59, 59), state, true).is_empty());
        assert_eq!(
            due_desktop_tasks(date_time(7, 0, 0), state, true),
            vec![DesktopScheduledTask::RefreshClassroomsAndTray]
        );
    }

    #[test]
    fn transient_classroom_failures_retry_twice_at_low_frequency() {
        let mut state = DesktopScheduleState::after_startup(
            date_time(6, 0, 0),
            PersistedDesktopTaskDates {
                classroom_refresh_date: None,
                notification_date: None,
            },
        );
        let task = DesktopScheduledTask::RefreshClassroomsAndTray;

        state.record_result(
            task,
            date_time(7, 0, 0).date(),
            date_time(7, 0, 0),
            DesktopTaskOutcome::RetryableFailure,
        );
        assert!(due_desktop_tasks(date_time(7, 14, 59), state, true).is_empty());
        assert_eq!(
            next_desktop_schedule_boundary(date_time(7, 0, 1), state, true),
            date_time(7, 15, 0)
        );
        assert_eq!(
            due_desktop_tasks(date_time(7, 15, 0), state, true),
            vec![task]
        );

        state.record_result(
            task,
            date_time(7, 15, 0).date(),
            date_time(7, 15, 0),
            DesktopTaskOutcome::RetryableFailure,
        );
        assert_eq!(state.classroom_retry.unwrap().attempts, 2);
        assert!(due_desktop_tasks(date_time(7, 29, 59), state, true).is_empty());

        state.record_result(
            task,
            date_time(7, 30, 0).date(),
            date_time(7, 30, 0),
            DesktopTaskOutcome::RetryableFailure,
        );
        assert_eq!(
            state.classroom_refresh_date,
            Some(date_time(7, 30, 0).date())
        );
        assert!(state.classroom_retry.is_none());
    }

    #[test]
    fn missing_credentials_do_not_schedule_retries() {
        let mut state = DesktopScheduleState::after_startup(
            date_time(6, 0, 0),
            PersistedDesktopTaskDates {
                classroom_refresh_date: None,
                notification_date: None,
            },
        );
        let task = DesktopScheduledTask::RefreshClassroomsAndTray;
        let outcome =
            ScheduledClassroomRefreshError::MissingCredentials("missing credentials".to_string())
                .task_outcome();
        assert_eq!(outcome, DesktopTaskOutcome::PermanentFailure);

        state.record_result(task, date_time(7, 0, 0).date(), date_time(7, 0, 0), outcome);

        assert!(state.classroom_retry.is_none());
        assert!(!due_desktop_tasks(date_time(8, 0, 0), state, true).contains(&task));
    }

    #[test]
    fn disabled_notifications_skip_the_task_and_seven_thirty_boundary() {
        let yesterday = date_time(0, 0, 0).date() - ChronoDuration::days(1);
        let state = DesktopScheduleState {
            tray_date: date_time(8, 0, 0).date(),
            classroom_refresh_date: Some(date_time(8, 0, 0).date()),
            notification_date: Some(yesterday),
            classroom_retry: None,
        };

        assert!(due_desktop_tasks(date_time(8, 0, 0), state, false).is_empty());
        assert_eq!(
            next_desktop_schedule_boundary(date_time(7, 0, 0), state, false),
            date_time(0, 0, 0) + ChronoDuration::days(1)
        );
    }

    #[test]
    fn scheduler_sleep_reaches_the_next_boundary_without_periodic_wakeups() {
        assert_eq!(
            scheduler_sleep_duration(date_time(7, 0, 0), date_time(8, 0, 0)),
            Duration::from_secs(60 * 60)
        );
        assert_eq!(
            scheduler_sleep_duration(date_time(8, 0, 0), date_time(7, 0, 0)),
            Duration::from_secs(1)
        );
    }
}

fn setup_app(app: &mut tauri::App) -> tauri::Result<()> {
    let account_access_revoked =
        settings_store::account_access_revoked(app.app_handle()).unwrap_or(true);
    LOCAL_DATA.set_account_access_revoked(account_access_revoked);

    #[cfg(not(mobile))]
    {
        let notifications_enabled = !account_access_revoked
            && settings_store::load(app.app_handle())
                .map(|settings| settings.daily_course_notifications_enabled)
                .unwrap_or(false);
        DESKTOP_NOTIFICATIONS_ENABLED.store(notifications_enabled, Ordering::Release);
        setup_tray(app)?;
        schedule_desktop_background_tasks(app.app_handle().clone());
    }

    #[cfg(mobile)]
    let _ = app;

    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default();
    #[cfg(not(mobile))]
    let builder = builder
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.show();
                let _ = window.unminimize();
                let _ = window.set_focus();
            }
        }))
        .plugin(tauri_plugin_notification::init());

    builder
        .setup(|app| {
            setup_app(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            #[cfg(not(mobile))]
            {
                keep_main_window_in_tray(window, event);
                if matches!(event, tauri::WindowEvent::Focused(true)) {
                    wake_desktop_scheduler();
                }
            }

            #[cfg(mobile)]
            let _ = (window, event);
        })
        .invoke_handler(tauri::generate_handler![
            get_metadata,
            load_saved_settings,
            save_saved_settings,
            clear_local_data,
            load_saved_schedule,
            load_saved_schedule_for_scope,
            load_saved_classrooms,
            load_saved_classrooms_for_scope,
            fetch_schedule,
            import_schedule_to_calendar,
            fetch_classrooms,
            fetch_holidays,
            show_desktop_widget,
            hide_desktop_widget
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_, event| {
            #[cfg(not(mobile))]
            if matches!(event, tauri::RunEvent::Resumed) {
                wake_desktop_scheduler();
            }

            #[cfg(mobile)]
            let _ = event;
        });
}
