use std::collections::HashSet;
use std::io::Cursor;
use std::time::Duration;

use calamine::{Data, Reader, Xls};
use chrono::NaiveDate;
use regex::Regex;
use reqwest::header::{REFERER, USER_AGENT};
use sha1::{Digest, Sha1};

use crate::auth::resolve_credentials;
use crate::config::{
    default_term_id, default_term_start_date, now_in_app_tz, JWGL_HOME_URL, JWGL_LOGIN_URL,
    JWGL_TIMETABLE_URL, SLOT_TIMES,
};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{Course, ScheduleRequest, ScheduleResponse};

const KEY_STR: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
const DEFAULT_USER_AGENT: &str =
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126 Safari/537.36";

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
        if name_index >= 0
            && Regex::new(r"^\(\d+\)$")
                .expect("valid regex")
                .is_match(&lines[name_index as usize])
        {
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
                    weekday,
                    start_slot,
                    end_slot,
                    section_text: parsed.section,
                    time_range: slot_time_range(start_slot, end_slot),
                });
            }
        }
    }

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
}
