use std::collections::HashSet;

use chrono::{Datelike, NaiveDate};

use crate::config::{today_in_app_tz, SLOT_TIMES};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{
    ClassroomStatus, ClassroomsResponse, Course, DateScheduleState, RecommendationResponse,
    RoomRecommendation, StayRange,
};

const ALL_SLOTS: std::ops::Range<usize> = 0..14;

pub fn date_state(
    courses: &[Course],
    target_date: NaiveDate,
    term_start_date: NaiveDate,
) -> DateScheduleState {
    let delta_days = (target_date - term_start_date).num_days();
    let week_number = delta_days.div_euclid(7) + 1;
    let weekday = target_date.weekday().number_from_monday() as i64;

    let mut day_courses: Vec<Course> = courses
        .iter()
        .filter(|course| course.weekday == weekday && course.week_numbers.contains(&week_number))
        .cloned()
        .collect();
    day_courses
        .sort_by(|left, right| (left.start_slot, &left.name).cmp(&(right.start_slot, &right.name)));

    let mut busy_slots: Vec<usize> = day_courses
        .iter()
        .flat_map(|course| course.start_slot..=course.end_slot)
        .filter(|slot| ALL_SLOTS.contains(slot))
        .collect::<HashSet<_>>()
        .into_iter()
        .collect();
    busy_slots.sort_unstable();
    let busy_set: HashSet<usize> = busy_slots.iter().copied().collect();
    let free_slots = ALL_SLOTS.filter(|slot| !busy_set.contains(slot)).collect();

    DateScheduleState {
        target_date: target_date.to_string(),
        week_number,
        weekday,
        busy_slots,
        free_slots,
        courses: day_courses,
    }
}

pub fn compact_ranges(slots: &[usize]) -> Vec<StayRange> {
    if slots.is_empty() {
        return Vec::new();
    }
    let mut sorted_slots = slots.to_vec();
    sorted_slots.sort_unstable();
    sorted_slots.dedup();

    let mut ranges = Vec::new();
    let mut start = sorted_slots[0];
    let mut previous = sorted_slots[0];
    for slot in sorted_slots.into_iter().skip(1) {
        if slot == previous + 1 {
            previous = slot;
            continue;
        }
        ranges.push(make_range(start, previous));
        start = slot;
        previous = slot;
    }
    ranges.push(make_range(start, previous));
    ranges
}

fn make_range(start_slot: usize, end_slot: usize) -> StayRange {
    StayRange {
        start_slot,
        end_slot,
        length: end_slot - start_slot + 1,
        start_time: SLOT_TIMES[start_slot].0.to_string(),
        end_time: SLOT_TIMES[end_slot].1.to_string(),
    }
}

pub fn recommend(
    courses: &[Course],
    term_start_date: NaiveDate,
    classrooms: ClassroomsResponse,
    target_date: Option<NaiveDate>,
    selected_slots: Option<Vec<usize>>,
    buildings: Vec<String>,
    min_seats: usize,
    use_schedule_filter: bool,
) -> RecommendationResponse {
    let date_to_check = target_date.unwrap_or_else(today_in_app_tz);
    let state = date_state(courses, date_to_check, term_start_date);
    let mut valid_selected: Vec<usize> = selected_slots
        .clone()
        .unwrap_or_default()
        .into_iter()
        .filter(|slot| ALL_SLOTS.contains(slot))
        .collect();
    valid_selected.sort_unstable();
    valid_selected.dedup();

    let schedule_allowed_slots: Vec<usize> = if use_schedule_filter {
        state.free_slots.clone()
    } else {
        ALL_SLOTS.collect()
    };
    let allowed_set: HashSet<usize> = schedule_allowed_slots.iter().copied().collect();
    let source_slots = if selected_slots.is_none() {
        schedule_allowed_slots
    } else {
        valid_selected.clone()
    };
    let target_slots: Vec<usize> = source_slots
        .into_iter()
        .filter(|slot| allowed_set.contains(slot))
        .collect();
    let target_set: HashSet<usize> = target_slots.iter().copied().collect();
    let building_filter: HashSet<String> = buildings
        .into_iter()
        .filter(|building| !building.is_empty())
        .collect();

    let mut recommendations = Vec::new();
    for room in classrooms.rooms.iter() {
        if !building_filter.is_empty() && !building_filter.contains(&room.building) {
            continue;
        }
        if room.size.is_some_and(|size| size < min_seats) {
            continue;
        }

        let available: HashSet<usize> = room.available_slots.iter().copied().collect();
        let mut matched_slots: Vec<usize> = target_set.intersection(&available).copied().collect();
        matched_slots.sort_unstable();
        if matched_slots.is_empty() {
            continue;
        }

        let matched_set: HashSet<usize> = matched_slots.iter().copied().collect();
        let fits_selected = !valid_selected.is_empty()
            && valid_selected.iter().all(|slot| matched_set.contains(slot));
        if !valid_selected.is_empty() && !fits_selected {
            continue;
        }

        let ranges = compact_ranges(&matched_slots);
        let longest_range = ranges.iter().max_by_key(|range| range.length).cloned();
        let seat_score = ((room.size.unwrap_or(0) as f64) / 200.0).min(1.0);
        let coverage_score = matched_slots.len() as f64 / target_slots.len().max(1) as f64;
        let continuous_score = longest_range
            .as_ref()
            .map(|range| range.length)
            .unwrap_or(0) as f64
            / 14.0;
        let score = (coverage_score * 70.0 + continuous_score * 25.0 + seat_score * 5.0) * 100.0;
        let score = score.round() / 100.0;

        recommendations.push(RoomRecommendation {
            classroom: room.clone(),
            matched_slots,
            ranges,
            longest_range,
            fits_selected_slots: fits_selected,
            score,
        });
    }

    recommendations.sort_by(|left, right| {
        let left_key = (
            left.longest_range
                .as_ref()
                .map(|range| range.length)
                .unwrap_or(0),
            left.matched_slots.len(),
            left.classroom.size.unwrap_or(0),
        );
        let right_key = (
            right
                .longest_range
                .as_ref()
                .map(|range| range.length)
                .unwrap_or(0),
            right.matched_slots.len(),
            right.classroom.size.unwrap_or(0),
        );
        right_key
            .cmp(&left_key)
            .then_with(|| right.score.total_cmp(&left.score))
    });

    RecommendationResponse {
        schedule: state,
        classrooms,
        selected_slots: target_slots,
        recommendations,
    }
}

pub fn parse_optional_date(
    value: Option<&str>,
    field_name: &str,
) -> ServiceResult<Option<NaiveDate>> {
    value
        .filter(|item| !item.trim().is_empty())
        .map(|item| {
            NaiveDate::parse_from_str(item.trim(), "%Y-%m-%d")
                .map_err(|_| ServiceError::with_status(format!("{field_name}格式不正确。"), 400))
        })
        .transpose()
}

#[allow(dead_code)]
fn _room_name(room: &ClassroomStatus) -> &str {
    &room.name
}

#[cfg(test)]
mod tests {
    use chrono::NaiveDate;

    use super::*;

    #[test]
    fn compact_ranges_groups_contiguous_slots() {
        let ranges = compact_ranges(&[0, 1, 2, 5, 6]);
        let compact: Vec<_> = ranges
            .iter()
            .map(|range| (range.start_slot, range.end_slot, range.length))
            .collect();
        assert_eq!(compact, vec![(0, 2, 3), (5, 6, 2)]);
    }

    #[test]
    fn recommendation_prioritizes_longest_stay() {
        let courses = vec![Course {
            id: "c1".to_string(),
            name: "课程".to_string(),
            teacher: String::new(),
            room: String::new(),
            week_text: String::new(),
            week_numbers: vec![1],
            weekday: 1,
            start_slot: 2,
            end_slot: 3,
            section_text: String::new(),
            time_range: String::new(),
        }];
        let classrooms = ClassroomsResponse {
            campus_id: "01".to_string(),
            campus_name: "西土城".to_string(),
            target_date: "2026-03-02".to_string(),
            fetched_at: "2026-03-02T00:00:00+08:00".to_string(),
            realtime: true,
            provider: "jwglweixin".to_string(),
            rooms: vec![
                ClassroomStatus {
                    id: "A-101".to_string(),
                    building: "A".to_string(),
                    room: "101".to_string(),
                    name: "A-101".to_string(),
                    size: Some(80),
                    r#type: String::new(),
                    available_slots: vec![0, 1, 4, 5, 6, 7],
                    source: "jwglweixin".to_string(),
                },
                ClassroomStatus {
                    id: "B-201".to_string(),
                    building: "B".to_string(),
                    room: "201".to_string(),
                    name: "B-201".to_string(),
                    size: Some(120),
                    r#type: String::new(),
                    available_slots: vec![0, 4, 5],
                    source: "jwglweixin".to_string(),
                },
            ],
        };
        let term_start = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        let result = recommend(
            &courses,
            term_start,
            classrooms,
            Some(term_start),
            None,
            Vec::new(),
            0,
            true,
        );
        assert_eq!(
            date_state(&courses, term_start, term_start).busy_slots,
            vec![2, 3]
        );
        assert_eq!(result.recommendations[0].classroom.name, "A-101");
        assert_eq!(
            result.recommendations[0]
                .longest_range
                .as_ref()
                .unwrap()
                .length,
            4
        );
    }

    #[test]
    fn recommendation_can_ignore_personal_schedule_filter() {
        let courses = vec![Course {
            id: "c1".to_string(),
            name: "课程".to_string(),
            teacher: String::new(),
            room: String::new(),
            week_text: String::new(),
            week_numbers: vec![1],
            weekday: 1,
            start_slot: 2,
            end_slot: 3,
            section_text: String::new(),
            time_range: String::new(),
        }];
        let classrooms = ClassroomsResponse {
            campus_id: "01".to_string(),
            campus_name: "西土城".to_string(),
            target_date: "2026-03-02".to_string(),
            fetched_at: "2026-03-02T00:00:00+08:00".to_string(),
            realtime: true,
            provider: "jwglweixin".to_string(),
            rooms: vec![ClassroomStatus {
                id: "A-101".to_string(),
                building: "A".to_string(),
                room: "101".to_string(),
                name: "A-101".to_string(),
                size: Some(80),
                r#type: String::new(),
                available_slots: vec![2, 3],
                source: "jwglweixin".to_string(),
            }],
        };
        let term_start = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        let result = recommend(
            &courses,
            term_start,
            classrooms,
            Some(term_start),
            Some(vec![2, 3]),
            Vec::new(),
            0,
            false,
        );
        assert_eq!(result.selected_slots, vec![2, 3]);
        assert_eq!(result.recommendations[0].classroom.name, "A-101");
    }

    #[test]
    fn recommendation_respects_explicit_empty_selected_slots() {
        let classrooms = ClassroomsResponse {
            campus_id: "01".to_string(),
            campus_name: "西土城".to_string(),
            target_date: "2026-03-02".to_string(),
            fetched_at: "2026-03-02T00:00:00+08:00".to_string(),
            realtime: true,
            provider: "jwglweixin".to_string(),
            rooms: vec![ClassroomStatus {
                id: "A-101".to_string(),
                building: "A".to_string(),
                room: "101".to_string(),
                name: "A-101".to_string(),
                size: Some(80),
                r#type: String::new(),
                available_slots: vec![0, 1],
                source: "jwglweixin".to_string(),
            }],
        };
        let term_start = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        let result = recommend(
            &[],
            term_start,
            classrooms,
            Some(term_start),
            Some(Vec::new()),
            Vec::new(),
            0,
            true,
        );
        assert_eq!(result.selected_slots, Vec::<usize>::new());
        assert!(result.recommendations.is_empty());
    }
}
