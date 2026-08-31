use std::collections::{BTreeMap, BTreeSet};

use chrono::{Datelike, NaiveDate};
use where_to_study_lib::config::today_in_app_tz;
use where_to_study_lib::models::{
    ClassroomStatus, ClassroomsCacheResponse, Course, HolidaysResponse, ImportantEventItem,
    ImportantEventsResponse, ScheduleResponse, ShuttleBusResponse,
};
use where_to_study_lib::public_queries::{ImportantEventFilter, ImportantEventSourceFilter};
use zeroize::Zeroizing;

const TERM_VALIDITY_WEEKS: i64 = 26;

pub enum Tab {
    Home,
    Schedule,
    Planner,
    Calendar,
    Settings,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum QuerySection {
    Shuttle,
    Events,
}

pub struct App {
    pub tab: Tab,
    pub selected_tab_index: usize,
    pub schedule: Option<ScheduleResponse>,
    pub classrooms: Option<ClassroomsCacheResponse>,
    pub holidays: BTreeMap<i32, HolidaysResponse>,
    pub holiday_requests: BTreeSet<i32>,
    pub status_message: Option<String>,
    pub error_message: Option<String>,
    pub loading: bool,
    pub theme_dark: bool,
    pub campus_id: String,
    pub selected_buildings: Vec<String>,
    pub available_buildings: Vec<String>,
    pub building_cursor: usize,
    pub room_scroll: usize,
    pub selected_slots: Vec<usize>,
    pub all_slots_selected: bool,
    pub calendar_month: NaiveDate,
    pub login_account: String,
    pub login_password: Zeroizing<String>,
    pub settings_focus: usize,
    pub settings_editing: bool,
    pub credentials_saved: bool,
    pub saved_account: String,
    pub query_open: bool,
    pub query_section: QuerySection,
    pub shuttle: Option<ShuttleBusResponse>,
    pub important_events: Option<ImportantEventsResponse>,
    pub favorite_events: Vec<ImportantEventItem>,
    pub query_search: String,
    pub query_search_editing: bool,
    pub query_event_type: Option<String>,
    pub query_category: Option<String>,
    pub query_source: ImportantEventSourceFilter,
    pub query_include_ended: bool,
    pub query_favorites_only: bool,
    pub query_event_cursor: usize,
    pub query_scroll: usize,
    request_sequence: u64,
    pending_schedule: Option<u64>,
    pending_classrooms: Option<u64>,
    pending_shuttle: Option<u64>,
    pending_events: Option<u64>,
}

impl App {
    pub fn new(theme_dark: bool) -> Self {
        let today = today_in_app_tz();
        Self {
            tab: Tab::Home,
            selected_tab_index: 0,
            schedule: None,
            classrooms: None,
            holidays: BTreeMap::new(),
            holiday_requests: BTreeSet::new(),
            status_message: None,
            error_message: None,
            loading: false,
            theme_dark,
            campus_id: "01".to_string(),
            selected_buildings: Vec::new(),
            available_buildings: Vec::new(),
            building_cursor: 0,
            room_scroll: 0,
            selected_slots: (0..14).collect(),
            all_slots_selected: true,
            calendar_month: NaiveDate::from_ymd_opt(today.year(), today.month(), 1)
                .unwrap_or(today),
            login_account: String::new(),
            login_password: Zeroizing::new(String::new()),
            settings_focus: 0,
            settings_editing: false,
            credentials_saved: false,
            saved_account: String::new(),
            query_open: false,
            query_section: QuerySection::Shuttle,
            shuttle: None,
            important_events: None,
            favorite_events: Vec::new(),
            query_search: String::new(),
            query_search_editing: false,
            query_event_type: None,
            query_category: None,
            query_source: ImportantEventSourceFilter::All,
            query_include_ended: false,
            query_favorites_only: false,
            query_event_cursor: 0,
            query_scroll: 0,
            request_sequence: 0,
            pending_schedule: None,
            pending_classrooms: None,
            pending_shuttle: None,
            pending_events: None,
        }
    }

    pub fn set_error(&mut self, message: String) {
        self.status_message = None;
        self.error_message = Some(message);
    }

    pub fn clear_error(&mut self) {
        self.error_message = None;
    }

    pub fn set_status(&mut self, message: String) {
        self.error_message = None;
        self.status_message = Some(message);
    }

    pub fn schedule_week_on(&self, date: NaiveDate) -> Option<i64> {
        let schedule = self.schedule.as_ref()?;
        let term_start = NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d").ok()?;
        let elapsed_days = (date - term_start).num_days();
        if !(0..TERM_VALIDITY_WEEKS * 7).contains(&elapsed_days) {
            return None;
        }
        Some(elapsed_days.div_euclid(7) + 1)
    }

    pub fn current_week(&self) -> Option<i64> {
        self.schedule_week_on(today_in_app_tz())
    }

    pub fn today_courses(&self) -> Vec<&Course> {
        self.courses_on(today_in_app_tz())
    }

    pub fn courses_on(&self, date: NaiveDate) -> Vec<&Course> {
        let Some(schedule) = self.schedule.as_ref() else {
            return vec![];
        };
        let Some(week) = self.schedule_week_on(date) else {
            return vec![];
        };
        let weekday = date.weekday().num_days_from_monday() as i64 + 1;
        let mut courses: Vec<&Course> = schedule
            .courses
            .iter()
            .filter(|course| course.weekday == weekday && course.week_numbers.contains(&week))
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
            .find(|campus| campus.campus_id == self.campus_id)
        else {
            return vec![];
        };
        let mut rooms: Vec<&ClassroomStatus> = campus
            .rooms
            .iter()
            .filter(|room| self.selected_buildings.contains(&room.building))
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

    pub fn building_names(&self) -> Vec<String> {
        let mut names: Vec<String> = self
            .classrooms
            .as_ref()
            .and_then(|cache| {
                cache
                    .campuses
                    .iter()
                    .find(|campus| campus.campus_id == self.campus_id)
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

    pub fn select_all_buildings(&mut self) {
        self.selected_buildings = self.available_buildings.clone();
        self.building_cursor = self
            .building_cursor
            .min(self.available_buildings.len().saturating_sub(1));
        self.room_scroll = 0;
    }

    pub fn toggle_current_building(&mut self) {
        let Some(building) = self.available_buildings.get(self.building_cursor).cloned() else {
            return;
        };
        if let Some(index) = self
            .selected_buildings
            .iter()
            .position(|selected| selected == &building)
        {
            self.selected_buildings.remove(index);
        } else {
            self.selected_buildings.push(building);
            self.selected_buildings.sort();
        }
        self.room_scroll = 0;
    }

    pub fn move_building_cursor(&mut self, delta: isize) {
        let max = self.available_buildings.len().saturating_sub(1) as isize;
        self.building_cursor = (self.building_cursor as isize + delta).clamp(0, max) as usize;
    }

    pub fn holiday_on(&self, date: NaiveDate) -> Option<(&'static str, String)> {
        let date_str = date.format("%Y-%m-%d").to_string();
        self.holidays
            .get(&date.year())?
            .items
            .iter()
            .find(|item| item.date == date_str)
            .map(|item| {
                let kind = if item.kind == "holiday" { "休" } else { "班" };
                (kind, item.name.clone())
            })
    }

    pub fn request_holidays_for(&mut self, year: i32) -> bool {
        if self.holidays.contains_key(&year) || self.holiday_requests.contains(&year) {
            return false;
        }
        self.holiday_requests.insert(year);
        true
    }

    pub fn finish_holidays(&mut self, year: i32, response: Option<HolidaysResponse>) {
        self.holiday_requests.remove(&year);
        if let Some(response) = response {
            self.holidays.insert(year, response);
        }
    }

    pub fn start_schedule_request(&mut self) -> u64 {
        let request_id = self.next_request_id();
        self.pending_schedule = Some(request_id);
        self.sync_loading();
        request_id
    }

    pub fn start_classrooms_request(&mut self) -> u64 {
        let request_id = self.next_request_id();
        self.pending_classrooms = Some(request_id);
        self.sync_loading();
        request_id
    }

    pub fn finish_schedule_request(&mut self, request_id: u64) -> bool {
        if self.pending_schedule != Some(request_id) {
            return false;
        }
        self.pending_schedule = None;
        self.sync_loading();
        true
    }

    pub fn finish_classrooms_request(&mut self, request_id: u64) -> bool {
        if self.pending_classrooms != Some(request_id) {
            return false;
        }
        self.pending_classrooms = None;
        self.sync_loading();
        true
    }

    pub fn start_shuttle_request(&mut self) -> u64 {
        let request_id = self.next_request_id();
        self.pending_shuttle = Some(request_id);
        self.sync_loading();
        request_id
    }

    pub fn start_events_request(&mut self) -> u64 {
        let request_id = self.next_request_id();
        self.pending_events = Some(request_id);
        self.sync_loading();
        request_id
    }

    pub fn finish_shuttle_request(&mut self, request_id: u64) -> bool {
        if self.pending_shuttle != Some(request_id) {
            return false;
        }
        self.pending_shuttle = None;
        self.sync_loading();
        true
    }

    pub fn finish_events_request(&mut self, request_id: u64) -> bool {
        if self.pending_events != Some(request_id) {
            return false;
        }
        self.pending_events = None;
        self.sync_loading();
        true
    }

    pub fn invalidate_data_requests(&mut self) {
        self.pending_schedule = None;
        self.pending_classrooms = None;
        self.pending_shuttle = None;
        self.pending_events = None;
        self.sync_loading();
    }

    fn next_request_id(&mut self) -> u64 {
        self.request_sequence = self.request_sequence.wrapping_add(1).max(1);
        self.request_sequence
    }

    fn sync_loading(&mut self) {
        self.loading = self.pending_schedule.is_some()
            || self.pending_classrooms.is_some()
            || self.pending_shuttle.is_some()
            || self.pending_events.is_some();
    }

    pub fn all_query_events(&self) -> Vec<ImportantEventItem> {
        where_to_study_lib::public_queries::merge_live_and_favorite_events(
            self.important_events
                .as_ref()
                .map(|response| response.items.as_slice())
                .unwrap_or_default(),
            &self.favorite_events,
        )
    }

    pub fn event_types(&self) -> Vec<String> {
        where_to_study_lib::public_queries::available_event_types(&self.all_query_events())
    }

    pub fn event_categories(&self) -> Vec<String> {
        where_to_study_lib::public_queries::available_event_categories(&self.all_query_events())
    }

    pub fn visible_query_events(&self) -> Vec<ImportantEventItem> {
        where_to_study_lib::public_queries::filter_important_events(
            &self.all_query_events(),
            &self.favorite_events,
            &ImportantEventFilter {
                query: self.query_search.clone(),
                event_type: self.query_event_type.clone(),
                category: self.query_category.clone(),
                source: self.query_source,
                include_ended: self.query_include_ended,
                favorites_only: self.query_favorites_only,
            },
            chrono::Utc::now(),
        )
    }

    pub fn selected_query_event(&self) -> Option<ImportantEventItem> {
        self.visible_query_events()
            .get(self.query_event_cursor)
            .cloned()
    }

    pub fn clamp_query_cursor(&mut self) {
        let length = self.visible_query_events().len();
        self.query_event_cursor = self.query_event_cursor.min(length.saturating_sub(1));
        self.query_scroll = self.query_scroll.min(self.query_event_cursor);
    }

    pub fn move_query_cursor(&mut self, delta: isize) {
        let maximum = self.visible_query_events().len().saturating_sub(1) as isize;
        self.query_event_cursor =
            (self.query_event_cursor as isize + delta).clamp(0, maximum) as usize;
        if self.query_event_cursor < self.query_scroll {
            self.query_scroll = self.query_event_cursor;
        } else if self.query_event_cursor >= self.query_scroll.saturating_add(12) {
            self.query_scroll = self.query_event_cursor.saturating_sub(11);
        }
    }

    pub fn cycle_query_event_type(&mut self) {
        let options = self.event_types();
        self.query_event_type = cycle_optional(&options, self.query_event_type.as_deref());
        self.query_event_cursor = 0;
        self.query_scroll = 0;
    }

    pub fn cycle_query_category(&mut self) {
        let options = self.event_categories();
        self.query_category = cycle_optional(&options, self.query_category.as_deref());
        self.query_event_cursor = 0;
        self.query_scroll = 0;
    }

    pub fn cycle_query_source(&mut self) {
        self.query_source = match self.query_source {
            ImportantEventSourceFilter::All => ImportantEventSourceFilter::Public,
            ImportantEventSourceFilter::Public => ImportantEventSourceFilter::School,
            ImportantEventSourceFilter::School => ImportantEventSourceFilter::All,
        };
        self.query_event_cursor = 0;
        self.query_scroll = 0;
    }

    pub fn is_favorite(&self, item: &ImportantEventItem) -> bool {
        let key = where_to_study_lib::public_queries::favorite_key(item);
        self.favorite_events
            .iter()
            .any(|favorite| where_to_study_lib::public_queries::favorite_key(favorite) == key)
    }

    pub fn toggle_selected_event_favorite(
        &mut self,
    ) -> where_to_study_lib::error::ServiceResult<bool> {
        let item = self.selected_query_event().ok_or_else(|| {
            where_to_study_lib::error::ServiceError::new("当前没有可收藏的事件。")
        })?;
        where_to_study_lib::public_queries::toggle_favorite_event(&mut self.favorite_events, &item)
    }
}

fn cycle_optional(options: &[String], current: Option<&str>) -> Option<String> {
    if options.is_empty() {
        return None;
    }
    match current.and_then(|current| options.iter().position(|value| value == current)) {
        None => Some(options[0].clone()),
        Some(index) if index + 1 < options.len() => Some(options[index + 1].clone()),
        Some(_) => None,
    }
}

pub const TAB_LABELS: [&str; 5] = ["概览", "课表", "空教室", "日历", "设置"];

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_schedule() -> ScheduleResponse {
        ScheduleResponse {
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            fetched_at: "2026-01-01T00:00:00+08:00".to_string(),
            courses: vec![
                Course {
                    id: "c2".to_string(),
                    name: "神经网络".to_string(),
                    teacher: "示例教师".to_string(),
                    room: "教3-539".to_string(),
                    week_text: "1-2".to_string(),
                    week_numbers: vec![1, 2],
                    exam_week_numbers: vec![],
                    weekday: 1,
                    start_slot: 7,
                    end_slot: 8,
                    section_text: "8-9节".to_string(),
                    time_range: "14:45-16:25".to_string(),
                },
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
            ],
        }
    }

    fn sample_classrooms() -> ClassroomsCacheResponse {
        ClassroomsCacheResponse {
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
        }
    }

    #[test]
    fn schedule_week_rejects_dates_outside_the_term() {
        let mut app = App::new(false);
        app.schedule = Some(sample_schedule());
        assert_eq!(
            app.schedule_week_on(NaiveDate::from_ymd_opt(2026, 3, 2).unwrap()),
            Some(1)
        );
        assert_eq!(
            app.schedule_week_on(NaiveDate::from_ymd_opt(2026, 3, 1).unwrap()),
            None
        );
        assert_eq!(
            app.schedule_week_on(NaiveDate::from_ymd_opt(2026, 8, 31).unwrap()),
            None
        );
    }

    #[test]
    fn courses_on_sorts_by_start_slot() {
        let mut app = App::new(false);
        app.schedule = Some(sample_schedule());
        let courses = app.courses_on(NaiveDate::from_ymd_opt(2026, 3, 2).unwrap());
        assert_eq!(courses.len(), 2);
        assert_eq!(courses[0].name, "数据挖掘");
        assert_eq!(courses[1].name, "神经网络");
    }

    #[test]
    fn matching_rooms_requires_explicit_buildings_and_slots() {
        let mut app = App::new(false);
        app.classrooms = Some(sample_classrooms());
        app.available_buildings = app.building_names();
        assert!(app.matching_rooms().is_empty());

        app.select_all_buildings();
        assert_eq!(app.matching_rooms().len(), 2);

        app.selected_buildings = vec!["教1".to_string()];
        assert_eq!(app.matching_rooms().len(), 1);

        app.selected_buildings = app.available_buildings.clone();
        app.all_slots_selected = false;
        app.selected_slots = vec![0, 1];
        assert_eq!(app.matching_rooms().len(), 1);
        assert_eq!(app.matching_rooms()[0].room, "101");
    }

    #[test]
    fn stale_request_responses_are_ignored() {
        let mut app = App::new(false);
        let first = app.start_schedule_request();
        let second = app.start_schedule_request();
        assert!(!app.finish_schedule_request(first));
        assert!(app.loading);
        assert!(app.finish_schedule_request(second));
        assert!(!app.loading);
    }

    #[test]
    fn building_toggle_selects_only_the_current_entry() {
        let mut app = App::new(false);
        app.available_buildings = vec!["教1".to_string(), "教2".to_string()];
        app.select_all_buildings();
        app.building_cursor = 1;
        app.toggle_current_building();
        assert_eq!(app.selected_buildings, vec!["教1".to_string()]);
    }

    #[test]
    fn success_and_error_messages_are_mutually_exclusive() {
        let mut app = App::new(false);
        app.set_error("请输入密码。".to_string());
        assert_eq!(app.error_message.as_deref(), Some("请输入密码。"));
        assert!(app.status_message.is_none());

        app.set_status("凭据已保存到本地文件".to_string());
        assert!(app.error_message.is_none());
        assert_eq!(app.status_message.as_deref(), Some("凭据已保存到本地文件"));

        app.set_error("网络错误".to_string());
        assert_eq!(app.error_message.as_deref(), Some("网络错误"));
        assert!(app.status_message.is_none());
    }

    fn sample_event(id: &str, deadline: &str, category: &str) -> ImportantEventItem {
        ImportantEventItem {
            id: id.to_string(),
            name: format!("事件 {id}"),
            event_type: "conference".to_string(),
            source_type: "contest_ddl".to_string(),
            primary_deadline: deadline.to_string(),
            deadline_label: Some("提交截止".to_string()),
            organizer: Some("组织方".to_string()),
            official_url: None,
            source_name: Some("Contest DDL".to_string()),
            source_url: None,
            categories: vec![category.to_string()],
            tags: Vec::new(),
            level: None,
            location: None,
            status: None,
            description: None,
            eligibility: None,
            notes: None,
            region: None,
            mode: None,
            published_at: None,
            stale: false,
            archived: false,
        }
    }

    #[test]
    fn query_filters_derive_real_categories_and_default_to_upcoming() {
        let mut app = App::new(false);
        app.important_events = Some(ImportantEventsResponse {
            fetched_at: "2026-08-31T00:00:00+08:00".to_string(),
            source: "fixture".to_string(),
            used_backup: false,
            items: vec![
                sample_event("future", "2099-09-01T12:00:00+08:00", "人工智能"),
                sample_event("past", "2020-01-01T12:00:00+08:00", "系统"),
            ],
        });
        assert_eq!(app.event_categories(), ["人工智能", "系统"]);
        assert_eq!(app.visible_query_events().len(), 1);
        app.query_include_ended = true;
        assert_eq!(app.visible_query_events().len(), 2);
        app.query_category = Some("系统".to_string());
        assert_eq!(app.visible_query_events()[0].id, "past");
    }

    #[test]
    fn query_request_ids_keep_network_results_independent_from_view_switching() {
        let mut app = App::new(false);
        let shuttle = app.start_shuttle_request();
        let events = app.start_events_request();
        app.query_section = QuerySection::Events;
        assert!(app.finish_shuttle_request(shuttle));
        assert!(app.loading);
        assert!(app.finish_events_request(events));
        assert!(!app.loading);
    }
}
