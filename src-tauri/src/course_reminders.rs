//! Local pre-class reminders. Sleeps until an actual reminder/date boundary;
//! independent of classroom network refreshes. New plans contain future work.
use std::{collections::BTreeMap, fs, io::Write, sync::Mutex};

use chrono::{Duration, NaiveDateTime};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tauri::{Emitter, Manager};
use tempfile::NamedTempFile;

use crate::{academic, models::SavedSettings, models::ScheduleResponse};

#[derive(Clone, PartialEq, Eq)]
struct Preferences {
    enabled: bool,
    minutes: Vec<u16>,
    english: bool,
    revision: u64,
}

static PREFERENCES: Mutex<Preferences> = Mutex::new(Preferences {
    enabled: false,
    minutes: Vec::new(),
    english: false,
    revision: 0,
});
static WORKER: Mutex<Option<std::thread::Thread>> = Mutex::new(None);

pub fn wake() {
    if let Some(worker) = WORKER
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .as_ref()
    {
        worker.unpark();
    }
}

pub fn start(app: tauri::AppHandle) {
    std::thread::spawn(move || {
        *WORKER
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(std::thread::current());
        let mut runtime = Runtime::default();
        loop {
            let next = runtime.tick(&app);
            let now = crate::desktop_now();
            let midnight = crate::next_daily_trigger_after(now, 0, 0);
            crate::sleep_until(next.map_or(midnight, |next| next.min(midnight)));
        }
    });
}

pub fn configure(app: &tauri::AppHandle, settings: &SavedSettings) {
    let mut current = PREFERENCES
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let mut minutes = settings.course_reminder_minutes.clone();
    minutes.sort_unstable();
    let enabled = settings.course_reminders_enabled && !settings.account.trim().is_empty();
    let english = settings.ui_language == "en";
    if current.enabled == enabled && current.minutes == minutes && current.english == english {
        return;
    }
    let became_enabled = enabled && !current.enabled;
    current.enabled = enabled;
    current.minutes = minutes;
    current.english = english;
    current.revision = current.revision.wrapping_add(1);
    if let Err(error) = crate::desktop_notifications::clear_preclass(&app.config().identifier) {
        let _ = app.emit("schedule:daily-notification-error", error);
    }
    drop(current);
    if became_enabled {
        crate::desktop_notifications::request_permission();
    }
    crate::wake_desktop_scheduler();
}

#[derive(Debug, Clone)]
struct Planned {
    id: String,
    fire_at: NaiveDateTime,
    expires_at: NaiveDateTime,
    start: NaiveDateTime,
    name: String,
    room: String,
    minutes: u16,
}

fn plan(
    schedule: &ScheduleResponse,
    account: &str,
    minutes: &[u16],
    now: NaiveDateTime,
) -> Vec<Planned> {
    if !crate::models::valid_course_reminder_minutes(minutes) {
        return Vec::new();
    }
    let Some(term_start) = academic::iso_date(&schedule.term_start_date) else {
        return Vec::new();
    };
    let schedule = academic::effective_schedule(schedule);
    let mut items = BTreeMap::new();
    for offset in 0..=8 {
        let Some(day) = now.date().checked_add_signed(Duration::days(offset)) else {
            continue;
        };
        for course in &schedule.courses {
            if !academic::occurs_on(course, day, term_start) {
                continue;
            }
            let Some((start_minute, _)) = academic::course_minutes(course) else {
                continue;
            };
            let Some(time) = chrono::NaiveTime::from_hms_opt(
                (start_minute / 60) as u32,
                (start_minute % 60) as u32,
                0,
            ) else {
                continue;
            };
            let start = day.and_time(time);
            for &lead in minutes {
                let Some(fire_at) = start.checked_sub_signed(Duration::minutes(i64::from(lead)))
                else {
                    continue;
                };
                if fire_at <= now {
                    continue;
                }
                // Identity excludes fetch time and room, so unchanged refreshes
                // cannot duplicate a notification. Only hashes reach the ledger.
                let identity = serde_json::to_vec(&(
                    account,
                    &schedule.term_id,
                    &course.id,
                    start.to_string(),
                    lead,
                ))
                .unwrap_or_default();
                let id = format!("{:x}", Sha256::digest(identity));
                let next = minutes
                    .iter()
                    .filter(|&&value| value < lead)
                    .max()
                    .copied()
                    .unwrap_or(0);
                let expires_at = (fire_at + Duration::seconds(60))
                    .min(start - Duration::minutes(i64::from(next)));
                items.entry(id.clone()).or_insert(Planned {
                    id,
                    fire_at,
                    expires_at,
                    start,
                    name: course.name.clone(),
                    room: course.room.clone(),
                    minutes: lead,
                });
            }
        }
    }
    let mut items: Vec<_> = items.into_values().collect();
    items.sort_by(|a, b| (a.fire_at, &a.id).cmp(&(b.fire_at, &b.id)));
    items
}

fn is_due(item: &Planned, now: NaiveDateTime) -> bool {
    item.fire_at <= now && now < item.expires_at && now < item.start
}

fn revalidated_due(
    schedule: &ScheduleResponse,
    account: &str,
    minutes: &[u16],
    now: NaiveDateTime,
    armed: &[Planned],
) -> Vec<Planned> {
    // A refresh may finish at the exact trigger boundary. Keep only previously
    // armed identities still present in the latest effective timetable, using
    // fresh titles/rooms. Never introduce an unarmed reminder from the past.
    plan(schedule, account, minutes, now - Duration::seconds(60))
        .into_iter()
        .filter(|item| is_due(item, now) && armed.iter().any(|old| old.id == item.id))
        .collect()
}

const LEDGER_FILE: &str = "course-reminder-delivered.json";

#[derive(Default, Serialize, Deserialize)]
struct Ledger(BTreeMap<String, i64>);

pub fn clear(app: &tauri::AppHandle) -> Result<(), String> {
    let path = app
        .path()
        .app_config_dir()
        .map_err(|e| e.to_string())?
        .join(LEDGER_FILE);
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.to_string()),
    }
}

impl Ledger {
    fn load(app: &tauri::AppHandle) -> Self {
        app.path()
            .app_config_dir()
            .ok()
            .and_then(|p| fs::read(p.join(LEDGER_FILE)).ok())
            .and_then(|bytes| serde_json::from_slice(&bytes).ok())
            .unwrap_or_default()
    }

    fn save(&self, app: &tauri::AppHandle) -> Result<(), String> {
        let parent = app.path().app_config_dir().map_err(|e| e.to_string())?;
        fs::create_dir_all(&parent).map_err(|e| e.to_string())?;
        let mut file = NamedTempFile::new_in(&parent).map_err(|e| e.to_string())?;
        serde_json::to_writer(&mut file, self).map_err(|e| e.to_string())?;
        file.flush().map_err(|e| e.to_string())?;
        file.persist(parent.join(LEDGER_FILE))
            .map_err(|e| e.to_string())?;
        Ok(())
    }
}

#[derive(Default)]
pub struct Runtime {
    pending: Vec<Planned>,
    stamp: Option<(crate::LocalDataGeneration, u64, u64)>,
    recoveries: u8,
}

impl Runtime {
    pub fn tick(&mut self, app: &tauri::AppHandle) -> Option<NaiveDateTime> {
        let expected = PREFERENCES
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let generation = crate::LOCAL_DATA.begin();
        let revision = crate::COURSE_EDITS_REVISION.load(std::sync::atomic::Ordering::SeqCst);
        let stamp = (generation, revision, expected.revision);
        if self.stamp.is_none_or(|(account, _, preferences)| {
            account != generation || preferences != expected.revision
        }) || !expected.enabled
        {
            self.pending.clear();
        }
        self.stamp = Some(stamp);
        if !expected.enabled {
            return None;
        }

        // Same account gate and edit/preference checks as the daily summary.
        // Clearing data waits for delivery and then removes our notification.
        let result = crate::LOCAL_DATA.with_current_account(generation, || {
            crate::publish_current_course_content(&crate::COURSE_EDITS_REVISION, revision, || {
                let preferences = PREFERENCES
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if *preferences != expected {
                    return Ok(None);
                }
                let now = crate::desktop_now();
                let schedule = crate::load_current_schedule(app)?;
                let account = crate::saved_account_scope()?.unwrap_or_default();
                let mut ledger = Ledger::load(app);
                ledger
                    .0
                    .retain(|_, expires| *expires > now.and_utc().timestamp());
                let due = schedule
                    .as_ref()
                    .map(|schedule| {
                        revalidated_due(schedule, &account, &expected.minutes, now, &self.pending)
                    })
                    .unwrap_or_default();
                let due: Vec<_> = due
                    .into_iter()
                    .filter(|item| !ledger.0.contains_key(&item.id))
                    .collect();
                if !due.is_empty() {
                    let title = if expected.english {
                        "Upcoming classes"
                    } else {
                        "课前提醒"
                    };
                    let body = due
                        .iter()
                        .map(|item| {
                            if expected.english {
                                format!(
                                    "{} · {} ({} min before) · {}",
                                    item.name,
                                    item.start.format("%H:%M"),
                                    item.minutes,
                                    item.room
                                )
                            } else {
                                format!(
                                    "{} · {}（提前 {} 分钟）· {}",
                                    item.name,
                                    item.start.format("%H:%M"),
                                    item.minutes,
                                    item.room
                                )
                            }
                        })
                        .collect::<Vec<_>>()
                        .join("\n");
                    crate::desktop_notifications::show_preclass(
                        &app.config().identifier,
                        title,
                        &body,
                    )?;
                    for item in due {
                        ledger.0.insert(
                            item.id.clone(),
                            (item.start + Duration::days(2)).and_utc().timestamp(),
                        );
                    }
                    ledger.save(app)?;
                }
                self.pending = schedule
                    .map(|s| plan(&s, &account, &expected.minutes, now))
                    .unwrap_or_default();
                self.pending.retain(|item| !ledger.0.contains_key(&item.id));
                Ok(self.pending.first().map(|item| item.fire_at))
            })
        });
        match result {
            Ok(next) => {
                self.recoveries = 0;
                next.flatten()
            }
            Err(error) => {
                let _ = app.emit("schedule:daily-notification-error", error.message());
                self.recover_after_failure(crate::desktop_now())
            }
        }
    }

    fn recover_after_failure(&mut self, now: NaiveDateTime) -> Option<NaiveDateTime> {
        // Do not replay the failed/expired slot or discard independent future
        // slots. A missing cache gets at most three bounded recovery attempts.
        self.pending.retain(|item| item.fire_at > now);
        self.recoveries = self.recoveries.saturating_add(1);
        let next = self.pending.first().map(|item| item.fire_at);
        if self.recoveries <= 3 {
            let retry = now + Duration::minutes(1);
            Some(next.map_or(retry, |next| next.min(retry)))
        } else {
            next
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn now(time: &str) -> NaiveDateTime {
        NaiveDateTime::parse_from_str(&format!("2026-09-21 {time}"), "%Y-%m-%d %H:%M:%S").unwrap()
    }
    fn schedule() -> ScheduleResponse {
        ScheduleResponse {
            term_id: "2026-2027-1".into(),
            term_start_date: "2026-09-21".into(),
            courses: vec![crate::models::Course {
                id: "math".into(),
                name: "Math".into(),
                weekday: 1,
                week_numbers: vec![1],
                start_slot: 0,
                end_slot: 1,
                ..Default::default()
            }],
            ..Default::default()
        }
    }
    #[test]
    fn custom_offsets_are_distinct_and_do_not_replay() {
        let items = plan(&schedule(), "account", &[10, 5], now("07:00:00"));
        assert_eq!(items.len(), 2);
        assert_eq!(items[0].fire_at, now("07:50:00"));
        assert_eq!(items[1].fire_at, now("07:55:00"));
        assert_ne!(items[0].id, items[1].id);
        assert!(is_due(&items[0], now("07:50:30")));
        assert!(!is_due(&items[0], now("07:55:00")));
        assert_eq!(
            plan(&schedule(), "account", &[10, 5], now("07:51:00")).len(),
            1
        );
        assert!(plan(&schedule(), "account", &[10, 5], now("08:00:00")).is_empty());
    }
    #[test]
    fn duplicate_courses_refresh_and_account_identity() {
        let mut input = schedule();
        input.courses.push(input.courses[0].clone());
        let a = plan(&input, "account", &[10], now("07:00:00"));
        assert_eq!(a.len(), 1);
        input.fetched_at = "new fetch".into();
        assert_eq!(
            a[0].id,
            plan(&input, "account", &[10], now("07:00:00"))[0].id
        );
        assert_ne!(a[0].id, plan(&input, "other", &[10], now("07:00:00"))[0].id);
        input.courses.clear();
        assert!(plan(&input, "account", &[10], now("07:00:00")).is_empty());
    }
    #[test]
    fn invalid_offsets_and_cross_day() {
        for minutes in [
            vec![],
            vec![0],
            vec![1441],
            vec![10, 10],
            vec![1, 2, 3, 4, 5, 6],
        ] {
            assert!(plan(&schedule(), "a", &minutes, now("07:00:00")).is_empty());
        }
        let items = plan(
            &schedule(),
            "a",
            &[1440],
            now("07:00:00") - Duration::days(1),
        );
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].fire_at, now("08:00:00") - Duration::days(1));
    }

    #[test]
    fn timed_exams_override_courses_and_undated_times_do_not_notify() {
        let mut input = schedule();
        input.exam_schedule = Some(academic::ExamSchedule {
            term_id: input.term_id.clone(),
            status: "fresh".into(),
            account_key: academic::account_key("a"),
            items: vec![
                academic::ExamArrangement {
                    id: "exam".into(),
                    name: "Exam".into(),
                    date: "2026-09-21".into(),
                    start_time: "08:00".into(),
                    end_time: "09:00".into(),
                    ..Default::default()
                },
                academic::ExamArrangement {
                    id: "unknown".into(),
                    name: "Time pending".into(),
                    date: "2026-09-21".into(),
                    ..Default::default()
                },
            ],
            ..Default::default()
        });
        let items = plan(&input, "a", &[10, 5], now("07:00:00"));
        assert_eq!(items.len(), 2);
        assert!(items.iter().all(|item| item.name == "Exam"));
    }

    #[test]
    fn shanghai_course_date_stays_independent_of_host_timezone() {
        let beijing = chrono::DateTime::parse_from_rfc3339("2026-09-20T23:00:00Z")
            .unwrap()
            .with_timezone(&chrono_tz::Asia::Shanghai)
            .naive_local();
        assert_eq!(beijing, now("07:00:00"));
        let item = &plan(&schedule(), "a", &[10], beijing)[0];
        assert_eq!(item.fire_at, now("07:50:00"));
        assert!(!is_due(item, now("07:49:59")));
        assert!(!is_due(item, now("08:00:00")));
    }

    #[test]
    fn one_delivery_failure_does_not_cancel_later_offsets() {
        let mut runtime = Runtime {
            pending: plan(&schedule(), "a", &[10, 5], now("07:00:00")),
            ..Default::default()
        };
        assert_eq!(
            runtime.recover_after_failure(now("07:50:00")),
            Some(now("07:51:00"))
        );
        assert_eq!(runtime.pending.len(), 1);
        assert_eq!(runtime.pending[0].fire_at, now("07:55:00"));
        runtime.recover_after_failure(now("07:51:00"));
        runtime.recover_after_failure(now("07:52:00"));
        assert_eq!(
            runtime.recover_after_failure(now("07:53:00")),
            Some(now("07:55:00"))
        );
        assert_eq!(runtime.recover_after_failure(now("08:00:00")), None);
    }

    #[test]
    fn recovery_without_any_future_work_is_bounded() {
        let mut runtime = Runtime::default();
        for _ in 0..3 {
            assert_eq!(
                runtime.recover_after_failure(now("07:00:00")),
                Some(now("07:01:00"))
            );
        }
        assert_eq!(runtime.recover_after_failure(now("07:00:00")), None);
    }

    #[test]
    fn unchanged_refresh_preserves_armed_due_but_deletion_or_new_past_event_does_not() {
        let mut input = schedule();
        let armed = plan(&input, "a", &[10, 5], now("07:00:00"));
        input.fetched_at = "new".into();
        input.courses[0].room = "Updated room".into();
        let due = revalidated_due(&input, "a", &[10, 5], now("07:50:01"), &armed);
        assert_eq!(due.len(), 1);
        assert_eq!(due[0].room, "Updated room");
        assert!(revalidated_due(&input, "a", &[10, 5], now("07:50:01"), &[]).is_empty());
        input.courses.clear();
        assert!(revalidated_due(&input, "a", &[10, 5], now("07:50:01"), &armed).is_empty());
    }
}
