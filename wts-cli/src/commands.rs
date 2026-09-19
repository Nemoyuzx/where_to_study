use chrono::{Datelike, NaiveDate};
use where_to_study_lib::academic::{self, GradeRequest};
use where_to_study_lib::config::today_in_app_tz;
use where_to_study_lib::course_deletions::{self, CourseDeletion};
use where_to_study_lib::error::{ServiceError, ServiceResult};
#[cfg(test)]
use where_to_study_lib::models::Course;
use where_to_study_lib::models::{ClassroomsRequest, ScheduleRequest, ScheduleResponse};
use zeroize::{Zeroize, Zeroizing};

use crate::credentials;
use crate::output;

const TERM_VALIDITY_WEEKS: i64 = 26;

pub struct EventsOptions {
    pub search: Option<String>,
    pub event_type: Option<String>,
    pub category: Option<String>,
    pub source: String,
    pub include_ended: bool,
    pub favorites_only: bool,
    pub favorite: Option<String>,
    pub unfavorite: Option<String>,
    pub json: bool,
}

/// Parse a yyyy-MM-dd date, defaulting to today (Shanghai timezone).
fn parse_date(value: Option<&str>) -> ServiceResult<NaiveDate> {
    match value {
        Some(text) => NaiveDate::parse_from_str(text.trim(), "%Y-%m-%d")
            .map_err(|_| ServiceError::new(format!("日期格式不正确：{text}，请使用 yyyy-MM-dd。"))),
        None => Ok(today_in_app_tz()),
    }
}

/// Load credentials, requiring both account and password.
fn require_credentials() -> ServiceResult<where_to_study_lib::credential_store::Credentials> {
    let Some(credentials) = credentials::load()? else {
        return Err(ServiceError::new(
            "尚未保存教务账号。请先运行：where-to-study-cli login",
        ));
    };
    if credentials.account.trim().is_empty() || credentials.password.is_empty() {
        return Err(ServiceError::new(
            "已保存的凭据不完整。请重新运行：where-to-study-cli login",
        ));
    }
    Ok(credentials)
}

fn schedule_request(
    mut credentials: where_to_study_lib::credential_store::Credentials,
) -> ScheduleRequest {
    ScheduleRequest {
        account: Some(std::mem::take(&mut credentials.account)),
        password: Some(std::mem::take(&mut credentials.password)),
        term_id: None,
        term_start_date: None,
        automatic_term_detection_enabled: None,
    }
}

pub fn login(account: Option<String>, use_academic_password: bool) -> ServiceResult<()> {
    let entered_account = match account {
        Some(value) => Zeroizing::new(value),
        None => credentials::prompt_account()?,
    };
    let account = entered_account.trim().to_string();
    if account.is_empty() {
        return Err(ServiceError::new("请输入教务账号。"));
    }
    let mut existing = credentials::load()?;
    let mut entered = credentials::prompt_password("教务密码（同账号留空则保留已保存密码）：")?;
    let password = if entered.is_empty() {
        let Some(saved) = existing.as_mut().filter(|credentials| {
            credentials.account.trim() == account && !credentials.password.is_empty()
        }) else {
            return Err(ServiceError::new("请输入教务密码。"));
        };
        std::mem::take(&mut saved.password)
    } else {
        std::mem::take(&mut *entered)
    };
    let mut cloud = if use_academic_password {
        Zeroizing::new(String::new())
    } else {
        credentials::prompt_password(
            "教学云平台密码（选填；同账号留空保持，未设置时使用教务密码）：",
        )?
    };
    credentials::save(
        &account,
        password,
        std::mem::take(&mut *cloud),
        use_academic_password,
    )?;
    where_to_study_lib::assignments::clear_cache();
    where_to_study_lib::classrooms::clear_session();
    println!(
        "已保存教务凭据到本地配置文件：{}",
        credentials::storage_description()?
    );
    Ok(())
}

pub fn logout() -> ServiceResult<()> {
    credentials::clear()?;
    where_to_study_lib::assignments::clear_cache();
    where_to_study_lib::classrooms::clear_session();
    println!("已清除 CLI 本地配置文件中的教务凭据。");
    Ok(())
}

fn saved_deletions(
    credentials: &where_to_study_lib::credential_store::Credentials,
) -> ServiceResult<Vec<CourseDeletion>> {
    if !where_to_study_lib::scoped_cache::is_valid_account_scope(&credentials.account_scope) {
        return Ok(vec![]);
    }
    course_deletions::load(
        &credentials::deletion_path(&credentials.account_scope)?,
        &credentials.account_scope,
    )
}

async fn raw_schedule(
    credentials: &where_to_study_lib::credential_store::Credentials,
) -> ServiceResult<ScheduleResponse> {
    let mut request = schedule_request(credentials.clone());
    let result = where_to_study_lib::schedule::fetch_schedule(&request).await;
    if let Some(password) = request.password.as_mut() {
        password.zeroize();
    }
    let response = result?;
    ensure_credentials_current(credentials)?;
    Ok(response)
}

async fn effective_schedule(
    credentials: &where_to_study_lib::credential_store::Credentials,
) -> ServiceResult<ScheduleResponse> {
    let raw = raw_schedule(credentials).await?;
    Ok(course_deletions::apply(
        &raw,
        &saved_deletions(credentials)?,
    ))
}

pub async fn courses(json: bool) -> ServiceResult<()> {
    let mut schedule = effective_schedule(&require_credentials()?).await?;
    schedule.courses.retain(|course| !academic::is_exam(course));
    if json {
        print_json(&schedule)?;
    } else {
        println!(
            "学期 {} · {} 条课程安排",
            schedule.term_id,
            schedule.courses.len()
        );
        for course in schedule.courses {
            println!(
                "{}  {}  {}  周{} {}  {}",
                course.id,
                course.name,
                course.teacher,
                course.weekday,
                course.time_range,
                course.room
            );
        }
    }
    Ok(())
}

pub async fn delete_course(
    course_id: String,
    date: Option<String>,
    yes: bool,
) -> ServiceResult<()> {
    let credentials = require_credentials()?;
    let path = credentials::deletion_path(&credentials.account_scope)?;
    let raw = raw_schedule(&credentials).await?;
    let rule = CourseDeletion::create(&raw, &course_id, date.as_deref())?;
    let mut records = saved_deletions(&credentials)?;
    let scope = rule.date.as_deref().unwrap_or("本学期整门课程");
    if !yes {
        use std::io::Write;
        print!("仅从本地课表删除「{}」({scope})？学校课程、作业和已导出日历保持不变；可恢复。输入 y 确认：", rule.name);
        std::io::stdout()
            .flush()
            .map_err(|_| ServiceError::new("无法显示确认提示。"))?;
        let mut confirmation = String::new();
        std::io::stdin()
            .read_line(&mut confirmation)
            .map_err(|_| ServiceError::new("无法读取确认输入。"))?;
        if !confirmation.trim().eq_ignore_ascii_case("y") {
            println!("已取消。");
            return Ok(());
        }
    }
    if !records.iter().any(|existing| existing.id == rule.id) {
        records.push(rule.clone());
    }
    course_deletions::save(&path, &credentials.account_scope, &records)?;
    println!(
        "已删除本地课程「{}」。恢复：where-to-study-cli course-restore {}",
        rule.name, rule.id
    );
    Ok(())
}

pub fn course_deletions(json: bool) -> ServiceResult<()> {
    let records = saved_deletions(&require_credentials()?)?;
    if json {
        print_json(&records)?;
    } else {
        for rule in records {
            println!(
                "{}  {}  {}  {}  {}",
                rule.id,
                rule.term_id,
                rule.name,
                rule.teacher,
                rule.date.as_deref().unwrap_or("本学期整门课程")
            );
        }
    }
    Ok(())
}

pub fn restore_course(deletion_id: String) -> ServiceResult<()> {
    let credentials = require_credentials()?;
    let mut records = saved_deletions(&credentials)?;
    let before = records.len();
    records.retain(|record| record.id != deletion_id);
    if before == records.len() {
        return Err(ServiceError::new("当前账号中没有该课程删除记录。"));
    }
    course_deletions::save(
        &credentials::deletion_path(&credentials.account_scope)?,
        &credentials.account_scope,
        &records,
    )?;
    println!("已恢复该课程删除记录，下次查询课表时生效。");
    Ok(())
}

pub async fn assignments(date: Option<String>, json: bool) -> ServiceResult<()> {
    let credential_revision = where_to_study_lib::assignments::credential_revision();
    let credentials = require_credentials()?;
    let request = where_to_study_lib::models::AssignmentsRequest {
        date: parse_date(date.as_deref())?.to_string(),
    };
    let response = where_to_study_lib::assignments::fetch_assignments(
        &request,
        &credentials.account,
        credentials.assignment_password(),
        &credentials.account_scope,
        credential_revision,
    )
    .await?;
    ensure_assignment_credentials_current(&credentials)?;
    if json {
        print_json(&response)?;
    } else {
        println!("{} · {} 项作业", response.date, response.items.len());
        for item in response.items {
            println!(
                "{}  {}  {}",
                item.deadline,
                item.course_name.as_deref().unwrap_or(""),
                item.title
            );
        }
    }
    Ok(())
}

pub async fn assignment_list(json: bool) -> ServiceResult<()> {
    let revision = where_to_study_lib::assignments::credential_revision();
    let credentials = require_credentials()?;
    let items = where_to_study_lib::assignments::fetch_assignment_list(
        &credentials.account,
        credentials.assignment_password(),
        &credentials.account_scope,
        revision,
        true,
    )
    .await?;
    ensure_assignment_credentials_current(&credentials)?;
    if json {
        print_json(&serde_json::json!({"source": "https://ucloud.bupt.edu.cn", "items": items}))?;
    } else {
        println!("教学云 · {} 项课程作业 DDL", items.len());
        for item in items {
            println!(
                "{}  {}  {}  {}",
                item.deadline,
                item.course_name.as_deref().unwrap_or("课程未标注"),
                item.title,
                item.status.as_deref().unwrap_or("")
            );
        }
    }
    Ok(())
}

fn ensure_assignment_credentials_current(
    expected: &where_to_study_lib::credential_store::Credentials,
) -> ServiceResult<()> {
    let current = require_credentials()?;
    if !academic_identity_matches(&current, expected)
        || current.teaching_cloud_password != expected.teaching_cloud_password
    {
        return Err(ServiceError::new("查询期间凭据已改变，请重新查询。"));
    }
    Ok(())
}

fn print_json(value: &impl serde::Serialize) -> ServiceResult<()> {
    println!(
        "{}",
        serde_json::to_string_pretty(value).map_err(|_| ServiceError::new("无法序列化输出。"))?
    );
    Ok(())
}

fn ensure_credentials_current(
    expected: &where_to_study_lib::credential_store::Credentials,
) -> ServiceResult<()> {
    let current = require_credentials()?;
    if !academic_identity_matches(&current, expected) {
        return Err(ServiceError::new("查询期间凭据已改变，请重新查询。"));
    }
    Ok(())
}

fn academic_identity_matches(
    left: &where_to_study_lib::credential_store::Credentials,
    right: &where_to_study_lib::credential_store::Credentials,
) -> bool {
    left.account == right.account
        && left.password == right.password
        && left.account_scope == right.account_scope
}

pub async fn grade_terms(json: bool) -> ServiceResult<()> {
    let credentials = require_credentials()?;
    let terms = academic::fetch_terms(&credentials.account, &credentials.password).await?;
    ensure_credentials_current(&credentials)?;
    if json {
        return print_json(&terms);
    }
    println!("当前学期：{}", terms.current_term_id);
    for term in terms.terms {
        println!("{}  {}", term.id, term.name);
    }
    Ok(())
}

pub fn grade_request(
    term: Option<String>,
    all_terms: bool,
    records: &str,
) -> ServiceResult<GradeRequest> {
    let record_type = match records {
        "best" => "1",
        "first" => "0",
        "all" => "",
        _ => return Err(ServiceError::new("成绩记录类型应为 best、first 或 all。")),
    };
    if !all_terms && term.as_ref().is_some_and(|value| value.trim().is_empty()) {
        return Err(ServiceError::new(
            "学期不能为空；查询全部学期请使用 --all-terms。",
        ));
    }
    Ok(GradeRequest {
        term_id: if all_terms { Some(String::new()) } else { term },
        record_type: Some(record_type.into()),
    })
}

pub async fn grades(
    term: Option<String>,
    all_terms: bool,
    records: String,
    json: bool,
) -> ServiceResult<()> {
    let query = grade_request(term, all_terms, &records)?;
    let credentials = require_credentials()?;
    let report =
        academic::fetch_grades(&credentials.account, &credentials.password, &query).await?;
    ensure_credentials_current(&credentials)?;
    if json {
        return print_json(&report);
    }
    println!("{}", output::grade_report_text(&report));
    Ok(())
}

pub async fn exams(json: bool) -> ServiceResult<()> {
    let credentials = require_credentials()?;
    let schedule = raw_schedule(&credentials).await?;
    ensure_credentials_current(&credentials)?;
    if json {
        return print_json(&schedule.exam_schedule);
    }
    println!("{}", output::exam_status(&schedule));
    if let Some(exams) = schedule.exam_schedule {
        for exam in exams.items {
            println!(
                "考试 · {}  {}  {}  {}",
                exam.name,
                if exam.date.is_empty() {
                    "日期待定"
                } else {
                    &exam.date
                },
                if exam.start_time.is_empty() {
                    format!("时间待定 · {}", exam.time_text)
                } else {
                    format!("{}-{}", exam.start_time, exam.end_time)
                },
                exam.room
            );
        }
    }
    Ok(())
}

pub async fn schedule(date: Option<String>, json: bool) -> ServiceResult<()> {
    let credentials = require_credentials()?;
    let target_date = parse_date(date.as_deref())?;
    let schedule = effective_schedule(&credentials).await?;
    let week = schedule_week_for_query(&schedule, target_date, false)?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&day_schedule_json(&schedule, target_date, week))
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_schedule_day(&schedule, target_date, week)
}

pub async fn week(date: Option<String>, json: bool) -> ServiceResult<()> {
    let credentials = require_credentials()?;
    let target_date = parse_date(date.as_deref())?;
    let schedule = effective_schedule(&credentials).await?;
    let week = schedule_week_for_query(&schedule, target_date, true)?;
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&week_schedule_json(&schedule, target_date, week))
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_schedule_week(&schedule, target_date, week)
}

pub async fn classrooms(
    campus: String,
    buildings: Vec<String>,
    slots: Option<String>,
    json: bool,
) -> ServiceResult<()> {
    let mut credentials = require_credentials()?;
    let target_date = today_in_app_tz();
    let campus_id = if campus.trim().is_empty() {
        "01".to_string()
    } else {
        campus.trim().to_string()
    };
    let request = ClassroomsRequest {
        account: Some(std::mem::take(&mut credentials.account)),
        password: Some(std::mem::take(&mut credentials.password)),
        campus_id: Some(campus_id.clone()),
        target_date: Some(target_date.format("%Y-%m-%d").to_string()),
    };
    let cache = where_to_study_lib::classrooms::fetch_all_classrooms(&request).await?;
    let campus_data = cache
        .campuses
        .iter()
        .find(|campus| campus.campus_id == campus_id)
        .ok_or_else(|| ServiceError::new(format!("响应中未找到校区 {campus_id} 的数据。")))?;

    // Parse slot filter: "1-3,5" -> [1,2,3,5]
    let slot_filter: Option<Vec<usize>> = match slots {
        Some(text) if !text.trim().is_empty() => Some(parse_slot_filter(&text)?),
        _ => None,
    };

    let mut rooms: Vec<&where_to_study_lib::models::ClassroomStatus> = campus_data
        .rooms
        .iter()
        .filter(|room| buildings.is_empty() || buildings.iter().any(|b| room.building == b.trim()))
        .filter(|room| {
            slot_filter
                .as_ref()
                .is_none_or(|slots| slots.iter().all(|slot| room.available_slots.contains(slot)))
        })
        .collect();
    rooms.sort_by(|a, b| a.building.cmp(&b.building).then(a.room.cmp(&b.room)));

    if json {
        let payload = serde_json::json!({
            "campus_id": campus_data.campus_id,
            "campus_name": campus_data.campus_name,
            "target_date": campus_data.target_date,
            "fetched_at": campus_data.fetched_at,
            "provider": campus_data.provider,
            "rooms": rooms.iter().map(|room| serde_json::json!({
                "id": room.id,
                "building": room.building,
                "room": room.room,
                "name": room.name,
                "size": room.size,
                "available_slots": room.available_slots,
            })).collect::<Vec<_>>(),
        });
        println!(
            "{}",
            serde_json::to_string_pretty(&payload)
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_classrooms(campus_data, &rooms, slot_filter.as_deref())
}

pub async fn holidays(year: Option<i32>, json: bool) -> ServiceResult<()> {
    let year = year.unwrap_or_else(|| today_in_app_tz().year());
    where_to_study_lib::holidays::validate_fetch_year(year)
        .map_err(|e| ServiceError::new(e.message))?;
    let response = match where_to_study_lib::holidays::fetch_remote(year).await {
        Ok(response) => response,
        Err(_) => where_to_study_lib::holidays::offline_response(year)?,
    };
    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&response)
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_holidays(&response)
}

pub async fn shuttle(json: bool) -> ServiceResult<()> {
    let response = where_to_study_lib::public_queries::fetch_shuttle_bus().await?;
    let today = where_to_study_lib::public_queries::shuttle_today(&response);
    if json {
        let payload = serde_json::json!({
            "schema_version": response.schema_version,
            "generated_at": response.generated_at,
            "service_status": response.status,
            "source": response.source,
            "stats": response.stats,
            "today": today,
        });
        println!(
            "{}",
            serde_json::to_string_pretty(&payload)
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    output::print_shuttle(&response, &today)
}

fn event_matches_identifier(
    item: &where_to_study_lib::models::ImportantEventItem,
    identifier: &str,
) -> bool {
    item.id == identifier || where_to_study_lib::public_queries::favorite_key(item) == identifier
}

pub async fn events(options: EventsOptions) -> ServiceResult<()> {
    use where_to_study_lib::public_queries::{ImportantEventFilter, ImportantEventSourceFilter};

    let mut favorites = where_to_study_lib::public_queries::load_favorite_events()?;
    let mut action = None;
    if let Some(identifier) = options.unfavorite.as_deref() {
        let Some(index) = favorites
            .iter()
            .position(|item| event_matches_identifier(item, identifier))
        else {
            return Err(ServiceError::new(format!(
                "未找到收藏：{identifier}。请使用 events --favorites-only 查看 favorite_key。"
            )));
        };
        favorites.remove(index);
        where_to_study_lib::public_queries::save_favorite_events(&favorites)?;
        action = Some(format!("已取消收藏 {identifier}"));
    }

    let remote = where_to_study_lib::public_queries::fetch_important_events().await;
    let (live, fetched_at, source, used_backup, remote_error) = match remote {
        Ok(response) => (
            response.items,
            Some(response.fetched_at),
            Some(response.source),
            response.used_backup,
            None,
        ),
        Err(error) if !favorites.is_empty() => (
            Vec::new(),
            None,
            Some("本地收藏快照".to_string()),
            false,
            Some(error.message),
        ),
        Err(error) => return Err(error),
    };
    let combined =
        where_to_study_lib::public_queries::merge_live_and_favorite_events(&live, &favorites);

    if let Some(identifier) = options.favorite.as_deref() {
        let matches: Vec<_> = combined
            .iter()
            .filter(|item| event_matches_identifier(item, identifier))
            .collect();
        let item = match matches.as_slice() {
            [] => {
                return Err(ServiceError::new(format!(
                    "查询结果中未找到 {identifier}。请先运行 events 获取 favorite_key。"
                )))
            }
            [item] => *item,
            _ => {
                return Err(ServiceError::new(format!(
                    "ID {identifier} 不唯一，请使用输出中的 favorite_key。"
                )))
            }
        };
        if favorites.iter().any(|favorite| {
            where_to_study_lib::public_queries::favorite_key(favorite)
                == where_to_study_lib::public_queries::favorite_key(item)
        }) {
            action = Some(format!(
                "已经收藏 {}",
                where_to_study_lib::public_queries::favorite_key(item)
            ));
        } else {
            favorites.push(item.clone());
            where_to_study_lib::public_queries::save_favorite_events(&favorites)?;
            action = Some(format!(
                "已收藏 {}",
                where_to_study_lib::public_queries::favorite_key(item)
            ));
        }
    }

    let source_filter = match options.source.as_str() {
        "public" => ImportantEventSourceFilter::Public,
        "school" => ImportantEventSourceFilter::School,
        _ => ImportantEventSourceFilter::All,
    };
    let filter = ImportantEventFilter {
        query: options.search.unwrap_or_default(),
        event_type: options.event_type,
        category: options.category,
        source: source_filter,
        include_ended: options.include_ended,
        favorites_only: options.favorites_only,
    };
    let combined =
        where_to_study_lib::public_queries::merge_live_and_favorite_events(&live, &favorites);
    let items = where_to_study_lib::public_queries::filter_important_events(
        &combined,
        &favorites,
        &filter,
        chrono::Utc::now(),
    );

    if options.json {
        let favorite_keys: std::collections::HashSet<String> = favorites
            .iter()
            .map(where_to_study_lib::public_queries::favorite_key)
            .collect();
        let items: Vec<_> = items
            .iter()
            .map(|item| {
                serde_json::json!({
                    "favorite": favorite_keys.contains(&where_to_study_lib::public_queries::favorite_key(item)),
                    "favorite_key": where_to_study_lib::public_queries::favorite_key(item),
                    "event": item,
                })
            })
            .collect();
        let payload = serde_json::json!({
            "fetched_at": fetched_at,
            "source": source,
            "used_backup": used_backup,
            "remote_error": remote_error,
            "action": action,
            "filters": {
                "search": filter.query,
                "event_type": filter.event_type,
                "category": filter.category,
                "source": options.source,
                "include_ended": filter.include_ended,
                "favorites_only": filter.favorites_only,
            },
            "items": items,
        });
        println!(
            "{}",
            serde_json::to_string_pretty(&payload)
                .map_err(|error| ServiceError::new(format!("无法序列化输出：{error}")))?
        );
        return Ok(());
    }
    if let Some(action) = action {
        println!("{action}");
    }
    if let Some(error) = remote_error.as_deref() {
        eprintln!("提示：远程数据不可用，正在显示本地收藏快照：{error}");
    }
    output::print_important_events(
        &items,
        &favorites,
        source.as_deref().unwrap_or("未知来源"),
        fetched_at.as_deref(),
    )
}

fn week_schedule_json(
    schedule: &ScheduleResponse,
    date: NaiveDate,
    week: i64,
) -> serde_json::Value {
    let monday = date
        .checked_sub_days(chrono::Days::new(
            (date.weekday().num_days_from_monday()) as u64,
        ))
        .unwrap_or(date);
    let days: Vec<serde_json::Value> = (0..7)
        .map(|offset| {
            let day = monday + chrono::Duration::days(offset);
            let courses = courses_on_day(schedule, day, week);
            serde_json::json!({
                "date": day.format("%Y-%m-%d").to_string(),
                "courses": courses,
            })
        })
        .collect();
    serde_json::json!({
        "term_id": schedule.term_id,
        "week_number": (week > 0).then_some(week),
        "exam_schedule": schedule.exam_schedule,
        "days": days,
    })
}

fn day_schedule_json(schedule: &ScheduleResponse, date: NaiveDate, week: i64) -> serde_json::Value {
    serde_json::json!({
        "term_id": schedule.term_id,
        "term_start_date": schedule.term_start_date,
        "fetched_at": schedule.fetched_at,
        "date": date.format("%Y-%m-%d").to_string(),
        "week_number": (week > 0).then_some(week),
        "exam_schedule": schedule.exam_schedule,
        "courses": courses_on_day(schedule, date, week),
    })
}

fn schedule_term_start(schedule: &ScheduleResponse) -> ServiceResult<NaiveDate> {
    NaiveDate::parse_from_str(&schedule.term_start_date, "%Y-%m-%d")
        .map_err(|_| ServiceError::new("课表返回的学期开始日期格式不正确。"))
}

fn schedule_week_number(schedule: &ScheduleResponse, date: NaiveDate) -> ServiceResult<i64> {
    let term_start = schedule_term_start(schedule)?;
    let term_end =
        term_start + chrono::Duration::weeks(TERM_VALIDITY_WEEKS) - chrono::Duration::days(1);
    if date < term_start || date > term_end {
        return Err(ServiceError::new(format!(
            "目标日期不在当前课表学期 {} 的有效范围内（{} 至 {}）。",
            schedule.term_id, term_start, term_end
        )));
    }
    Ok((date - term_start).num_days().div_euclid(7) + 1)
}

fn schedule_week_for_query(
    schedule: &ScheduleResponse,
    date: NaiveDate,
    weekly: bool,
) -> ServiceResult<i64> {
    schedule_week_number(schedule, date).or_else(|error| {
        let start = schedule_term_start(schedule)?;
        let first = if weekly {
            date - chrono::Duration::days(i64::from(date.weekday().num_days_from_monday()))
        } else {
            date
        };
        let present = (0..if weekly { 7 } else { 1 }).any(|offset| {
            schedule.courses.iter().any(|course| {
                academic::is_exam(course)
                    && academic::occurs_on(course, first + chrono::Duration::days(offset), start)
            })
        });
        if present {
            Ok(0)
        } else {
            Err(error)
        }
    })
}

fn courses_on_day(
    schedule: &ScheduleResponse,
    date: NaiveDate,
    _week: i64,
) -> Vec<serde_json::Value> {
    let courses = output::day_courses(schedule, date);
    courses
        .iter()
        .map(|course| {
            serde_json::json!({
                "id": course.id,
                "name": course.name,
                "teacher": course.teacher,
                "room": course.room,
                "time_range": course.time_range,
                "start_slot": (!academic::is_exam(course)).then_some(course.start_slot + 1),
                "end_slot": (!academic::is_exam(course)).then_some(course.end_slot + 1),
                "event_kind": course.event_kind,
                "event_date": course.event_date,
                "start_time": course.start_time,
                "end_time": course.end_time,
            })
        })
        .collect()
}

fn parse_slot_filter(text: &str) -> ServiceResult<Vec<usize>> {
    let mut selected = Vec::new();
    for part in text.split(',') {
        let part = part.trim();
        if part.is_empty() {
            continue;
        }
        if let Some((left, right)) = part.split_once('-') {
            let start: usize = left
                .trim()
                .parse()
                .map_err(|_| ServiceError::new(format!("节次格式不正确：{part}")))?;
            let end: usize = right
                .trim()
                .parse()
                .map_err(|_| ServiceError::new(format!("节次格式不正确：{part}")))?;
            if start == 0 || end < start || end > 14 {
                return Err(ServiceError::new(format!("节次范围不正确：{part}")));
            }
            selected.extend(start - 1..end);
        } else {
            let slot: usize = part
                .parse()
                .map_err(|_| ServiceError::new(format!("节次格式不正确：{part}")))?;
            if slot == 0 || slot > 14 {
                return Err(ServiceError::new(format!("节次范围不正确：{part}")));
            }
            selected.push(slot - 1);
        }
    }
    selected.sort_unstable();
    selected.dedup();
    if selected.is_empty() {
        return Err(ServiceError::new("节次筛选不能为空。"));
    }
    Ok(selected)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn academic_password_changes_invalidate_even_with_unchanged_cloud_password() {
        let first = where_to_study_lib::credential_store::Credentials {
            account: "synthetic-account".into(),
            password: "fixture-old".into(),
            teaching_cloud_password: Some("fixture-cloud".into()),
            account_scope: "fixture-scope".into(),
        };
        let mut second = first.clone();
        second.password = "fixture-new".into();
        assert_eq!(
            first.teaching_cloud_password,
            second.teaching_cloud_password
        );
        assert!(!academic_identity_matches(&first, &second));
    }

    #[test]
    fn grade_requests_keep_current_and_all_semesters_distinct() {
        assert_eq!(grade_request(None, false, "best").unwrap().term_id, None);
        assert_eq!(
            grade_request(None, true, "best").unwrap().term_id,
            Some(String::new())
        );
        assert_eq!(
            grade_request(None, false, "first")
                .unwrap()
                .record_type
                .as_deref(),
            Some("0")
        );
        assert_eq!(
            grade_request(None, false, "all")
                .unwrap()
                .record_type
                .as_deref(),
            Some("")
        );
        assert!(grade_request(Some(String::new()), false, "best").is_err());
    }

    #[test]
    fn late_exams_use_actual_date_without_fake_slots_or_teaching_week() {
        let mut schedule = fixture_schedule();
        schedule.courses.push(Course {
            id: "synthetic-exam".into(),
            name: "合成晚间考试".into(),
            event_kind: Some("exam".into()),
            event_date: Some("2026-09-01".into()),
            start_time: Some("22:10".into()),
            end_time: Some("23:00".into()),
            ..Default::default()
        });
        let date = NaiveDate::from_ymd_opt(2026, 9, 1).unwrap();
        assert_eq!(schedule_week_for_query(&schedule, date, false).unwrap(), 0);
        let json = day_schedule_json(&schedule, date, 0);
        assert!(json["week_number"].is_null());
        assert_eq!(json["courses"][0]["event_date"], "2026-09-01");
        assert_eq!(json["courses"][0]["start_time"], "22:10");
        assert!(json["courses"][0]["start_slot"].is_null());
        assert!(courses_on_day(&schedule, date + chrono::Duration::days(7), 0).is_empty());
        schedule.courses[0].start_time = None;
        schedule.courses[0].end_time = None;
        assert_eq!(output::course_time(&schedule.courses[0]), "全天 · 时间待定");
    }

    #[test]
    fn slot_filter_parses_ranges_and_singles() {
        assert_eq!(parse_slot_filter("1-3,5").unwrap(), vec![0, 1, 2, 4]);
        assert_eq!(parse_slot_filter("1,2,3").unwrap(), vec![0, 1, 2]);
        assert_eq!(
            parse_slot_filter("1-14").unwrap(),
            (0..14).collect::<Vec<_>>()
        );
    }

    #[test]
    fn slot_filter_dedups_and_sorts() {
        assert_eq!(parse_slot_filter("5,3,5,1-2").unwrap(), vec![0, 1, 2, 4]);
        assert_eq!(parse_slot_filter("1-1").unwrap(), vec![0]);
    }

    #[test]
    fn slot_filter_rejects_invalid() {
        assert!(parse_slot_filter("0").is_err());
        assert!(parse_slot_filter("15").is_err());
        assert!(parse_slot_filter("3-2").is_err());
        assert!(parse_slot_filter("abc").is_err());
        assert!(parse_slot_filter("1-15").is_err());
        assert!(parse_slot_filter(",").is_err());
    }

    #[test]
    fn parse_date_defaults_to_today() {
        assert!(parse_date(None).is_ok());
        assert!(parse_date(Some("2026-09-01")).is_ok());
        assert!(parse_date(Some("2026-13-01")).is_err());
        assert!(parse_date(Some("2026/09/01")).is_err());
    }

    fn fixture_schedule() -> ScheduleResponse {
        ScheduleResponse {
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            fetched_at: String::new(),
            courses: Vec::new(),
            exam_schedule: None,
        }
    }

    #[test]
    fn schedule_json_does_not_expose_removed_exam_week_semantics() {
        let date = NaiveDate::from_ymd_opt(2026, 3, 2).unwrap();
        let schedule = ScheduleResponse {
            term_id: "2025-2026-2".to_string(),
            term_start_date: "2026-03-02".to_string(),
            fetched_at: String::new(),
            courses: vec![Course {
                source_course_id: String::new(),
                id: "legacy".to_string(),
                name: "旧缓存课程".to_string(),
                teacher: String::new(),
                room: String::new(),
                week_text: "1".to_string(),
                week_numbers: vec![1],
                exam_week_numbers: vec![1],
                weekday: 1,
                start_slot: 0,
                end_slot: 1,
                section_text: "1-2节".to_string(),
                time_range: "08:00-09:35".to_string(),
                ..Default::default()
            }],
            exam_schedule: None,
        };
        let courses = courses_on_day(&schedule, date, 1);
        assert_eq!(courses.len(), 1);
        assert!(courses[0].get("is_exam").is_none());
    }

    #[test]
    fn schedule_week_rejects_dates_outside_returned_term() {
        let schedule = fixture_schedule();
        assert!(
            schedule_week_number(&schedule, NaiveDate::from_ymd_opt(2026, 3, 1).unwrap()).is_err()
        );
        assert_eq!(
            schedule_week_number(&schedule, NaiveDate::from_ymd_opt(2026, 3, 2).unwrap()).unwrap(),
            1
        );
        assert_eq!(
            schedule_week_number(&schedule, NaiveDate::from_ymd_opt(2026, 8, 30).unwrap()).unwrap(),
            26
        );
        assert!(
            schedule_week_number(&schedule, NaiveDate::from_ymd_opt(2026, 9, 1).unwrap()).is_err()
        );
    }
}
