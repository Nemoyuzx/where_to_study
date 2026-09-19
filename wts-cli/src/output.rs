use chrono::{Datelike, Duration, NaiveDate};
use where_to_study_lib::academic::{self, GradeReport};
use where_to_study_lib::error::ServiceResult;
use where_to_study_lib::models::{ClassroomsResponse, Course, HolidaysResponse, ScheduleResponse};
use where_to_study_lib::public_queries::{TodayShuttlePresentation, TodayShuttleRoute};

const WEEKDAY_LABELS: [&str; 7] = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];

pub fn day_courses(schedule: &ScheduleResponse, date: NaiveDate) -> Vec<&Course> {
    let Ok(start) = NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d") else {
        return vec![];
    };
    let mut courses: Vec<&Course> = schedule
        .courses
        .iter()
        .filter(|course| academic::occurs_on(course, date, start))
        .collect();
    courses.sort_by(|a, b| {
        academic::course_minutes(a)
            .cmp(&academic::course_minutes(b))
            .then(a.name.cmp(&b.name))
    });
    courses
}

pub fn course_time(course: &Course) -> String {
    match academic::course_minutes(course) {
        Some((start, end)) => format!(
            "{:02}:{:02}-{:02}:{:02}",
            start / 60,
            start % 60,
            end / 60,
            end % 60
        ),
        None => "全天 · 时间待定".into(),
    }
}

pub fn exam_status(schedule: &ScheduleResponse) -> String {
    match &schedule.exam_schedule {
        None => "尚未获取考试安排。".into(),
        Some(exams) => {
            let state = match exams.status.as_str() {
                "failed" => "考试安排获取失败",
                "stale" => "考试安排为旧缓存",
                _ if exams.items.is_empty() => "暂无考试安排",
                _ => "考试安排已同步",
            };
            let pending = exams
                .items
                .iter()
                .filter(|exam| exam.date.is_empty())
                .map(|exam| exam.name.as_str())
                .collect::<Vec<_>>();
            format!(
                "{state}。{}{}",
                exams.message,
                if pending.is_empty() {
                    String::new()
                } else {
                    format!(" 日期待定：{}", pending.join("、"))
                }
            )
        }
    }
}

pub fn grade_report_text(report: &GradeReport) -> String {
    let term = if report.term_id.is_empty() {
        "全部学期"
    } else {
        &report.term_id
    };
    let records = match report.record_type.as_str() {
        "1" => "最好成绩",
        "0" => "首次成绩",
        _ => "全部记录",
    };
    let mut lines = vec![format!(
        "{term} · {records} · {} 条成绩",
        report.items.len()
    )];
    if !report.average_grade_point.is_empty() {
        lines.push(format!("平均学分绩点：{}", report.average_grade_point));
    }
    if report.items.is_empty() {
        lines.push("暂无已公布成绩；可使用 --all-terms 查看全部学期。".into());
    }
    for item in &report.items {
        lines.push(format!(
            "{}  成绩：{}  学分：{}  {}",
            item.name,
            if item.score.is_empty() {
                "未公布"
            } else {
                &item.score
            },
            if item.credits.is_empty() {
                "未公布"
            } else {
                &item.credits
            },
            item.semester_name
        ));
        let details = [
            &item.course_code,
            &item.course_attribute,
            &item.course_nature,
            &item.exam_nature,
            &item.grade_status,
        ]
        .into_iter()
        .filter(|value| !value.is_empty())
        .cloned()
        .collect::<Vec<_>>();
        if !details.is_empty() {
            lines.push(format!("  {}", details.join(" · ")));
        }
    }
    lines.join("\n")
}

pub fn print_schedule_day(
    schedule: &ScheduleResponse,
    date: NaiveDate,
    week: i64,
) -> ServiceResult<()> {
    let weekday = WEEKDAY_LABELS[date.weekday().num_days_from_monday() as usize];
    let courses = day_courses(schedule, date);
    println!(
        "{} {} · 公历第 {} 周 · {} · {} 项安排",
        date.format("%Y-%m-%d"),
        weekday,
        date.iso_week().week(),
        if week > 0 {
            format!("教学第 {week} 周")
        } else {
            "教学周范围外".into()
        },
        courses.len()
    );
    println!(
        "学期 {}（第一周周一 {}）",
        schedule.term_id, schedule.term_start_date
    );
    println!("{}", exam_status(schedule));
    if courses.is_empty() {
        println!("今天没有课程。");
        return Ok(());
    }
    for course in &courses {
        let time = course_time(course);
        let room = if course.room.is_empty() {
            "地点未标注"
        } else {
            &course.room
        };
        let teacher = if course.teacher.is_empty() {
            ""
        } else {
            &course.teacher
        };
        println!(
            "  {}{}  {}  {}  {}",
            if academic::is_exam(course) {
                "考试 · "
            } else {
                ""
            },
            course.name,
            time,
            room,
            teacher
        );
    }
    Ok(())
}

pub fn print_schedule_week(
    schedule: &ScheduleResponse,
    date: NaiveDate,
    week: i64,
) -> ServiceResult<()> {
    let monday = date
        .checked_sub_days(chrono::Days::new(
            date.weekday().num_days_from_monday() as u64
        ))
        .unwrap_or(date);
    println!(
        "公历第 {} 周 · {}（{} 起）",
        monday.iso_week().week(),
        if week > 0 {
            format!("教学第 {week} 周")
        } else {
            "教学周范围外".into()
        },
        monday.format("%Y-%m-%d")
    );
    println!("{}", exam_status(schedule));
    for offset in 0..7 {
        let day = monday + Duration::days(offset);
        let courses = day_courses(schedule, day);
        let weekday = WEEKDAY_LABELS[offset as usize];
        if courses.is_empty() {
            println!("  {} {}：无课", day.format("%m-%d"), weekday);
            continue;
        }
        println!("  {} {}：", day.format("%m-%d"), weekday);
        for course in &courses {
            let time = course_time(course);
            let room = if course.room.is_empty() {
                "地点未标注"
            } else {
                &course.room
            };
            println!(
                "    {}{}  {}  {}",
                if academic::is_exam(course) {
                    "考试 · "
                } else {
                    ""
                },
                course.name,
                time,
                room
            );
        }
    }
    Ok(())
}

pub fn print_classrooms(
    campus: &ClassroomsResponse,
    rooms: &[&where_to_study_lib::models::ClassroomStatus],
    slot_filter: Option<&[usize]>,
) -> ServiceResult<()> {
    println!(
        "{} · {} · {} · 数据源 {}",
        campus.campus_name, campus.target_date, campus.fetched_at, campus.provider
    );
    let filter_note = match slot_filter {
        Some(slots) => format!(
            "（筛选节次：{}）",
            slots
                .iter()
                .map(|slot| (slot + 1).to_string())
                .collect::<Vec<_>>()
                .join(",")
        ),
        None => String::new(),
    };
    println!("匹配教室 {} 间{filter_note}", rooms.len());
    if rooms.is_empty() {
        return Ok(());
    }
    let mut current_building = String::new();
    for room in rooms {
        if room.building != current_building {
            current_building = room.building.clone();
            println!("  [{}]", current_building);
        }
        let size = room
            .size
            .map(|s| format!("{s}座"))
            .unwrap_or_else(|| "座位未知".to_string());
        let slots = room
            .available_slots
            .iter()
            .map(|slot| (slot + 1).to_string())
            .collect::<Vec<_>>()
            .join(",");
        println!(
            "    {}-{}  {size}  空闲节次: {slots}",
            room.building, room.room
        );
    }
    Ok(())
}

pub fn print_holidays(response: &HolidaysResponse) -> ServiceResult<()> {
    println!(
        "{} 年节假日（{}，来源 {}）",
        response.year, response.fetched_at, response.source
    );
    let mut holiday_dates: Vec<&where_to_study_lib::models::HolidayItem> = response
        .items
        .iter()
        .filter(|item| item.kind == "holiday")
        .collect();
    holiday_dates.sort_by(|a, b| a.date.cmp(&b.date));
    let mut workdays: Vec<&where_to_study_lib::models::HolidayItem> = response
        .items
        .iter()
        .filter(|item| item.kind == "workday")
        .collect();
    workdays.sort_by(|a, b| a.date.cmp(&b.date));
    println!("放假：");
    for item in &holiday_dates {
        println!("  {} {}", item.date, item.name);
    }
    println!("调休上班：");
    if workdays.is_empty() {
        println!("  （无）");
    }
    for item in &workdays {
        println!("  {} {}", item.date, item.name);
    }
    Ok(())
}

fn print_shuttle_route(route: &TodayShuttleRoute) {
    println!("  {} → {} · {}", route.from, route.to, route.period_label);
    if route.departures.is_empty() {
        println!("    今日无发车安排");
        return;
    }
    for departure in &route.departures {
        let marker = if departure.next {
            "下一班"
        } else if departure.departed {
            "已发车"
        } else {
            "待发车"
        };
        println!(
            "    {}  {}×{}  {marker}",
            departure.time, departure.vehicle, departure.count
        );
    }
}

pub fn print_shuttle(
    response: &where_to_study_lib::models::ShuttleBusResponse,
    today: &TodayShuttlePresentation,
) -> ServiceResult<()> {
    println!("{} · {}", today.date, today.status);
    if let Some(next) = &today.next_departure {
        println!("{next}");
    }
    if today.stale {
        println!("提示：服务当前返回缓存数据，请以学校通知为准。");
    }
    if let Some(title) = &today.notice_title {
        println!("生效通知：{title}");
    }
    for route in &today.routes {
        print_shuttle_route(route);
    }
    if !today.stops.is_empty() {
        println!("发车地点：");
        for stop in &today.stops {
            println!("  {}：{}", stop.campus, stop.location);
        }
    }
    println!(
        "第三方来源：{} · 生成于 {}\n{}",
        response.source.name, response.generated_at, response.source.page_url
    );
    Ok(())
}

pub fn print_important_events(
    items: &[where_to_study_lib::models::ImportantEventItem],
    favorites: &[where_to_study_lib::models::ImportantEventItem],
    source: &str,
    fetched_at: Option<&str>,
) -> ServiceResult<()> {
    let favorite_keys: std::collections::HashSet<String> = favorites
        .iter()
        .map(where_to_study_lib::public_queries::favorite_key)
        .collect();
    println!(
        "重要事件 {} 项 · 默认按 DDL 升序{}",
        items.len(),
        fetched_at
            .map(|value| format!(" · 数据时间 {value}"))
            .unwrap_or_default()
    );
    for item in items {
        let key = where_to_study_lib::public_queries::favorite_key(item);
        let favorite = if favorite_keys.contains(&key) {
            "★"
        } else {
            "☆"
        };
        let source_label = if item.source_type == "school_notice" {
            "校内"
        } else {
            "公开"
        };
        println!(
            "{favorite} {}  [{} · {}] {}",
            item.primary_deadline, source_label, item.event_type, item.name
        );
        if !item.categories.is_empty() {
            println!("    分类：{}", item.categories.join(" / "));
        }
        println!("    favorite_key: {key}");
    }
    if items.is_empty() {
        println!("没有符合条件的事件。");
    }
    println!("第三方来源：{source}\n显示数据仅供参考，请以实际情况为准。");
    Ok(())
}

#[cfg(test)]
mod academic_tests {
    use super::*;
    use where_to_study_lib::academic::GradeItem;

    #[test]
    fn grade_output_preserves_zero_qualitative_missing_and_school_gpa() {
        let mut report = GradeReport {
            items: vec![
                GradeItem {
                    name: "合成零分".into(),
                    score: "0".into(),
                    credits: "0".into(),
                    semester_name: "合成学期".into(),
                    ..Default::default()
                },
                GradeItem {
                    name: "合成文字".into(),
                    score: "优秀".into(),
                    ..Default::default()
                },
                GradeItem {
                    name: "合成未公布".into(),
                    ..Default::default()
                },
            ],
            ..Default::default()
        };
        let text = grade_report_text(&report);
        assert!(text.contains("成绩：0  学分：0"));
        assert!(text.contains("成绩：优秀"));
        assert!(text.contains("成绩：未公布"));
        assert!(text.contains("合成学期"));
        assert!(!text.contains("平均学分绩点"));
        report.average_grade_point = "0".into();
        assert!(grade_report_text(&report).contains("平均学分绩点：0"));
    }
}
