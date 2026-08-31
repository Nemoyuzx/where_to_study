use chrono::{Datelike, Duration, NaiveDate};
use where_to_study_lib::error::ServiceResult;
use where_to_study_lib::models::{ClassroomsResponse, Course, HolidaysResponse, ScheduleResponse};
use where_to_study_lib::public_queries::{TodayShuttlePresentation, TodayShuttleRoute};

const WEEKDAY_LABELS: [&str; 7] = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];

fn day_courses(schedule: &ScheduleResponse, date: NaiveDate, week: i64) -> Vec<&Course> {
    let weekday = date.weekday().num_days_from_monday() as i64 + 1;
    let mut courses: Vec<&Course> = schedule
        .courses
        .iter()
        .filter(|course| course.weekday == weekday && course.week_numbers.contains(&week))
        .collect();
    courses.sort_by(|a, b| a.start_slot.cmp(&b.start_slot).then(a.name.cmp(&b.name)));
    courses
}

fn slot_label(index: usize) -> String {
    format!("第 {} 节", index + 1)
}

pub fn print_schedule_day(
    schedule: &ScheduleResponse,
    date: NaiveDate,
    week: i64,
) -> ServiceResult<()> {
    let weekday = WEEKDAY_LABELS[date.weekday().num_days_from_monday() as usize];
    let courses = day_courses(schedule, date, week);
    println!(
        "{} {} · 公历第 {} 周 · 教学第 {} 周 · {} 门课",
        date.format("%Y-%m-%d"),
        weekday,
        date.iso_week().week(),
        week,
        courses.len()
    );
    println!(
        "学期 {}（第一周周一 {}）",
        schedule.term_id, schedule.term_start_date
    );
    if courses.is_empty() {
        println!("今天没有课程。");
        return Ok(());
    }
    for course in &courses {
        let time = if course.time_range.is_empty() {
            format!(
                "{}-{}",
                slot_label(course.start_slot),
                slot_label(course.end_slot)
            )
        } else {
            course.time_range.clone()
        };
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
        println!("  {}  {}  {}  {}", course.name, time, room, teacher);
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
        "公历第 {} 周 · 教学第 {} 周（{} 起）",
        monday.iso_week().week(),
        week,
        monday.format("%Y-%m-%d")
    );
    for offset in 0..7 {
        let day = monday + Duration::days(offset);
        let courses = day_courses(schedule, day, week);
        let weekday = WEEKDAY_LABELS[offset as usize];
        if courses.is_empty() {
            println!("  {} {}：无课", day.format("%m-%d"), weekday);
            continue;
        }
        println!("  {} {}：", day.format("%m-%d"), weekday);
        for course in &courses {
            let time = if course.time_range.is_empty() {
                format!(
                    "{}-{}",
                    slot_label(course.start_slot),
                    slot_label(course.end_slot)
                )
            } else {
                course.time_range.clone()
            };
            let room = if course.room.is_empty() {
                "地点未标注"
            } else {
                &course.room
            };
            println!("    {}  {}  {}", course.name, time, room);
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
