use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

fn default_true() -> bool {
    true
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SlotMetadata {
    pub index: usize,
    pub label: String,
    pub start: String,
    pub end: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CampusMetadata {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MetadataResponse {
    pub campuses: Vec<CampusMetadata>,
    pub slots: Vec<SlotMetadata>,
    pub default_term_id: String,
    pub default_term_start_date: String,
    pub supports_calendar_import: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SavedSettings {
    #[serde(default)]
    pub account: String,
    #[serde(default)]
    pub has_saved_password: bool,
    #[serde(default)]
    pub term_id: String,
    #[serde(default)]
    pub term_start_date: String,
    #[serde(default)]
    pub campus_id: String,
    #[serde(default)]
    pub default_min_seats: usize,
    #[serde(default)]
    pub ui_language: String,
    #[serde(default)]
    pub daily_course_notifications_enabled: bool,
    #[serde(default = "default_true")]
    pub automatic_term_detection_enabled: bool,
    #[serde(default = "default_true")]
    pub weather_enabled: bool,
    #[serde(default = "default_true")]
    pub almanac_enabled: bool,
    #[serde(default = "default_true")]
    pub competition_deadlines_enabled: bool,
    #[serde(default = "default_true")]
    pub conference_deadlines_enabled: bool,
    #[serde(default = "default_true")]
    pub school_contest_notices_enabled: bool,
    #[serde(default = "default_true")]
    pub summer_camp_deadlines_enabled: bool,
    #[serde(default = "default_true")]
    pub hackathon_deadlines_enabled: bool,
    #[serde(default)]
    pub custom_deadlines_enabled: bool,
    #[serde(default)]
    pub custom_deadlines_url: String,
}

impl SavedSettings {
    pub fn with_defaults() -> Self {
        Self {
            account: String::new(),
            has_saved_password: false,
            term_id: String::new(),
            term_start_date: String::new(),
            campus_id: crate::config::CAMPUSES[0].id.to_string(),
            default_min_seats: 0,
            ui_language: "system".to_string(),
            daily_course_notifications_enabled: false,
            automatic_term_detection_enabled: true,
            weather_enabled: true,
            almanac_enabled: true,
            competition_deadlines_enabled: true,
            conference_deadlines_enabled: true,
            school_contest_notices_enabled: true,
            summer_camp_deadlines_enabled: true,
            hackathon_deadlines_enabled: true,
            custom_deadlines_enabled: false,
            custom_deadlines_url: String::new(),
        }
    }

    pub fn apply_defaults(&mut self) {
        if self.campus_id.trim().is_empty() {
            self.campus_id = crate::config::CAMPUSES[0].id.to_string();
        }
        if !matches!(self.ui_language.as_str(), "system" | "zh-Hans" | "en") {
            self.ui_language = "system".to_string();
        }
    }
}

#[derive(Clone, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct SaveSettingsRequest {
    #[serde(default)]
    pub account: String,
    #[serde(default)]
    pub password: Option<String>,
    #[serde(default)]
    pub term_id: String,
    #[serde(default)]
    pub term_start_date: String,
    #[serde(default)]
    pub campus_id: String,
    #[serde(default)]
    pub default_min_seats: usize,
    #[serde(default)]
    pub ui_language: String,
    #[serde(default)]
    pub daily_course_notifications_enabled: bool,
    #[serde(default = "default_true")]
    pub automatic_term_detection_enabled: bool,
    #[serde(default = "default_true")]
    pub weather_enabled: bool,
    #[serde(default = "default_true")]
    pub almanac_enabled: bool,
    #[serde(default = "default_true")]
    pub competition_deadlines_enabled: bool,
    #[serde(default = "default_true")]
    pub conference_deadlines_enabled: bool,
    #[serde(default = "default_true")]
    pub school_contest_notices_enabled: bool,
    #[serde(default = "default_true")]
    pub summer_camp_deadlines_enabled: bool,
    #[serde(default = "default_true")]
    pub hackathon_deadlines_enabled: bool,
    #[serde(default)]
    pub custom_deadlines_enabled: bool,
    #[serde(default)]
    pub custom_deadlines_url: String,
}

impl SaveSettingsRequest {
    pub fn apply_defaults(&mut self) {
        if self.campus_id.trim().is_empty() {
            self.campus_id = crate::config::CAMPUSES[0].id.to_string();
        }
        if !matches!(self.ui_language.as_str(), "system" | "zh-Hans" | "en") {
            self.ui_language = "system".to_string();
        }
    }
}

#[cfg(test)]
mod term_default_tests {
    use super::*;

    #[test]
    fn saved_and_request_defaults_do_not_materialize_term_values() {
        let mut saved = SavedSettings::with_defaults();
        saved.apply_defaults();
        assert!(saved.term_id.is_empty());
        assert!(saved.term_start_date.is_empty());

        let mut request = SaveSettingsRequest {
            account: String::new(),
            password: None,
            term_id: String::new(),
            term_start_date: String::new(),
            campus_id: String::new(),
            default_min_seats: 0,
            ui_language: String::new(),
            daily_course_notifications_enabled: false,
            automatic_term_detection_enabled: true,
            weather_enabled: true,
            almanac_enabled: true,
            competition_deadlines_enabled: true,
            conference_deadlines_enabled: true,
            school_contest_notices_enabled: true,
            summer_camp_deadlines_enabled: true,
            hackathon_deadlines_enabled: true,
            custom_deadlines_enabled: false,
            custom_deadlines_url: String::new(),
        };
        request.apply_defaults();
        assert!(request.term_id.is_empty());
        assert!(request.term_start_date.is_empty());
    }
}

#[derive(Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct ScheduleRequest {
    pub account: Option<String>,
    pub password: Option<String>,
    pub term_id: Option<String>,
    pub term_start_date: Option<String>,
    #[serde(default)]
    pub automatic_term_detection_enabled: Option<bool>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WeatherRequest {
    pub campus_id: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WeatherDay {
    pub date: String,
    pub weekday: String,
    pub weather_day: String,
    pub weather_night: String,
    pub temp_max: i32,
    pub temp_min: i32,
    pub precipitation_probability: Option<u8>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WeatherResponse {
    pub campus_id: String,
    pub campus_name: String,
    pub district: String,
    pub current_weather: String,
    pub current_temperature: i32,
    pub report_time: String,
    pub source: String,
    pub days: Vec<WeatherDay>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AlmanacRequest {
    pub date: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct AlmanacResponse {
    pub date: String,
    pub weekday: String,
    pub lunar_date: String,
    pub ganzhi_year: String,
    pub ganzhi_month: String,
    pub ganzhi_day: String,
    pub zodiac: String,
    pub solar_term: Option<String>,
    pub lunar_festival: Option<String>,
    pub solar_festival: Option<String>,
    pub yi: Option<String>,
    pub ji: Option<String>,
    pub source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeadlinesRequest {
    pub date: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarRangeRequest {
    pub start_date: String,
    pub end_date: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CustomDeadlineCalendarRequest {
    pub url: String,
    pub start_date: String,
    pub end_date: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeadlineItem {
    pub id: String,
    pub name: String,
    pub event_type: String,
    pub source_type: String,
    pub primary_deadline: String,
    pub organizer: Option<String>,
    pub official_url: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeadlinesResponse {
    pub date: String,
    pub fetched_at: String,
    pub source: String,
    pub used_backup: bool,
    pub items: Vec<DeadlineItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeadlineCalendarResponse {
    pub start_date: String,
    pub end_date: String,
    pub fetched_at: String,
    pub source: String,
    pub used_backup: bool,
    pub items: Vec<DeadlineItem>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImportantEventItem {
    pub id: String,
    pub name: String,
    pub event_type: String,
    pub source_type: String,
    pub primary_deadline: String,
    pub deadline_label: Option<String>,
    pub organizer: Option<String>,
    pub official_url: Option<String>,
    pub source_name: Option<String>,
    pub source_url: Option<String>,
    #[serde(default)]
    pub categories: Vec<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    pub level: Option<String>,
    pub location: Option<String>,
    pub status: Option<String>,
    pub description: Option<String>,
    pub eligibility: Option<String>,
    pub notes: Option<String>,
    pub region: Option<String>,
    pub mode: Option<String>,
    pub published_at: Option<String>,
    #[serde(default)]
    pub stale: bool,
    #[serde(default)]
    pub archived: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ImportantEventsResponse {
    pub fetched_at: String,
    pub source: String,
    pub used_backup: bool,
    pub items: Vec<ImportantEventItem>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShuttleBusSource {
    pub name: String,
    pub page_url: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShuttleBusStats {
    pub notices: usize,
    pub images: usize,
    pub parsed_schedules: usize,
    pub needs_review: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShuttleBusStop {
    pub campus: String,
    pub location: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShuttleBusPeriod {
    pub label: String,
    pub start_date: Option<String>,
    pub end_date: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShuttleBusService {
    pub vehicle: String,
    pub count: usize,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ShuttleBusRow {
    pub departure_time: String,
    #[serde(default)]
    pub services: std::collections::HashMap<String, Option<ShuttleBusService>>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShuttleBusSchedule {
    pub period: ShuttleBusPeriod,
    pub from: Option<String>,
    pub to: Option<String>,
    pub parse_status: String,
    pub parse_confidence: f64,
    pub parse_engine: String,
    #[serde(default)]
    pub rows: Vec<ShuttleBusRow>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShuttleBusNotice {
    pub id: String,
    pub title: String,
    pub published_at: String,
    pub source_url: String,
    pub parse_status: String,
    #[serde(default)]
    pub stops: Vec<ShuttleBusStop>,
    #[serde(default)]
    pub notes: Vec<String>,
    #[serde(default)]
    pub schedules: Vec<ShuttleBusSchedule>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ShuttleBusResponse {
    pub schema_version: String,
    pub generated_at: String,
    pub status: String,
    pub source: ShuttleBusSource,
    pub stats: ShuttleBusStats,
    pub last_parsed_notice_id: Option<String>,
    #[serde(default)]
    pub items: Vec<ShuttleBusNotice>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssignmentsRequest {
    pub date: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AssignmentDeadlineItem {
    pub id: String,
    pub title: String,
    pub course_name: Option<String>,
    pub deadline: String,
    pub status: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AssignmentsResponse {
    pub date: String,
    pub source: String,
    pub items: Vec<AssignmentDeadlineItem>,
    pub unavailable_reason: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AssignmentCalendarResponse {
    pub start_date: String,
    pub end_date: String,
    pub source: String,
    pub items: Vec<AssignmentDeadlineItem>,
}

#[derive(Clone, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct ClassroomsRequest {
    pub account: Option<String>,
    pub password: Option<String>,
    pub campus_id: Option<String>,
    pub target_date: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HolidaysRequest {
    pub year: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HolidayItem {
    pub date: String,
    pub name: String,
    #[serde(rename = "type")]
    pub kind: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct HolidaysResponse {
    pub year: i32,
    pub source: String,
    pub fetched_at: String,
    pub items: Vec<HolidayItem>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Course {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub teacher: String,
    #[serde(default)]
    pub room: String,
    #[serde(default)]
    pub week_text: String,
    #[serde(default)]
    pub week_numbers: Vec<i64>,
    #[serde(default)]
    pub exam_week_numbers: Vec<i64>,
    pub weekday: i64,
    pub start_slot: usize,
    pub end_slot: usize,
    #[serde(default)]
    pub section_text: String,
    #[serde(default)]
    pub time_range: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScheduleResponse {
    pub term_id: String,
    pub term_start_date: String,
    pub fetched_at: String,
    pub courses: Vec<Course>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClassroomStatus {
    pub id: String,
    pub building: String,
    pub room: String,
    pub name: String,
    pub size: Option<usize>,
    #[serde(default)]
    pub r#type: String,
    #[serde(default)]
    pub available_slots: Vec<usize>,
    #[serde(default = "default_classroom_source")]
    pub source: String,
}

fn default_classroom_source() -> String {
    "sjd".to_string()
}

pub const CLASSROOMS_CACHE_VERSION: u32 = 2;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClassroomsResponse {
    pub campus_id: String,
    pub campus_name: String,
    pub target_date: String,
    pub fetched_at: String,
    #[serde(default = "default_realtime")]
    pub realtime: bool,
    #[serde(default = "default_classroom_source")]
    pub provider: String,
    pub rooms: Vec<ClassroomStatus>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClassroomsCacheResponse {
    #[serde(default)]
    pub cache_version: u32,
    pub target_date: String,
    pub fetched_at: String,
    #[serde(default = "default_realtime")]
    pub realtime: bool,
    #[serde(default = "default_classroom_source")]
    pub provider: String,
    #[serde(default)]
    pub campuses: Vec<ClassroomsResponse>,
}

fn default_realtime() -> bool {
    true
}

#[cfg(not(mobile))]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DateScheduleState {
    pub target_date: String,
    pub week_number: i64,
    pub weekday: i64,
    pub busy_slots: Vec<usize>,
    pub free_slots: Vec<usize>,
    pub courses: Vec<Course>,
}
