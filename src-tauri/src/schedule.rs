use std::collections::HashSet;
use std::io::Cursor;
use std::time::Duration;

use calamine::{Data, Reader, Xls};
use chrono::{Datelike, Duration as ChronoDuration, NaiveDate};
use regex::Regex;
use reqwest::header::{REFERER, USER_AGENT};
use serde_json::Value;
use sha1::{Digest, Sha1};

use crate::auth::resolve_credentials;
use crate::classrooms::{login_empty_classroom, sjd_headers};
use crate::config::{
    default_term_id, default_term_start_date, now_in_app_tz, JWGL_HOME_URL, JWGL_LOGIN_URL,
    JWGL_TIMETABLE_URL, SJD_REST_CLASSROOM_PAGE_URL, SJD_STUDENT_CURRICULUM_URL, SLOT_TIMES,
};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{Course, ScheduleRequest, ScheduleResponse};

const KEY_STR: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
const DEFAULT_USER_AGENT: &str =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36";
const EXAM_WEEK_ORDINALS: [usize; 2] = [17, 18];

pub fn encode_inp(raw: &str) -> String {
    let bytes = raw.as_bytes();
    let mut output = String::new();
    let mut index = 0;
    while index < bytes.len() {
        let chr1 = bytes[index];
        index += 1;
        let chr2 = if index < bytes.len() { bytes[index] } else { 0 };
        index += 1;
        let chr3 = if index < bytes.len() { bytes[index] } else { 0 };
        index += 1;

        let enc1 = chr1 >> 2;
        let enc2 = ((chr1 & 3) << 4) | (chr2 >> 4);
        let mut enc3 = ((chr2 & 15) << 2) | (chr3 >> 6);
        let mut enc4 = chr3 & 63;
        if chr2 == 0 {
            enc3 = 64;
            enc4 = 64;
        } else if chr3 == 0 {
            enc4 = 64;
        }

        output.push(KEY_STR[enc1 as usize] as char);
        output.push(KEY_STR[enc2 as usize] as char);
        output.push(KEY_STR[enc3 as usize] as char);
        output.push(KEY_STR[enc4 as usize] as char);
    }
    output
}

pub fn encode_login(account: &str, password: &str) -> String {
    format!("{}%%%{}", encode_inp(account), encode_inp(password))
}

pub fn expand_week_numbers(week_text: &str) -> Vec<i64> {
    let mut raw = week_text.replace('，', ",").replace(' ', "");
    let odd_only = raw.contains('单');
    let even_only = raw.contains('双');
    raw = raw.replace('周', "");
    raw = Regex::new(r"\[.*?\]")
        .expect("valid regex")
        .replace_all(&raw, "")
        .to_string();
    raw = Regex::new(r"\(.*?\)")
        .expect("valid regex")
        .replace_all(&raw, "")
        .to_string();

    let mut week_numbers = Vec::new();
    for item in raw.split(',').filter(|item| !item.is_empty()) {
        if let Some((left, right)) = item.split_once('-') {
            if let (Ok(start), Ok(end)) = (left.parse::<i64>(), right.parse::<i64>()) {
                week_numbers.extend(start..=end);
            }
        } else if let Ok(week) = item.parse::<i64>() {
            week_numbers.push(week);
        }
    }

    week_numbers.sort_unstable();
    week_numbers.dedup();
    if odd_only {
        return week_numbers
            .into_iter()
            .filter(|week| week % 2 == 1)
            .collect();
    }
    if even_only {
        return week_numbers
            .into_iter()
            .filter(|week| week % 2 == 0)
            .collect();
    }
    week_numbers
}

pub fn parse_cell_courses(cell_info: &str) -> Vec<ParsedCourse> {
    let lines: Vec<String> = cell_info
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .map(ToOwned::to_owned)
        .collect();
    let mut courses = Vec::new();
    let course_number_regex = Regex::new(r"^\(\d+\)$").expect("valid regex");

    for (index, line) in lines.iter().enumerate() {
        if !line.contains("[周]") || !line.chars().any(|character| character.is_ascii_digit()) {
            continue;
        }
        if index + 2 >= lines.len() {
            continue;
        }
        let room = lines[index + 1].clone();
        let section = lines[index + 2].clone();
        if !section.contains('节') {
            continue;
        }

        let teacher = if index >= 1 {
            lines[index - 1].clone()
        } else {
            String::new()
        };
        let mut name_index = index as isize - 2;
        if name_index >= 0 && course_number_regex.is_match(&lines[name_index as usize]) {
            name_index -= 1;
        }
        if name_index < 0 {
            continue;
        }

        courses.push(ParsedCourse {
            name: lines[name_index as usize].clone(),
            teacher,
            week: line.clone(),
            room,
            section,
        });
    }

    courses
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedCourse {
    pub name: String,
    pub teacher: String,
    pub week: String,
    pub room: String,
    pub section: String,
}

fn slot_time_range(start_slot: usize, end_slot: usize) -> String {
    format!("{}-{}", SLOT_TIMES[start_slot].0, SLOT_TIMES[end_slot].1)
}

pub fn annotate_exam_weeks(courses: &mut [Course]) {
    let mut existing_weeks: Vec<i64> = courses
        .iter()
        .flat_map(|course| course.week_numbers.iter().copied())
        .filter(|week| *week > 0)
        .collect();
    existing_weeks.sort_unstable();
    existing_weeks.dedup();

    let exam_weeks: HashSet<i64> = EXAM_WEEK_ORDINALS
        .iter()
        .filter_map(|ordinal| existing_weeks.get(ordinal - 1).copied())
        .collect();

    for course in courses {
        course.exam_week_numbers = course
            .week_numbers
            .iter()
            .copied()
            .filter(|week| exam_weeks.contains(week))
            .collect();
    }
}

fn json_string(value: Option<&Value>) -> String {
    value
        .and_then(|item| {
            item.as_str()
                .map(ToOwned::to_owned)
                .or_else(|| item.as_i64().map(|number| number.to_string()))
                .or_else(|| item.as_u64().map(|number| number.to_string()))
        })
        .unwrap_or_default()
}

pub fn parse_sjd_week_numbers(course: &Value) -> Vec<i64> {
    let details = json_string(course.get("classWeekDetails"));
    let mut weeks: Vec<i64> = Regex::new(r"\d+")
        .expect("valid regex")
        .find_iter(&details)
        .filter_map(|item| item.as_str().parse::<i64>().ok())
        .collect();
    if weeks.is_empty() {
        weeks = expand_week_numbers(&json_string(course.get("classWeek")));
    }
    weeks.sort_unstable();
    weeks.dedup();
    weeks
}

pub fn parse_sjd_slots(course: &Value) -> Option<(usize, usize)> {
    let class_time = json_string(course.get("classTime"));
    let class_time_tail: String = class_time.chars().skip(1).collect();
    let node_regex = Regex::new(r"\d{2}").expect("valid regex");
    let mut nodes: Vec<usize> = node_regex
        .find_iter(&class_time_tail)
        .filter_map(|item| item.as_str().parse::<usize>().ok())
        .collect();

    if nodes.is_empty() {
        nodes = Regex::new(r"\d+")
            .expect("valid regex")
            .find_iter(&json_string(course.get("weekNoteDetail")))
            .filter_map(|item| item.as_str().parse::<usize>().ok())
            .collect();
    }
    let start_slot = nodes.iter().min().copied()?.checked_sub(1)?;
    let end_slot = nodes.iter().max().copied()?.checked_sub(1)?;
    if start_slot >= SLOT_TIMES.len() || end_slot >= SLOT_TIMES.len() || start_slot > end_slot {
        return None;
    }
    Some((start_slot, end_slot))
}

fn collect_sjd_course_items<'a>(value: &'a Value, output: &mut Vec<&'a Value>) {
    match value {
        Value::Object(map) => {
            if map.contains_key("courseName") || map.contains_key("jx0408id") {
                output.push(value);
                return;
            }
            for child in map.values() {
                collect_sjd_course_items(child, output);
            }
        }
        Value::Array(items) => {
            for child in items {
                collect_sjd_course_items(child, output);
            }
        }
        _ => {}
    }
}

pub fn parse_sjd_courses(
    payload: &Value,
    term_id: String,
    term_start_date: NaiveDate,
) -> ServiceResult<ScheduleResponse> {
    let data = payload
        .get("data")
        .and_then(Value::as_array)
        .ok_or_else(|| ServiceError::new("移动教务课表返回为空。"))?;
    let Some(root) = data.first() else {
        return Err(ServiceError::new("移动教务课表返回为空。"));
    };
    let raw_items = root
        .get("item")
        .or_else(|| root.get("courses"))
        .unwrap_or(&Value::Null);

    let mut raw_courses = Vec::new();
    collect_sjd_course_items(raw_items, &mut raw_courses);

    let mut courses = Vec::new();
    let mut seen_ids = HashSet::new();
    for raw_course in raw_courses {
        let Some((start_slot, end_slot)) = parse_sjd_slots(raw_course) else {
            continue;
        };
        let weekday = json_string(
            raw_course
                .get("weekDay")
                .or_else(|| raw_course.get("classTime")),
        )
        .chars()
        .next()
        .and_then(|character| character.to_digit(10))
        .map(i64::from);
        let Some(weekday) = weekday else {
            continue;
        };
        if !(1..=7).contains(&weekday) {
            continue;
        }

        let name = json_string(raw_course.get("courseName")).trim().to_string();
        let name = if name.is_empty() {
            "未命名课程".to_string()
        } else {
            name
        };
        let teacher = json_string(raw_course.get("teacherName"))
            .trim()
            .to_string();
        let building = json_string(raw_course.get("buildingName"))
            .trim()
            .to_string();
        let room = json_string(
            raw_course
                .get("classroomName")
                .or_else(|| raw_course.get("location")),
        )
        .trim()
        .to_string();
        let location = if !building.is_empty() && !room.is_empty() && !room.contains(&building) {
            format!("{building}-{room}")
        } else if !room.is_empty() {
            room
        } else {
            building
        };
        let week_text = json_string(
            raw_course
                .get("classWeek")
                .or_else(|| raw_course.get("classWeekDetails")),
        )
        .trim()
        .to_string();
        let week_numbers = parse_sjd_week_numbers(raw_course);
        let stable = [
            json_string(raw_course.get("jx0408id")),
            name.clone(),
            teacher.clone(),
            location.clone(),
            week_text.clone(),
            weekday.to_string(),
            start_slot.to_string(),
            end_slot.to_string(),
        ]
        .join("|");
        let mut hasher = Sha1::new();
        hasher.update(stable.as_bytes());
        let course_id = format!("{:x}", hasher.finalize())[..12].to_string();
        if !seen_ids.insert(course_id.clone()) {
            continue;
        }
        let start_time = json_string(raw_course.get("startTime"));
        let end_time = json_string(
            raw_course
                .get("endTIme")
                .or_else(|| raw_course.get("endTime")),
        );
        courses.push(Course {
            id: course_id,
            name,
            teacher,
            room: location,
            week_text,
            week_numbers,
            exam_week_numbers: Vec::new(),
            weekday,
            start_slot,
            end_slot,
            section_text: format!("{}-{}节", start_slot + 1, end_slot + 1),
            time_range: format!(
                "{}-{}",
                if start_time.is_empty() {
                    SLOT_TIMES[start_slot].0
                } else {
                    start_time.as_str()
                },
                if end_time.is_empty() {
                    SLOT_TIMES[end_slot].1
                } else {
                    end_time.as_str()
                }
            ),
        });
    }

    annotate_exam_weeks(&mut courses);
    courses.sort_by(|left, right| {
        (left.weekday, left.start_slot, &left.name).cmp(&(
            right.weekday,
            right.start_slot,
            &right.name,
        ))
    });
    Ok(ScheduleResponse {
        term_id,
        term_start_date: term_start_date.to_string(),
        fetched_at: now_in_app_tz(),
        courses,
    })
}

pub fn infer_term_start_date(payload: &Value) -> Option<NaiveDate> {
    let root = payload.get("data").and_then(Value::as_array)?.first()?;
    let week = json_string(root.get("week").or_else(|| {
        root.get("topInfo")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .and_then(|item| item.get("week"))
    }))
    .parse::<i64>()
    .ok()?;
    let dated = root
        .get("date")
        .and_then(Value::as_array)?
        .iter()
        .find(|item| item.get("mxrq").is_some() && json_string(item.get("zc")) != "all")?;
    let day = NaiveDate::parse_from_str(&json_string(dated.get("mxrq")), "%Y-%m-%d").ok()?;
    let weekday = json_string(dated.get("xqid"))
        .parse::<i64>()
        .unwrap_or_else(|_| i64::from(day.weekday().number_from_monday()));
    let monday = day - ChronoDuration::days(weekday - 1);
    Some(monday - ChronoDuration::weeks(week - 1))
}

fn cell_to_string(cell: Option<&Data>) -> String {
    match cell {
        Some(Data::String(value)) => value.trim().to_string(),
        Some(Data::Float(value)) if value.fract() == 0.0 => format!("{}", *value as i64),
        Some(Data::Float(value)) => value.to_string(),
        Some(Data::Int(value)) => value.to_string(),
        Some(Data::Bool(value)) => value.to_string(),
        Some(Data::DateTime(value)) => value.to_string(),
        Some(Data::DateTimeIso(value)) => value.clone(),
        Some(Data::DurationIso(value)) => value.clone(),
        _ => String::new(),
    }
}

pub fn parse_timetable_xls(
    content: &[u8],
    term_id: String,
    term_start_date: NaiveDate,
) -> ServiceResult<ScheduleResponse> {
    let cursor = Cursor::new(content.to_vec());
    let mut workbook = Xls::new(cursor).map_err(|_| {
        ServiceError::new("教务返回的课表文件无法解析，可能是登录失败或教务系统格式变化。")
    })?;
    let range = workbook
        .worksheet_range_at(0)
        .ok_or_else(|| ServiceError::new("教务返回的课表文件没有工作表。"))?
        .map_err(|_| ServiceError::new("教务返回的课表文件无法读取。"))?;

    let (row_count, column_count) = range.get_size();
    let max_row = row_count.min(17);
    let max_col = column_count.min(8);
    let mut courses = Vec::new();
    let mut seen_ids = HashSet::new();

    for column in 1..max_col {
        let weekday = column as i64;
        for row in 3..max_row {
            let cell_info = cell_to_string(range.get_value((row as u32, column as u32)));
            if cell_info.trim().is_empty() {
                continue;
            }
            if row > 3 {
                let previous = cell_to_string(range.get_value(((row - 1) as u32, column as u32)));
                if previous == cell_info {
                    continue;
                }
            }

            let mut end_row = row;
            while end_row + 1 < max_row {
                let next = cell_to_string(range.get_value(((end_row + 1) as u32, column as u32)));
                if next != cell_info {
                    break;
                }
                end_row += 1;
            }

            let start_slot = row - 3;
            let end_slot = end_row - 3;
            for parsed in parse_cell_courses(&cell_info) {
                let week_numbers = expand_week_numbers(&parsed.week);
                let stable = [
                    parsed.name.as_str(),
                    parsed.teacher.as_str(),
                    parsed.room.as_str(),
                    parsed.week.as_str(),
                    &weekday.to_string(),
                    &start_slot.to_string(),
                    &end_slot.to_string(),
                ]
                .join("|");
                let mut hasher = Sha1::new();
                hasher.update(stable.as_bytes());
                let course_id = format!("{:x}", hasher.finalize())[..12].to_string();
                if !seen_ids.insert(course_id.clone()) {
                    continue;
                }
                courses.push(Course {
                    id: course_id,
                    name: parsed.name,
                    teacher: parsed.teacher,
                    room: parsed.room,
                    week_text: parsed.week,
                    week_numbers,
                    exam_week_numbers: Vec::new(),
                    weekday,
                    start_slot,
                    end_slot,
                    section_text: parsed.section,
                    time_range: slot_time_range(start_slot, end_slot),
                });
            }
        }
    }

    annotate_exam_weeks(&mut courses);
    courses.sort_by(|left, right| {
        (left.weekday, left.start_slot, &left.name).cmp(&(
            right.weekday,
            right.start_slot,
            &right.name,
        ))
    });
    Ok(ScheduleResponse {
        term_id,
        term_start_date: term_start_date.to_string(),
        fetched_at: now_in_app_tz(),
        courses,
    })
}

async fn fetch_sjd_schedule(
    account: &Option<String>,
    password: &Option<String>,
    term_id: String,
    fallback_term_start_date: NaiveDate,
) -> ServiceResult<ScheduleResponse> {
    let (user, secret) = resolve_credentials(account, password)?;
    let token = login_empty_classroom(&user, &secret).await?;

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .redirect(reqwest::redirect::Policy::limited(10))
        .build()
        .map_err(|error| ServiceError::new(format!("无法初始化网络客户端：{error}")))?;

    let current_response = client
        .post(SJD_STUDENT_CURRICULUM_URL)
        .query(&[("week", "")])
        .headers(sjd_headers(Some(&token), SJD_REST_CLASSROOM_PAGE_URL))
        .send()
        .await
        .map_err(|_| ServiceError::new("无法连接移动教务课表服务，请稍后重试。"))?;
    let all_response = client
        .post(SJD_STUDENT_CURRICULUM_URL)
        .query(&[("week", "all")])
        .headers(sjd_headers(Some(&token), SJD_REST_CLASSROOM_PAGE_URL))
        .send()
        .await
        .map_err(|_| ServiceError::new("无法连接移动教务课表服务，请稍后重试。"))?;

    for response in [&current_response, &all_response] {
        if response.status().as_u16() >= 400 {
            return Err(ServiceError::new(format!(
                "移动教务课表获取失败，HTTP {}。",
                response.status().as_u16()
            )));
        }
    }

    let current_payload: Value = current_response
        .json()
        .await
        .map_err(|_| ServiceError::new("移动教务课表返回了无法识别的数据。"))?;
    let all_payload: Value = all_response
        .json()
        .await
        .map_err(|_| ServiceError::new("移动教务课表返回了无法识别的数据。"))?;

    for payload in [&current_payload, &all_payload] {
        let success = payload
            .get("code")
            .and_then(Value::as_i64)
            .map(|code| code == 1)
            .unwrap_or(false)
            || payload.get("code").and_then(Value::as_str) == Some("1");
        if !success {
            let message = payload
                .get("Msg")
                .or_else(|| payload.get("msg"))
                .and_then(Value::as_str)
                .unwrap_or("移动教务课表获取失败。");
            return Err(ServiceError::new(message));
        }
    }

    let inferred_start =
        infer_term_start_date(&current_payload).unwrap_or(fallback_term_start_date);
    let inferred_term_id = json_string(
        current_payload
            .get("data")
            .and_then(Value::as_array)
            .and_then(|items| items.first())
            .and_then(|item| item.get("semesterId").or_else(|| item.get("xnxq01id"))),
    );
    parse_sjd_courses(
        &all_payload,
        if inferred_term_id.is_empty() {
            term_id
        } else {
            inferred_term_id
        },
        inferred_start,
    )
}

async fn fetch_schedule_legacy(
    payload: &ScheduleRequest,
    term_id: String,
    term_start_date: NaiveDate,
) -> ServiceResult<ScheduleResponse> {
    let (user, secret) = resolve_credentials(&payload.account, &payload.password)?;
    let encoded = encode_login(&user, &secret);

    let client = reqwest::Client::builder()
        .timeout(Duration::from_secs(30))
        .cookie_store(true)
        .redirect(reqwest::redirect::Policy::limited(10))
        .build()
        .map_err(|error| ServiceError::new(format!("无法初始化网络客户端：{error}")))?;

    client.get(JWGL_HOME_URL).send().await.map_err(|_| {
        ServiceError::new("无法连接新版教务系统，请确认网络能访问 jwgl.bupt.edu.cn。")
    })?;

    let login_response = client
        .post(JWGL_LOGIN_URL)
        .header(
            REFERER,
            "https://jwgl.bupt.edu.cn/jsxsd/xk/LoginToXk?method=exit",
        )
        .header(USER_AGENT, DEFAULT_USER_AGENT)
        .form(&[
            ("userAccount", user.as_str()),
            ("userPassWord", ""),
            ("encoded", encoded.as_str()),
        ])
        .send()
        .await
        .map_err(|_| {
            ServiceError::new("无法连接新版教务系统，请确认网络能访问 jwgl.bupt.edu.cn。")
        })?;

    if login_response.status().as_u16() >= 400 {
        return Err(ServiceError::new(format!(
            "新版教务登录失败，HTTP {}。",
            login_response.status().as_u16()
        )));
    }

    let params = [
        ("xnxq01id", term_id.as_str()),
        ("zc", ""),
        ("kbjcmsid", "9475847A3F3033D1E05377B5030AA94D"),
    ];
    let response = client
        .post(JWGL_TIMETABLE_URL)
        .query(&params)
        .form(&params)
        .send()
        .await
        .map_err(|_| ServiceError::new("无法获取课表打印文件，请稍后重试。"))?;

    let status = response.status();
    let content = response
        .bytes()
        .await
        .map_err(|_| ServiceError::new("课表下载失败，请稍后重试。"))?;
    let head_len = content.len().min(500);
    let text_head = String::from_utf8_lossy(&content[..head_len]).to_lowercase();
    if status.as_u16() >= 400 || text_head.contains("<html") || text_head.contains("login") {
        return Err(ServiceError::with_status(
            "课表获取失败，请检查账号、密码、学期编号或校园网访问状态。",
            401,
        ));
    }
    if content.len() < 200 {
        return Err(ServiceError::new("教务返回的课表内容为空。"));
    }

    parse_timetable_xls(&content, term_id, term_start_date)
}

pub async fn fetch_schedule(payload: &ScheduleRequest) -> ServiceResult<ScheduleResponse> {
    let user_term_id = payload.term_id.as_deref().unwrap_or_default().trim();
    let term_id = if user_term_id.is_empty() {
        default_term_id()
    } else {
        user_term_id.to_string()
    };
    let term_start_source = payload
        .term_start_date
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .map(str::trim)
        .map(ToOwned::to_owned)
        .unwrap_or_else(default_term_start_date);
    let term_start_date = NaiveDate::parse_from_str(&term_start_source, "%Y-%m-%d")
        .map_err(|_| ServiceError::with_status("第一周周一日期格式不正确。", 400))?;

    match fetch_sjd_schedule(
        &payload.account,
        &payload.password,
        term_id.clone(),
        term_start_date,
    )
    .await
    {
        Ok(schedule) => Ok(schedule),
        Err(_) => fetch_schedule_legacy(payload, term_id, term_start_date).await,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_login_matches_reference_shape() {
        assert_eq!(encode_login("2023000000", "abc"), "MjAyMzAwMDAwMA==%%%YWJj");
    }

    #[test]
    fn expand_week_numbers_with_odd_even() {
        assert_eq!(expand_week_numbers("1-5[周]"), vec![1, 2, 3, 4, 5]);
        assert_eq!(expand_week_numbers("1-5[周](单)"), vec![1, 3, 5]);
        assert_eq!(expand_week_numbers("2,4,6[周]"), vec![2, 4, 6]);
    }

    #[test]
    fn parse_cell_courses_from_bupt_cell_text() {
        let parsed = parse_cell_courses("高等数学\n张三\n1-16[周]\n教一楼-101\n1-2节");
        assert_eq!(
            parsed,
            vec![ParsedCourse {
                name: "高等数学".to_string(),
                teacher: "张三".to_string(),
                week: "1-16[周]".to_string(),
                room: "教一楼-101".to_string(),
                section: "1-2节".to_string(),
            }]
        );
    }

    #[test]
    fn annotate_exam_weeks_counts_existing_weeks_in_order() {
        let mut courses = vec![
            Course {
                id: "weekly".to_string(),
                name: "周课".to_string(),
                teacher: String::new(),
                room: String::new(),
                week_text: "2-19".to_string(),
                week_numbers: (2..=19).collect(),
                exam_week_numbers: Vec::new(),
                weekday: 1,
                start_slot: 0,
                end_slot: 1,
                section_text: String::new(),
                time_range: String::new(),
            },
            Course {
                id: "literal-17".to_string(),
                name: "原始第十七周".to_string(),
                teacher: String::new(),
                room: String::new(),
                week_text: "17".to_string(),
                week_numbers: vec![17],
                exam_week_numbers: Vec::new(),
                weekday: 2,
                start_slot: 0,
                end_slot: 1,
                section_text: String::new(),
                time_range: String::new(),
            },
        ];

        annotate_exam_weeks(&mut courses);

        assert_eq!(courses[0].exam_week_numbers, vec![18, 19]);
        assert!(courses[1].exam_week_numbers.is_empty());
    }

    #[test]
    fn parse_sjd_courses_from_curriculum_payload() {
        let payload = serde_json::json!({
            "data": [
                {
                    "item": [
                        [
                            [
                                {
                                    "classWeek": "1-16",
                                    "classWeekDetails": ",1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,",
                                    "classTime": "1030405",
                                    "weekDay": "1",
                                    "courseName": "数据挖掘",
                                    "teacherName": "测试教师",
                                    "buildingName": "教三楼",
                                    "classroomName": "3-335",
                                    "startTime": "09:50",
                                    "endTIme": "12:15",
                                    "jx0408id": "course-1"
                                }
                            ]
                        ]
                    ]
                }
            ]
        });
        let term_start = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        let result = parse_sjd_courses(&payload, "2025-2026-2".to_string(), term_start).unwrap();
        let course = &result.courses[0];

        assert_eq!(course.name, "数据挖掘");
        assert_eq!(course.room, "教三楼-3-335");
        assert_eq!(course.weekday, 1);
        assert_eq!(course.start_slot, 2);
        assert_eq!(course.end_slot, 4);
        assert_eq!(course.week_numbers, (1..=16).collect::<Vec<_>>());
    }

    #[test]
    fn infer_term_start_date_from_sjd_current_week() {
        let payload = serde_json::json!({
            "data": [
                {
                    "week": "14",
                    "date": [
                        { "mxrq": "2026-06-01", "xqid": "1", "zc": "14" },
                        { "mxrq": "2026-06-02", "xqid": "2", "zc": "14" }
                    ]
                }
            ]
        });
        assert_eq!(
            infer_term_start_date(&payload),
            NaiveDate::from_ymd_opt(2026, 3, 2)
        );
    }
}
