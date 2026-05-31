use chrono::{NaiveDate, Utc};
use chrono_tz::Asia::Shanghai;

use crate::models::{CampusMetadata, SlotMetadata};

pub const JWGL_HOME_URL: &str = "https://jwgl.bupt.edu.cn/jsxsd/";
pub const JWGL_LOGIN_URL: &str = "https://jwgl.bupt.edu.cn/jsxsd/xk/LoginToXk";
pub const JWGL_TIMETABLE_URL: &str = "https://jwgl.bupt.edu.cn/jsxsd/xskb/xskb_print.do";

pub const SJD_ORIGIN: &str = "http://jwglweixin.bupt.edu.cn";
pub const SJD_LOGIN_PAGE_URL: &str = "http://jwglweixin.bupt.edu.cn/sjd/#/login";
pub const SJD_REST_CLASSROOM_PAGE_URL: &str = "http://jwglweixin.bupt.edu.cn/sjd/#/restClassroom";
pub const SJD_STUDENT_CURRICULUM_URL: &str =
    "http://jwglweixin.bupt.edu.cn/bjyddx/student/curriculum";
pub const EMPTY_CLASSROOM_LOGIN_URL: &str = "http://jwglweixin.bupt.edu.cn/bjyddx/login";
pub const EMPTY_CLASSROOM_IDLE_URL: &str =
    "http://jwglweixin.bupt.edu.cn/bjyddx/student/getIdleClassroom";

pub const DEFAULT_TERM_ID: &str = "2025-2026-2";
pub const DEFAULT_TERM_START_DATE: &str = "2026-03-02";

pub const SLOT_TIMES: [(&str, &str); 14] = [
    ("08:00", "08:45"),
    ("08:50", "09:35"),
    ("09:50", "10:35"),
    ("10:40", "11:25"),
    ("11:30", "12:15"),
    ("13:00", "13:45"),
    ("13:50", "14:35"),
    ("14:45", "15:30"),
    ("15:40", "16:25"),
    ("16:35", "17:20"),
    ("17:25", "18:10"),
    ("18:30", "19:15"),
    ("19:20", "20:05"),
    ("20:10", "20:55"),
];

#[derive(Debug, Clone, Copy)]
pub struct Campus {
    pub id: &'static str,
    pub name: &'static str,
}

pub const CAMPUSES: [Campus; 2] = [
    Campus {
        id: "01",
        name: "西土城",
    },
    Campus {
        id: "04",
        name: "沙河",
    },
];

pub fn default_term_id() -> String {
    std::env::var("DEFAULT_TERM_ID").unwrap_or_else(|_| DEFAULT_TERM_ID.to_string())
}

pub fn default_term_start_date() -> String {
    std::env::var("DEFAULT_TERM_START_DATE").unwrap_or_else(|_| DEFAULT_TERM_START_DATE.to_string())
}

pub fn campuses_payload() -> Vec<CampusMetadata> {
    CAMPUSES
        .iter()
        .map(|campus| CampusMetadata {
            id: campus.id.to_string(),
            name: campus.name.to_string(),
        })
        .collect()
}

pub fn slot_payload() -> Vec<SlotMetadata> {
    SLOT_TIMES
        .iter()
        .enumerate()
        .map(|(index, (start, end))| SlotMetadata {
            index,
            label: (index + 1).to_string(),
            start: (*start).to_string(),
            end: (*end).to_string(),
        })
        .collect()
}

pub fn normalize_campus_id(campus_id: Option<&str>) -> String {
    let value = campus_id.unwrap_or(CAMPUSES[0].id).trim();
    if value.is_empty() {
        return CAMPUSES[0].id.to_string();
    }
    if value.chars().all(|character| character.is_ascii_digit()) {
        return format!("{:0>2}", value);
    }
    value.to_string()
}

pub fn campus_name(campus_id: &str) -> String {
    let normalized = normalize_campus_id(Some(campus_id));
    CAMPUSES
        .iter()
        .find(|campus| campus.id == normalized)
        .map(|campus| campus.name.to_string())
        .unwrap_or_else(|| format!("校区 {normalized}"))
}

pub fn now_in_app_tz() -> String {
    Utc::now().with_timezone(&Shanghai).to_rfc3339()
}

pub fn today_in_app_tz() -> NaiveDate {
    Utc::now().with_timezone(&Shanghai).date_naive()
}
