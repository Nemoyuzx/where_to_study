use chrono::{Datelike, Duration as ChronoDuration, NaiveDate, SecondsFormat, Utc};
use chrono_tz::Asia::Shanghai;

use crate::models::{CampusMetadata, SlotMetadata};

pub const SJD_ORIGIN: &str = "https://jwglweixin.bupt.edu.cn";
pub const SJD_LOGIN_PAGE_URL: &str = "https://jwglweixin.bupt.edu.cn/sjd/#/login";
pub const SJD_REST_CLASSROOM_PAGE_URL: &str = "https://jwglweixin.bupt.edu.cn/sjd/#/restClassroom";
pub const SJD_STUDENT_CURRICULUM_URL: &str =
    "https://jwglweixin.bupt.edu.cn/bjyddx/student/curriculum";
pub const EMPTY_CLASSROOM_LOGIN_URL: &str = "https://jwglweixin.bupt.edu.cn/bjyddx/login";
pub const EMPTY_CLASSROOM_TODAY_URL: &str = "https://jwglweixin.bupt.edu.cn/bjyddx/todayClassrooms";

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

pub fn suggested_term_for_date(date: NaiveDate) -> (String, String) {
    let (term_id, anchor) = if (2..=7).contains(&date.month()) {
        (
            format!("{}-{}-2", date.year() - 1, date.year()),
            NaiveDate::from_ymd_opt(date.year(), 3, 2).expect("valid spring term anchor"),
        )
    } else {
        let fall_start_year = if date.month() == 1 {
            date.year() - 1
        } else {
            date.year()
        };
        (
            format!("{}-{}-1", fall_start_year, fall_start_year + 1),
            NaiveDate::from_ymd_opt(fall_start_year, 9, 1).expect("valid fall term anchor"),
        )
    };
    let monday = anchor - ChronoDuration::days(i64::from(anchor.weekday().num_days_from_monday()));
    (term_id, monday.to_string())
}

pub fn is_valid_term_id(value: &str) -> bool {
    let bytes = value.trim().as_bytes();
    bytes.len() == 11
        && bytes[0..4].iter().all(u8::is_ascii_digit)
        && bytes[4] == b'-'
        && bytes[5..9].iter().all(u8::is_ascii_digit)
        && bytes[9] == b'-'
        && matches!(bytes[10], b'1' | b'2')
}

pub fn default_term() -> (String, String) {
    (String::new(), String::new())
}

pub fn default_term_id() -> String {
    default_term().0
}

pub fn default_term_start_date() -> String {
    default_term().1
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
    Utc::now()
        .with_timezone(&Shanghai)
        .to_rfc3339_opts(SecondsFormat::Secs, false)
}

pub fn today_in_app_tz() -> NaiveDate {
    Utc::now().with_timezone(&Shanghai).date_naive()
}

#[cfg(test)]
mod term_tests {
    use super::*;

    #[test]
    fn term_suggestion_tracks_the_shanghai_calendar_period() {
        assert_eq!(
            suggested_term_for_date(NaiveDate::from_ymd_opt(2026, 3, 15).unwrap()),
            ("2025-2026-2".to_string(), "2026-03-02".to_string())
        );
        assert_eq!(
            suggested_term_for_date(NaiveDate::from_ymd_opt(2026, 8, 24).unwrap()),
            ("2026-2027-1".to_string(), "2026-08-31".to_string())
        );
        assert_eq!(
            suggested_term_for_date(NaiveDate::from_ymd_opt(2026, 1, 15).unwrap()),
            ("2025-2026-1".to_string(), "2025-09-01".to_string())
        );
    }

    #[test]
    fn persisted_and_metadata_term_defaults_stay_empty() {
        assert_eq!(default_term(), (String::new(), String::new()));
        assert!(default_term_id().is_empty());
        assert!(default_term_start_date().is_empty());
    }

    #[test]
    fn term_ids_follow_the_shared_four_digit_contract() {
        for valid in ["2025-2026-1", "2025-2026-2", " 2025-2026-2 "] {
            assert!(is_valid_term_id(valid), "valid term id rejected: {valid}");
        }
        for invalid in [
            "",
            "garbage",
            "2025-2026",
            "25-2026-1",
            "2025-26-1",
            "2025-2026-0",
            "2025-2026-3",
        ] {
            assert!(
                !is_valid_term_id(invalid),
                "invalid term id accepted: {invalid}"
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn app_timestamp_uses_second_precision_rfc3339() {
        let timestamp = now_in_app_tz();

        assert!(!timestamp.contains('.'));
        assert!(chrono::DateTime::parse_from_rfc3339(&timestamp).is_ok());
    }

    #[test]
    fn sjd_transport_uses_https_for_all_endpoints() {
        for endpoint in [
            SJD_ORIGIN,
            SJD_LOGIN_PAGE_URL,
            SJD_REST_CLASSROOM_PAGE_URL,
            SJD_STUDENT_CURRICULUM_URL,
            EMPTY_CLASSROOM_LOGIN_URL,
            EMPTY_CLASSROOM_TODAY_URL,
        ] {
            assert!(
                endpoint.starts_with("https://"),
                "insecure endpoint: {endpoint}"
            );
        }
    }
}
