use chrono::{Datelike, NaiveDate};
use where_to_study_lib::config::today_in_app_tz;
use where_to_study_lib::error::{ServiceError, ServiceResult};
use where_to_study_lib::models::{ClassroomsRequest, Course, ScheduleRequest, ScheduleResponse};
use zeroize::Zeroizing;

use crate::credentials;
use crate::output;

const TERM_VALIDITY_WEEKS: i64 = 26;

/// Parse a yyyy-MM-dd date, defaulting to today (Shanghai timezone).
fn parse_date(value: Option<&str>) -> ServiceResult<NaiveDate> {
    match value {
        Some(text) => NaiveDate::parse_from_str(text.trim(), "%Y-%m-%d")
            .map_err(|_| ServiceError::new(format!("日期格式不正确：{text}，请使用 yyyy-MM-dd。"))),
        None => Ok(today_in_app_tz()),
    }
}

/// Load credentials, requiring both account and password.
fn require_credentials() -> ServiceResult<where_to_study_lib::credential_store::Credentials> {
    let Some(credentials) = credentials::load()? else {
        return Err(ServiceError::new(
            "尚未保存教务账号。请先运行：where-to-study-cli login",
        ));
    };
    if credentials.account.trim().is_empty() || credentials.password.is_empty() {
        return Err(ServiceError::new(
            "已保存的凭据不完整。请重新运行：where-to-study-cli login",
        ));
    }
    Ok(credentials)
}

fn schedule_request(
    mut credentials: where_to_study_lib::credential_store::Credentials,
) -> ScheduleRequest {
    ScheduleRequest {
        account: Some(std::mem::take(&mut credentials.account)),
        password: Some(std::mem::take(&mut credentials.password)),
        term_id: None,
        term_start_date: None,
        automatic_term_detection_enabled: None,
    }
}

pub fn login(account: Option<String>) -> ServiceResult<()> {
    let entered_account = match account {
        Some(value) => Zeroizing::new(value),
        None => credentials::prompt_account()?,
    };
    let account = entered_account.trim().to_string();
    if account.is_empty() {
        return Err(ServiceError::new("请输入教务账号。"));
    }
    let mut existing = credentials::load()?;
    let mut entered = credentials::prompt_password("教务密码（同账号留空则保留已保存密码）：")?;
    let password = if entered.is_empty() {
        let Some(saved) = existing.as_mut().filter(|credentials| {
            credentials.account.trim() == account && !credentials.password.is_empty()
        }) else {
            return Err(ServiceError::new("请输入教务密码。"));
        };
        std::mem::take(&mut saved.password)
    } else {
        std::mem::take(&mut *entered)
    };
    credentials::save(&account, password)?;
    println!(
        "已保存账号 {account} 的凭据到本地配置文件：{}",
        credentials::storage_description()?
    );
    Ok(())
}

pub fn logout() -> ServiceResult<()> {
    credentials::clear()?;
    println!("已清除 CLI 本地配置文件中的教务凭据。");
    Ok(())
}

pub async fn schedule(date: Option<String>, json: bool) -> ServiceResult<()> {
    let credentials = require_credentials()?;
    let target_date = parse_date(date.as_deref())?;
    let request = schedule_request(credentials);
    let schedule = where_to_study_lib::schedule::fetch_schedule(&request).await?;
    let week = schedule_week_number(&schedule, target_date)?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&day_schedule_json(&schedule, target_date, week))
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_schedule_day(&schedule, target_date, week)
}

pub async fn week(date: Option<String>, json: bool) -> ServiceResult<()> {
    let credentials = require_credentials()?;
    let target_date = parse_date(date.as_deref())?;
    let request = schedule_request(credentials);
    let schedule = where_to_study_lib::schedule::fetch_schedule(&request).await?;
    let week = schedule_week_number(&schedule, target_date)?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&week_schedule_json(&schedule, target_date, week))
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_schedule_week(&schedule, target_date, week)
}

pub async fn classrooms(
    campus: String,
    buildings: Vec<String>,
    slots: Option<String>,
    json: bool,
) -> ServiceResult<()> {
    let mut credentials = require_credentials()?;
    let target_date = today_in_app_tz();
    let campus_id = if campus.trim().is_empty() {
        "01".to_string()
    } else {
        campus.trim().to_string()
    };
    let request = ClassroomsRequest {
        account: Some(std::mem::take(&mut credentials.account)),
        password: Some(std::mem::take(&mut credentials.password)),
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

fn week_schedule_json(
    schedule: &ScheduleResponse,
    date: NaiveDate,
    week: i64,
) -> serde_json::Value {
    let monday = date
        .checked_sub_days(chrono::Days::new(
            (date.weekday().num_days_from_monday()) as u64,
        ))
        .unwrap_or(date);
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

fn day_schedule_json(schedule: &ScheduleResponse, date: NaiveDate, week: i64) -> serde_json::Value {
    serde_json::json!({
        "term_id": schedule.term_id,
        "term_start_date": schedule.term_start_date,
        "fetched_at": schedule.fetched_at,
        "date": date.format("%Y-%m-%d").to_string(),
        "week_number": week,
        "courses": courses_on_day(schedule, date, week),
    })
}

fn schedule_term_start(schedule: &ScheduleResponse) -> ServiceResult<NaiveDate> {
    NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d")
        .map_err(|_| ServiceError::new("课表返回的学期开始日期格式不正确。"))
}

fn schedule_week_number(schedule: &ScheduleResponse, date: NaiveDate) -> ServiceResult<i64> {
    let term_start = schedule_term_start(schedule)?;
    let term_end =
        term_start + chrono::Duration::weeks(TERM_VALIDITY_WEEKS) - chrono::Duration::days(1);
    if date < term_start || date > term_end {
        return Err(ServiceError::new(format!(
            "目标日期不在当前课表学期 {} 的有效范围内（{} 至 {}）。",
            schedule.term_id, term_start, term_end
        )));
    }
    Ok((date - term_start).num_days().div_euclid(7) + 1)
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
    if selected.is_empty() {
        return Err(ServiceError::new("节次筛选不能为空。"));
    }
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
        assert!(parse_slot_filter(",").is_err());
    }

    #[test]
    fn parse_date_defaults_to_today() {
        assert!(parse_date(None).is_ok());
        assert!(parse_date(Some("2026-09-01")).is_ok());
        assert!(parse_date(Some("2026-13-01")).is_err());
        assert!(parse_date(Some("2026/09/01")).is_err());
    }

    fn fixture_schedule() -> ScheduleResponse {
        ScheduleResponse {
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            fetched_at: String::new(),
            courses: Vec::new(),
        }
    }

    #[test]
    fn schedule_json_does_not_expose_removed_exam_week_semantics() {
        let date = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        let schedule = ScheduleResponse {
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            fetched_at: String::new(),
            courses: vec![Course {
                id: "legacy".to_string(),
                name: "旧缓存课程".to_string(),
                teacher: String::new(),
                room: String::new(),
                week_text: "1".to_string(),
                week_numbers: vec![1],
                exam_week_numbers: vec![1],
                weekday: 1,
                start_slot: 0,
                end_slot: 1,
                section_text: "1-2节".to_string(),
                time_range: "08:00-09:35".to_string(),
            }],
        };
        let courses = courses_on_day(&schedule, date, 1);
        assert_eq!(courses.len(), 1);
        assert!(courses[0].get("is_exam").is_none());
    }

    #[test]
    fn schedule_week_rejects_dates_outside_returned_term() {
        let schedule = fixture_schedule();
        assert!(
            schedule_week_number(&schedule, NaiveDate::from_ymd_opt(2026, 3, 1).unwrap()).is_err()
        );
        assert_eq!(
            schedule_week_number(&schedule, NaiveDate::from_ymd_opt(2026, 3, 2).unwrap()).unwrap(),
            1
        );
        assert_eq!(
            schedule_week_number(&schedule, NaiveDate::from_ymd_opt(2026, 8, 30).unwrap()).unwrap(),
            26
        );
        assert!(
            schedule_week_number(&schedule, NaiveDate::from_ymd_opt(2026, 9, 1).unwrap()).is_err()
        );
    }
}
