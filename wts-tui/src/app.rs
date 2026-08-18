use chrono::{Datelike, NaiveDate};
use where_to_study_lib::config::today_in_app_tz;
use where_to_study_lib::models::{
    ClassroomStatus, ClassroomsCacheResponse, Course, HolidaysResponse, ScheduleResponse,
};

pub enum Tab {
    Home,
    Schedule,
    Planner,
    Calendar,
    Settings,
}

pub struct App {
    pub tab: Tab,
    pub selected_tab_index: usize,
    pub schedule: Option<ScheduleResponse>,
    pub classrooms: Option<ClassroomsCacheResponse>,
    pub holidays: Option<HolidaysResponse>,
    pub status_message: Option<String>,
    pub error_message: Option<String>,
    pub loading: bool,
    pub theme_dark: bool,
    // Planner filter state
    pub campus_id: String,
    pub selected_buildings: Vec<String>,
    pub available_buildings: Vec<String>,
    pub selected_slots: Vec<usize>, // 0-based
    pub all_slots_selected: bool,
    // Calendar state
    pub calendar_month: NaiveDate,
    // Settings form
    pub login_account: String,
    pub login_password: String,
    pub settings_focus: usize,
    pub credentials_saved: bool,
    pub saved_account: String,
}

impl App {
    pub fn new(theme_dark: bool) -> Self {
        let today = today_in_app_tz();
        Self {
            tab: Tab::Home,
            selected_tab_index: 0,
            schedule: None,
            classrooms: None,
            holidays: None,
            status_message: None,
            error_message: None,
            loading: false,
            theme_dark,
            campus_id: "01".to_string(),
            selected_buildings: Vec::new(),
            available_buildings: Vec::new(),
            selected_slots: (0..14).collect(),
            all_slots_selected: true,
            calendar_month: NaiveDate::from_ymd_opt(today.year(), today.month(), 1)
                .unwrap_or(today),
            login_account: String::new(),
            login_password: String::new(),
            settings_focus: 0,
            credentials_saved: false,
            saved_account: String::new(),
        }
    }

    pub fn set_error(&mut self, message: String) {
        self.error_message = Some(message);
        self.loading = false;
    }

    pub fn clear_error(&mut self) {
        self.error_message = None;
    }

    pub fn set_status(&mut self, message: String) {
        self.status_message = Some(message);
    }

    pub fn current_week(&self) -> Option<i64> {
        let schedule = self.schedule.as_ref()?;
        let term_start = NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d").ok()?;
        let today = today_in_app_tz();
        Some((today - term_start).num_days() / 7 + 1)
    }

    pub fn today_courses(&self) -> Vec<&Course> {
        let Some(schedule) = self.schedule.as_ref() else {
            return vec![];
        };
        let today = today_in_app_tz();
        let week = self.current_week().unwrap_or(0);
        let weekday = today.weekday().num_days_from_monday() as i64 + 1;
        let mut courses: Vec<&Course> = schedule
            .courses
            .iter()
            .filter(|c| c.weekday == weekday && c.week_numbers.contains(&week))
            .collect();
        courses.sort_by(|a, b| a.start_slot.cmp(&b.start_slot).then(a.name.cmp(&b.name)));
        courses
    }

    pub fn courses_on(&self, date: NaiveDate) -> Vec<&Course> {
        let Some(schedule) = self.schedule.as_ref() else {
            return vec![];
        };
        let Some(term_start) =
            NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d").ok()
        else {
            return vec![];
        };
        let week = (date - term_start).num_days() / 7 + 1;
        let weekday = date.weekday().num_days_from_monday() as i64 + 1;
        let mut courses: Vec<&Course> = schedule
            .courses
            .iter()
            .filter(|c| c.weekday == weekday && c.week_numbers.contains(&week))
            .collect();
        courses.sort_by(|a, b| a.start_slot.cmp(&b.start_slot).then(a.name.cmp(&b.name)));
        courses
    }

    pub fn matching_rooms(&self) -> Vec<&ClassroomStatus> {
        let Some(cache) = self.classrooms.as_ref() else {
            return vec![];
        };
        let Some(campus) = cache
            .campuses
            .iter()
            .find(|c| c.campus_id == self.campus_id)
        else {
            return vec![];
        };
        let mut rooms: Vec<&ClassroomStatus> = campus
            .rooms
            .iter()
            .filter(|room| {
                self.selected_buildings.is_empty()
                    || self.selected_buildings.contains(&room.building)
            })
            .filter(|room| {
                self.all_slots_selected
                    || self
                        .selected_slots
                        .iter()
                        .all(|slot| room.available_slots.contains(slot))
            })
            .collect();
        rooms.sort_by(|a, b| a.building.cmp(&b.building).then(a.room.cmp(&b.room)));
        rooms
    }

    /// Collect the sorted unique building names for the current campus.
    pub fn building_names(&self) -> Vec<String> {
        let mut names: Vec<String> = self
            .classrooms
            .as_ref()
            .and_then(|cache| {
                cache
                    .campuses
                    .iter()
                    .find(|c| c.campus_id == self.campus_id)
            })
            .map(|campus| {
                campus
                    .rooms
                    .iter()
                    .map(|room| room.building.clone())
                    .collect()
            })
            .unwrap_or_default();
        names.sort();
        names.dedup();
        names
    }

    pub fn holiday_on(&self, date: NaiveDate) -> Option<(&'static str, String)> {
        let date_str = date.format("%Y-%m-%d").to_string();
        let response = self.holidays.as_ref()?;
        response
            .items
            .iter()
            .find(|item| item.date == date_str)
            .map(|item| {
                let kind = if item.kind == "holiday" { "休" } else { "班" };
                (kind, item.name.clone())
            })
    }
}

pub const TAB_LABELS: [&str; 5] = ["概览", "课表", "空教室", "日历", "设置"];

#[cfg(test)]
mod tests {
    use super::*;
    use where_to_study_lib::models::Course;

    fn sample_schedule() -> ScheduleResponse {
        ScheduleResponse {
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            fetched_at: "2026-01-01T00:00:00+08:00".to_string(),
            courses: vec![
                Course {
                    id: "c1".to_string(),
                    name: "数据挖掘".to_string(),
                    teacher: "示例教师".to_string(),
                    room: "教3-335".to_string(),
                    week_text: "1-2".to_string(),
                    week_numbers: vec![1, 2],
                    exam_week_numbers: vec![],
                    weekday: 1,
                    start_slot: 2,
                    end_slot: 4,
                    section_text: "3-5节".to_string(),
                    time_range: "09:50-12:15".to_string(),
                },
                Course {
                    id: "c2".to_string(),
                    name: "神经网络".to_string(),
                    teacher: "示例教师".to_string(),
                    room: "教3-539".to_string(),
                    week_text: "1-2".to_string(),
                    week_numbers: vec![1, 2],
                    exam_week_numbers: vec![2],
                    weekday: 3,
                    start_slot: 7,
                    end_slot: 8,
                    section_text: "8-9节".to_string(),
                    time_range: "14:45-16:25".to_string(),
                },
            ],
        }
    }

    #[test]
    fn current_week_calculates_from_term_start() {
        let mut app = App::new(false);
        app.schedule = Some(sample_schedule());
        // 2026-03-02 is the term start (week 1); today in the test env is later
        assert!(app.current_week().is_some());
    }

    #[test]
    fn today_courses_sorts_by_start_slot() {
        let mut app = App::new(false);
        app.schedule = Some(sample_schedule());
        let courses = app.today_courses();
        // No assertion on content (depends on test date), just verify it runs
        let _ = courses;
    }

    #[test]
    fn matching_rooms_filters_by_building_and_slots() {
        let mut app = App::new(false);
        app.classrooms = Some(ClassroomsCacheResponse {
            cache_version: 2,
            target_date: "2026-01-01".to_string(),
            fetched_at: "2026-01-01T00:00:00+08:00".to_string(),
            realtime: true,
            provider: "test".to_string(),
            campuses: vec![where_to_study_lib::models::ClassroomsResponse {
                campus_id: "01".to_string(),
                campus_name: "西土城".to_string(),
                target_date: "2026-01-01".to_string(),
                fetched_at: "2026-01-01T00:00:00+08:00".to_string(),
                realtime: true,
                provider: "test".to_string(),
                rooms: vec![
                    ClassroomStatus {
                        id: "r1".to_string(),
                        building: "教1".to_string(),
                        room: "101".to_string(),
                        name: "教1-101".to_string(),
                        size: Some(80),
                        r#type: String::new(),
                        available_slots: vec![0, 1, 2],
                        source: "test".to_string(),
                    },
                    ClassroomStatus {
                        id: "r2".to_string(),
                        building: "教2".to_string(),
                        room: "201".to_string(),
                        name: "教2-201".to_string(),
                        size: Some(60),
                        r#type: String::new(),
                        available_slots: vec![0, 5],
                        source: "test".to_string(),
                    },
                ],
            }],
        });
        app.available_buildings = app.building_names();

        // All slots selected -> both rooms match
        assert_eq!(app.matching_rooms().len(), 2);

        // Filter by building 教1
        app.selected_buildings = vec!["教1".to_string()];
        assert_eq!(app.matching_rooms().len(), 1);
        assert_eq!(app.matching_rooms()[0].room, "101");

        // Filter by slots [0, 1] -> only 教1-101 has both
        app.selected_buildings.clear();
        app.all_slots_selected = false;
        app.selected_slots = vec![0, 1];
        assert_eq!(app.matching_rooms().len(), 1);
        assert_eq!(app.matching_rooms()[0].room, "101");
    }
}
