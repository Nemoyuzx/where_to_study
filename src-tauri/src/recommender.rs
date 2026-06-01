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
        .filter(|course| course.weekday == weekday && course.week_numbers.contains(&week_number))
        .cloned()
        .collect();
    day_courses.sort_by(|left, right| {
        (left.start_slot, &left.name).cmp(&(right.start_slot, &right.name))
    });

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

#[cfg(test)]
mod tests {
    use chrono::NaiveDate;

    use super::*;

    #[test]
    fn date_state_marks_busy_and_free_slots() {
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
        let term_start = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        let state = date_state(&courses, term_start, term_start);

        assert_eq!(state.busy_slots, vec![2, 3]);
        assert_eq!(state.free_slots.len(), 12);
        assert_eq!(state.courses.len(), 1);
    }
}
