//! Local-only timetable edits. Keep the fetched snapshot intact so edits can be
//! restored and re-applied after refresh, without making university-side writes.
use crate::{
    error::{ServiceError, ServiceResult},
    models::{Course, ScheduleResponse},
    scoped_cache,
};
use chrono::{Datelike, Duration, NaiveDate};
use serde::{Deserialize, Serialize};
use sha1::{Digest, Sha1};
use std::{fs, io::Write, path::Path};
use tempfile::NamedTempFile;

pub const FILE_NAME: &str = "course-deletions.json";
const MAX_RECORDS: usize = 1000;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CourseDeletion {
    pub id: String,
    pub term_id: String,
    #[serde(default)]
    pub source_course_id: String,
    pub name: String,
    pub teacher: String,
    /// None removes the course for the semester; Some removes one dated meeting.
    pub date: Option<String>,
    pub start_slot: usize,
    pub end_slot: usize,
}

fn date(value: &str) -> ServiceResult<NaiveDate> {
    let parsed = NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ServiceError::new("课程日期格式不正确。"))?;
    if parsed.to_string() != value {
        return Err(ServiceError::new("课程日期格式不正确。"));
    }
    Ok(parsed)
}

fn occurs_on(schedule: &ScheduleResponse, course: &Course, day: NaiveDate) -> bool {
    let Ok(start) = date(&schedule.term_start_date) else {
        return false;
    };
    if start.weekday() != chrono::Weekday::Mon {
        return false;
    }
    let elapsed = (day - start).num_days();
    elapsed >= 0
        && i64::from(day.weekday().number_from_monday()) == course.weekday
        && course.week_numbers.contains(&(elapsed.div_euclid(7) + 1))
}

impl CourseDeletion {
    pub fn create(
        schedule: &ScheduleResponse,
        course_id: &str,
        occurrence: Option<&str>,
    ) -> ServiceResult<Self> {
        if schedule.term_id.trim().is_empty() {
            return Err(ServiceError::new("请先获取有效学期的课表。"));
        }
        let course = schedule
            .courses
            .iter()
            .find(|course| course.id == course_id)
            .ok_or_else(|| ServiceError::new("课程已变化，请重新选择。"))?;
        if course.name.trim().is_empty() {
            return Err(ServiceError::new("无法识别此课程。"));
        }
        if let Some(value) = occurrence {
            if !occurs_on(schedule, course, date(value)?) {
                return Err(ServiceError::new("所选日期没有这次课程。"));
            }
        }
        let mut record = Self {
            id: String::new(),
            term_id: schedule.term_id.clone(),
            source_course_id: course.source_course_id.trim().to_string(),
            name: course.name.trim().to_string(),
            teacher: course.teacher.trim().to_string(),
            date: occurrence.map(str::to_string),
            start_slot: if occurrence.is_some() {
                course.start_slot
            } else {
                0
            },
            end_slot: if occurrence.is_some() {
                course.end_slot
            } else {
                0
            },
        };
        let bytes =
            serde_json::to_vec(&record).map_err(|_| ServiceError::new("无法保存课程删除记录。"))?;
        record.id = format!("{:x}", Sha1::digest(bytes));
        Ok(record)
    }

    fn matches_course(&self, course: &Course) -> bool {
        if !self.source_course_id.is_empty() && !course.source_course_id.trim().is_empty() {
            self.source_course_id == course.source_course_id.trim()
        } else {
            self.name == course.name.trim() && self.teacher == course.teacher.trim()
        }
    }
}

pub fn apply(schedule: &ScheduleResponse, records: &[CourseDeletion]) -> ScheduleResponse {
    let mut visible = schedule.clone();
    let start = date(&schedule.term_start_date).ok();
    visible.courses.retain_mut(|course| {
        let rules: Vec<_> = records
            .iter()
            .filter(|record| record.term_id == schedule.term_id && record.matches_course(course))
            .collect();
        if rules.iter().any(|record| record.date.is_none()) {
            return false;
        }
        if let Some(start) = start {
            let start_slot = course.start_slot;
            let end_slot = course.end_slot;
            let weekday = course.weekday;
            course.week_numbers.retain(|week| {
                let offset = week
                    .checked_sub(1)
                    .and_then(|value| value.checked_mul(7))
                    .and_then(|value| value.checked_add(weekday - 1));
                let day = offset
                    .and_then(Duration::try_days)
                    .and_then(|offset| start.checked_add_signed(offset));
                !rules.iter().any(|record| {
                    record.start_slot == start_slot
                        && record.end_slot == end_slot
                        && day.is_some_and(|day| {
                            record.date.as_deref() == Some(day.to_string().as_str())
                        })
                })
            });
        }
        !course.week_numbers.is_empty()
    });
    visible
}

pub fn load(path: &Path, scope: &str) -> ServiceResult<Vec<CourseDeletion>> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let size = fs::metadata(path)
        .map_err(|_| ServiceError::new("无法读取课程删除记录。"))?
        .len();
    if size > 1024 * 1024 {
        return Err(ServiceError::new("课程删除记录过大。"));
    }
    let bytes = fs::read(path).map_err(|_| ServiceError::new("无法读取课程删除记录。"))?;
    let records = scoped_cache::decode::<Vec<CourseDeletion>>(&bytes, scope, "课程删除记录")?
        .unwrap_or_default();
    if records.len() > MAX_RECORDS {
        return Err(ServiceError::new("课程删除记录过多。"));
    }
    Ok(records)
}

pub fn save(path: &Path, scope: &str, records: &[CourseDeletion]) -> ServiceResult<()> {
    if records.len() > MAX_RECORDS {
        return Err(ServiceError::new("课程删除记录过多，请先恢复部分课程。"));
    }
    let bytes = scoped_cache::encode(scope, &records, "课程删除记录")?;
    if bytes.len() > 1024 * 1024 {
        return Err(ServiceError::new("课程删除记录过大，请先恢复部分课程。"));
    }
    let directory = path
        .parent()
        .ok_or_else(|| ServiceError::new("课程删除记录路径无效。"))?;
    fs::create_dir_all(directory).map_err(|_| ServiceError::new("无法创建课程删除记录目录。"))?;
    let mut file = NamedTempFile::new_in(directory)
        .map_err(|_| ServiceError::new("无法保存课程删除记录。"))?;
    file.write_all(&bytes)
        .and_then(|_| file.as_file().sync_all())
        .map_err(|_| ServiceError::new("无法保存课程删除记录。"))?;
    file.persist(path)
        .map_err(|_| ServiceError::new("无法更新课程删除记录。"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    fn snapshot() -> ScheduleResponse {
        serde_json::from_str(include_str!("../../contracts/v1/fixtures/schedule.json")).unwrap()
    }
    #[test]
    fn whole_course_survives_refresh_and_isolated_by_term() {
        let mut raw = snapshot();
        raw.courses[0].source_course_id = "source-a".into();
        let rule = CourseDeletion::create(&raw, &raw.courses[0].id, None).unwrap();
        let mut changed = raw.clone();
        changed.courses[0].id = "new-row".into();
        changed.courses[0].room = "new-room".into();
        assert_eq!(
            apply(&changed, &[rule.clone()]).courses.len(),
            raw.courses.len() - 1
        );
        changed.term_id = "another-term".into();
        assert_eq!(apply(&changed, &[rule]).courses.len(), raw.courses.len());
        assert_eq!(apply(&raw, &[]).courses.len(), raw.courses.len());
    }
    #[test]
    fn occurrence_removes_only_matching_week_and_time() {
        let mut raw = snapshot();
        raw.term_start_date = "2026-03-02".into();
        raw.courses[0].weekday = 1;
        raw.courses[0].week_numbers = vec![1, 2, 3];
        let rule = CourseDeletion::create(&raw, &raw.courses[0].id, Some("2026-03-09")).unwrap();
        let mut second_meeting = raw.courses[0].clone();
        second_meeting.id = "afternoon".into();
        second_meeting.start_slot += 5;
        second_meeting.end_slot += 5;
        raw.courses.push(second_meeting);
        let result = apply(&raw, &[rule]);
        assert_eq!(result.courses[0].week_numbers, vec![1, 3]);
        assert_eq!(result.courses.last().unwrap().week_numbers, vec![1, 2, 3]);
        assert_eq!(raw.courses[0].week_numbers, vec![1, 2, 3]);
        assert!(CourseDeletion::create(&raw, &raw.courses[0].id, Some("2026-03-10")).is_err());
    }
    #[test]
    fn fallback_never_matches_different_teacher_when_ids_absent() {
        let mut raw = snapshot();
        raw.courses[0].source_course_id.clear();
        let rule = CourseDeletion::create(&raw, &raw.courses[0].id, None).unwrap();
        let mut changed = raw.clone();
        changed.courses[0].teacher.push_str("another teacher");
        assert_eq!(apply(&changed, &[rule]).courses.len(), raw.courses.len());
    }
    #[test]
    fn disk_rules_are_account_scoped_and_restore_is_atomic() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join(FILE_NAME);
        let scope_a = scoped_cache::new_account_scope().unwrap();
        let scope_b = scoped_cache::new_account_scope().unwrap();
        let raw = snapshot();
        let rule = CourseDeletion::create(&raw, &raw.courses[0].id, None).unwrap();
        save(&path, &scope_a, &[rule.clone()]).unwrap();
        assert_eq!(load(&path, &scope_a).unwrap(), vec![rule]);
        assert!(load(&path, &scope_b).unwrap().is_empty());
        save(&path, &scope_a, &[]).unwrap();
        assert!(load(&path, &scope_a).unwrap().is_empty());
    }
}
