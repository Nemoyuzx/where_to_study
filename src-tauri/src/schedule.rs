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
    default_term_id, default_term_start_date, now_in_app_tz, SJD_REST_CLASSROOM_PAGE_URL,
    SJD_STUDENT_CURRICULUM_URL, SLOT_TIMES,
};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{Course, ScheduleRequest, ScheduleResponse};

const EXAM_WEEK_ORDINALS: [usize; 2] = [17, 18];

pub fn expand_week_numbers(week_text: &str) -> Vec<i64> {
    let mut raw = week_text.replace('，', ",").replace(' ', "");
    let odd_only = raw.contains('单');
    let even_only = raw.contains('双');
    raw = raw.replace(['周', '单', '双'], "");
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
}
