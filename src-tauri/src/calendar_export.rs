use std::fs;
use std::path::PathBuf;
use std::process::Command;

use chrono::{DateTime, Duration as ChronoDuration, FixedOffset, NaiveDate, Utc};
use tauri::{AppHandle, Manager};

use crate::academic;
use crate::error::{ServiceError, ServiceResult};
use crate::models::{Course, DeadlineItem, ScheduleResponse};

const CALENDAR_FILE_NAME: &str = "where-to-study-personal-courses.ics";
const FAVORITES_CALENDAR_FILE_NAME: &str = "where-to-study-favorite-deadlines.ics";

pub const fn is_supported() -> bool {
    cfg!(target_os = "macos")
}

fn export_path(app: &AppHandle, file_name: &str) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_cache_dir()
        .map_err(|error| ServiceError::new(format!("无法定位日历导出目录：{error}")))?;
    Ok(directory.join(file_name))
}

pub fn clear(app: &AppHandle) -> ServiceResult<()> {
    for file_name in [CALENDAR_FILE_NAME, FAVORITES_CALENDAR_FILE_NAME] {
        let path = export_path(app, file_name)?;
        match fs::remove_file(path) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(ServiceError::new(format!(
                    "无法清除本地日历导出文件：{error}"
                )))
            }
        }
    }
    Ok(())
}

fn escape_ics_text(value: &str) -> String {
    value
        .replace('\\', "\\\\")
        .replace(';', "\\;")
        .replace(',', "\\,")
        .replace('\r', "")
        .replace('\n', "\\n")
}

fn sanitize_uid(value: &str) -> String {
    value
        .chars()
        .map(|character| {
            if character.is_ascii_alphanumeric() || matches!(character, '-' | '_' | '.') {
                character
            } else {
                '-'
            }
        })
        .collect()
}

fn event_description(course: &Course) -> String {
    let mut lines = Vec::new();
    if !course.teacher.trim().is_empty() {
        lines.push(format!("教师：{}", course.teacher));
    }
    if !course.week_text.trim().is_empty() {
        lines.push(format!("周次：{}", course.week_text));
    }
    if !course.section_text.trim().is_empty() {
        lines.push(format!("节次：{}", course.section_text));
    }
    lines.join("\n")
}

fn build_ics(schedule: &ScheduleResponse) -> ServiceResult<String> {
    let schedule = academic::effective_schedule(schedule);
    let term_start_date = academic::iso_date(&schedule.term_start_date)
        .ok_or_else(|| ServiceError::new("第一周周一日期格式不正确，无法导入苹果日历。"))?;
    let dtstamp = Utc::now().format("%Y%m%dT%H%M%SZ").to_string();
    let mut lines = vec![
        "BEGIN:VCALENDAR".to_string(),
        "VERSION:2.0".to_string(),
        "PRODID:-//Where To Study//Personal Courses//CN".to_string(),
        "CALSCALE:GREGORIAN".to_string(),
        "METHOD:PUBLISH".to_string(),
        "X-WR-CALNAME:Where To Study 个人课表".to_string(),
        "X-WR-TIMEZONE:Asia/Shanghai".to_string(),
    ];

    let mut emitted = std::collections::HashSet::new();
    for course in &schedule.courses {
        if academic::is_exam(course) {
            let Some(day) = course.event_date.as_deref().and_then(academic::iso_date) else {
                continue;
            };
            let uid = format!(
                "{}-{}-exam-{}@where-to-study.local",
                sanitize_uid(&schedule.term_id),
                sanitize_uid(&course.id),
                day.format("%Y%m%d")
            );
            if !emitted.insert(uid.clone()) {
                continue;
            }
            lines.extend([
                "BEGIN:VEVENT".to_owned(),
                format!("UID:{uid}"),
                format!("DTSTAMP:{dtstamp}"),
            ]);
            let timed = academic::course_minutes(course);
            if let Some((start, end)) = timed {
                append_timed_dates(&mut lines, day, start, end)?;
            } else {
                let next = day
                    .succ_opt()
                    .ok_or_else(|| ServiceError::new("考试日期超出日历范围。"))?;
                lines.extend([
                    format!("DTSTART;VALUE=DATE:{}", day.format("%Y%m%d")),
                    format!("DTEND;VALUE=DATE:{}", next.format("%Y%m%d")),
                    "TRANSP:TRANSPARENT".into(),
                ]);
            }
            let title = if timed.is_some() {
                format!("考试 · {}", course.name)
            } else {
                format!("考试 · 时间待定 · {}", course.name)
            };
            let original = schedule
                .exam_schedule
                .as_ref()
                .and_then(|snapshot| snapshot.items.iter().find(|item| item.id == course.id));
            let description = original
                .map(|item| item.time_text.as_str())
                .unwrap_or_default();
            lines.extend([
                format!("SUMMARY:{}", escape_ics_text(&title)),
                format!("LOCATION:{}", escape_ics_text(&course.room)),
                format!("DESCRIPTION:{}", escape_ics_text(description)),
                "END:VEVENT".to_owned(),
            ]);
            continue;
        }
        let Some((start, end)) = academic::course_minutes(course) else {
            continue;
        };
        if !(1..=7).contains(&course.weekday) {
            continue;
        }

        for week_number in &course.week_numbers {
            if *week_number < 1 {
                continue;
            }
            let event_date = week_number
                .checked_sub(1)
                .and_then(|week| week.checked_mul(7))
                .and_then(|days| days.checked_add(course.weekday - 1))
                .and_then(ChronoDuration::try_days)
                .and_then(|delta| term_start_date.checked_add_signed(delta));
            let Some(event_date) = event_date else {
                continue;
            };
            let uid = format!(
                "{}-{}-{}@where-to-study.local",
                sanitize_uid(&schedule.term_id),
                sanitize_uid(&course.id),
                week_number
            );
            if !emitted.insert(uid.clone()) {
                continue;
            }

            lines.extend([
                "BEGIN:VEVENT".to_string(),
                format!("UID:{uid}"),
                format!("DTSTAMP:{dtstamp}"),
            ]);
            append_timed_dates(&mut lines, event_date, start, end)?;
            lines.extend([
                format!("SUMMARY:{}", escape_ics_text(&course.name)),
                format!("LOCATION:{}", escape_ics_text(&course.room)),
                format!(
                    "DESCRIPTION:{}",
                    escape_ics_text(&event_description(course))
                ),
                "END:VEVENT".to_string(),
            ]);
        }
    }

    lines.push("END:VCALENDAR".to_string());
    Ok(format!("{}\r\n", lines.join("\r\n")))
}

fn append_timed_dates(
    lines: &mut Vec<String>,
    day: NaiveDate,
    start: i64,
    end: i64,
) -> ServiceResult<()> {
    let midnight = day
        .and_hms_opt(0, 0, 0)
        .ok_or_else(|| ServiceError::new("课程日期格式不正确。"))?;
    let start = midnight
        .checked_add_signed(ChronoDuration::minutes(start))
        .ok_or_else(|| ServiceError::new("课程开始时间超出日历范围。"))?;
    let end = midnight
        .checked_add_signed(ChronoDuration::minutes(end))
        .ok_or_else(|| ServiceError::new("课程结束时间超出日历范围。"))?;
    // 24:00 must be encoded as the following day's 00:00 in RFC 5545.
    lines.extend([
        format!(
            "DTSTART;TZID=Asia/Shanghai:{}",
            start.format("%Y%m%dT%H%M%S")
        ),
        format!("DTEND;TZID=Asia/Shanghai:{}", end.format("%Y%m%dT%H%M%S")),
    ]);
    Ok(())
}

fn safe_calendar_url(value: Option<&str>) -> Option<&str> {
    value.filter(|url| {
        (url.starts_with("https://") || url.starts_with("http://")) && !url.contains(['\r', '\n'])
    })
}

fn favorite_uid(item: &DeadlineItem) -> String {
    // FNV-1a keeps the UID deterministic without exposing a potentially long
    // custom-feed URL. The deadline itself is deliberately excluded so an
    // edited time updates the same calendar event instead of creating a copy.
    let identity = format!(
        "{}|{}|{}",
        item.source_type,
        item.id,
        item.source_url.as_deref().unwrap_or_default()
    );
    let mut hash = 0xcbf29ce484222325_u64;
    for byte in identity.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("favorite-{hash:016x}@where-to-study.local")
}

fn favorite_description(item: &DeadlineItem) -> String {
    let mut lines = Vec::new();
    if let Some(organizer) = item
        .organizer
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        lines.push(format!("主办方：{organizer}"));
    }
    if let Some(source) = item
        .source_name
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        lines.push(format!("来源：{source}"));
    }
    if let Some(url) = safe_calendar_url(item.official_url.as_deref()) {
        lines.push(format!("详情：{url}"));
    }
    lines.join("\n")
}

fn build_favorite_ics(items: &[DeadlineItem]) -> ServiceResult<String> {
    if items.is_empty() {
        return Err(ServiceError::new("没有可导入的收藏日程。"));
    }
    let shanghai_offset = FixedOffset::east_opt(8 * 60 * 60)
        .ok_or_else(|| ServiceError::new("无法创建上海时区。"))?;
    let dtstamp = Utc::now().format("%Y%m%dT%H%M%SZ").to_string();
    let mut lines = vec![
        "BEGIN:VCALENDAR".to_string(),
        "VERSION:2.0".to_string(),
        "PRODID:-//Where To Study//Favorite Deadlines//CN".to_string(),
        "CALSCALE:GREGORIAN".to_string(),
        "METHOD:PUBLISH".to_string(),
        "X-WR-CALNAME:Where To Study 收藏日程".to_string(),
        "X-WR-TIMEZONE:Asia/Shanghai".to_string(),
    ];

    for item in items {
        let deadline =
            DateTime::parse_from_rfc3339(item.primary_deadline.trim()).map_err(|_| {
                ServiceError::new(format!("收藏日程“{}”的截止时间格式不正确。", item.name))
            })?;
        let start = deadline.with_timezone(&shanghai_offset);
        let end = start + ChronoDuration::minutes(30);
        let uid = favorite_uid(item);
        lines.extend([
            "BEGIN:VEVENT".to_string(),
            format!("UID:{uid}"),
            format!("DTSTAMP:{dtstamp}"),
            format!(
                "DTSTART;TZID=Asia/Shanghai:{}",
                start.format("%Y%m%dT%H%M%S")
            ),
            format!("DTEND;TZID=Asia/Shanghai:{}", end.format("%Y%m%dT%H%M%S")),
            format!(
                "SUMMARY:{}",
                escape_ics_text(&format!("DDL：{}", item.name))
            ),
            format!(
                "DESCRIPTION:{}",
                escape_ics_text(&favorite_description(item))
            ),
        ]);
        if let Some(url) = safe_calendar_url(item.official_url.as_deref()) {
            lines.push(format!("URL:{url}"));
        }
        lines.push("END:VEVENT".to_string());
    }

    lines.push("END:VCALENDAR".to_string());
    Ok(format!("{}\r\n", lines.join("\r\n")))
}

fn write_and_open(app: &AppHandle, file_name: &str, content: &str) -> ServiceResult<PathBuf> {
    let path = export_path(app, file_name)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建日历导出目录：{error}")))?;
    }
    fs::write(&path, content)
        .map_err(|error| ServiceError::new(format!("无法写入日历文件：{error}")))?;
    Command::new("open")
        .arg(&path)
        .spawn()
        .map_err(|error| ServiceError::new(format!("无法打开苹果日历：{error}")))?;
    Ok(path)
}

pub fn export_and_open(app: &AppHandle, schedule: &ScheduleResponse) -> ServiceResult<PathBuf> {
    if !is_supported() {
        return Err(ServiceError::new("当前平台不支持导入苹果日历。"));
    }

    let content = build_ics(schedule)?;
    write_and_open(app, CALENDAR_FILE_NAME, &content)
}

pub fn export_favorites_and_open(
    app: &AppHandle,
    items: &[DeadlineItem],
) -> ServiceResult<PathBuf> {
    if !is_supported() {
        return Err(ServiceError::new("当前平台不支持导入苹果日历。"));
    }
    let content = build_favorite_ics(items)?;
    write_and_open(app, FAVORITES_CALENDAR_FILE_NAME, &content)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::academic::{account_key, ExamArrangement, ExamSchedule};

    fn schedule_with_exams(items: Vec<ExamArrangement>) -> ScheduleResponse {
        ScheduleResponse {
            term_id: "2026-2027-1".into(),
            term_start_date: "2026-09-07".into(),
            courses: vec![Course {
                id: "lesson".into(),
                name: "合成课程".into(),
                weekday: 1,
                week_numbers: vec![1, 2],
                start_slot: 0,
                end_slot: 1,
                time_range: "08:00-09:35".into(),
                ..Default::default()
            }],
            exam_schedule: Some(ExamSchedule {
                term_id: "2026-2027-1".into(),
                account_key: account_key("synthetic"),
                status: "fresh".into(),
                items,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    fn exam(id: &str, date: &str, start: &str, end: &str) -> ExamArrangement {
        ExamArrangement {
            id: id.into(),
            name: "合成考试, 实践".into(),
            date: date.into(),
            start_time: start.into(),
            end_time: end.into(),
            room: "示例考场".into(),
            time_text: format!("{date} {start}-{end}"),
            ..Default::default()
        }
    }

    #[test]
    fn calendar_exports_actual_exam_minutes_and_suppresses_only_overlap() {
        let raw = schedule_with_exams(vec![exam("exam", "2026-09-07", "09:20", "10:20")]);
        let original = serde_json::to_value(&raw).unwrap();
        let ics = build_ics(&raw).unwrap();
        assert_eq!(ics.matches("BEGIN:VEVENT").count(), 2);
        assert!(ics.contains("DTSTART;TZID=Asia/Shanghai:20260907T092000"));
        assert!(ics.contains("DTEND;TZID=Asia/Shanghai:20260907T102000"));
        assert!(!ics.contains("DTSTART;TZID=Asia/Shanghai:20260907T080000"));
        assert!(ics.contains("DTSTART;TZID=Asia/Shanghai:20260914T080000"));
        assert!(ics.contains("SUMMARY:考试 · 合成考试\\, 实践"));
        assert_eq!(serde_json::to_value(&raw).unwrap(), original);
    }

    #[test]
    fn calendar_encodes_midnight_end_on_the_following_day() {
        let raw = schedule_with_exams(vec![exam("late", "2026-12-31", "23:15", "24:00")]);
        let ics = build_ics(&raw).unwrap();
        assert!(ics.contains("DTSTART;TZID=Asia/Shanghai:20261231T231500"));
        assert!(ics.contains("DTEND;TZID=Asia/Shanghai:20270101T000000"));
        assert!(!ics.contains("T240000"));
    }

    #[test]
    fn calendar_exports_pending_as_transparent_all_day_and_omits_unknown_dates() {
        let raw = schedule_with_exams(vec![
            exam("pending", "2026-09-07", "", ""),
            exam("undated", "", "09:00", "11:00"),
        ]);
        let ics = build_ics(&raw).unwrap();
        assert_eq!(ics.matches("BEGIN:VEVENT").count(), 3);
        assert!(ics.contains("DTSTART;VALUE=DATE:20260907\r\nDTEND;VALUE=DATE:20260908"));
        assert!(ics.contains("TRANSP:TRANSPARENT"));
        assert!(ics.contains("SUMMARY:考试 · 时间待定 · 合成考试"));
        assert!(!ics.contains("undated"));
        assert!(ics.contains("DTSTART;TZID=Asia/Shanghai:20260907T080000"));
    }

    #[test]
    fn calendar_keeps_touching_courses_and_checks_date_arithmetic() {
        let mut raw = schedule_with_exams(vec![exam("touch", "2026-09-07", "09:35", "10:20")]);
        raw.courses[0].week_numbers = vec![1, 1, i64::MAX];
        let ics = build_ics(&raw).unwrap();
        assert_eq!(ics.matches("BEGIN:VEVENT").count(), 2);
        assert!(ics.contains("20260907T080000"));
        raw.term_start_date = "2026-09-7".into();
        assert!(build_ics(&raw).is_err());
    }

    #[test]
    fn calendar_does_not_export_exams_from_a_different_semester_or_failed_cache() {
        let mut raw = schedule_with_exams(vec![exam("exam", "2026-09-07", "09:00", "10:20")]);
        raw.exam_schedule.as_mut().unwrap().term_id = "different-term".into();
        assert!(!build_ics(&raw).unwrap().contains("SUMMARY:考试"));
        raw.exam_schedule.as_mut().unwrap().term_id = raw.term_id.clone();
        raw.exam_schedule.as_mut().unwrap().status = "failed".into();
        assert!(!build_ics(&raw).unwrap().contains("SUMMARY:考试"));
    }

    fn favorite() -> DeadlineItem {
        DeadlineItem {
            id: "contest-1".to_string(),
            name: "创新赛, Final".to_string(),
            event_type: "competition".to_string(),
            source_type: "contest_ddl".to_string(),
            primary_deadline: "2026-08-24T18:30:00+08:00".to_string(),
            organizer: Some("示例组委会".to_string()),
            official_url: Some("https://example.com/detail".to_string()),
            source_name: Some("Contest DDL".to_string()),
            source_url: Some("https://example.com/feed.json".to_string()),
        }
    }

    #[test]
    fn favorite_calendar_keeps_deadline_time_url_and_escaped_text() {
        let ics = build_favorite_ics(&[favorite()]).expect("build favorite calendar");
        assert!(ics.contains("DTSTART;TZID=Asia/Shanghai:20260824T183000"));
        assert!(ics.contains("DTEND;TZID=Asia/Shanghai:20260824T190000"));
        assert!(ics.contains("SUMMARY:DDL：创新赛\\, Final"));
        assert!(ics.contains("URL:https://example.com/detail"));
        assert!(ics.contains("主办方：示例组委会\\n来源：Contest DDL"));
    }

    #[test]
    fn favorite_calendar_rejects_empty_and_invalid_deadlines() {
        assert_eq!(
            build_favorite_ics(&[]).unwrap_err().message,
            "没有可导入的收藏日程。"
        );
        let mut invalid = favorite();
        invalid.primary_deadline = "2026-08-24".to_string();
        assert!(build_favorite_ics(&[invalid])
            .unwrap_err()
            .message
            .contains("截止时间格式不正确"));
    }

    #[test]
    fn favorite_calendar_uid_stays_stable_when_the_deadline_moves() {
        let original = favorite();
        let mut moved = original.clone();
        moved.primary_deadline = "2026-08-25T09:00:00+08:00".to_string();
        assert_eq!(favorite_uid(&original), favorite_uid(&moved));

        let mut other_source = original.clone();
        other_source.source_url = Some("https://another.example/feed.json".to_string());
        assert_ne!(favorite_uid(&original), favorite_uid(&other_source));
    }
}
