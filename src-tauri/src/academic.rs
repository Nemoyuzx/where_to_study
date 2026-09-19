//! Read-only student academic queries. Credentials and private responses never go
//! through a third-party proxy; grades are not persisted by this service.
use std::collections::HashSet;
use std::sync::LazyLock;

use chrono::{Datelike, Duration, NaiveDate};
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::classrooms::{
    read_sjd_json_response, session_epoch, sjd_headers, sjd_http_client, with_sjd_session_at,
};
use crate::config::{now_in_app_tz as now_iso_string, SJD_REST_CLASSROOM_PAGE_URL, SLOT_TIMES};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{Course, ScheduleResponse};
use crate::session_cache::SessionEpoch;

const BASE: &str = "https://jwglweixin.bupt.edu.cn/bjyddx";
const MAX_BYTES: usize = 4 * 1024 * 1024;
const MAX_ITEMS: usize = 5_000;
const MAX_FIELD: usize = 2_048;

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AcademicTerm {
    pub id: String,
    pub name: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct GradeTerms {
    pub current_term_id: String,
    pub terms: Vec<AcademicTerm>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct GradeItem {
    pub id: String,
    pub name: String,
    pub score: String,
    pub credits: String,
    pub course_code: String,
    pub course_attribute: String,
    pub course_nature: String,
    pub exam_nature: String,
    pub semester_name: String,
    pub grade_status: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct GradeReport {
    pub term_id: String,
    pub record_type: String,
    pub fetched_at: String,
    pub average_grade_point: String,
    pub items: Vec<GradeItem>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct GradeRequest {
    /// None means the school's current term; Some("") means all terms.
    pub term_id: Option<String>,
    pub record_type: Option<String>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExamArrangement {
    pub id: String,
    pub name: String,
    pub date: String,
    pub start_time: String,
    pub end_time: String,
    pub room: String,
    pub seat: String,
    pub time_text: String,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ExamSchedule {
    pub term_id: String,
    pub account_key: String,
    pub fetched_at: String,
    pub status: String,
    pub message: String,
    pub items: Vec<ExamArrangement>,
}

pub fn account_key(account: &str) -> String {
    format!("sha256:{:x}", Sha256::digest(account.trim().as_bytes()))
}

fn stable_id(parts: &[&str]) -> String {
    // Length-prefix fields so separators in source text cannot collide.
    let mut hash = Sha256::new();
    for part in parts {
        hash.update((part.len() as u64).to_be_bytes());
        hash.update(part.as_bytes());
    }
    format!("{:x}", hash.finalize())
}

fn text(value: Option<&Value>) -> ServiceResult<String> {
    let result = match value {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(s)) => s.trim().to_owned(),
        Some(Value::Number(n)) => n.to_string(),
        _ => return Err(ServiceError::new("教务数据字段格式不正确。")),
    };
    if result.len() > MAX_FIELD {
        return Err(ServiceError::new("教务数据字段过长。"));
    }
    Ok(result)
}

fn rows(payload: &Value) -> ServiceResult<&Vec<Value>> {
    if !(payload.get("code").and_then(Value::as_i64) == Some(1)
        || payload.get("code").and_then(Value::as_str) == Some("1"))
    {
        return Err(ServiceError::new("教务查询失败，请检查登录状态后重试。"));
    }
    let values = payload
        .get("data")
        .and_then(Value::as_array)
        .ok_or_else(|| ServiceError::new("教务查询返回了无法识别的数据结构。"))?;
    if values.len() > MAX_ITEMS {
        return Err(ServiceError::new("教务查询条目过多。"));
    }
    Ok(values)
}

pub fn parse_current_term(payload: &Value) -> ServiceResult<String> {
    let list = rows(payload)?;
    let term = text(list.first().and_then(|x| x.get("semesterId")))?;
    validate_term(&term, false)?;
    Ok(term)
}

fn validate_term(term: &str, allow_empty: bool) -> ServiceResult<()> {
    if (allow_empty && term.is_empty())
        || (!term.is_empty()
            && term.len() <= 64
            && term
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_')))
    {
        return Ok(());
    }
    Err(ServiceError::new("请选择学校返回的有效学期。"))
}

pub fn parse_terms(payload: &Value) -> ServiceResult<Vec<AcademicTerm>> {
    let mut seen = HashSet::new();
    let mut result = Vec::new();
    for row in rows(payload)? {
        let id = text(row.get("semesterId"))?;
        validate_term(&id, false)?;
        if !seen.insert(id.clone()) {
            continue;
        }
        let name = text(row.get("semesterName"))?;
        result.push(AcademicTerm {
            name: if name.is_empty() { id.clone() } else { name },
            id,
        });
    }
    Ok(result)
}

pub fn parse_grades(payload: &Value, term: &str, record_type: &str) -> ServiceResult<GradeReport> {
    validate_term(term, true)?;
    if !matches!(record_type, "" | "0" | "1") {
        return Err(ServiceError::new("成绩记录类型不正确。"));
    }
    let data = rows(payload)?;
    if data.len() > 1 {
        return Err(ServiceError::new("成绩汇总格式不正确。"));
    }
    let mut result = GradeReport {
        term_id: term.into(),
        record_type: record_type.into(),
        fetched_at: now_iso_string(),
        ..Default::default()
    };
    let Some(summary) = data.first() else {
        return Ok(result);
    };
    result.average_grade_point = text(summary.get("pjxfjd"))?;
    let achievements = summary
        .get("achievement")
        .and_then(Value::as_array)
        .ok_or_else(|| ServiceError::new("成绩列表格式不正确。"))?;
    if achievements.len() > MAX_ITEMS {
        return Err(ServiceError::new("成绩条目过多。"));
    }
    let mut seen = HashSet::new();
    for row in achievements {
        let mut item = GradeItem {
            name: text(row.get("courseName"))?,
            score: text(row.get("fraction"))?,
            credits: text(row.get("credit"))?,
            course_code: text(row.get("kcbh"))?,
            course_attribute: text(row.get("curriculumAttributes"))?,
            course_nature: text(row.get("courseNature"))?,
            exam_nature: text(row.get("examinationNature"))?,
            semester_name: text(row.get("curSemesterName"))?,
            grade_status: text(row.get("cjbs"))?,
            ..Default::default()
        };
        if item.name.is_empty() {
            return Err(ServiceError::new("成绩课程名称缺失。"));
        }
        let record_id = text(row.get("cj0708id"))?;
        let id = if record_id.is_empty() {
            stable_id(&[
                &item.name,
                &item.course_code,
                &item.score,
                &item.credits,
                &item.course_attribute,
                &item.course_nature,
                &item.exam_nature,
                &item.semester_name,
                &item.grade_status,
            ])
        } else {
            stable_id(&[&record_id])
        };
        item.id = format!("grade:{id}");
        if seen.insert(item.id.clone()) {
            result.items.push(item);
        }
    }
    Ok(result)
}

pub fn minutes(value: &str) -> Option<i64> {
    let (h, m) = value.split_once(':')?;
    if h.is_empty()
        || h.len() > 2
        || m.len() != 2
        || !h.bytes().chain(m.bytes()).all(|b| b.is_ascii_digit())
    {
        return None;
    }
    let h = h.parse::<i64>().ok()?;
    let m = m.parse::<i64>().ok()?;
    ((h < 24 && m < 60) || (h == 24 && m == 0)).then_some(h * 60 + m)
}

pub(crate) fn iso_date(value: &str) -> Option<NaiveDate> {
    let parsed = NaiveDate::parse_from_str(value, "%Y-%m-%d").ok()?;
    (parsed.format("%Y-%m-%d").to_string() == value && (1900..=2200).contains(&parsed.year()))
        .then_some(parsed)
}

pub fn parse_exam_time(value: &str) -> (String, String, String) {
    static DATE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"([12][0-9]{3})[-/年.]([0-9]{1,2})[-/月.]([0-9]{1,2})(?:日)?").unwrap()
    });
    let normalized = value.replace('：', ":");
    let mut dates = HashSet::new();
    for c in DATE.captures_iter(&normalized) {
        let full = c.get(0).expect("full date match");
        if normalized[..full.start()]
            .chars()
            .last()
            .is_some_and(|x| x.is_ascii_digit())
            || normalized[full.end()..]
                .chars()
                .next()
                .is_some_and(|x| x.is_ascii_digit())
        {
            return (String::new(), String::new(), String::new());
        }
        let date = NaiveDate::from_ymd_opt(
            c[1].parse().unwrap_or(0),
            c[2].parse().unwrap_or(0),
            c[3].parse().unwrap_or(0),
        );
        let Some(date) = date else {
            return (String::new(), String::new(), String::new());
        };
        let date = date.format("%Y-%m-%d").to_string();
        if iso_date(&date).is_none() {
            return (String::new(), String::new(), String::new());
        }
        dates.insert(date);
    }
    if dates.len() != 1 {
        return (String::new(), String::new(), String::new());
    }
    let date = dates.into_iter().next().unwrap_or_default();
    // Look-ahead is unavailable in Rust regex. Find times independently so the
    // separator consumed by one match is not needed by the next match.
    static CLOCK: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}))?").unwrap());
    let candidates: Vec<_> = CLOCK.captures_iter(&normalized).collect();
    if candidates.len() != 2 {
        return (date, String::new(), String::new());
    }
    let mut values = Vec::new();
    for c in &candidates {
        if c.get(3).is_some_and(|s| s.as_str() != "00") {
            return (date, String::new(), String::new());
        }
        let full = c.get(0).expect("full regex match");
        let start = full.start();
        let end = full.end();
        if normalized[..start]
            .chars()
            .last()
            .is_some_and(|x| x.is_ascii_digit())
            || normalized[end..]
                .chars()
                .next()
                .is_some_and(|x| x.is_ascii_digit())
        {
            return (date, String::new(), String::new());
        }
        values.push(format!(
            "{:02}:{}",
            c[1].parse::<u32>().unwrap_or(99),
            &c[2]
        ));
    }
    let separator =
        &normalized[candidates[0].get(0).unwrap().end()..candidates[1].get(0).unwrap().start()];
    let separator = DATE.replace_all(separator, "");
    if separator.trim().is_empty()
        || !separator
            .chars()
            .all(|c| c.is_whitespace() || matches!(c, '-' | '–' | '—' | '~' | '～' | '至' | '到'))
    {
        return (date, String::new(), String::new());
    }
    if values.len() == 2 {
        if let (Some(start), Some(end)) = (minutes(&values[0]), minutes(&values[1])) {
            if start < end && start < 1440 {
                return (date, values[0].clone(), values[1].clone());
            }
        }
    }
    (date, String::new(), String::new())
}

pub fn parse_exams(payload: &Value, term: &str, key: &str) -> ServiceResult<ExamSchedule> {
    let mut items = Vec::new();
    let mut seen = HashSet::new();
    for row in rows(payload)? {
        let name = text(row.get("courseName"))?;
        if name.is_empty() {
            return Err(ServiceError::new("考试课程名称缺失。"));
        }
        let room = text(row.get("examinationPlace"))?;
        // The verified school response has no seat field. Keep the normalized
        // field empty until an actual upstream seat contract is established.
        let seat = String::new();
        let mut time_text = text(row.get("time"))?;
        let mut auxiliary_time = None;
        if time_text.is_empty() {
            let fields = [
                text(row.get("ksqssj"))?,
                text(row.get("zssj1"))?,
                text(row.get("zssj2"))?,
            ];
            if iso_date(&fields[0]).is_some() && fields[1].len() == 5 && fields[2].len() == 5 {
                if let (Some(start), Some(end)) = (minutes(&fields[1]), minutes(&fields[2])) {
                    if start < end && start < 1440 {
                        auxiliary_time =
                            Some((fields[0].clone(), fields[1].clone(), fields[2].clone()));
                    }
                }
            }
            // Preserve the auxiliary text while using the separate fields
            // as the clock range, without inventing a display delimiter.
            time_text = fields.join(" ").trim().into();
        }
        let (date, start_time, end_time) =
            auxiliary_time.unwrap_or_else(|| parse_exam_time(&time_text));
        let id = format!(
            "exam:{}",
            stable_id(&[
                &name,
                &date,
                &start_time,
                &end_time,
                &room,
                &seat,
                &time_text
            ])
        );
        if seen.insert(id.clone()) {
            items.push(ExamArrangement {
                id,
                name,
                date,
                start_time,
                end_time,
                room,
                seat,
                time_text,
            });
        }
    }
    let unknown = items
        .iter()
        .filter(|e| e.date.is_empty() || e.start_time.is_empty())
        .count();
    Ok(ExamSchedule {
        term_id: term.into(),
        account_key: key.into(),
        fetched_at: now_iso_string(),
        status: "fresh".into(),
        message: if unknown > 0 {
            format!("{unknown} 项考试日期或时间待定，请查看原始安排。")
        } else {
            String::new()
        },
        items,
    })
}

async fn request(path: &str, token: &str, query: &[(&str, &str)]) -> ServiceResult<Value> {
    // Only callers in this module select a fixed endpoint, never a user URL.
    if !matches!(
        path,
        "/currentTerm" | "/semesterList" | "/student/termGPA" | "/student/examinationArrangement"
    ) {
        return Err(ServiceError::new("不支持的教务查询。"));
    }
    let response = sjd_http_client(25)?
        .post(format!("{BASE}{path}"))
        .headers(sjd_headers(Some(token), SJD_REST_CLASSROOM_PAGE_URL))
        .query(query)
        .send()
        .await
        .map_err(|_| ServiceError::new("无法连接学校教务查询服务。"))?;
    read_sjd_json_response(response, MAX_BYTES, "教务查询").await
}

pub fn fetch_terms<'a>(
    account: &'a str,
    password: &'a str,
) -> impl std::future::Future<Output = ServiceResult<GradeTerms>> + 'a {
    fetch_terms_at(session_epoch(), account, password)
}

pub async fn fetch_terms_at(
    epoch: SessionEpoch,
    account: &str,
    password: &str,
) -> ServiceResult<GradeTerms> {
    with_sjd_session_at(epoch, account, password, |token| async move {
        fetch_terms_with_token(&token).await
    })
    .await
}

async fn fetch_terms_with_token(token: &str) -> ServiceResult<GradeTerms> {
    let current_term_id = parse_current_term(&request("/currentTerm", token, &[]).await?)?;
    let mut terms = parse_terms(&request("/semesterList", token, &[]).await?)?;
    if !terms.iter().any(|t| t.id == current_term_id) {
        terms.insert(
            0,
            AcademicTerm {
                id: current_term_id.clone(),
                name: current_term_id.clone(),
            },
        );
    }
    Ok(GradeTerms {
        current_term_id,
        terms,
    })
}

pub fn fetch_grades<'a>(
    account: &'a str,
    password: &'a str,
    query: &'a GradeRequest,
) -> impl std::future::Future<Output = ServiceResult<GradeReport>> + 'a {
    fetch_grades_at(session_epoch(), account, password, query)
}

pub async fn fetch_grades_at(
    epoch: SessionEpoch,
    account: &str,
    password: &str,
    query: &GradeRequest,
) -> ServiceResult<GradeReport> {
    let record_type = query.record_type.as_deref().unwrap_or("1");
    if !matches!(record_type, "" | "0" | "1") {
        return Err(ServiceError::new("成绩记录类型不正确。"));
    }
    with_sjd_session_at(epoch, account, password, |token| async move {
        fetch_grades_with_token(&token, query, record_type).await
    })
    .await
}

async fn fetch_grades_with_token(
    token: &str,
    query: &GradeRequest,
    record_type: &str,
) -> ServiceResult<GradeReport> {
    let term = match &query.term_id {
        Some(term) => term.trim().to_string(),
        None => parse_current_term(&request("/currentTerm", token, &[]).await?)?,
    };
    validate_term(&term, true)?;
    let payload = request(
        "/student/termGPA",
        token,
        &[("semester", &term), ("type", record_type)],
    )
    .await?;
    parse_grades(&payload, &term, record_type)
}

pub fn fetch_exams<'a>(
    account: &'a str,
    password: &'a str,
    term: Option<&'a str>,
) -> impl std::future::Future<Output = ServiceResult<ExamSchedule>> + 'a {
    fetch_exams_at(session_epoch(), account, password, term)
}

pub async fn fetch_exams_at(
    epoch: SessionEpoch,
    account: &str,
    password: &str,
    term: Option<&str>,
) -> ServiceResult<ExamSchedule> {
    with_sjd_session_at(epoch, account, password, |token| async move {
        let term = match term {
            Some(term) => term.to_string(),
            None => parse_current_term(&request("/currentTerm", &token, &[]).await?)?,
        };
        validate_term(&term, false)?;
        fetch_exams_using_token(&token, &term, &account_key(account)).await
    })
    .await
}

pub(crate) async fn fetch_exams_using_token(
    token: &str,
    term: &str,
    key: &str,
) -> ServiceResult<ExamSchedule> {
    let payload = request(
        "/student/examinationArrangement",
        token,
        &[("semester", term)],
    )
    .await?;
    parse_exams(&payload, term, key)
}

pub async fn fetch_exams_with_token(token: &str, term: &str, key: &str) -> ExamSchedule {
    match request(
        "/student/examinationArrangement",
        token,
        &[("semester", term)],
    )
    .await
    .and_then(|p| parse_exams(&p, term, key))
    {
        Ok(value) => value,
        Err(_) => ExamSchedule {
            term_id: term.into(),
            account_key: key.into(),
            fetched_at: now_iso_string(),
            status: "failed".into(),
            message: "考试安排同步失败，普通课程仍可查看。".into(),
            items: vec![],
        },
    }
}

pub fn is_exam(course: &Course) -> bool {
    course.event_kind.as_deref() == Some("exam")
}

pub fn course_minutes(course: &Course) -> Option<(i64, i64)> {
    if is_exam(course) {
        let start = minutes(course.start_time.as_deref()?)?;
        let end = minutes(course.end_time.as_deref()?)?;
        return (start < end && start < 1440).then_some((start, end));
    }
    // Ordinary lessons use the verified period indices. Only examinations
    // override the standard timetable with exact clock times.
    let start = minutes(SLOT_TIMES.get(course.start_slot)?.0)?;
    let end = minutes(SLOT_TIMES.get(course.end_slot)?.1)?;
    (start < end && start < 1440).then_some((start, end))
}

pub fn occurs_on(course: &Course, date: NaiveDate, term_start: NaiveDate) -> bool {
    if is_exam(course) {
        return course.event_date.as_deref().and_then(iso_date) == Some(date);
    }
    date >= term_start
        && course.weekday == i64::from(date.weekday().number_from_monday())
        && course
            .week_numbers
            .contains(&((date - term_start).num_days().div_euclid(7) + 1))
}

pub fn busy_slots(course: &Course) -> Vec<usize> {
    let Some((start, end)) = course_minutes(course) else {
        return vec![];
    };
    SLOT_TIMES
        .iter()
        .enumerate()
        .filter_map(|(index, (a, b))| (start < minutes(b)? && minutes(a)? < end).then_some(index))
        .collect()
}

pub fn effective_schedule(schedule: &ScheduleResponse) -> ScheduleResponse {
    let mut output = schedule.clone();
    output.courses.retain(|c| !is_exam(c));
    let Some(exams) = &schedule.exam_schedule else {
        return output;
    };
    if !matches!(exams.status.as_str(), "fresh" | "stale")
        || exams.account_key.trim().is_empty()
        || exams.term_id != schedule.term_id
    {
        return output;
    }
    let term_start = iso_date(&schedule.term_start_date);
    let mut projected = Vec::new();
    for exam in &exams.items {
        let Some(date) = iso_date(&exam.date) else {
            continue;
        };
        let mut course = Course {
            id: exam.id.clone(),
            name: exam.name.clone(),
            room: exam.room.clone(),
            weekday: i64::from(date.weekday().number_from_monday()),
            event_kind: Some("exam".into()),
            event_date: Some(exam.date.clone()),
            start_time: (!exam.start_time.is_empty()).then(|| exam.start_time.clone()),
            end_time: (!exam.end_time.is_empty()).then(|| exam.end_time.clone()),
            time_range: if exam.start_time.is_empty() {
                "时间待定".into()
            } else {
                format!("{}-{}", exam.start_time, exam.end_time)
            },
            section_text: if exam.seat.is_empty() {
                "考试".into()
            } else {
                format!("考试 · 座位 {}", exam.seat)
            },
            ..Default::default()
        };
        let slots = busy_slots(&course);
        course.start_slot = slots.first().copied().unwrap_or(0);
        course.end_slot = slots.last().copied().unwrap_or(0);
        // Dated exams deliberately have no teaching weeks: every consumer must
        // use event_date, including dates beyond the normal teaching calendar.
        projected.push(course);
    }
    if let Some(term_start) = term_start {
        for course in &mut output.courses {
            let range = course_minutes(course);
            let weekday = course.weekday;
            course.week_numbers.retain(|week| {
                let date = week
                    .checked_sub(1)
                    .and_then(|v| v.checked_mul(7))
                    .and_then(|v| {
                        weekday
                            .checked_sub(1)
                            .and_then(|offset| v.checked_add(offset))
                    })
                    .and_then(Duration::try_days)
                    .and_then(|d| term_start.checked_add_signed(d));
                !projected.iter().any(|exam| {
                    let Some(date) = date else {
                        return false;
                    };
                    if exam.event_date.as_deref().and_then(iso_date) != Some(date) {
                        return false;
                    }
                    match (range, course_minutes(exam)) {
                        (Some((a, b)), Some((c, d))) => a < d && c < b,
                        _ => false,
                    }
                })
            });
        }
        output.courses.retain(|c| !c.week_numbers.is_empty());
    }
    output.courses.extend(projected);
    output
}

pub fn merge_exam_fallback(current: &mut ScheduleResponse, previous: Option<&ScheduleResponse>) {
    let Some(failed) = current
        .exam_schedule
        .as_mut()
        .filter(|e| e.status == "failed")
    else {
        return;
    };
    if failed.term_id != current.term_id {
        return;
    }
    if let Some(old) = previous
        .filter(|s| s.term_id == current.term_id)
        .and_then(|s| s.exam_schedule.as_ref())
        .filter(|old| {
            matches!(old.status.as_str(), "fresh" | "stale")
                && old.account_key == failed.account_key
                && !old.account_key.is_empty()
                && old.term_id == failed.term_id
        })
    {
        failed.items = old.items.clone();
        failed.fetched_at = old.fetched_at.clone();
        failed.status = "stale".into();
        failed.message = "考试安排同步失败，正在显示此前缓存，请以学校最新安排为准。".into();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn lesson() -> Course {
        Course {
            id: "synthetic-course".into(),
            name: "合成课程".into(),
            weekday: 1,
            week_numbers: vec![1, 2],
            start_slot: 0,
            end_slot: 1,
            time_range: "08:00-09:35".into(),
            ..Default::default()
        }
    }

    fn exam(id: &str, date: &str, start: &str, end: &str) -> ExamArrangement {
        ExamArrangement {
            id: id.into(),
            name: "合成考试".into(),
            date: date.into(),
            start_time: start.into(),
            end_time: end.into(),
            ..Default::default()
        }
    }

    fn snapshot(items: Vec<ExamArrangement>) -> ScheduleResponse {
        ScheduleResponse {
            term_id: "2026-2027-1".into(),
            term_start_date: "2026-09-07".into(),
            courses: vec![lesson()],
            exam_schedule: Some(ExamSchedule {
                term_id: "2026-2027-1".into(),
                account_key: account_key("synthetic-a"),
                fetched_at: "2026-09-07T00:00:00+08:00".into(),
                status: "fresh".into(),
                items,
                ..Default::default()
            }),
            ..Default::default()
        }
    }

    #[test]
    fn grades_preserve_zero_text_and_verified_semester_metadata() {
        let payload = json!({"code": 1, "data": [{"pjxfjd": "3.50", "achievement": [
            {"courseName":"合成零分", "fraction":0, "credit":0, "curSemesterName":"示例学期", "cjbs":"学校原标记", "cj0708id":"synthetic-one"},
            {"courseName":"合成文字", "fraction":"合格", "credit":2, "kcbh":"DEMO", "curriculumAttributes":"任选", "courseNature":"实践", "examinationNature":"正常考试"},
            {"courseName":"合成未公布"}
        ]}]});
        let result = parse_grades(&payload, "", "").unwrap();
        assert_eq!(result.average_grade_point, "3.50");
        assert_eq!(
            (&result.items[0].score, &result.items[0].credits),
            (&"0".to_owned(), &"0".to_owned())
        );
        assert_eq!(result.items[0].semester_name, "示例学期");
        assert_eq!(result.items[0].grade_status, "学校原标记");
        assert_eq!(result.items[1].score, "合格");
        assert_eq!(result.items[1].credits, "2");
        assert!(result.items[2].score.is_empty());
        assert!(!result.items[0].id.contains("synthetic-one"));
    }

    #[test]
    fn grade_identity_is_stable_under_reordering_and_duplicate_rows() {
        let first = json!({"courseName":"课程", "fraction":"合格", "cj0708id":"one"});
        let second = json!({"courseName":"课程", "fraction":"合格", "cj0708id":"two"});
        let read =
            |rows| parse_grades(&json!({"code":1,"data":[{"achievement":rows}]}), "", "1").unwrap();
        let a = read(vec![first.clone(), second.clone(), first.clone()]);
        let b = read(vec![second, first]);
        assert_eq!(a.items.len(), 2);
        assert_eq!(a.items[0].id, b.items[1].id);
        assert_eq!(a.items[1].id, b.items[0].id);
        let fallback = read(vec![
            json!({"courseName":"课程", "curSemesterName":"学期一"}),
            json!({"courseName":"课程", "curSemesterName":"学期二"}),
        ]);
        assert_ne!(fallback.items[0].id, fallback.items[1].id);
    }

    #[test]
    fn academic_parsers_reject_failure_malformed_and_oversized_data() {
        for bad in [
            json!({"code":false,"data":[]}),
            json!({"code":0,"data":[]}),
            json!({"code":1}),
            json!({"code":1,"data":{}}),
            json!("<html>login</html>"),
        ] {
            assert!(parse_grades(&bad, "", "1").is_err());
            assert!(parse_exams(&bad, "term", "owner").is_err());
        }
        for bad in [
            json!({"code":1,"data":[{}]}),
            json!({"code":1,"data":[{"achievement":{}}]}),
            json!({"code":1,"data":[{"achievement":[]}, {"achievement":[]}]}),
            json!({"code":1,"data":[{"achievement":[{"courseName":"x", "fraction":true}]}]}),
        ] {
            assert!(parse_grades(&bad, "", "1").is_err());
        }
        assert!(parse_grades(&json!({"code":1,"data":[{"achievement":vec![json!({"courseName":"x"}); MAX_ITEMS + 1]}]}), "", "1").is_err());
        assert!(parse_exams(
            &json!({"code":1,"data":[{"courseName":"x".repeat(MAX_FIELD + 1)}]}),
            "term",
            "owner"
        )
        .is_err());
        assert!(parse_grades(&json!({"code":1,"data":[]}), "", "invalid").is_err());
        assert!(parse_grades(&json!({"code":"1","data":[]}), "", "1")
            .unwrap()
            .items
            .is_empty());
    }

    #[test]
    fn terms_use_school_ids_and_never_turn_malformed_into_empty() {
        let terms = parse_terms(&json!({"code":1,"data":[{"semesterId":"2026-2027-1","semesterName":"秋季"}, {"semesterId":"2026-2027-1"}, {"semesterId":"2025-2026-2"}]})).unwrap();
        assert_eq!(terms.len(), 2);
        assert_eq!(terms[0].name, "秋季");
        assert_eq!(terms[1].name, "2025-2026-2");
        assert!(parse_terms(&json!({"code":1,"data":[{}]})).is_err());
        assert!(parse_current_term(&json!({"code":1,"data":[]})).is_err());
        assert!(
            parse_current_term(&json!({"code":1,"data":[{"semesterId":"a&xs0101id=b"}]})).is_err()
        );
        assert_eq!(
            parse_current_term(&json!({"code":"1","data":[{"semesterId":"2026-2027-1"}]})).unwrap(),
            "2026-2027-1"
        );
    }

    #[test]
    fn exam_dates_and_clock_ranges_are_strict_and_support_midnight_end() {
        for source in [
            "2026-09-07 09:20-11:00",
            "2026年9月7日 9:20～11:00",
            "2026/9/7 09:20:00 至 11:00:00",
            "2026-09-07 09:20 - 2026-09-07 11:00",
        ] {
            assert_eq!(
                parse_exam_time(source),
                ("2026-09-07".into(), "09:20".into(), "11:00".into()),
                "{source}"
            );
        }
        assert_eq!(
            parse_exam_time("2026-09-07 23:00-24:00"),
            ("2026-09-07".into(), "23:00".into(), "24:00".into())
        );
        for source in [
            "2026-09-07 11:00-09:00",
            "2026-09-07 09:60-11:00",
            "2026-09-07 09:00:30-11:00",
            "2026-09-07 24:00-24:00",
            "2026-09-07 09:00 11:00",
            "2026-09-07 上午",
            "2026-09-07 109:00-11:00",
        ] {
            let (date, start, end) = parse_exam_time(source);
            assert_eq!(date, "2026-09-07", "{source}");
            assert!(start.is_empty() && end.is_empty(), "{source}");
        }
        for source in [
            "另行通知",
            "2026-02-30 09:00-11:00",
            "2026-09-07/2026-09-08 09:00-11:00",
            "2026-09-071 09:00-11:00",
        ] {
            assert_eq!(
                parse_exam_time(source),
                (String::new(), String::new(), String::new()),
                "{source}"
            );
        }
    }

    #[test]
    fn exams_use_verified_place_and_preserve_unknown_original_time() {
        let payload = json!({"code":1,"data":[{"courseName":"合成考试", "examinationPlace":"示例考场", "examAddress":"禁止猜字段", "time":"另行通知", "ksqssj":"2026-09-07 09:00-11:00"}]});
        let result = parse_exams(&payload, "2026-2027-1", "owner").unwrap();
        assert_eq!(result.items[0].room, "示例考场");
        assert_eq!(result.items[0].time_text, "另行通知");
        assert!(result.items[0].date.is_empty());
        assert!(result.message.contains("待定"));
        assert_eq!(
            result.items[0].id,
            parse_exams(&payload, "2026-2027-1", "owner").unwrap().items[0].id
        );
    }

    #[test]
    fn projection_overrides_one_occurrence_without_mutating_raw_or_exam_peers() {
        let raw = snapshot(vec![
            exam("one", "2026-09-07", "09:20", "10:20"),
            exam("two", "2026-09-07", "09:40", "10:50"),
        ]);
        let original = serde_json::to_value(&raw).unwrap();
        let effective = effective_schedule(&raw);
        assert_eq!(effective.courses[0].week_numbers, vec![2]);
        assert_eq!(effective.courses.iter().filter(|c| is_exam(c)).count(), 2);
        assert!(effective
            .courses
            .iter()
            .filter(|c| is_exam(c))
            .all(|c| c.week_numbers.is_empty()));
        assert_eq!(serde_json::to_value(&raw).unwrap(), original);
        assert_eq!(
            serde_json::to_value(effective_schedule(&effective)).unwrap(),
            serde_json::to_value(&effective).unwrap()
        );
    }

    #[test]
    fn separate_exam_date_and_clock_fields_form_a_range_without_overriding_primary() {
        let payload = json!({"code":1,"data":[
            {"courseName":"合成辅助考试","time":"","ksqssj":"2026-09-07","zssj1":"09:20","zssj2":"11:00"},
            {"courseName":"主字段待定","time":"另行通知","ksqssj":"2026-09-07","zssj1":"09:20","zssj2":"11:00"},
            {"courseName":"非法跨日","ksqssj":"2026-09-07","zssj1":"23:00","zssj2":"01:00"},
            {"courseName":"非法日期","ksqssj":"2026-02-30","zssj1":"09:20","zssj2":"11:00"},
            {"courseName":"非法分钟","ksqssj":"2026-09-07","zssj1":"09:60","zssj2":"11:00"}
        ]});
        let items = parse_exams(&payload, "2026-2027-1", "owner").unwrap().items;
        assert_eq!(
            (&items[0].date, &items[0].start_time, &items[0].end_time),
            (
                &"2026-09-07".to_owned(),
                &"09:20".to_owned(),
                &"11:00".to_owned()
            )
        );
        assert_eq!(items[0].time_text, "2026-09-07 09:20 11:00");
        assert_eq!(items[1].time_text, "另行通知");
        assert!(items[1].date.is_empty());
        assert!(items[2].start_time.is_empty());
        assert!(items[3].date.is_empty());
        assert!(items[4].start_time.is_empty());
    }

    #[test]
    fn touching_and_pending_exams_keep_courses_and_outside_term_dates_stay_explicit() {
        let raw = snapshot(vec![
            exam("touch", "2026-09-07", "09:35", "10:20"),
            exam("pending", "2026-09-07", "", ""),
            exam("undated", "", "09:00", "10:00"),
            exam("outside", "2026-12-21", "09:00", "10:00"),
        ]);
        let effective = effective_schedule(&raw);
        assert_eq!(effective.courses[0].week_numbers, vec![1, 2]);
        assert!(!effective.courses.iter().any(|c| c.id == "undated"));
        assert_eq!(
            course_minutes(
                effective
                    .courses
                    .iter()
                    .find(|c| c.id == "pending")
                    .unwrap()
            ),
            None
        );
        let future = effective
            .courses
            .iter()
            .find(|c| c.id == "outside")
            .unwrap();
        assert!(occurs_on(
            future,
            iso_date("2026-12-21").unwrap(),
            iso_date(&raw.term_start_date).unwrap()
        ));
        assert!(!occurs_on(
            future,
            iso_date("2026-12-22").unwrap(),
            iso_date(&raw.term_start_date).unwrap()
        ));
    }

    #[test]
    fn projection_rejects_failed_unowned_and_wrong_term_exams() {
        for (status, owner, term) in [
            ("failed", "owner", "2026-2027-1"),
            ("fresh", "", "2026-2027-1"),
            ("fresh", "owner", "old-term"),
        ] {
            let mut raw = snapshot(vec![exam("one", "2026-09-07", "09:00", "10:00")]);
            let exams = raw.exam_schedule.as_mut().unwrap();
            exams.status = status.into();
            exams.account_key = owner.into();
            exams.term_id = term.into();
            let effective = effective_schedule(&raw);
            assert_eq!(effective.courses.len(), 1);
            assert_eq!(effective.courses[0].week_numbers, vec![1, 2]);
        }
    }

    #[test]
    fn failed_exam_refresh_only_reuses_same_account_and_semester() {
        let old = snapshot(vec![exam("one", "2026-09-07", "09:00", "10:00")]);
        let mut fresh = snapshot(vec![]);
        merge_exam_fallback(&mut fresh, Some(&old));
        assert!(fresh.exam_schedule.unwrap().items.is_empty());
        for mismatch in ["none", "account", "exam-term", "parent-term"] {
            let mut current = snapshot(vec![]);
            current.exam_schedule.as_mut().unwrap().status = "failed".into();
            let mut previous = old.clone();
            match mismatch {
                "account" => {
                    previous.exam_schedule.as_mut().unwrap().account_key = account_key("b")
                }
                "exam-term" => previous.exam_schedule.as_mut().unwrap().term_id = "old".into(),
                "parent-term" => previous.term_id = "old".into(),
                _ => {}
            }
            merge_exam_fallback(&mut current, Some(&previous));
            let result = current.exam_schedule.unwrap();
            assert_eq!(result.status == "stale", mismatch == "none");
            assert_eq!(result.items.len(), usize::from(mismatch == "none"));
        }
    }

    #[test]
    fn minute_boundaries_reject_bad_ranges_without_panicking() {
        assert_eq!(minutes("24:00"), Some(1440));
        for value in ["24:01", "25:00", "-1:00", "09:0", "09:000", "x:00"] {
            assert_eq!(minutes(value), None);
        }
        let mut course = lesson();
        course.time_range.clear();
        course.start_slot = 4;
        course.end_slot = 0;
        assert_eq!(course_minutes(&course), None);
        let mut raw = snapshot(vec![exam("exam", "2026-09-07", "09:00", "10:00")]);
        raw.courses[0].weekday = i64::MIN;
        raw.courses[0].week_numbers = vec![i64::MIN, i64::MAX];
        let _ = effective_schedule(&raw);
        let mut course = lesson();
        course.week_numbers = vec![0];
        assert!(!occurs_on(
            &course,
            iso_date("2026-08-31").unwrap(),
            iso_date("2026-09-07").unwrap()
        ));
    }

    #[test]
    fn ordinary_course_slots_remain_authoritative_over_display_times() {
        let mut course = lesson();
        course.time_range = "22:00-23:00".into();
        course.start_time = Some("22:00".into());
        course.end_time = Some("23:00".into());
        assert_eq!(course_minutes(&course), Some((480, 575)));
        assert_eq!(busy_slots(&course), vec![0, 1]);
        course.event_kind = Some("exam".into());
        assert_eq!(course_minutes(&course), Some((1320, 1380)));
        course.event_kind = None;
        course.start_slot = usize::MAX;
        assert_eq!(course_minutes(&course), None);
    }
}
