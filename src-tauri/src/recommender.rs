use std::collections::HashSet;

use chrono::{Datelike, NaiveDate};

use crate::models::{Course, DateScheduleState};

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
        .filter(|course| crate::academic::occurs_on(course, target_date, term_start_date))
        .cloned()
        .collect();
    day_courses.sort_by(|left, right| {
        (
            crate::academic::course_minutes(left)
                .map(|v| v.0)
                .unwrap_or(-1),
            &left.name,
            &left.id,
        )
            .cmp(&(
                crate::academic::course_minutes(right)
                    .map(|v| v.0)
                    .unwrap_or(-1),
                &right.name,
                &right.id,
            ))
    });

    let mut busy_slots: Vec<usize> = day_courses
        .iter()
        .flat_map(crate::academic::busy_slots)
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

#[cfg(test)]
mod tests {
    use chrono::NaiveDate;

    use super::*;

    #[test]
    fn dated_exams_use_minutes_and_pending_exams_never_claim_a_slot() {
        let start = NaiveDate::from_ymd_opt(2026, 9, 7).unwrap();
        let exam_day = NaiveDate::from_ymd_opt(2026, 12, 21).unwrap();
        let courses = vec![
            Course {
                id: "actual".into(),
                name: "合成考试".into(),
                event_kind: Some("exam".into()),
                event_date: Some("2026-12-21".into()),
                start_time: Some("09:35".into()),
                end_time: Some("10:10".into()),
                start_slot: 0,
                end_slot: 0,
                ..Default::default()
            },
            Course {
                id: "pending".into(),
                name: "合成待定考试".into(),
                event_kind: Some("exam".into()),
                event_date: Some("2026-12-21".into()),
                ..Default::default()
            },
            Course {
                id: "undated".into(),
                event_kind: Some("exam".into()),
                ..Default::default()
            },
        ];
        let state = date_state(&courses, exam_day, start);
        assert_eq!(state.courses.len(), 2);
        assert_eq!(state.courses[0].id, "pending");
        assert_eq!(state.busy_slots, vec![2]); // 09:35 touches slot 2's end but overlaps slot 3.
        assert_eq!(state.free_slots.len(), 13);
        assert!(date_state(&courses, start, start).courses.is_empty());
    }

    #[test]
    fn recommendation_uses_the_exam_override_and_keeps_later_course_occurrences() {
        let start = NaiveDate::from_ymd_opt(2026, 9, 7).unwrap();
        let raw = crate::models::ScheduleResponse {
            term_id: "2026-2027-1".into(),
            term_start_date: start.to_string(),
            courses: vec![Course {
                id: "lesson".into(),
                weekday: 1,
                week_numbers: vec![1, 2],
                start_slot: 0,
                end_slot: 1,
                ..Default::default()
            }],
            exam_schedule: Some(crate::academic::ExamSchedule {
                term_id: "2026-2027-1".into(),
                status: "fresh".into(),
                account_key: crate::academic::account_key("synthetic"),
                items: vec![crate::academic::ExamArrangement {
                    id: "exam".into(),
                    name: "合成考试".into(),
                    date: start.to_string(),
                    start_time: "09:20".into(),
                    end_time: "10:20".into(),
                    ..Default::default()
                }],
                ..Default::default()
            }),
            ..Default::default()
        };
        let effective = crate::academic::effective_schedule(&raw);
        let today = date_state(&effective.courses, start, start);
        assert_eq!(today.courses[0].id, "exam");
        assert_eq!(today.busy_slots, vec![1, 2]);
        let later = date_state(&effective.courses, start + chrono::Duration::days(7), start);
        assert_eq!(later.courses[0].id, "lesson");
        assert_eq!(later.busy_slots, vec![0, 1]);
    }

    #[test]
    fn date_state_marks_busy_and_free_slots() {
        let courses = vec![Course {
            source_course_id: String::new(),
            id: "c1".to_string(),
            name: "课程".to_string(),
            teacher: String::new(),
            room: String::new(),
            week_text: String::new(),
            week_numbers: vec![1],
            exam_week_numbers: Vec::new(),
            weekday: 1,
            start_slot: 2,
            end_slot: 3,
            section_text: String::new(),
            time_range: String::new(),
            ..Default::default()
        }];
        let term_start = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        let state = date_state(&courses, term_start, term_start);

        assert_eq!(state.busy_slots, vec![2, 3]);
        assert_eq!(state.free_slots.len(), 12);
        assert_eq!(state.courses.len(), 1);
    }
}
