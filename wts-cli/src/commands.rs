use chrono::{Datelike, NaiveDate};
use where_to_study_lib::config::{default_term_start_date, today_in_app_tz};
use where_to_study_lib::error::{ServiceError, ServiceResult};
use where_to_study_lib::models::{ClassroomsRequest, Course, ScheduleRequest, ScheduleResponse};

use crate::credentials;
use crate::output;

/// Parse a yyyy-MM-dd date, defaulting to today (Shanghai timezone).
fn parse_date(value: Option<&str>) -> ServiceResult<NaiveDate> {
    match value {
        Some(text) => NaiveDate::parse_from_str(text.trim(), "%Y-%m-%d")
            .map_err(|_| ServiceError::new(format!("日期格式不正确：{text}，请使用 yyyy-MM-dd。"))),
        None => Ok(today_in_app_tz()),
    }
}

/// Load credentials, requiring both account and password.
fn require_credentials() -> ServiceResult<(String, String)> {
    let Some((account, password)) = credentials::load()? else {
        return Err(ServiceError::new(
            "尚未保存教务账号。请先运行：wts-cli login <学号>",
        ));
    };
    if account.trim().is_empty() || password.is_empty() {
        return Err(ServiceError::new(
            "已保存的凭据不完整。请重新运行：wts-cli login <学号>",
        ));
    }
    Ok((account, password))
}

pub fn login(account: String, password: Option<String>) -> ServiceResult<()> {
    let account = account.trim().to_string();
    if account.is_empty() {
        return Err(ServiceError::new("请输入教务账号。"));
    }
    let password = match password {
        Some(value) if !value.is_empty() => value,
        _ => {
            // Preserve the existing saved password when none is provided.
            if let Some((saved_account, saved_password)) = credentials::load()? {
                if saved_account.trim() == account && !saved_password.is_empty() {
                    credentials::save(&account, &saved_password)?;
                    println!("已保留账号 {account} 的已保存密码。");
                    return Ok(());
                }
            }
            credentials::prompt_password("教务密码：")?
        }
    };
    credentials::save(&account, &password)?;
    println!("已保存账号 {account} 的凭据到系统安全存储。");
    Ok(())
}

pub fn logout() -> ServiceResult<()> {
    credentials::clear()?;
    println!("已清除系统凭据存储中的教务账号。");
    Ok(())
}

pub async fn schedule(date: Option<String>, json: bool) -> ServiceResult<()> {
    let (account, password) = require_credentials()?;
    let target_date = parse_date(date.as_deref())?;
    let request = ScheduleRequest {
        account: Some(account),
        password: Some(password),
        term_id: None,
        term_start_date: None,
    };
    let schedule = where_to_study_lib::schedule::fetch_schedule(&request).await?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&day_schedule_json(&schedule, target_date))
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_schedule_day(&schedule, target_date)
}

pub async fn week(date: Option<String>, json: bool) -> ServiceResult<()> {
    let (account, password) = require_credentials()?;
    let target_date = parse_date(date.as_deref())?;
    let request = ScheduleRequest {
        account: Some(account),
        password: Some(password),
        term_id: None,
        term_start_date: None,
    };
    let schedule = where_to_study_lib::schedule::fetch_schedule(&request).await?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&week_schedule_json(&schedule, target_date))
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_schedule_week(&schedule, target_date)
}

pub async fn classrooms(
    campus: String,
    buildings: Vec<String>,
    slots: Option<String>,
    date: Option<String>,
    json: bool,
) -> ServiceResult<()> {
    let (account, password) = require_credentials()?;
    let target_date = parse_date(date.as_deref())?;
    let campus_id = if campus.trim().is_empty() {
        "01".to_string()
    } else {
        campus.trim().to_string()
    };
    let request = ClassroomsRequest {
        account: Some(account),
        password: Some(password),
        campus_id: Some(campus_id.clone()),
        target_date: Some(target_date.format("%Y-%m-%d").to_string()),
    };
    let cache = where_to_study_lib::classrooms::fetch_all_classrooms(&request).await?;
    let campus_data = cache
        .campuses
        .iter()
        .find(|campus| campus.campus_id == campus_id)
        .ok_or_else(|| ServiceError::new(format!("响应中未找到校区 {campus_id} 的数据。")))?;

    // Parse slot filter: "1-3,5" -> [1,2,3,5]
    let slot_filter: Option<Vec<usize>> = match slots {
        Some(text) if !text.trim().is_empty() => Some(parse_slot_filter(&text)?),
        _ => None,
    };

    let mut rooms: Vec<&where_to_study_lib::models::ClassroomStatus> = campus_data
        .rooms
        .iter()
        .filter(|room| buildings.is_empty() || buildings.iter().any(|b| room.building == b.trim()))
        .filter(|room| {
            slot_filter
                .as_ref()
                .is_none_or(|slots| slots.iter().all(|slot| room.available_slots.contains(slot)))
        })
        .collect();
    rooms.sort_by(|a, b| a.building.cmp(&b.building).then(a.room.cmp(&b.room)));

    if json {
        let payload = serde_json::json!({
            "campus_id": campus_data.campus_id,
            "campus_name": campus_data.campus_name,
            "target_date": campus_data.target_date,
            "fetched_at": campus_data.fetched_at,
            "provider": campus_data.provider,
            "rooms": rooms.iter().map(|room| serde_json::json!({
                "id": room.id,
                "building": room.building,
                "room": room.room,
                "name": room.name,
                "size": room.size,
                "available_slots": room.available_slots,
            })).collect::<Vec<_>>(),
        });
        println!(
            "{}",
            serde_json::to_string_pretty(&payload)
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_classrooms(campus_data, &rooms, slot_filter.as_deref())
}

pub async fn holidays(year: Option<i32>, json: bool) -> ServiceResult<()> {
    let year = year.unwrap_or_else(|| today_in_app_tz().year());
    where_to_study_lib::holidays::validate_fetch_year(year)
        .map_err(|e| ServiceError::new(e.message))?;
    let response = match where_to_study_lib::holidays::fetch_remote(year).await {
        Ok(response) => response,
        Err(_) => where_to_study_lib::holidays::offline_response(year)?,
    };
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&response)
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_holidays(&response)
}

fn week_schedule_json(schedule: &ScheduleResponse, date: NaiveDate) -> serde_json::Value {
    let monday = date
        .checked_sub_days(chrono::Days::new(
            (date.weekday().num_days_from_monday()) as u64,
        ))
        .unwrap_or(date);
    let week = (monday - schedule_term_start(schedule)).num_days() / 7 + 1;
    let days: Vec<serde_json::Value> = (0..7)
        .map(|offset| {
            let day = monday + chrono::Duration::days(offset);
            let courses = courses_on_day(schedule, day, week);
            serde_json::json!({
                "date": day.format("%Y-%m-%d").to_string(),
                "courses": courses,
            })
        })
        .collect();
    serde_json::json!({
        "term_id": schedule.term_id,
        "week_number": week,
        "days": days,
    })
}

fn day_schedule_json(schedule: &ScheduleResponse, date: NaiveDate) -> serde_json::Value {
    let week = (date - schedule_term_start(schedule)).num_days() / 7 + 1;
    serde_json::json!({
        "term_id": schedule.term_id,
        "term_start_date": schedule.term_start_date,
        "fetched_at": schedule.fetched_at,
        "date": date.format("%Y-%m-%d").to_string(),
        "week_number": week,
        "courses": courses_on_day(schedule, date, week),
    })
}

fn schedule_term_start(schedule: &ScheduleResponse) -> NaiveDate {
    NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d").unwrap_or_else(|_| {
        NaiveDate::parse_from_str(&default_term_start_date(), "%Y-%m-%d").unwrap()
    })
}

fn courses_on_day(
    schedule: &ScheduleResponse,
    date: NaiveDate,
    week: i64,
) -> Vec<serde_json::Value> {
    let weekday = date.weekday().num_days_from_monday() as i64 + 1;
    let mut courses: Vec<&Course> = schedule
        .courses
        .iter()
        .filter(|course| course.weekday == weekday && course.week_numbers.contains(&week))
        .collect();
    courses.sort_by(|a, b| a.start_slot.cmp(&b.start_slot).then(a.name.cmp(&b.name)));
    courses
        .iter()
        .map(|course| {
            serde_json::json!({
                "id": course.id,
                "name": course.name,
                "teacher": course.teacher,
                "room": course.room,
                "time_range": course.time_range,
                "start_slot": course.start_slot + 1,
                "end_slot": course.end_slot + 1,
                "is_exam": course.exam_week_numbers.contains(&week),
            })
        })
        .collect()
}

fn parse_slot_filter(text: &str) -> ServiceResult<Vec<usize>> {
    let mut selected = Vec::new();
    for part in text.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if let Some((left, right)) = part.split_once('-') {
            let start: usize = left
                .trim()
                .parse()
                .map_err(|_| ServiceError::new(format!("节次格式不正确：{part}")))?;
            let end: usize = right
                .trim()
                .parse()
                .map_err(|_| ServiceError::new(format!("节次格式不正确：{part}")))?;
            if start == 0 || end < start || end > 14 {
                return Err(ServiceError::new(format!("节次范围不正确：{part}")));
            }
            selected.extend(start - 1..end);
        } else {
            let slot: usize = part
                .parse()
                .map_err(|_| ServiceError::new(format!("节次格式不正确：{part}")))?;
            if slot == 0 || slot > 14 {
                return Err(ServiceError::new(format!("节次范围不正确：{part}")));
            }
            selected.push(slot - 1);
        }
    }
    selected.sort_unstable();
    selected.dedup();
    Ok(selected)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn slot_filter_parses_ranges_and_singles() {
        assert_eq!(parse_slot_filter("1-3,5").unwrap(), vec![0, 1, 2, 4]);
        assert_eq!(parse_slot_filter("1,2,3").unwrap(), vec![0, 1, 2]);
        assert_eq!(
            parse_slot_filter("1-14").unwrap(),
            (0..14).collect::<Vec<_>>()
        );
    }

    #[test]
    fn slot_filter_dedups_and_sorts() {
        assert_eq!(parse_slot_filter("5,3,5,1-2").unwrap(), vec![0, 1, 2, 4]);
        assert_eq!(parse_slot_filter("1-1").unwrap(), vec![0]);
    }

    #[test]
    fn slot_filter_rejects_invalid() {
        assert!(parse_slot_filter("0").is_err());
        assert!(parse_slot_filter("15").is_err());
        assert!(parse_slot_filter("3-2").is_err());
        assert!(parse_slot_filter("abc").is_err());
        assert!(parse_slot_filter("1-15").is_err());
    }

    #[test]
    fn parse_date_defaults_to_today() {
        assert!(parse_date(None).is_ok());
        assert!(parse_date(Some("2026-09-01")).is_ok());
        assert!(parse_date(Some("2026-13-01")).is_err());
        assert!(parse_date(Some("2026/09/01")).is_err());
    }
}
