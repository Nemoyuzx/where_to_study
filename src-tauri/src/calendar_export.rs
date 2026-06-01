use std::fs;
use std::path::PathBuf;
use std::process::Command;

use chrono::{Duration as ChronoDuration, NaiveDate, Utc};
use tauri::{AppHandle, Manager};

use crate::config;
use crate::error::{ServiceError, ServiceResult};
use crate::models::{Course, ScheduleResponse};

const CALENDAR_FILE_NAME: &str = "where-to-study-personal-courses.ics";

fn export_path(app: &AppHandle) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_cache_dir()
        .map_err(|error| ServiceError::new(format!("无法定位日历导出目录：{error}")))?;
    Ok(directory.join(CALENDAR_FILE_NAME))
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

pub fn export_and_open(app: &AppHandle, schedule: &ScheduleResponse) -> ServiceResult<PathBuf> {
    let path = export_path(app)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建日历导出目录：{error}")))?;
    }

    let content = build_ics(schedule)?;
    fs::write(&path, content)
        .map_err(|error| ServiceError::new(format!("无法写入日历文件：{error}")))?;
    Command::new("open")
        .arg(&path)
        .spawn()
        .map_err(|error| ServiceError::new(format!("无法打开苹果日历：{error}")))?;
    Ok(path)
}
