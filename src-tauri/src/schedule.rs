use std::collections::HashSet;

use chrono::{Datelike, Duration as ChronoDuration, NaiveDate};
use regex::Regex;
use serde_json::Value;
use sha1::{Digest, Sha1};

use crate::auth::resolve_credentials;
use crate::classrooms::{
    login_empty_classroom, read_sjd_json_response, sjd_headers, sjd_http_client,
    MAX_SJD_DATA_RESPONSE_BYTES,
};
use crate::config::{
    is_valid_term_id, now_in_app_tz, suggested_term_for_date, today_in_app_tz,
    SJD_REST_CLASSROOM_PAGE_URL, SJD_STUDENT_CURRICULUM_URL, SLOT_TIMES,
};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{Course, ScheduleRequest, ScheduleResponse};

pub fn expand_week_numbers(week_text: &str) -> Vec<i64> {
    let mut raw = week_text.replace('，', ",").replace(' ', "");
    // Global odd/even markers ("1-5(单)") apply to items without their own
    // suffix; when both markers appear ("1-17单,2-18双") each item keeps
    // its own parity instead of dropping one side.
    let global_odd = raw.contains('单');
    let global_even = raw.contains('双');
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
        let item_odd = item.contains('单');
        let item_even = item.contains('双');
        let clean = item.replace(['单', '双'], "");
        let mut expanded = Vec::new();
        if let Some((left, right)) = clean.split_once('-') {
            if let (Ok(start), Ok(end)) = (left.parse::<i64>(), right.parse::<i64>()) {
                expanded.extend(start..=end);
            }
        } else if let Ok(week) = clean.parse::<i64>() {
            expanded.push(week);
        }
        if item_odd || (!item_even && global_odd) {
            expanded.retain(|week| week % 2 == 1);
        } else if item_even || (!item_odd && global_even) {
            expanded.retain(|week| week % 2 == 0);
        }
        week_numbers.extend(expanded);
    }

    week_numbers.sort_unstable();
    week_numbers.dedup();
    week_numbers
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

fn normalize_course_room(value: &str) -> String {
    let normalized = value.trim().replace(['－', '—', '–'], "-");
    let Some((prefix, room)) = normalized.split_once('-') else {
        return normalized;
    };
    let building_prefix = prefix.strip_prefix('教').unwrap_or(prefix);
    if building_prefix.len() == 1
        && building_prefix.bytes().all(|byte| byte.is_ascii_digit())
        && room.len() == 3
        && room.bytes().all(|byte| byte.is_ascii_digit())
    {
        room.to_string()
    } else {
        normalized
    }
}

pub fn parse_sjd_week_numbers(course: &Value) -> Vec<i64> {
    let mut weeks = expand_week_numbers(&json_string(course.get("classWeek")));
    if weeks.is_empty() {
        weeks = expand_week_numbers(&json_string(course.get("classWeekDetails")));
    }
    if weeks.is_empty() {
        weeks = Regex::new(r"\d+")
            .expect("valid regex")
            .find_iter(&json_string(course.get("classWeekDetails")))
            .filter_map(|item| item.as_str().parse::<i64>().ok())
            .collect();
    }
    weeks.sort_unstable();
    weeks.dedup();
    weeks
}

pub fn parse_sjd_slots(course: &Value) -> Option<(usize, usize)> {
    let class_time = json_string(course.get("classTime"));
    // SJD encodes classTime as "<course-count><node><node>...", e.g. "1030405"
    // means one course using nodes 03, 04, 05. Skip the leading count digit.
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

const MAX_SJD_COURSE_NESTING_DEPTH: usize = 64;

fn collect_sjd_course_items<'a>(value: &'a Value, output: &mut Vec<&'a Value>) {
    collect_sjd_course_items_with_depth(value, output, 0)
}

fn collect_sjd_course_items_with_depth<'a>(
    value: &'a Value,
    output: &mut Vec<&'a Value>,
    depth: usize,
) {
    if depth > MAX_SJD_COURSE_NESTING_DEPTH {
        return;
    }
    match value {
        Value::Object(map) => {
            if map.contains_key("courseName") || map.contains_key("jx0408id") {
                output.push(value);
                return;
            }
            for child in map.values() {
                collect_sjd_course_items_with_depth(child, output, depth + 1);
            }
        }
        Value::Array(items) => {
            for child in items {
                collect_sjd_course_items_with_depth(child, output, depth + 1);
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
        let room = normalize_course_room(&json_string(
            raw_course
                .get("classroomName")
                .or_else(|| raw_course.get("location")),
        ));
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
            section_text: if start_slot == end_slot {
                format!("{}节", start_slot + 1)
            } else {
                format!("{}-{}节", start_slot + 1, end_slot + 1)
            },
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
    let dated = root
        .get("date")
        .and_then(Value::as_array)?
        .iter()
        .find(|item| item.get("mxrq").is_some() && json_string(item.get("zc")) != "all")?;
    let top_info_week = root
        .get("topInfo")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .and_then(|item| item.get("week"));
    let week = [dated.get("zc"), root.get("week"), top_info_week]
        .into_iter()
        .flatten()
        .find_map(|value| json_string(Some(value)).parse::<i64>().ok())?;
    if week < 0 {
        return None;
    }
    let day = NaiveDate::parse_from_str(&json_string(dated.get("mxrq")), "%Y-%m-%d").ok()?;
    let weekday = match json_string(dated.get("xqid")).parse::<i64>() {
        Ok(0) => 7,
        Ok(value @ 1..=7) => value,
        _ => i64::from(day.weekday().number_from_monday()),
    };
    let monday = day - ChronoDuration::days(weekday - 1);
    Some(monday - ChronoDuration::weeks(week - 1))
}

pub fn infer_term_id(payload: &Value) -> Option<String> {
    let root = payload.get("data").and_then(Value::as_array)?.first()?;
    let top_info = root
        .get("topInfo")
        .and_then(Value::as_array)
        .and_then(|items| items.first());
    [
        root.get("semesterId"),
        root.get("xnxq01id"),
        top_info.and_then(|item| item.get("semesterId")),
        top_info.and_then(|item| item.get("xnxq01id")),
    ]
    .into_iter()
    .flatten()
    .map(|value| json_string(Some(value)))
    .find(|value| !value.trim().is_empty())
    .map(|value| value.trim().to_string())
}

async fn fetch_sjd_schedule(
    account: &Option<String>,
    password: &Option<String>,
    term_id: String,
    fallback_term_start_date: NaiveDate,
) -> ServiceResult<ScheduleResponse> {
    let (user, secret) = resolve_credentials(account, password)?;
    let token = login_empty_classroom(&user, &secret).await?;

    let client = sjd_http_client(30)?;

    let current_response = client
        .post(SJD_STUDENT_CURRICULUM_URL)
        .query(&[("week", "")])
        .headers(sjd_headers(Some(&token), SJD_REST_CLASSROOM_PAGE_URL))
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法连接移动教务课表服务：{error}")))?;
    let all_response = client
        .post(SJD_STUDENT_CURRICULUM_URL)
        .query(&[("week", "all")])
        .headers(sjd_headers(Some(&token), SJD_REST_CLASSROOM_PAGE_URL))
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法连接移动教务课表服务：{error}")))?;

    for response in [&current_response, &all_response] {
        if response.status().as_u16() >= 400 {
            return Err(ServiceError::new(format!(
                "移动教务课表获取失败，HTTP {}。",
                response.status().as_u16()
            )));
        }
    }

    let current_payload = read_sjd_json_response(
        current_response,
        MAX_SJD_DATA_RESPONSE_BYTES,
        "移动教务课表",
    )
    .await?;
    let all_payload =
        read_sjd_json_response(all_response, MAX_SJD_DATA_RESPONSE_BYTES, "移动教务课表").await?;

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
    let inferred_term_id = infer_term_id(&current_payload).unwrap_or_default();
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

fn resolve_schedule_term(
    payload: &ScheduleRequest,
    current_term: (String, String),
) -> ServiceResult<(String, NaiveDate)> {
    let automatic = payload.automatic_term_detection_enabled.unwrap_or(true);
    let user_term_id = payload.term_id.as_deref().unwrap_or_default().trim();
    let (current_term_id, current_term_start) = current_term;
    let term_id = if automatic {
        current_term_id
    } else if user_term_id.is_empty() {
        return Err(ServiceError::with_status("请填写学期编号。", 400));
    } else if !is_valid_term_id(user_term_id) {
        return Err(ServiceError::with_status(
            "学期编号格式不正确，请使用 YYYY-YYYY-1 或 YYYY-YYYY-2。",
            400,
        ));
    } else {
        user_term_id.to_string()
    };
    let user_term_start = payload
        .term_start_date
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .map(str::trim);
    let term_start_source = if automatic {
        user_term_start
            .filter(|_| user_term_id == term_id)
            .filter(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d").is_ok())
            .unwrap_or(&current_term_start)
            .to_string()
    } else {
        user_term_start
            .ok_or_else(|| ServiceError::with_status("请填写第一周周一日期。", 400))?
            .to_string()
    };
    let term_start_date = NaiveDate::parse_from_str(&term_start_source, "%Y-%m-%d")
        .map_err(|_| ServiceError::with_status("第一周周一日期格式不正确。", 400))?;

    Ok((term_id, term_start_date))
}

pub async fn fetch_schedule(payload: &ScheduleRequest) -> ServiceResult<ScheduleResponse> {
    let current_term = suggested_term_for_date(today_in_app_tz());
    let (term_id, term_start_date) = resolve_schedule_term(payload, current_term)?;

    fetch_sjd_schedule(
        &payload.account,
        &payload.password,
        term_id,
        term_start_date,
    )
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expand_week_numbers_with_odd_even() {
        assert_eq!(expand_week_numbers("1-5[周]"), vec![1, 2, 3, 4, 5]);
        assert_eq!(expand_week_numbers("1-5[周](单)"), vec![1, 3, 5]);
        assert_eq!(expand_week_numbers("2,4,6[周]"), vec![2, 4, 6]);
    }

    #[test]
    fn automatic_schedule_fallback_uses_the_current_term_not_stale_request_values() {
        let payload = ScheduleRequest {
            account: None,
            password: None,
            term_id: Some("2025-2026-2".to_string()),
            term_start_date: Some("2026-03-02".to_string()),
            automatic_term_detection_enabled: None,
        };

        let resolved = resolve_schedule_term(
            &payload,
            ("2026-2027-1".to_string(), "2026-08-31".to_string()),
        )
        .unwrap();
        assert_eq!(resolved.0, "2026-2027-1");
        assert_eq!(resolved.1, NaiveDate::from_ymd_opt(2026, 8, 31).unwrap());
    }

    #[test]
    fn automatic_schedule_fallback_keeps_a_valid_same_term_start_date() {
        let payload = ScheduleRequest {
            account: None,
            password: None,
            term_id: Some("2026-2027-1".to_string()),
            term_start_date: Some("2026-09-07".to_string()),
            automatic_term_detection_enabled: Some(true),
        };

        let resolved = resolve_schedule_term(
            &payload,
            ("2026-2027-1".to_string(), "2026-08-31".to_string()),
        )
        .unwrap();
        assert_eq!(resolved.0, "2026-2027-1");
        assert_eq!(resolved.1, NaiveDate::from_ymd_opt(2026, 9, 7).unwrap());
    }

    #[test]
    fn manual_schedule_fallback_keeps_user_term_values() {
        let payload = ScheduleRequest {
            account: None,
            password: None,
            term_id: Some("2025-2026-2".to_string()),
            term_start_date: Some("2026-03-02".to_string()),
            automatic_term_detection_enabled: Some(false),
        };

        let resolved = resolve_schedule_term(
            &payload,
            ("2026-2027-1".to_string(), "2026-08-31".to_string()),
        )
        .unwrap();
        assert_eq!(resolved.0, "2025-2026-2");
        assert_eq!(resolved.1, NaiveDate::from_ymd_opt(2026, 3, 2).unwrap());
    }

    #[test]
    fn manual_schedule_requests_reject_empty_term_fields_without_fallback() {
        for payload in [
            ScheduleRequest {
                account: None,
                password: None,
                term_id: None,
                term_start_date: Some("2026-03-02".to_string()),
                automatic_term_detection_enabled: Some(false),
            },
            ScheduleRequest {
                account: None,
                password: None,
                term_id: Some("2025-2026-2".to_string()),
                term_start_date: None,
                automatic_term_detection_enabled: Some(false),
            },
        ] {
            assert!(resolve_schedule_term(
                &payload,
                ("2026-2027-1".to_string(), "2026-08-31".to_string()),
            )
            .is_err());
        }
    }

    #[test]
    fn manual_schedule_requests_reject_malformed_term_ids() {
        for invalid in ["garbage", "2025-2026-3", "2025-26-1"] {
            let payload = ScheduleRequest {
                account: None,
                password: None,
                term_id: Some(invalid.to_string()),
                term_start_date: Some("2026-03-02".to_string()),
                automatic_term_detection_enabled: Some(false),
            };
            let error = resolve_schedule_term(
                &payload,
                ("2026-2027-1".to_string(), "2026-08-31".to_string()),
            )
            .expect_err("malformed manual term id must fail");
            assert_eq!(
                error.message,
                "学期编号格式不正确，请使用 YYYY-YYYY-1 或 YYYY-YYYY-2。"
            );
        }
    }

    #[test]
    fn expand_week_numbers_keeps_both_parities_when_items_carry_own_markers() {
        assert_eq!(
            expand_week_numbers("1-17单,2-18双"),
            (1..=18)
                .filter(|week| week % 2 != 0 || (2..=18).contains(week))
                .collect::<Vec<_>>()
        );
        // Equivalent explicit assertion:
        assert_eq!(
            expand_week_numbers("1-17单,2-18双"),
            [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]
        );
    }

    #[test]
    fn parse_sjd_week_numbers_falls_back_to_bare_odd_even_suffixes() {
        let odd_course = serde_json::json!({ "classWeek": "1-17单" });
        let even_course = serde_json::json!({ "classWeek": "2-18双" });

        assert_eq!(
            parse_sjd_week_numbers(&odd_course),
            (1..=17).step_by(2).collect::<Vec<_>>()
        );
        assert_eq!(
            parse_sjd_week_numbers(&even_course),
            (2..=18).step_by(2).collect::<Vec<_>>()
        );
    }

    #[test]
    fn parse_sjd_week_numbers_prefers_class_week_over_details() {
        let course = serde_json::json!({ "classWeek": "2-18双", "classWeekDetails": "1,3,5" });
        assert_eq!(
            parse_sjd_week_numbers(&course),
            (2..=18).step_by(2).collect::<Vec<_>>()
        );
    }

    #[test]
    fn parse_sjd_week_numbers_expands_details_ranges_and_suffixes() {
        let ranged = serde_json::json!({ "classWeekDetails": "1-16" });
        assert_eq!(
            parse_sjd_week_numbers(&ranged),
            (1..=16).collect::<Vec<_>>()
        );

        let odd = serde_json::json!({ "classWeekDetails": "1-17单" });
        assert_eq!(
            parse_sjd_week_numbers(&odd),
            (1..=17).step_by(2).collect::<Vec<_>>()
        );

        let prefixed = serde_json::json!({ "classWeekDetails": "第1周,第3周" });
        assert_eq!(parse_sjd_week_numbers(&prefixed), vec![1, 3]);
    }

    #[test]
    fn course_collector_stops_at_the_nesting_depth_limit() {
        let mut nested = serde_json::json!({ "courseName": "深层课程", "jx0408id": "deep" });
        for _ in 0..100 {
            nested = serde_json::json!([nested]);
        }
        let mut found = Vec::new();
        collect_sjd_course_items(&nested, &mut found);
        assert!(
            found.is_empty(),
            "courses beyond the depth limit must be ignored"
        );

        let mut shallow = serde_json::json!({ "courseName": "浅层课程" });
        for _ in 0..8 {
            shallow = serde_json::json!({ "wrapper": shallow });
        }
        let mut found = Vec::new();
        collect_sjd_course_items(&shallow, &mut found);
        assert_eq!(
            found.len(),
            1,
            "courses within the depth limit must be collected"
        );
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
        assert_eq!(course.room, "教三楼-335");
        assert_eq!(course.weekday, 1);
        assert_eq!(course.start_slot, 2);
        assert_eq!(course.end_slot, 4);
        assert_eq!(course.week_numbers, (1..=16).collect::<Vec<_>>());
    }

    #[test]
    fn normalize_course_room_keeps_dual_door_rooms() {
        assert_eq!(normalize_course_room("3-335"), "335");
        assert_eq!(normalize_course_room("教1-101"), "101");
        assert_eq!(normalize_course_room("202-203"), "202-203");
        assert_eq!(normalize_course_room("217-218"), "217-218");
    }

    #[test]
    fn shared_sjd_fixtures_match_schedule_contract() {
        let expected: ScheduleResponse =
            serde_json::from_str(include_str!("../../contracts/v1/fixtures/schedule.json"))
                .expect("valid schedule fixture");
        let current: Value = serde_json::from_str(include_str!(
            "../../contracts/v1/fixtures/sjd-current-week.json"
        ))
        .expect("valid current-week fixture");
        let curriculum: Value = serde_json::from_str(include_str!(
            "../../contracts/v1/fixtures/sjd-curriculum.json"
        ))
        .expect("valid curriculum fixture");
        let term_start = infer_term_start_date(&current).expect("fixture term start");
        let mut actual = parse_sjd_courses(&curriculum, expected.term_id.clone(), term_start)
            .expect("parse shared schedule fixture");
        actual.fetched_at.clone_from(&expected.fetched_at);

        assert_eq!(
            serde_json::to_value(actual).expect("serialize parsed fixture"),
            serde_json::to_value(expected).expect("serialize expected fixture")
        );
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

    #[test]
    fn before_first_week_payload_infers_next_monday_and_nested_term_id() {
        let payload: Value = serde_json::from_str(include_str!(
            "../../contracts/v1/fixtures/sjd-before-first-week.json"
        ))
        .expect("valid before-first-week fixture");

        assert_eq!(infer_term_id(&payload).as_deref(), Some("2026-2027-1"));
        assert_eq!(
            infer_term_start_date(&payload),
            NaiveDate::from_ymd_opt(2026, 8, 31)
        );
    }

    #[test]
    fn term_id_falls_through_empty_semester_fields_to_xnxq_candidates() {
        let direct = serde_json::json!({
            "data": [{ "semesterId": "", "xnxq01id": "2026-2027-1" }]
        });
        assert_eq!(infer_term_id(&direct).as_deref(), Some("2026-2027-1"));

        let nested = serde_json::json!({
            "data": [{
                "semesterId": "",
                "xnxq01id": "",
                "topInfo": [{ "semesterId": "", "xnxq01id": "2026-2027-1" }]
            }]
        });
        assert_eq!(infer_term_id(&nested).as_deref(), Some("2026-2027-1"));
    }

    #[test]
    fn negative_teaching_weeks_are_not_used_as_term_dates() {
        let payload = serde_json::json!({
            "data": [{
                "week": "-1",
                "date": [{ "mxrq": "2026-08-24", "xqid": "1", "zc": "-1" }]
            }]
        });
        assert_eq!(infer_term_start_date(&payload), None);
    }

    #[test]
    fn date_week_number_wins_and_zero_weekday_means_sunday() {
        let payload = serde_json::json!({
            "data": [{
                "week": "1",
                "topInfo": [{ "week": "1" }],
                "date": [{ "mxrq": "2026-08-30", "xqid": "0", "zc": "0" }]
            }]
        });
        assert_eq!(
            infer_term_start_date(&payload),
            NaiveDate::from_ymd_opt(2026, 8, 31)
        );
    }
}
