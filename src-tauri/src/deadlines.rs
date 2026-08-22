use std::time::Duration;

use chrono::{DateTime, NaiveDate};
use reqwest::Url;
use serde::Deserialize;

use crate::error::{ServiceError, ServiceResult};
use crate::models::{DeadlineItem, DeadlinesRequest, DeadlinesResponse};

const PRIMARY_URL: &str = "https://nemoyuzx.github.io/contest-ddl/data/competitions.json";
const PRIMARY_HOST: &str = "nemoyuzx.github.io";
const BACKUP_URL: &str = "http://101.201.29.29/api/contest-events";
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
        let official_url = source.official_url.and_then(|value| {
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
        });
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

pub async fn fetch_deadlines(payload: &DeadlinesRequest) -> ServiceResult<DeadlinesResponse> {
    let date = parse_date(payload.date.trim())?;
    match fetch_source(PRIMARY_URL, PRIMARY_HOST, false).await {
        Ok(bytes) => Ok(DeadlinesResponse {
            date: date.to_string(),
            fetched_at: crate::config::now_in_app_tz(),
            source: PRIMARY_URL.to_string(),
            used_backup: false,
            items: parse_source(&bytes, date)?,
        }),
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
            Ok(DeadlinesResponse {
                date: date.to_string(),
                fetched_at: crate::config::now_in_app_tz(),
                source: BACKUP_URL.to_string(),
                used_backup: true,
                items: parse_source(&bytes, date)?,
            })
        }
    }
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
        assert!(validate_endpoint(
            &Url::parse("http://example.com/data").unwrap(),
            BACKUP_HOST,
            true
        )
        .is_err());
    }
}
