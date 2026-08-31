use std::collections::HashSet;
use std::env;
use std::fs;
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use chrono::{DateTime, NaiveDate, NaiveTime, Utc};
use chrono_tz::Asia::Shanghai;
use reqwest::Url;
use serde::{Deserialize, Serialize};

use crate::error::{ServiceError, ServiceResult};
use crate::models::{
    ImportantEventItem, ImportantEventsResponse, ShuttleBusNotice, ShuttleBusResponse,
    ShuttleBusSchedule, ShuttleBusStop,
};

const SHUTTLE_URL: &str = "https://where-to-study.cn/api/shuttle-bus";
const CONTEST_PRIMARY_URL: &str = "https://nemoyuzx.github.io/contest-ddl/data/competitions.json";
const CONTEST_BACKUP_URL: &str = "https://where-to-study.cn/api/contest-events";
const SCHOOL_NOTICES_URL: &str = "https://where-to-study.cn/api/contest-notices";
const SHUTTLE_HOST: &str = "where-to-study.cn";
const CONTEST_PRIMARY_HOST: &str = "nemoyuzx.github.io";
const SCHOOL_SOURCE_HOST: &str = "ucloud.bupt.edu.cn";
const SHUTTLE_SOURCE_HOST: &str = "hq.bupt.edu.cn";
const MAX_SHUTTLE_BYTES: usize = 512 * 1024;
const MAX_EVENT_BYTES: usize = 2 * 1024 * 1024;
const MAX_EVENT_ITEMS: usize = 5_000;
const CACHE_TTL: Duration = Duration::from_secs(5 * 60);
const USER_AGENT: &str = concat!("WhereToStudyTerminal/", env!("CARGO_PKG_VERSION"));
const FAVORITES_VERSION: u32 = 1;
const FAVORITES_FILE: &str = "favorite-events.json";

pub const IMPORTANT_EVENT_TYPES: [&str; 6] = [
    "competition",
    "conference",
    "journal_special_issue",
    "hackathon",
    "summer_camp",
    "pre_admission",
];

const WEEKDAYS: [&str; 7] = [
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
];

struct CacheEntry<T> {
    fetched_at: Instant,
    response: T,
}

static SHUTTLE_CACHE: OnceLock<Mutex<Option<CacheEntry<ShuttleBusResponse>>>> = OnceLock::new();
static EVENT_CACHE: OnceLock<Mutex<Option<CacheEntry<ImportantEventsResponse>>>> = OnceLock::new();

fn shuttle_cache() -> &'static Mutex<Option<CacheEntry<ShuttleBusResponse>>> {
    SHUTTLE_CACHE.get_or_init(|| Mutex::new(None))
}

fn event_cache() -> &'static Mutex<Option<CacheEntry<ImportantEventsResponse>>> {
    EVENT_CACHE.get_or_init(|| Mutex::new(None))
}

fn cached<T: Clone>(cache: &Mutex<Option<CacheEntry<T>>>) -> Option<T> {
    cache
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .as_ref()
        .filter(|entry| entry.fetched_at.elapsed() < CACHE_TTL)
        .map(|entry| entry.response.clone())
}

fn save_cached<T: Clone>(cache: &Mutex<Option<CacheEntry<T>>>, response: &T) {
    *cache
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(CacheEntry {
        fetched_at: Instant::now(),
        response: response.clone(),
    });
}

fn fixed_url(value: &str, host: &str) -> ServiceResult<Url> {
    let url = Url::parse(value)
        .map_err(|error| ServiceError::new(format!("公共查询接口地址无效：{error}")))?;
    if url.scheme() != "https"
        || url.host_str() != Some(host)
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
    {
        return Err(ServiceError::new("公共查询接口地址不受信任。"));
    }
    Ok(url)
}

fn trusted_https_url(value: Option<String>) -> Option<String> {
    let value = value?.trim().to_string();
    Url::parse(&value)
        .ok()
        .filter(|url| {
            url.scheme() == "https"
                && url.host_str().is_some()
                && url.username().is_empty()
                && url.password().is_none()
        })
        .map(|_| value)
}

fn trusted_source_url(value: &str, host: &str) -> bool {
    Url::parse(value).is_ok_and(|url| {
        url.scheme() == "https"
            && url.host_str() == Some(host)
            && url.username().is_empty()
            && url.password().is_none()
    })
}

fn public_client() -> ServiceResult<reqwest::Client> {
    reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(18))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|error| ServiceError::new(format!("无法创建公共查询请求：{error}")))
}

async fn fetch_limited(url: Url, maximum: usize, label: &str) -> ServiceResult<Vec<u8>> {
    let response = public_client()?
        .get(url)
        .header(reqwest::header::ACCEPT, "application/json")
        .header(reqwest::header::USER_AGENT, USER_AGENT)
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法获取{label}：{error}")))?;
    if response.status().is_redirection() {
        return Err(ServiceError::new(format!(
            "{label}接口返回了不受信任的重定向。"
        )));
    }
    let mut response = response
        .error_for_status()
        .map_err(|error| ServiceError::new(format!("{label}接口返回错误：{error}")))?;
    if response
        .content_length()
        .is_some_and(|length| length > maximum as u64)
    {
        return Err(ServiceError::new(format!("{label}响应超过安全上限。")));
    }
    let mut body = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| ServiceError::new(format!("无法读取{label}：{error}")))?
    {
        if body.len().saturating_add(chunk.len()) > maximum {
            return Err(ServiceError::new(format!("{label}响应超过安全上限。")));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

fn valid_text(value: &str, maximum: usize) -> bool {
    let value = value.trim();
    !value.is_empty() && value.chars().count() <= maximum
}

fn validate_shuttle_schedule(schedule: &ShuttleBusSchedule) -> ServiceResult<()> {
    if !valid_text(&schedule.period.label, 160)
        || schedule
            .from
            .as_deref()
            .is_some_and(|value| !valid_text(value, 80))
        || schedule
            .to
            .as_deref()
            .is_some_and(|value| !valid_text(value, 80))
        || !matches!(
            schedule.parse_status.as_str(),
            "parsed" | "needs_review" | "image_only"
        )
        || !schedule.parse_confidence.is_finite()
        || !(0.0..=1.0).contains(&schedule.parse_confidence)
        || !valid_text(&schedule.parse_engine, 80)
        || schedule.rows.len() > 100
    {
        return Err(ServiceError::new("班车时刻表字段不符合 Schema 1.0。"));
    }
    let start = schedule
        .period
        .start_date
        .as_deref()
        .map(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| ServiceError::new("班车运行开始日期无效。"))?;
    let end = schedule
        .period
        .end_date
        .as_deref()
        .map(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d"))
        .transpose()
        .map_err(|_| ServiceError::new("班车运行结束日期无效。"))?;
    if start.zip(end).is_some_and(|(start, end)| start > end) {
        return Err(ServiceError::new("班车运行日期范围无效。"));
    }
    for row in &schedule.rows {
        if NaiveTime::parse_from_str(&row.departure_time, "%H:%M").is_err()
            || row
                .services
                .keys()
                .any(|weekday| !WEEKDAYS.contains(&weekday.as_str()))
        {
            return Err(ServiceError::new("班车发车时间或星期字段无效。"));
        }
        if row
            .services
            .values()
            .flatten()
            .any(|service| !valid_text(&service.vehicle, 40) || !(1..=20).contains(&service.count))
        {
            return Err(ServiceError::new("班车车型或车辆数量无效。"));
        }
    }
    Ok(())
}

fn parse_shuttle(bytes: &[u8]) -> ServiceResult<ShuttleBusResponse> {
    let response: ShuttleBusResponse = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("班车数据解析失败：{error}")))?;
    if response.schema_version != "1.0"
        || !matches!(response.status.as_str(), "healthy" | "stale")
        || DateTime::parse_from_rfc3339(&response.generated_at).is_err()
        || !valid_text(&response.source.name, 100)
        || !trusted_source_url(&response.source.page_url, SHUTTLE_SOURCE_HOST)
        || response.items.len() > 100
    {
        return Err(ServiceError::new("班车数据不符合 Schema 1.0。"));
    }
    for notice in &response.items {
        if !valid_text(&notice.id, 160)
            || !valid_text(&notice.title, 300)
            || NaiveDate::parse_from_str(&notice.published_at, "%Y-%m-%d").is_err()
            || !trusted_source_url(&notice.source_url, SHUTTLE_SOURCE_HOST)
            || !matches!(
                notice.parse_status.as_str(),
                "parsed" | "partial" | "needs_review" | "text_only"
            )
            || notice.stops.len() > 20
            || notice.notes.len() > 40
            || notice.schedules.len() > 32
        {
            return Err(ServiceError::new("班车通知字段不符合 Schema 1.0。"));
        }
        if notice
            .stops
            .iter()
            .any(|stop| !valid_text(&stop.campus, 80) || !valid_text(&stop.location, 160))
            || notice.notes.iter().any(|note| !valid_text(note, 600))
        {
            return Err(ServiceError::new("班车站点或提示字段无效。"));
        }
        for schedule in &notice.schedules {
            validate_shuttle_schedule(schedule)?;
        }
    }
    Ok(response)
}

async fn fetch_shuttle_uncached() -> ServiceResult<ShuttleBusResponse> {
    let bytes = fetch_limited(
        fixed_url(SHUTTLE_URL, SHUTTLE_HOST)?,
        MAX_SHUTTLE_BYTES,
        "班车数据",
    )
    .await?;
    let response = parse_shuttle(&bytes)?;
    save_cached(shuttle_cache(), &response);
    Ok(response)
}

pub async fn fetch_shuttle_bus() -> ServiceResult<ShuttleBusResponse> {
    if let Some(response) = cached(shuttle_cache()) {
        return Ok(response);
    }
    fetch_shuttle_uncached().await
}

pub async fn refresh_shuttle_bus() -> ServiceResult<ShuttleBusResponse> {
    fetch_shuttle_uncached().await
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TodayShuttleDeparture {
    pub time: String,
    pub vehicle: String,
    pub count: usize,
    pub departed: bool,
    pub next: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TodayShuttleRoute {
    pub from: String,
    pub to: String,
    pub period_label: String,
    pub departures: Vec<TodayShuttleDeparture>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TodayShuttlePresentation {
    pub date: String,
    pub status: String,
    pub next_departure: Option<String>,
    pub notice_id: Option<String>,
    pub notice_title: Option<String>,
    pub notice_url: Option<String>,
    pub stops: Vec<ShuttleBusStop>,
    pub notes: Vec<String>,
    pub routes: Vec<TodayShuttleRoute>,
    pub stale: bool,
}

fn active_shuttle_notice(
    response: &ShuttleBusResponse,
    date: NaiveDate,
) -> Option<(&ShuttleBusNotice, Vec<&ShuttleBusSchedule>)> {
    let mut notices: Vec<&ShuttleBusNotice> = response
        .items
        .iter()
        .filter(|notice| {
            NaiveDate::parse_from_str(&notice.published_at, "%Y-%m-%d")
                .is_ok_and(|published| published <= date)
        })
        .collect();
    notices.sort_by(|left, right| {
        right
            .published_at
            .cmp(&left.published_at)
            .then(right.id.cmp(&left.id))
    });
    for notice in notices {
        let parsed: Vec<&ShuttleBusSchedule> = notice
            .schedules
            .iter()
            .filter(|schedule| schedule.parse_status == "parsed" && !schedule.rows.is_empty())
            .collect();
        if parsed.is_empty() {
            continue;
        }
        let active: Vec<&ShuttleBusSchedule> = parsed
            .into_iter()
            .filter(|schedule| {
                let Some(start) = schedule
                    .period
                    .start_date
                    .as_deref()
                    .and_then(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d").ok())
                else {
                    return false;
                };
                let end = schedule
                    .period
                    .end_date
                    .as_deref()
                    .and_then(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d").ok());
                start <= date && end.is_none_or(|end| date <= end)
            })
            .collect();
        if active.is_empty() {
            // A newer authoritative timetable must not be replaced by an older notice in a gap.
            return None;
        }
        let latest_start = active
            .iter()
            .filter_map(|schedule| schedule.period.start_date.as_deref())
            .max()?;
        return Some((
            notice,
            active
                .into_iter()
                .filter(|schedule| schedule.period.start_date.as_deref() == Some(latest_start))
                .collect(),
        ));
    }
    None
}

pub fn shuttle_today(response: &ShuttleBusResponse) -> TodayShuttlePresentation {
    shuttle_at(response, Utc::now())
}

pub fn shuttle_at(response: &ShuttleBusResponse, now: DateTime<Utc>) -> TodayShuttlePresentation {
    use chrono::{Datelike, Timelike};

    let local = now.with_timezone(&Shanghai);
    let date = local.date_naive();
    let weekday = WEEKDAYS[local.weekday().num_days_from_monday() as usize];
    let now_minutes = local.hour() * 60 + local.minute();
    let selection = active_shuttle_notice(response, date);
    let mut routes = Vec::new();
    if let Some((_, schedules)) = selection.as_ref() {
        for schedule in schedules {
            let (Some(from), Some(to)) = (schedule.from.as_ref(), schedule.to.as_ref()) else {
                continue;
            };
            let mut departures: Vec<TodayShuttleDeparture> = schedule
                .rows
                .iter()
                .filter_map(|row| {
                    row.services
                        .get(weekday)
                        .and_then(Option::as_ref)
                        .map(|service| {
                            let time = NaiveTime::parse_from_str(&row.departure_time, "%H:%M")
                                .expect("validated shuttle time");
                            TodayShuttleDeparture {
                                time: row.departure_time.clone(),
                                vehicle: service.vehicle.clone(),
                                count: service.count,
                                departed: time.hour() * 60 + time.minute() <= now_minutes,
                                next: false,
                            }
                        })
                })
                .collect();
            departures.sort_by(|left, right| left.time.cmp(&right.time));
            routes.push(TodayShuttleRoute {
                from: from.clone(),
                to: to.clone(),
                period_label: schedule.period.label.clone(),
                departures,
            });
        }
    }
    routes.sort_by(|left, right| {
        (&left.from, &left.to, &left.period_label).cmp(&(
            &right.from,
            &right.to,
            &right.period_label,
        ))
    });
    let mut next: Option<(usize, usize, String)> = None;
    for (route_index, route) in routes.iter().enumerate() {
        for (departure_index, departure) in route.departures.iter().enumerate() {
            if !departure.departed
                && next
                    .as_ref()
                    .is_none_or(|(_, _, time)| departure.time < *time)
            {
                next = Some((route_index, departure_index, departure.time.clone()));
            }
        }
    }
    if let Some((route_index, departure_index, _)) = &next {
        routes[*route_index].departures[*departure_index].next = true;
    }
    let departure_count: usize = routes.iter().map(|route| route.departures.len()).sum();
    let vehicle_count: usize = routes
        .iter()
        .flat_map(|route| &route.departures)
        .map(|departure| departure.count)
        .sum();
    let status = if selection.is_none() {
        "未找到当前生效的班车时刻表".to_string()
    } else if departure_count == 0 {
        "今日暂无已安排班车".to_string()
    } else {
        format!("今日安排 {departure_count} 个发车时刻 · {vehicle_count} 辆车")
    };
    let next_departure = next.map(|(route_index, _, time)| {
        let route = &routes[route_index];
        format!("下一班 {time} · {} → {}", route.from, route.to)
    });
    let (notice_id, notice_title, notice_url, stops, notes) = selection
        .map(|(notice, _)| {
            (
                Some(notice.id.clone()),
                Some(notice.title.clone()),
                Some(notice.source_url.clone()),
                notice.stops.clone(),
                notice.notes.clone(),
            )
        })
        .unwrap_or_default();
    TodayShuttlePresentation {
        date: date.to_string(),
        status,
        next_departure: next_departure
            .or_else(|| (departure_count > 0).then(|| "今日班车已结束".to_string())),
        notice_id,
        notice_title,
        notice_url,
        stops,
        notes,
        routes,
        stale: response.status == "stale",
    }
}

#[derive(Debug, Deserialize)]
struct ContestEnvelope {
    schema_version: String,
    generated_at: String,
    timezone: String,
    items: Vec<ContestItem>,
}

#[derive(Debug, Deserialize)]
struct ContestItem {
    id: String,
    name: String,
    event_type: String,
    primary_deadline: Option<String>,
    #[serde(default)]
    organizer: Option<String>,
    #[serde(default)]
    official_url: Option<String>,
    #[serde(default)]
    categories: Vec<String>,
    #[serde(default)]
    tags: Vec<String>,
    #[serde(default)]
    level: Option<String>,
    #[serde(default)]
    location: Option<String>,
    #[serde(default)]
    status: Option<String>,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    notes: Option<String>,
    #[serde(default)]
    eligibility: Option<String>,
    #[serde(default)]
    region: Option<String>,
    #[serde(default)]
    mode: Option<String>,
    #[serde(default)]
    registration_deadline: Option<String>,
    #[serde(default)]
    abstract_deadline: Option<String>,
    #[serde(default)]
    submission_deadline: Option<String>,
    #[serde(default)]
    competition_start: Option<String>,
    #[serde(default)]
    competition_end: Option<String>,
    #[serde(default)]
    source: Option<ContestSource>,
    #[serde(default)]
    stale: bool,
    #[serde(default)]
    archived: bool,
}

#[derive(Debug, Deserialize)]
struct ContestSource {
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SchoolEnvelope {
    schema_version: String,
    generated_at: String,
    timezone: String,
    status: String,
    source: SchoolSource,
    #[serde(default)]
    items: Vec<SchoolNotice>,
}

#[derive(Debug, Deserialize)]
struct SchoolSource {
    name: String,
    url: String,
}

#[derive(Debug, Deserialize)]
struct SchoolNotice {
    id: String,
    #[serde(default)]
    name: Option<String>,
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    primary_deadline: Option<String>,
    #[serde(default)]
    primary_deadline_label: Option<String>,
    #[serde(default)]
    deadlines: Vec<SchoolDeadline>,
    #[serde(default)]
    source: Option<String>,
    #[serde(default)]
    source_url: Option<String>,
    #[serde(default)]
    published_at: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SchoolDeadline {
    date: String,
    #[serde(default)]
    label: Option<String>,
}

fn normalized_optional(value: Option<String>, maximum: usize) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty() && value.chars().count() <= maximum)
}

fn normalized_labels(values: Vec<String>) -> Vec<String> {
    let mut seen = HashSet::new();
    values
        .into_iter()
        .filter_map(|value| normalized_optional(Some(value), 80))
        .filter(|value| seen.insert(value.clone()))
        .take(32)
        .collect()
}

fn deadline_label(item: &ContestItem) -> Option<String> {
    let deadline = item.primary_deadline.as_deref()?;
    [
        (item.registration_deadline.as_deref(), "报名截止"),
        (item.abstract_deadline.as_deref(), "摘要截止"),
        (item.submission_deadline.as_deref(), "提交截止"),
        (item.competition_start.as_deref(), "活动开始"),
        (item.competition_end.as_deref(), "活动结束"),
    ]
    .into_iter()
    .find_map(|(value, label)| (value == Some(deadline)).then(|| label.to_string()))
}

fn parse_contest_events(bytes: &[u8]) -> ServiceResult<(Vec<ImportantEventItem>, String)> {
    let envelope: ContestEnvelope = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("公开重要事件解析失败：{error}")))?;
    if envelope.schema_version != "1.4"
        || envelope.timezone != "Asia/Shanghai"
        || DateTime::parse_from_rfc3339(&envelope.generated_at).is_err()
        || envelope.items.len() > MAX_EVENT_ITEMS
    {
        return Err(ServiceError::new("公开重要事件不符合 Schema 1.4。"));
    }
    let mut items = Vec::new();
    for item in envelope.items {
        if item.archived || !IMPORTANT_EVENT_TYPES.contains(&item.event_type.as_str()) {
            continue;
        }
        let id = item.id.trim();
        let name = item.name.trim();
        let Some(deadline) = item.primary_deadline.as_deref() else {
            continue;
        };
        let Ok(deadline) = DateTime::parse_from_rfc3339(deadline) else {
            continue;
        };
        if !valid_text(id, 128) || !valid_text(name, 240) {
            continue;
        }
        let source_name = item
            .source
            .as_ref()
            .and_then(|source| normalized_optional(source.name.clone(), 120));
        let source_url = item
            .source
            .as_ref()
            .and_then(|source| trusted_https_url(source.url.clone()));
        let deadline_label = deadline_label(&item);
        items.push(ImportantEventItem {
            id: id.to_string(),
            name: name.to_string(),
            event_type: item.event_type,
            source_type: "contest_ddl".to_string(),
            primary_deadline: deadline.to_rfc3339(),
            deadline_label,
            organizer: normalized_optional(item.organizer, 200),
            official_url: trusted_https_url(item.official_url),
            source_name,
            source_url,
            categories: normalized_labels(item.categories),
            tags: normalized_labels(item.tags),
            level: normalized_optional(item.level, 120),
            location: normalized_optional(item.location, 200),
            status: normalized_optional(item.status, 64),
            description: normalized_optional(item.description, 2_000),
            eligibility: normalized_optional(item.eligibility, 500),
            notes: normalized_optional(item.notes, 4_000),
            region: normalized_optional(item.region, 80),
            mode: normalized_optional(item.mode, 80),
            published_at: None,
            stale: item.stale,
            archived: false,
        });
    }
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    Ok((items, envelope.generated_at))
}

fn parse_school_events(bytes: &[u8]) -> ServiceResult<(Vec<ImportantEventItem>, String)> {
    let envelope: SchoolEnvelope = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("校内重要事件解析失败：{error}")))?;
    if envelope.schema_version != "1.0"
        || envelope.timezone != "Asia/Shanghai"
        || !matches!(envelope.status.as_str(), "healthy" | "stale")
        || DateTime::parse_from_rfc3339(&envelope.generated_at).is_err()
        || !valid_text(&envelope.source.name, 120)
        || !trusted_source_url(&envelope.source.url, SCHOOL_SOURCE_HOST)
        || envelope.items.len() > MAX_EVENT_ITEMS
    {
        return Err(ServiceError::new("校内重要事件不符合 Schema 1.0。"));
    }
    let mut items = Vec::new();
    for notice in envelope.items {
        let id = notice.id.trim().to_string();
        let name = notice
            .name
            .as_deref()
            .or(notice.title.as_deref())
            .map(str::trim)
            .filter(|name| valid_text(name, 240))
            .map(str::to_string);
        if !valid_text(&id, 128) || name.is_none() {
            continue;
        }
        let name = name.expect("checked name");
        let source_name =
            normalized_optional(notice.source, 120).unwrap_or_else(|| envelope.source.name.clone());
        let official_url = trusted_https_url(notice.source_url);
        let published_at = notice.published_at.and_then(|value| {
            NaiveDate::parse_from_str(value.trim(), "%Y-%m-%d")
                .ok()
                .map(|_| value.trim().to_string())
        });
        let deadlines = if notice.deadlines.is_empty() {
            notice
                .primary_deadline
                .map(|date| {
                    vec![SchoolDeadline {
                        date,
                        label: notice.primary_deadline_label,
                    }]
                })
                .unwrap_or_default()
        } else {
            notice.deadlines
        };
        for (index, deadline) in deadlines.into_iter().enumerate() {
            let Ok(parsed_deadline) = DateTime::parse_from_rfc3339(deadline.date.trim()) else {
                continue;
            };
            items.push(ImportantEventItem {
                id: format!("school:{id}:{index}"),
                name: name.clone(),
                event_type: "competition".to_string(),
                source_type: "school_notice".to_string(),
                primary_deadline: parsed_deadline.to_rfc3339(),
                deadline_label: normalized_optional(deadline.label, 80)
                    .or_else(|| Some("截止时间".to_string())),
                organizer: Some(source_name.clone()),
                official_url: official_url.clone(),
                source_name: Some(source_name.clone()),
                source_url: official_url.clone(),
                categories: vec!["校内竞赛通知".to_string()],
                tags: Vec::new(),
                level: None,
                location: None,
                status: Some(if parsed_deadline > Utc::now() {
                    "upcoming".to_string()
                } else {
                    "ended".to_string()
                }),
                description: None,
                eligibility: None,
                notes: None,
                region: None,
                mode: None,
                published_at: published_at.clone(),
                stale: envelope.status == "stale",
                archived: false,
            });
        }
    }
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    Ok((items, envelope.generated_at))
}

async fn fetch_contest_source() -> ServiceResult<(Vec<ImportantEventItem>, String, bool)> {
    let primary = fetch_limited(
        fixed_url(CONTEST_PRIMARY_URL, CONTEST_PRIMARY_HOST)?,
        MAX_EVENT_BYTES,
        "公开重要事件",
    )
    .await
    .and_then(|bytes| parse_contest_events(&bytes));
    match primary {
        Ok((items, _)) => Ok((items, CONTEST_PRIMARY_URL.to_string(), false)),
        Err(primary_error) => {
            let (items, _) = fetch_limited(
                fixed_url(CONTEST_BACKUP_URL, SHUTTLE_HOST)?,
                MAX_EVENT_BYTES,
                "备用公开重要事件",
            )
            .await
            .and_then(|bytes| parse_contest_events(&bytes))
            .map_err(|backup_error| {
                ServiceError::new(format!(
                    "主重要事件源不可用（{}）；备用源也不可用（{}）。",
                    primary_error.message, backup_error.message
                ))
            })?;
            Ok((items, CONTEST_BACKUP_URL.to_string(), true))
        }
    }
}

async fn fetch_events_uncached() -> ServiceResult<ImportantEventsResponse> {
    let public = fetch_contest_source().await;
    let school = fetch_limited(
        fixed_url(SCHOOL_NOTICES_URL, SHUTTLE_HOST)?,
        MAX_EVENT_BYTES,
        "校内竞赛通知",
    )
    .await
    .and_then(|bytes| parse_school_events(&bytes));
    let (mut items, source, used_backup) = match (public, school) {
        (Ok((mut public, source, used_backup)), Ok((school, _))) => {
            public.extend(school);
            (
                public,
                format!("{source} + {SCHOOL_NOTICES_URL}"),
                used_backup,
            )
        }
        (Ok((public, source, used_backup)), Err(_)) => (public, source, used_backup),
        (Err(_), Ok((school, _))) => (school, SCHOOL_NOTICES_URL.to_string(), false),
        (Err(public_error), Err(school_error)) => {
            return Err(ServiceError::new(format!(
                "公开重要事件不可用（{}）；校内竞赛通知也不可用（{}）。",
                public_error.message, school_error.message
            )));
        }
    };
    let mut seen = HashSet::new();
    items.retain(|item| {
        item.source_type != "assignment"
            && item.source_type != "custom"
            && seen.insert(favorite_key(item))
    });
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    items.truncate(MAX_EVENT_ITEMS);
    let response = ImportantEventsResponse {
        fetched_at: crate::config::now_in_app_tz(),
        source,
        used_backup,
        items,
    };
    save_cached(event_cache(), &response);
    Ok(response)
}

pub async fn fetch_important_events() -> ServiceResult<ImportantEventsResponse> {
    if let Some(response) = cached(event_cache()) {
        return Ok(response);
    }
    fetch_events_uncached().await
}

pub async fn refresh_important_events() -> ServiceResult<ImportantEventsResponse> {
    fetch_events_uncached().await
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ImportantEventSourceFilter {
    #[default]
    All,
    Public,
    School,
}

#[derive(Debug, Clone, Default)]
pub struct ImportantEventFilter {
    pub query: String,
    pub event_type: Option<String>,
    pub category: Option<String>,
    pub source: ImportantEventSourceFilter,
    pub include_ended: bool,
    pub favorites_only: bool,
}

pub fn favorite_key(item: &ImportantEventItem) -> String {
    format!("{}:{}", item.source_type, item.id)
}

pub fn available_event_types(items: &[ImportantEventItem]) -> Vec<String> {
    IMPORTANT_EVENT_TYPES
        .iter()
        .filter(|event_type| {
            items.iter().any(|item| {
                item.event_type == **event_type
                    && matches!(item.source_type.as_str(), "contest_ddl" | "school_notice")
            })
        })
        .map(|event_type| (*event_type).to_string())
        .collect()
}

pub fn available_event_categories(items: &[ImportantEventItem]) -> Vec<String> {
    let mut categories: Vec<String> = items
        .iter()
        .flat_map(|item| item.categories.iter().cloned())
        .collect();
    categories.sort();
    categories.dedup();
    categories
}

pub fn merge_live_and_favorite_events(
    live: &[ImportantEventItem],
    favorites: &[ImportantEventItem],
) -> Vec<ImportantEventItem> {
    let mut items = live.to_vec();
    let mut seen: HashSet<String> = items.iter().map(favorite_key).collect();
    for item in favorites {
        if seen.insert(favorite_key(item)) {
            items.push(item.clone());
        }
    }
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    items
}

pub fn filter_important_events(
    items: &[ImportantEventItem],
    favorites: &[ImportantEventItem],
    filter: &ImportantEventFilter,
    now: DateTime<Utc>,
) -> Vec<ImportantEventItem> {
    let favorite_ids: HashSet<String> = favorites.iter().map(favorite_key).collect();
    let query = filter.query.trim().to_lowercase();
    let mut filtered: Vec<ImportantEventItem> = items
        .iter()
        .filter(|item| {
            if item.archived
                || !IMPORTANT_EVENT_TYPES.contains(&item.event_type.as_str())
                || !matches!(item.source_type.as_str(), "contest_ddl" | "school_notice")
            {
                return false;
            }
            let Ok(deadline) = DateTime::parse_from_rfc3339(&item.primary_deadline) else {
                return false;
            };
            let haystack = [
                Some(item.name.as_str()),
                item.organizer.as_deref(),
                item.level.as_deref(),
                item.location.as_deref(),
                item.description.as_deref(),
                item.eligibility.as_deref(),
                item.notes.as_deref(),
                item.region.as_deref(),
                item.mode.as_deref(),
                item.status.as_deref(),
                item.deadline_label.as_deref(),
                item.source_name.as_deref(),
            ]
            .into_iter()
            .flatten()
            .chain(item.categories.iter().map(String::as_str))
            .chain(item.tags.iter().map(String::as_str))
            .collect::<Vec<_>>()
            .join(" ")
            .to_lowercase();
            (query.is_empty() || haystack.contains(&query))
                && filter
                    .event_type
                    .as_deref()
                    .is_none_or(|event_type| item.event_type == event_type)
                && filter
                    .category
                    .as_deref()
                    .is_none_or(|category| item.categories.iter().any(|value| value == category))
                && match filter.source {
                    ImportantEventSourceFilter::All => true,
                    ImportantEventSourceFilter::Public => item.source_type == "contest_ddl",
                    ImportantEventSourceFilter::School => item.source_type == "school_notice",
                }
                && (filter.include_ended || deadline.with_timezone(&Utc) >= now)
                && (!filter.favorites_only || favorite_ids.contains(&favorite_key(item)))
        })
        .cloned()
        .collect();
    filtered.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    filtered
}

#[derive(Debug, Serialize, Deserialize)]
struct FavoritesFile {
    version: u32,
    updated_at: String,
    items: Vec<ImportantEventItem>,
}

fn config_root() -> Option<PathBuf> {
    #[cfg(target_os = "windows")]
    {
        return env::var_os("LOCALAPPDATA")
            .or_else(|| env::var_os("APPDATA"))
            .map(PathBuf::from);
    }
    #[cfg(target_os = "macos")]
    {
        env::var_os("HOME").map(|home| {
            PathBuf::from(home)
                .join("Library")
                .join("Application Support")
        })
    }
    #[cfg(all(not(target_os = "windows"), not(target_os = "macos")))]
    {
        env::var_os("XDG_CONFIG_HOME")
            .filter(|value| !value.is_empty())
            .map(PathBuf::from)
            .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
    }
}

pub fn favorite_events_path() -> ServiceResult<PathBuf> {
    config_root()
        .map(|root| root.join("where-to-study").join(FAVORITES_FILE))
        .ok_or_else(|| ServiceError::new("无法确定重要事件收藏目录。"))
}

fn load_favorites_from(path: &Path) -> ServiceResult<Vec<ImportantEventItem>> {
    let metadata = match fs::symlink_metadata(path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(error) => {
            return Err(ServiceError::new(format!(
                "无法检查重要事件收藏文件（{}）：{error}",
                path.display()
            )));
        }
    };
    if metadata.file_type().is_symlink() || !metadata.is_file() || metadata.len() > 2 * 1024 * 1024
    {
        return Err(ServiceError::new(format!(
            "重要事件收藏必须是大小合理的普通文件：{}",
            path.display()
        )));
    }
    let payload = fs::read(path).map_err(|error| {
        ServiceError::new(format!(
            "无法读取重要事件收藏（{}）：{error}",
            path.display()
        ))
    })?;
    let stored: FavoritesFile = serde_json::from_slice(&payload)
        .map_err(|error| ServiceError::new(format!("重要事件收藏格式不正确：{error}")))?;
    if stored.version != FAVORITES_VERSION || stored.items.len() > MAX_EVENT_ITEMS {
        return Err(ServiceError::new("重要事件收藏版本或数量不受支持。"));
    }
    let mut seen = HashSet::new();
    Ok(stored
        .items
        .into_iter()
        .filter(|item| {
            !item.archived
                && IMPORTANT_EVENT_TYPES.contains(&item.event_type.as_str())
                && matches!(item.source_type.as_str(), "contest_ddl" | "school_notice")
                && DateTime::parse_from_rfc3339(&item.primary_deadline).is_ok()
                && seen.insert(favorite_key(item))
        })
        .collect())
}

fn save_favorites_to(path: &Path, items: &[ImportantEventItem]) -> ServiceResult<()> {
    let parent = path
        .parent()
        .ok_or_else(|| ServiceError::new("重要事件收藏路径缺少父目录。"))?;
    fs::create_dir_all(parent)
        .map_err(|error| ServiceError::new(format!("无法创建重要事件收藏目录：{error}")))?;
    if fs::symlink_metadata(parent)
        .is_ok_and(|metadata| metadata.file_type().is_symlink() || !metadata.is_dir())
    {
        return Err(ServiceError::new("重要事件收藏目录不是普通目录。"));
    }
    if fs::symlink_metadata(path)
        .is_ok_and(|metadata| metadata.file_type().is_symlink() || !metadata.is_file())
    {
        return Err(ServiceError::new("重要事件收藏路径不是普通文件。"));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(parent, fs::Permissions::from_mode(0o700))
            .map_err(|error| ServiceError::new(format!("无法限制重要事件收藏目录权限：{error}")))?;
    }
    let stored = FavoritesFile {
        version: FAVORITES_VERSION,
        updated_at: Utc::now().to_rfc3339(),
        items: items.to_vec(),
    };
    let payload = serde_json::to_vec_pretty(&stored)
        .map_err(|error| ServiceError::new(format!("无法序列化重要事件收藏：{error}")))?;
    let mut temporary = tempfile::NamedTempFile::new_in(parent)
        .map_err(|error| ServiceError::new(format!("无法创建收藏临时文件：{error}")))?;
    temporary
        .write_all(&payload)
        .and_then(|_| temporary.as_file().sync_all())
        .map_err(|error| ServiceError::new(format!("无法写入收藏临时文件：{error}")))?;
    #[cfg(target_os = "windows")]
    if path.exists() {
        fs::remove_file(path)
            .map_err(|error| ServiceError::new(format!("无法替换旧收藏文件：{error}")))?;
    }
    temporary
        .persist(path)
        .map_err(|error| ServiceError::new(format!("无法提交重要事件收藏：{}", error.error)))?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))
            .map_err(|error| ServiceError::new(format!("无法限制重要事件收藏文件权限：{error}")))?;
    }
    Ok(())
}

pub fn load_favorite_events() -> ServiceResult<Vec<ImportantEventItem>> {
    load_favorites_from(&favorite_events_path()?)
}

pub fn save_favorite_events(items: &[ImportantEventItem]) -> ServiceResult<()> {
    let mut unique = Vec::new();
    let mut seen = HashSet::new();
    for item in items {
        if seen.insert(favorite_key(item)) {
            unique.push(item.clone());
        }
    }
    save_favorites_to(&favorite_events_path()?, &unique)
}

pub fn toggle_favorite_event(
    favorites: &mut Vec<ImportantEventItem>,
    item: &ImportantEventItem,
) -> ServiceResult<bool> {
    let key = favorite_key(item);
    if let Some(index) = favorites
        .iter()
        .position(|favorite| favorite_key(favorite) == key)
    {
        let removed = favorites.remove(index);
        if let Err(error) = save_favorite_events(favorites) {
            favorites.insert(index, removed);
            return Err(error);
        }
        Ok(false)
    } else {
        favorites.push(item.clone());
        if let Err(error) = save_favorite_events(favorites) {
            favorites.pop();
            return Err(error);
        }
        Ok(true)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn contest_fixture() -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "schema_version":"1.4",
            "generated_at":"2026-08-30T13:21:07+08:00",
            "timezone":"Asia/Shanghai",
            "items":[
                {"id":"c1","name":"AI Conference","event_type":"conference","categories":["人工智能"],"tags":["CCF A"],"organizer":"Example","primary_deadline":"2026-09-01T23:59:59+08:00","submission_deadline":"2026-09-01T23:59:59+08:00","notes":"paper deadline"},
                {"id":"old","name":"Ended Hackathon","event_type":"hackathon","categories":["开发"],"primary_deadline":"2026-01-01T12:00:00+08:00"},
                {"id":"assignment","name":"作业","event_type":"assignment","primary_deadline":"2026-09-01T12:00:00+08:00"},
                {"id":"archived","name":"Archived","event_type":"competition","primary_deadline":"2026-09-01T12:00:00+08:00","archived":true}
            ]
        }))
        .unwrap()
    }

    fn school_fixture() -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "schema_version":"1.0",
            "generated_at":"2026-08-30T13:59:26Z",
            "timezone":"Asia/Shanghai",
            "status":"healthy",
            "source":{"name":"北京邮电大学教学云平台 · 教务通知","url":"https://ucloud.bupt.edu.cn/#/consulting?tab=1"},
            "items":[{"id":"n1","name":"校内竞赛","source":"北京邮电大学教学云平台","source_url":"https://ucloud.bupt.edu.cn/#/consulting?id=1","published_at":"2026-08-30","primary_deadline":"2026-09-02T12:00:00+08:00","primary_deadline_label":"报名截止"}]
        }))
        .unwrap()
    }

    fn shuttle_fixture() -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "schema_version":"1.0","generated_at":"2026-08-31T00:59:26Z","status":"healthy",
            "source":{"name":"北京邮电大学后勤部","page_url":"https://hq.bupt.edu.cn/tzgg.htm"},
            "stats":{"notices":1,"images":1,"parsed_schedules":2,"needs_review":0},"last_parsed_notice_id":"n1",
            "items":[{"id":"n1","title":"班车安排","published_at":"2026-08-19","source_url":"https://hq.bupt.edu.cn/info/1010/1541.htm","parse_status":"parsed","stops":[],"notes":[],"schedules":[
                {"period":{"label":"第一时段","start_date":"2026-08-27","end_date":"2026-09-04"},"from":"西土城","to":"沙河","parse_status":"parsed","parse_confidence":0.98,"parse_engine":"ocr","rows":[{"departure_time":"06:30","services":{"monday":{"vehicle":"大巴","count":1}}},{"departure_time":"12:00","services":{"monday":{"vehicle":"大巴","count":1}}}]},
                {"period":{"label":"第二时段","start_date":"2026-09-07","end_date":null},"from":"西土城","to":"沙河","parse_status":"parsed","parse_confidence":0.98,"parse_engine":"ocr","rows":[{"departure_time":"07:00","services":{"monday":{"vehicle":"大巴","count":1}}}]}
            ]}]
        }))
        .unwrap()
    }

    #[test]
    fn strict_parsers_keep_supported_metadata_and_exclude_non_events() {
        let (public, generated_at) = parse_contest_events(&contest_fixture()).unwrap();
        assert_eq!(generated_at, "2026-08-30T13:21:07+08:00");
        assert_eq!(public.len(), 2);
        let conference = public.iter().find(|item| item.id == "c1").unwrap();
        assert_eq!(conference.deadline_label.as_deref(), Some("提交截止"));
        assert_eq!(conference.notes.as_deref(), Some("paper deadline"));
        let (school, _) = parse_school_events(&school_fixture()).unwrap();
        assert_eq!(school.len(), 1);
        assert_eq!(school[0].source_type, "school_notice");
        assert_eq!(school[0].categories, ["校内竞赛通知"]);
    }

    #[test]
    fn event_filter_defaults_to_upcoming_and_sorts_by_deadline() {
        let (mut items, _) = parse_contest_events(&contest_fixture()).unwrap();
        let (school, _) = parse_school_events(&school_fixture()).unwrap();
        items.extend(school);
        let now = DateTime::parse_from_rfc3339("2026-08-31T00:00:00+08:00")
            .unwrap()
            .with_timezone(&Utc);
        let visible = filter_important_events(&items, &[], &ImportantEventFilter::default(), now);
        assert_eq!(visible.len(), 2);
        assert_eq!(visible[0].id, "c1");
        assert_eq!(visible[1].source_type, "school_notice");

        let filter = ImportantEventFilter {
            query: "paper".to_string(),
            event_type: Some("conference".to_string()),
            category: Some("人工智能".to_string()),
            source: ImportantEventSourceFilter::Public,
            include_ended: true,
            favorites_only: false,
        };
        assert_eq!(filter_important_events(&items, &[], &filter, now).len(), 1);
    }

    #[test]
    fn available_types_ignore_custom_favorites() {
        let (mut items, _) = parse_contest_events(&contest_fixture()).unwrap();
        let mut custom = items[0].clone();
        custom.id = "custom-journal".to_string();
        custom.event_type = "journal_special_issue".to_string();
        custom.source_type = "custom".to_string();
        items.push(custom);
        let types = available_event_types(&items);
        assert!(types.contains(&"conference".to_string()));
        assert!(!types.contains(&"journal_special_issue".to_string()));
    }

    #[test]
    fn shuttle_presentation_uses_only_the_active_period_and_marks_next() {
        let response = parse_shuttle(&shuttle_fixture()).unwrap();
        let now = DateTime::parse_from_rfc3339("2026-08-31T08:00:00+08:00")
            .unwrap()
            .with_timezone(&Utc);
        let today = shuttle_at(&response, now);
        assert_eq!(today.routes.len(), 1);
        assert_eq!(today.routes[0].period_label, "第一时段");
        assert!(today.routes[0].departures[0].departed);
        assert!(today.routes[0].departures[1].next);
    }

    #[test]
    fn shuttle_does_not_resurrect_an_old_notice_during_a_period_gap() {
        let response = parse_shuttle(&shuttle_fixture()).unwrap();
        let now = DateTime::parse_from_rfc3339("2026-09-05T08:00:00+08:00")
            .unwrap()
            .with_timezone(&Utc);
        assert!(shuttle_at(&response, now).routes.is_empty());
    }

    #[test]
    fn favorite_file_round_trips_and_rejects_symlinks() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join(FAVORITES_FILE);
        let (items, _) = parse_contest_events(&contest_fixture()).unwrap();
        let conference = items.iter().find(|item| item.id == "c1").unwrap();
        save_favorites_to(&path, std::slice::from_ref(conference)).unwrap();
        let loaded = load_favorites_from(&path).unwrap();
        assert_eq!(loaded.len(), 1);
        assert_eq!(favorite_key(&loaded[0]), "contest_ddl:c1");

        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;
            let link = directory.path().join("favorites-link.json");
            symlink(&path, &link).unwrap();
            assert!(load_favorites_from(&link).is_err());
        }
    }

    #[test]
    fn fixed_endpoints_are_https_and_do_not_use_www_redirects() {
        assert_eq!(
            fixed_url(SHUTTLE_URL, SHUTTLE_HOST).unwrap().host_str(),
            Some(SHUTTLE_HOST)
        );
        assert!(!SHUTTLE_URL.contains("www."));
        assert_eq!(
            fixed_url(CONTEST_BACKUP_URL, SHUTTLE_HOST)
                .unwrap()
                .scheme(),
            "https"
        );
    }
}
