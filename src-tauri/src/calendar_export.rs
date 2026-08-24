use std::fs;
use std::path::PathBuf;
use std::process::Command;

use chrono::{DateTime, Duration as ChronoDuration, FixedOffset, NaiveDate, Utc};
use tauri::{AppHandle, Manager};

use crate::config;
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
    let term_start_date = NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d")
        .map_err(|_| ServiceError::new("第一周周一日期格式不正确，无法导入苹果日历。"))?;
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

    for course in &schedule.courses {
        let Some((start_time, _)) = config::SLOT_TIMES.get(course.start_slot) else {
            continue;
        };
        let Some((_, end_time)) = config::SLOT_TIMES.get(course.end_slot) else {
            continue;
        };
        if !(1..=7).contains(&course.weekday) {
            continue;
        }

        for week_number in &course.week_numbers {
            if *week_number < 1 {
                continue;
            }
            let days = (*week_number - 1) * 7 + (course.weekday - 1);
            let event_date = term_start_date + ChronoDuration::days(days);
            let date_stamp = event_date.format("%Y%m%d").to_string();
            let start_stamp = start_time.replace(':', "");
            let end_stamp = end_time.replace(':', "");
            let uid = format!(
                "{}-{}-{}@where-to-study.local",
                sanitize_uid(&schedule.term_id),
                sanitize_uid(&course.id),
                week_number
            );

            lines.extend([
                "BEGIN:VEVENT".to_string(),
                format!("UID:{uid}"),
                format!("DTSTAMP:{dtstamp}"),
                format!("DTSTART;TZID=Asia/Shanghai:{date_stamp}T{start_stamp}00"),
                format!("DTEND;TZID=Asia/Shanghai:{date_stamp}T{end_stamp}00"),
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
