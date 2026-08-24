use std::collections::{HashMap, HashSet};
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use chrono::{DateTime, NaiveDate};
use reqwest::Url;
use serde::Deserialize;

use crate::error::{ServiceError, ServiceResult};
use crate::models::{
    CalendarRangeRequest, DeadlineCalendarResponse, DeadlineItem, DeadlinesRequest,
    DeadlinesResponse,
};

const PRIMARY_URL: &str = "https://nemoyuzx.github.io/contest-ddl/data/competitions.json";
const PRIMARY_HOST: &str = "nemoyuzx.github.io";
const BACKUP_URL: &str = "http://101.201.29.29/api/contest-events";
const SCHOOL_NOTICES_URL: &str = "http://101.201.29.29/api/contest-notices";
const BACKUP_HOST: &str = "101.201.29.29";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const MAX_ITEMS_PER_DAY: usize = 100;
const MAX_CUSTOM_ITEMS: usize = 5_000;
const MAX_CALENDAR_RANGE_DAYS: i64 = 370;
const SOURCE_CACHE_TTL: Duration = Duration::from_secs(5 * 60);
const USER_AGENT: &str = concat!("WhereToStudy/", env!("CARGO_PKG_VERSION"));

struct SourceCacheEntry {
    fetched_at: Instant,
    bytes: Vec<u8>,
}

static SOURCE_CACHE: OnceLock<Mutex<HashMap<String, SourceCacheEntry>>> = OnceLock::new();

fn source_cache() -> &'static Mutex<HashMap<String, SourceCacheEntry>> {
    SOURCE_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn cached_source(endpoint: &str) -> Option<Vec<u8>> {
    let cache = source_cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    cache
        .get(endpoint)
        .filter(|entry| entry.fetched_at.elapsed() < SOURCE_CACHE_TTL)
        .map(|entry| entry.bytes.clone())
}

fn cache_source(endpoint: &str, bytes: &[u8]) {
    let mut cache = source_cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    cache.insert(
        endpoint.to_string(),
        SourceCacheEntry {
            fetched_at: Instant::now(),
            bytes: bytes.to_vec(),
        },
    );
}

#[derive(Debug, Deserialize)]
struct SourceEnvelope {
    items: Vec<SourceDeadline>,
}

#[derive(Debug, Deserialize)]
struct CustomSourceEnvelope {
    version: u32,
    source: String,
    #[serde(default)]
    homepage: Option<String>,
    #[serde(default)]
    updated_at: Option<String>,
    items: Vec<CustomSourceDeadline>,
    #[serde(flatten)]
    extra: HashMap<String, serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct CustomSourceDeadline {
    id: String,
    name: String,
    event_type: String,
    primary_deadline: Option<String>,
    #[serde(default)]
    organizer: Option<String>,
    #[serde(default)]
    official_url: Option<String>,
    #[serde(flatten)]
    extra: HashMap<String, serde_json::Value>,
}

#[derive(Debug, Deserialize)]
struct SourceDeadline {
    id: String,
    name: String,
    event_type: String,
    primary_deadline: Option<String>,
    #[serde(default)]
    organizer: Option<String>,
    #[serde(default)]
    official_url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SchoolNoticeEnvelope {
    #[serde(default)]
    items: Vec<SchoolNotice>,
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
    deadlines: Vec<SchoolNoticeDeadline>,
    #[serde(default)]
    source: Option<String>,
    #[serde(default)]
    source_url: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SchoolNoticeDeadline {
    date: String,
    #[serde(default)]
    label: Option<String>,
}

fn parse_date(value: &str) -> ServiceResult<NaiveDate> {
    if value.len() != 10
        || value.as_bytes().get(4) != Some(&b'-')
        || value.as_bytes().get(7) != Some(&b'-')
    {
        return Err(ServiceError::with_status("DDL 日期格式不正确。", 400));
    }
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ServiceError::with_status("DDL 日期格式不正确。", 400))
}

fn validate_endpoint(url: &Url, host: &str, allow_plain_http: bool) -> ServiceResult<()> {
    let scheme_allowed = url.scheme() == "https" || (allow_plain_http && url.scheme() == "http");
    if !scheme_allowed || url.host_str() != Some(host) {
        return Err(ServiceError::new("DDL 数据源地址不受信任。"));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(ServiceError::new("DDL 数据源地址不得携带用户信息。"));
    }
    Ok(())
}

fn blocked_ipv4(address: Ipv4Addr) -> bool {
    let [first, second, third, _] = address.octets();
    first == 0
        || first == 10
        || first == 127
        || (first == 100 && (64..=127).contains(&second))
        || (first == 169 && second == 254)
        || (first == 172 && (16..=31).contains(&second))
        || (first == 192 && second == 0)
        || (first == 192 && second == 168)
        || (first == 192 && second == 0 && third == 2)
        || (first == 198 && (second == 18 || second == 19))
        || (first == 198 && second == 51 && third == 100)
        || (first == 203 && second == 0 && third == 113)
        || first >= 224
}

fn blocked_ipv6(address: Ipv6Addr) -> bool {
    if let Some(mapped) = address.to_ipv4() {
        return blocked_ipv4(mapped);
    }
    let segments = address.segments();
    address.is_loopback()
        || address.is_unspecified()
        || address.is_unique_local()
        || address.is_unicast_link_local()
        || address.is_multicast()
        || (segments[0] == 0x2001 && segments[1] == 0x0db8)
}

fn blocked_literal_address(host: &str) -> bool {
    match host.parse::<IpAddr>() {
        Ok(IpAddr::V4(address)) => blocked_ipv4(address),
        Ok(IpAddr::V6(address)) => blocked_ipv6(address),
        Err(_) => false,
    }
}

pub fn validate_custom_feed_endpoint(endpoint: &str) -> ServiceResult<Url> {
    let trimmed = endpoint.trim();
    let url = Url::parse(trimmed)
        .map_err(|error| ServiceError::with_status(format!("自定义日程地址无效：{error}"), 400))?;
    let Some(host) = url.host_str() else {
        return Err(ServiceError::with_status("自定义日程地址缺少主机名。", 400));
    };
    let normalized_host = host.trim_end_matches('.').to_ascii_lowercase();
    let literal_host = normalized_host
        .strip_prefix('[')
        .and_then(|value| value.strip_suffix(']'))
        .unwrap_or(&normalized_host);
    if url.scheme() != "https"
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
        || normalized_host == "localhost"
        || normalized_host.ends_with(".localhost")
        || blocked_literal_address(literal_host)
    {
        return Err(ServiceError::with_status(
            "自定义日程只允许不含凭据、片段或本地地址的公开 HTTPS URL。",
            400,
        ));
    }
    Ok(url)
}

async fn read_limited(mut response: reqwest::Response) -> ServiceResult<Vec<u8>> {
    if response
        .content_length()
        .is_some_and(|length| length > MAX_RESPONSE_BYTES as u64)
    {
        return Err(ServiceError::new("DDL 数据响应过大。"));
    }
    let mut body = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| ServiceError::new(format!("无法读取 DDL 数据：{error}")))?
    {
        if body.len() + chunk.len() > MAX_RESPONSE_BYTES {
            return Err(ServiceError::new("DDL 数据响应过大。"));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

async fn fetch_source(
    endpoint: &str,
    host: &'static str,
    allow_plain_http: bool,
) -> ServiceResult<Vec<u8>> {
    if let Some(bytes) = cached_source(endpoint) {
        return Ok(bytes);
    }
    let url = Url::parse(endpoint)
        .map_err(|error| ServiceError::new(format!("DDL 数据源地址无效：{error}")))?;
    validate_endpoint(&url, host, allow_plain_http)?;
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(15))
        // Both endpoints are fixed. Refusing redirects prevents the plaintext
        // backup from becoming an open redirect to another host.
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|error| ServiceError::new(format!("无法创建 DDL 请求：{error}")))?;
    let response = client
        .get(url)
        .header(reqwest::header::ACCEPT, "application/json")
        .header(reqwest::header::USER_AGENT, USER_AGENT)
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法获取 DDL 数据：{error}")))?;
    if response.status().is_redirection() {
        return Err(ServiceError::new("DDL 数据源返回了不受信任的重定向。"));
    }
    let response = response
        .error_for_status()
        .map_err(|error| ServiceError::new(format!("DDL 数据源返回错误：{error}")))?;
    let bytes = read_limited(response).await?;
    cache_source(endpoint, &bytes);
    Ok(bytes)
}

async fn fetch_custom_source(endpoint: &str) -> ServiceResult<Vec<u8>> {
    let url = validate_custom_feed_endpoint(endpoint)?;
    let cache_key = url.as_str().to_string();
    if let Some(bytes) = cached_source(&cache_key) {
        return Ok(bytes);
    }
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(15))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|error| ServiceError::new(format!("无法创建自定义日程请求：{error}")))?;
    let response = client
        .get(url)
        .header(reqwest::header::ACCEPT, "application/json")
        .header(reqwest::header::USER_AGENT, USER_AGENT)
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法获取自定义日程：{error}")))?;
    if response.status().is_redirection() {
        return Err(ServiceError::new("自定义日程接口返回了不受信任的重定向。"));
    }
    let response = response
        .error_for_status()
        .map_err(|error| ServiceError::new(format!("自定义日程接口返回错误：{error}")))?;
    let bytes = read_limited(response).await?;
    cache_source(&cache_key, &bytes);
    Ok(bytes)
}

fn parse_source_range(
    bytes: &[u8],
    start_date: NaiveDate,
    end_date: NaiveDate,
) -> ServiceResult<Vec<DeadlineItem>> {
    let envelope: SourceEnvelope = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("DDL 数据解析失败：{error}")))?;
    let max_items = MAX_ITEMS_PER_DAY.saturating_mul(
        (end_date.signed_duration_since(start_date).num_days() + 1).max(1) as usize,
    );
    let mut items = Vec::new();
    for source in envelope.items {
        if !matches!(
            source.event_type.as_str(),
            "competition" | "summer_camp" | "hackathon"
        ) {
            continue;
        }
        let Some(deadline) = source.primary_deadline else {
            continue;
        };
        let Ok(parsed_deadline) = DateTime::parse_from_rfc3339(&deadline) else {
            continue;
        };
        let Some(deadline_date) = deadline
            .get(..10)
            .and_then(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d").ok())
        else {
            continue;
        };
        if deadline_date < start_date || deadline_date > end_date {
            continue;
        }
        let id = source.id.trim();
        let name = source.name.trim();
        if id.is_empty() || name.is_empty() {
            continue;
        }
        let official_url = trusted_https_url(source.official_url);
        items.push(DeadlineItem {
            id: id.to_string(),
            name: name.to_string(),
            event_type: source.event_type,
            source_type: "contest_ddl".to_string(),
            primary_deadline: parsed_deadline.to_rfc3339(),
            organizer: source
                .organizer
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty()),
            official_url,
            source_name: None,
            source_url: None,
        });
        if items.len() >= max_items {
            break;
        }
    }
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    Ok(items)
}

fn parse_custom_source_range(
    bytes: &[u8],
    start_date: NaiveDate,
    end_date: NaiveDate,
    feed_url: &str,
) -> ServiceResult<Vec<DeadlineItem>> {
    let envelope: CustomSourceEnvelope = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("自定义日程数据解析失败：{error}")))?;
    if envelope.version != 1 {
        return Err(ServiceError::with_status(
            "自定义日程接口版本必须为 1。",
            400,
        ));
    }
    if !envelope.extra.is_empty() {
        return Err(ServiceError::with_status(
            "自定义日程不符合 v1 接口规范。",
            400,
        ));
    }
    let source_name = envelope.source.trim();
    if source_name.is_empty() || source_name.chars().count() > 80 {
        return Err(ServiceError::with_status("自定义日程来源名称无效。", 400));
    }
    if envelope.items.len() > MAX_CUSTOM_ITEMS {
        return Err(ServiceError::with_status(
            "自定义日程条目超过 5000 项。",
            400,
        ));
    }
    if envelope
        .homepage
        .as_deref()
        .is_some_and(|value| trusted_https_url(Some(value.to_string())).is_none())
    {
        return Err(ServiceError::with_status(
            "自定义日程来源主页必须使用 HTTPS。",
            400,
        ));
    }
    let source_url = trusted_https_url(envelope.homepage.clone())
        .or_else(|| trusted_https_url(Some(feed_url.to_string())));
    if envelope
        .updated_at
        .as_deref()
        .is_some_and(|value| DateTime::parse_from_rfc3339(value).is_err())
    {
        return Err(ServiceError::with_status(
            "自定义日程更新时间格式不正确。",
            400,
        ));
    }

    let max_items = MAX_ITEMS_PER_DAY.saturating_mul(
        (end_date.signed_duration_since(start_date).num_days() + 1).max(1) as usize,
    );
    let mut items = Vec::new();
    let mut accepted_per_day = HashMap::<NaiveDate, usize>::new();
    for source in envelope.items {
        if !source.extra.is_empty() {
            continue;
        }
        if !matches!(
            source.event_type.as_str(),
            "competition" | "summer_camp" | "hackathon" | "custom"
        ) {
            continue;
        }
        let Some(deadline) = source.primary_deadline else {
            continue;
        };
        let Ok(parsed_deadline) = DateTime::parse_from_rfc3339(&deadline) else {
            continue;
        };
        let Some(deadline_date) = deadline
            .get(..10)
            .and_then(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d").ok())
        else {
            continue;
        };
        if deadline_date < start_date || deadline_date > end_date {
            continue;
        }
        if accepted_per_day
            .get(&deadline_date)
            .is_some_and(|count| *count >= MAX_ITEMS_PER_DAY)
        {
            continue;
        }
        let id = source.id.trim();
        let name = source.name.trim();
        if id.is_empty()
            || id.chars().count() > 128
            || name.is_empty()
            || name.chars().count() > 200
        {
            continue;
        }
        let organizer = match source.organizer {
            Some(value) => {
                let normalized = value.trim();
                if normalized.is_empty() || normalized.chars().count() > 200 {
                    continue;
                }
                Some(normalized.to_string())
            }
            None => None,
        };
        let official_url = match source.official_url {
            Some(value) => {
                let Some(url) = trusted_https_url(Some(value)) else {
                    continue;
                };
                Some(url)
            }
            None => None,
        };
        items.push(DeadlineItem {
            id: format!("custom:{id}"),
            name: name.to_string(),
            event_type: source.event_type,
            source_type: "custom".to_string(),
            primary_deadline: parsed_deadline.to_rfc3339(),
            organizer: organizer.or_else(|| Some(source_name.to_string())),
            official_url,
            source_name: Some(source_name.to_string()),
            source_url: source_url.clone(),
        });
        *accepted_per_day.entry(deadline_date).or_default() += 1;
        if items.len() >= max_items {
            break;
        }
    }
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    Ok(items)
}

#[cfg(test)]
fn parse_source(bytes: &[u8], requested_date: NaiveDate) -> ServiceResult<Vec<DeadlineItem>> {
    parse_source_range(bytes, requested_date, requested_date)
}

fn parse_school_notices_range(
    bytes: &[u8],
    start_date: NaiveDate,
    end_date: NaiveDate,
) -> ServiceResult<Vec<DeadlineItem>> {
    let envelope: SchoolNoticeEnvelope = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("校内竞赛通知解析失败：{error}")))?;
    let max_items = MAX_ITEMS_PER_DAY.saturating_mul(
        (end_date.signed_duration_since(start_date).num_days() + 1).max(1) as usize,
    );
    let mut items = Vec::new();
    for notice in envelope.items {
        let id = notice.id.trim().to_string();
        let name = notice
            .name
            .as_deref()
            .or(notice.title.as_deref())
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(str::to_string);
        let Some(name) = name else { continue };
        if id.is_empty() {
            continue;
        }
        let source_name = notice
            .source
            .as_deref()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .unwrap_or("北京邮电大学教学云平台")
            .to_string();
        let official_url = trusted_https_url(notice.source_url);
        let deadlines = if notice.deadlines.is_empty() {
            notice
                .primary_deadline
                .map(|date| {
                    vec![SchoolNoticeDeadline {
                        date,
                        label: notice.primary_deadline_label,
                    }]
                })
                .unwrap_or_default()
        } else {
            notice.deadlines
        };
        for (index, entry) in deadlines.into_iter().enumerate() {
            let deadline = entry.date.trim();
            let Ok(parsed_deadline) = DateTime::parse_from_rfc3339(deadline) else {
                continue;
            };
            let Some(deadline_date) = deadline
                .get(..10)
                .and_then(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d").ok())
            else {
                continue;
            };
            if deadline_date < start_date || deadline_date > end_date {
                continue;
            }
            let label = entry
                .label
                .as_deref()
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .unwrap_or("截止时间");
            items.push(DeadlineItem {
                id: format!("school:{id}:{index}"),
                name: name.clone(),
                event_type: "competition".to_string(),
                source_type: "school_notice".to_string(),
                primary_deadline: parsed_deadline.to_rfc3339(),
                organizer: Some(format!("{source_name} · {label}")),
                official_url: official_url.clone(),
                source_name: None,
                source_url: None,
            });
            if items.len() >= max_items {
                break;
            }
        }
        if items.len() >= max_items {
            break;
        }
    }
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    Ok(items)
}

fn parse_school_notices(
    bytes: &[u8],
    requested_date: NaiveDate,
) -> ServiceResult<Vec<DeadlineItem>> {
    parse_school_notices_range(bytes, requested_date, requested_date)
}

fn trusted_https_url(value: Option<String>) -> Option<String> {
    value.and_then(|value| {
        let trimmed = value.trim();
        Url::parse(trimmed)
            .ok()
            .filter(|url| {
                url.scheme() == "https"
                    && url.host_str().is_some()
                    && url.username().is_empty()
                    && url.password().is_none()
            })
            .map(|_| trimmed.to_string())
    })
}

fn merge_items(groups: impl IntoIterator<Item = Vec<DeadlineItem>>) -> Vec<DeadlineItem> {
    merge_items_with_limit(groups, MAX_ITEMS_PER_DAY)
}

fn merge_items_with_limit(
    groups: impl IntoIterator<Item = Vec<DeadlineItem>>,
    max_items: usize,
) -> Vec<DeadlineItem> {
    let mut seen = HashSet::new();
    let mut items = Vec::new();
    for item in groups.into_iter().flatten() {
        let key = format!(
            "{}\u{1f}{}\u{1f}{}\u{1f}{}",
            item.source_type,
            item.event_type,
            item.name.trim().to_lowercase(),
            item.primary_deadline
        );
        if seen.insert(key) {
            items.push(item);
        }
    }
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    items.truncate(max_items);
    items
}

async fn fetch_contest_deadlines(
    date: NaiveDate,
) -> ServiceResult<(Vec<DeadlineItem>, String, bool)> {
    fetch_contest_deadlines_range(date, date).await
}

async fn fetch_contest_deadlines_range(
    start_date: NaiveDate,
    end_date: NaiveDate,
) -> ServiceResult<(Vec<DeadlineItem>, String, bool)> {
    match fetch_source(PRIMARY_URL, PRIMARY_HOST, false).await {
        Ok(bytes) => Ok((
            parse_source_range(&bytes, start_date, end_date)?,
            PRIMARY_URL.to_string(),
            false,
        )),
        Err(primary_error) => {
            let bytes =
                fetch_source(BACKUP_URL, BACKUP_HOST, true)
                    .await
                    .map_err(|backup_error| {
                        ServiceError::new(format!(
                            "主 DDL 数据源不可用（{}）；备用数据源也不可用（{}）。",
                            primary_error.message, backup_error.message
                        ))
                    })?;
            Ok((
                parse_source_range(&bytes, start_date, end_date)?,
                BACKUP_URL.to_string(),
                true,
            ))
        }
    }
}

pub async fn fetch_deadlines(payload: &DeadlinesRequest) -> ServiceResult<DeadlinesResponse> {
    let date = parse_date(payload.date.trim())?;
    let contest = fetch_contest_deadlines(date).await;
    let school = fetch_source(SCHOOL_NOTICES_URL, BACKUP_HOST, true)
        .await
        .and_then(|bytes| parse_school_notices(&bytes, date));
    let (contest_items, source, used_backup) = match (contest, school) {
        (Ok((contest_items, source, used_backup)), Ok(school_items)) => (
            merge_items([contest_items, school_items]),
            source,
            used_backup,
        ),
        (Ok((contest_items, source, used_backup)), Err(_)) => (contest_items, source, used_backup),
        (Err(_), Ok(school_items)) => (school_items, SCHOOL_NOTICES_URL.to_string(), false),
        (Err(contest_error), Err(school_error)) => {
            return Err(ServiceError::new(format!(
                "公开活动 DDL 不可用（{}）；校内竞赛通知也不可用（{}）。",
                contest_error.message, school_error.message
            )));
        }
    };
    Ok(DeadlinesResponse {
        date: date.to_string(),
        fetched_at: crate::config::now_in_app_tz(),
        source,
        used_backup,
        items: contest_items,
    })
}

pub async fn fetch_deadline_calendar(
    payload: &CalendarRangeRequest,
) -> ServiceResult<DeadlineCalendarResponse> {
    let start = parse_date(payload.start_date.trim())?;
    let end = parse_date(payload.end_date.trim())?;
    let day_count = end.signed_duration_since(start).num_days() + 1;
    if !(1..=MAX_CALENDAR_RANGE_DAYS).contains(&day_count) {
        return Err(ServiceError::with_status(
            "DDL 日历查询范围必须在 1 至 370 天内。",
            400,
        ));
    }

    let contest = fetch_contest_deadlines_range(start, end).await;
    let school = fetch_source(SCHOOL_NOTICES_URL, BACKUP_HOST, true)
        .await
        .and_then(|bytes| parse_school_notices_range(&bytes, start, end));
    let (contest_items, source, used_backup) = match (contest, school) {
        (Ok((contest_items, source, used_backup)), Ok(school_items)) => (
            merge_items_with_limit(
                [contest_items, school_items],
                MAX_ITEMS_PER_DAY.saturating_mul(day_count as usize),
            ),
            source,
            used_backup,
        ),
        (Ok((contest_items, source, used_backup)), Err(_)) => (contest_items, source, used_backup),
        (Err(_), Ok(school_items)) => (school_items, SCHOOL_NOTICES_URL.to_string(), false),
        (Err(contest_error), Err(school_error)) => {
            return Err(ServiceError::new(format!(
                "公开活动 DDL 不可用（{}）；校内竞赛通知也不可用（{}）。",
                contest_error.message, school_error.message
            )));
        }
    };

    Ok(DeadlineCalendarResponse {
        start_date: start.to_string(),
        end_date: end.to_string(),
        fetched_at: crate::config::now_in_app_tz(),
        source,
        used_backup,
        items: contest_items,
    })
}

pub async fn fetch_custom_deadline_calendar(
    payload: &crate::models::CustomDeadlineCalendarRequest,
) -> ServiceResult<DeadlineCalendarResponse> {
    let start = parse_date(payload.start_date.trim())?;
    let end = parse_date(payload.end_date.trim())?;
    let day_count = end.signed_duration_since(start).num_days() + 1;
    if !(1..=MAX_CALENDAR_RANGE_DAYS).contains(&day_count) {
        return Err(ServiceError::with_status(
            "自定义日程查询范围必须在 1 至 370 天内。",
            400,
        ));
    }
    let url = validate_custom_feed_endpoint(&payload.url)?;
    let bytes = fetch_custom_source(url.as_str()).await?;
    let items = parse_custom_source_range(&bytes, start, end, url.as_str())?;
    Ok(DeadlineCalendarResponse {
        start_date: start.to_string(),
        end_date: end.to_string(),
        fetched_at: crate::config::now_in_app_tz(),
        source: url.to_string(),
        used_backup: false,
        items,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parser_filters_selected_day_and_supported_types() {
        let data = r#"{
          "items":[
            {"id":"c1","name":"数据库竞赛","event_type":"competition","primary_deadline":"2026-08-22T18:00:00+08:00","organizer":"组委会","official_url":"https://example.com/c1"},
            {"id":"h1","name":"校园黑客松","event_type":"hackathon","primary_deadline":"2026-08-22T23:59:59+08:00"},
            {"id":"s1","name":"夏令营","event_type":"summer_camp","primary_deadline":"2026-08-23T23:59:59+08:00"},
            {"id":"x1","name":"未知类型","event_type":"other","primary_deadline":"2026-08-22T12:00:00+08:00"}
          ]
        }"#;
        let date = NaiveDate::from_ymd_opt(2026, 8, 22).unwrap();
        let parsed = parse_source(data.as_bytes(), date).unwrap();
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].event_type, "competition");
        assert_eq!(parsed[0].source_type, "contest_ddl");
        assert_eq!(parsed[1].event_type, "hackathon");
    }

    #[test]
    fn parser_drops_plaintext_official_links() {
        let data = r#"{"items":[{"id":"c1","name":"竞赛","event_type":"competition","primary_deadline":"2026-08-22T18:00:00+08:00","official_url":"http://example.com"}]}"#;
        let date = NaiveDate::from_ymd_opt(2026, 8, 22).unwrap();
        let parsed = parse_source(data.as_bytes(), date).unwrap();
        assert_eq!(parsed[0].official_url, None);
    }

    #[test]
    fn calendar_parser_returns_each_supported_deadline_in_the_requested_range() {
        let data = r#"{"items":[
          {"id":"d1","name":"第一项","event_type":"competition","primary_deadline":"2026-08-17T18:00:00+08:00"},
          {"id":"d2","name":"第二项","event_type":"hackathon","primary_deadline":"2026-08-23T23:59:59+08:00"},
          {"id":"d3","name":"范围外","event_type":"summer_camp","primary_deadline":"2026-08-24T23:59:59+08:00"}
        ]}"#;
        let start = NaiveDate::from_ymd_opt(2026, 8, 17).unwrap();
        let end = NaiveDate::from_ymd_opt(2026, 8, 23).unwrap();
        let parsed = parse_source_range(data.as_bytes(), start, end).unwrap();
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].id, "d1");
        assert_eq!(parsed[1].id, "d2");
    }

    #[test]
    fn calendar_merge_does_not_apply_the_single_day_item_cap_to_a_year() {
        let items: Vec<_> = (0..150)
            .map(|index| DeadlineItem {
                id: format!("id-{index}"),
                name: format!("event-{index}"),
                event_type: "competition".to_string(),
                source_type: "contest_ddl".to_string(),
                primary_deadline: format!(
                    "2026-{:02}-{:02}T18:00:00+08:00",
                    (index / 28) + 1,
                    (index % 28) + 1
                ),
                organizer: None,
                official_url: None,
                source_name: None,
                source_url: None,
            })
            .collect();
        assert_eq!(merge_items([items.clone()]).len(), MAX_ITEMS_PER_DAY);
        assert_eq!(
            merge_items_with_limit([items], 365 * MAX_ITEMS_PER_DAY).len(),
            150
        );
    }

    #[test]
    fn endpoint_policy_only_allows_the_pinned_primary_and_backup_hosts() {
        assert!(validate_endpoint(&Url::parse(PRIMARY_URL).unwrap(), PRIMARY_HOST, false).is_ok());
        assert!(validate_endpoint(&Url::parse(BACKUP_URL).unwrap(), BACKUP_HOST, true).is_ok());
        assert!(
            validate_endpoint(&Url::parse(SCHOOL_NOTICES_URL).unwrap(), BACKUP_HOST, true).is_ok()
        );
        assert!(validate_endpoint(
            &Url::parse("http://example.com/data").unwrap(),
            BACKUP_HOST,
            true
        )
        .is_err());
    }

    #[test]
    fn custom_endpoint_policy_requires_public_credential_free_https() {
        assert!(validate_custom_feed_endpoint("https://calendar.example.com/feed.json").is_ok());
        for rejected in [
            "http://calendar.example.com/feed.json",
            "https://localhost/feed.json",
            "https://calendar.localhost/feed.json",
            "https://127.0.0.1/feed.json",
            "https://192.168.1.2/feed.json",
            "https://[::1]/feed.json",
            "https://user:password@example.com/feed.json",
            "https://example.com/feed.json#fragment",
        ] {
            assert!(
                validate_custom_feed_endpoint(rejected).is_err(),
                "unexpectedly accepted {rejected}"
            );
        }
    }

    #[test]
    fn custom_feed_fixture_uses_v1_contract_and_custom_source_identity() {
        let fixture = include_bytes!("../../contracts/v1/fixtures/custom-deadline-feed.json");
        let start = NaiveDate::from_ymd_opt(2026, 9, 1).unwrap();
        let end = NaiveDate::from_ymd_opt(2026, 10, 31).unwrap();
        let parsed = parse_custom_source_range(
            fixture,
            start,
            end,
            "https://calendar.example.com/feed.json",
        )
        .unwrap();
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].id, "custom:example-registration");
        assert_eq!(parsed[0].event_type, "custom");
        assert_eq!(parsed[0].source_type, "custom");
        assert_eq!(parsed[0].organizer.as_deref(), Some("示例组织方"));
        assert_eq!(parsed[0].source_name.as_deref(), Some("示例自定义日程"));
        assert_eq!(
            parsed[0].source_url.as_deref(),
            Some("https://example.com/calendar")
        );
        assert_eq!(parsed[1].id, "custom:example-competition");
    }

    #[test]
    fn custom_feed_rejects_unknown_contract_versions() {
        let payload = br#"{"version":2,"source":"test","items":[]}"#;
        let date = NaiveDate::from_ymd_opt(2026, 9, 1).unwrap();
        assert!(parse_custom_source_range(
            payload,
            date,
            date,
            "https://calendar.example.com/feed.json",
        )
        .is_err());
    }

    #[test]
    fn custom_feed_rejects_invalid_envelopes_and_skips_unsafe_items() {
        let date = NaiveDate::from_ymd_opt(2026, 9, 18).unwrap();
        for payload in [
            br#"{"version":1,"source":"missing items"}"#.as_slice(),
            br#"{"version":1,"source":"bad homepage","homepage":"http://example.com","items":[]}"#
                .as_slice(),
            br#"{"version":1,"source":"bad update","updated_at":"2026-08-24","items":[]}"#
                .as_slice(),
            br#"{"version":1,"source":"extra","items":[],"unknown":true}"#.as_slice(),
        ] {
            assert!(parse_custom_source_range(
                payload,
                date,
                date,
                "https://calendar.example.com/feed.json",
            )
            .is_err());
        }

        let oversized_organizer = "x".repeat(201);
        let payload = serde_json::to_vec(&serde_json::json!({
            "version": 1,
            "source": "Example",
            "items": [
                {
                    "id": "unsafe",
                    "name": "Unsafe",
                    "event_type": "custom",
                    "primary_deadline": "2026-09-18T12:00:00+08:00",
                    "official_url": "http://example.com"
                },
                {
                    "id": "organizer",
                    "name": "Organizer",
                    "event_type": "custom",
                    "primary_deadline": "2026-09-18T13:00:00+08:00",
                    "organizer": oversized_organizer
                },
                {
                    "id": "unknown-field",
                    "name": "Unknown field",
                    "event_type": "custom",
                    "primary_deadline": "2026-09-18T14:00:00+08:00",
                    "unknown": true
                }
            ]
        }))
        .unwrap();
        let parsed = parse_custom_source_range(
            &payload,
            date,
            date,
            "https://calendar.example.com/feed.json",
        )
        .unwrap();
        assert!(parsed.is_empty());
    }

    #[test]
    fn custom_feed_caps_each_calendar_day_at_one_hundred_items() {
        let items = (0..105)
            .map(|index| {
                serde_json::json!({
                    "id": format!("item-{index}"),
                    "name": format!("Item {index}"),
                    "event_type": "custom",
                    "primary_deadline": "2026-09-18T23:59:00+08:00"
                })
            })
            .collect::<Vec<_>>();
        let payload = serde_json::to_vec(&serde_json::json!({
            "version": 1,
            "source": "Daily limit fixture",
            "items": items
        }))
        .unwrap();
        let date = NaiveDate::from_ymd_opt(2026, 9, 18).unwrap();

        let parsed = parse_custom_source_range(
            &payload,
            date,
            date,
            "https://calendar.example.com/feed.json",
        )
        .unwrap();
        assert_eq!(parsed.len(), MAX_ITEMS_PER_DAY);
    }

    #[test]
    fn source_cache_reuses_the_complete_feed_payload() {
        let endpoint = "test://deadline-startup-preheat";
        let payload = br#"{"items":[{"id":"first"},{"id":"last"}]}"#;
        cache_source(endpoint, payload);
        assert_eq!(cached_source(endpoint).as_deref(), Some(payload.as_slice()));
        source_cache()
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove(endpoint);
    }

    #[test]
    fn school_notice_parser_expands_deadlines_and_filters_the_selected_day() {
        let data = r#"{
          "items":[{
            "id":"bupt-ucloud-1",
            "name":"校内创新竞赛",
            "deadlines":[
              {"date":"2026-08-22T10:00:00+08:00","label":"材料提交"},
              {"date":"2026-08-23T23:59:59+08:00","label":"报名截止"}
            ],
            "source":"北京邮电大学教学云平台",
            "source_url":"https://ucloud.bupt.edu.cn/#/consulting?type=1&id=1"
          }]
        }"#;
        let date = NaiveDate::from_ymd_opt(2026, 8, 22).unwrap();
        let parsed = parse_school_notices(data.as_bytes(), date).unwrap();
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].event_type, "competition");
        assert_eq!(parsed[0].source_type, "school_notice");
        assert_eq!(
            parsed[0].organizer.as_deref(),
            Some("北京邮电大学教学云平台 · 材料提交")
        );
        assert_eq!(
            parsed[0].official_url.as_deref(),
            Some("https://ucloud.bupt.edu.cn/#/consulting?type=1&id=1")
        );
    }
}
