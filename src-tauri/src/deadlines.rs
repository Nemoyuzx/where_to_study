use std::collections::HashSet;
use std::time::Duration;

use chrono::{DateTime, NaiveDate};
use reqwest::Url;
use serde::Deserialize;

use crate::error::{ServiceError, ServiceResult};
use crate::models::{DeadlineItem, DeadlinesRequest, DeadlinesResponse};

const PRIMARY_URL: &str = "https://nemoyuzx.github.io/contest-ddl/data/competitions.json";
const PRIMARY_HOST: &str = "nemoyuzx.github.io";
const BACKUP_URL: &str = "http://101.201.29.29/api/contest-events";
const SCHOOL_NOTICES_URL: &str = "http://101.201.29.29/api/contest-notices";
const BACKUP_HOST: &str = "101.201.29.29";
const MAX_RESPONSE_BYTES: usize = 2 * 1024 * 1024;
const MAX_ITEMS_PER_DAY: usize = 100;
const USER_AGENT: &str = concat!("WhereToStudy/", env!("CARGO_PKG_VERSION"));

#[derive(Debug, Deserialize)]
struct SourceEnvelope {
    items: Vec<SourceDeadline>,
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
    read_limited(response).await
}

fn parse_source(bytes: &[u8], requested_date: NaiveDate) -> ServiceResult<Vec<DeadlineItem>> {
    let envelope: SourceEnvelope = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("DDL 数据解析失败：{error}")))?;
    let requested = requested_date.to_string();
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
        if deadline.get(..10) != Some(requested.as_str()) {
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
            primary_deadline: parsed_deadline.to_rfc3339(),
            organizer: source
                .organizer
                .map(|value| value.trim().to_string())
                .filter(|value| !value.is_empty()),
            official_url,
        });
        if items.len() >= MAX_ITEMS_PER_DAY {
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
    let envelope: SchoolNoticeEnvelope = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("校内竞赛通知解析失败：{error}")))?;
    let requested = requested_date.to_string();
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
            if deadline.get(..10) != Some(requested.as_str()) {
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
                primary_deadline: parsed_deadline.to_rfc3339(),
                organizer: Some(format!("{source_name} · {label}")),
                official_url: official_url.clone(),
            });
            if items.len() >= MAX_ITEMS_PER_DAY {
                break;
            }
        }
        if items.len() >= MAX_ITEMS_PER_DAY {
            break;
        }
    }
    items.sort_by(|left, right| {
        (&left.primary_deadline, &left.name).cmp(&(&right.primary_deadline, &right.name))
    });
    Ok(items)
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
    let mut seen = HashSet::new();
    let mut items = Vec::new();
    for item in groups.into_iter().flatten() {
        let key = format!(
            "{}\u{1f}{}\u{1f}{}",
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
    items.truncate(MAX_ITEMS_PER_DAY);
    items
}

async fn fetch_contest_deadlines(
    date: NaiveDate,
) -> ServiceResult<(Vec<DeadlineItem>, String, bool)> {
    match fetch_source(PRIMARY_URL, PRIMARY_HOST, false).await {
        Ok(bytes) => Ok((parse_source(&bytes, date)?, PRIMARY_URL.to_string(), false)),
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
            Ok((parse_source(&bytes, date)?, BACKUP_URL.to_string(), true))
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
