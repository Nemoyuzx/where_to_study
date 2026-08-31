use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use chrono::{DateTime, NaiveDate, NaiveTime};
use reqwest::Url;

use crate::error::{ServiceError, ServiceResult};
use crate::models::{ShuttleBusResponse, ShuttleBusSchedule};

const SHUTTLE_URL: &str = "https://where-to-study.cn/api/shuttle-bus";
const SHUTTLE_HOST: &str = "where-to-study.cn";
const SOURCE_HOST: &str = "hq.bupt.edu.cn";
const MAX_RESPONSE_BYTES: usize = 512 * 1024;
const CACHE_TTL: Duration = Duration::from_secs(5 * 60);
const USER_AGENT: &str = concat!("WhereToStudy/", env!("CARGO_PKG_VERSION"));
const WEEKDAYS: [&str; 7] = [
    "monday",
    "tuesday",
    "wednesday",
    "thursday",
    "friday",
    "saturday",
    "sunday",
];

struct ShuttleCacheEntry {
    fetched_at: Instant,
    response: ShuttleBusResponse,
}

static CACHE: OnceLock<Mutex<Option<ShuttleCacheEntry>>> = OnceLock::new();

fn cache() -> &'static Mutex<Option<ShuttleCacheEntry>> {
    CACHE.get_or_init(|| Mutex::new(None))
}

fn cached_response() -> Option<ShuttleBusResponse> {
    cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .as_ref()
        .filter(|entry| entry.fetched_at.elapsed() < CACHE_TTL)
        .map(|entry| entry.response.clone())
}

fn save_cache(response: &ShuttleBusResponse) {
    *cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(ShuttleCacheEntry {
        fetched_at: Instant::now(),
        response: response.clone(),
    });
}

fn validate_fixed_endpoint() -> ServiceResult<Url> {
    let url = Url::parse(SHUTTLE_URL)
        .map_err(|error| ServiceError::new(format!("班车接口地址无效：{error}")))?;
    if url.scheme() != "https"
        || url.host_str() != Some(SHUTTLE_HOST)
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(ServiceError::new("班车接口地址不受信任。"));
    }
    Ok(url)
}

fn trusted_https_url(value: &str, allowed_host: &str) -> bool {
    Url::parse(value).is_ok_and(|url| {
        url.scheme() == "https"
            && url.host_str() == Some(allowed_host)
            && url.username().is_empty()
            && url.password().is_none()
    })
}

fn valid_text(value: &str, maximum: usize) -> bool {
    let text = value.trim();
    !text.is_empty() && text.chars().count() <= maximum
}

fn valid_optional_text(value: Option<&str>, maximum: usize) -> bool {
    value.is_none_or(|text| valid_text(text, maximum))
}

fn validate_schedule(schedule: &ShuttleBusSchedule) -> ServiceResult<()> {
    if !valid_text(&schedule.period.label, 120)
        || !valid_optional_text(schedule.from.as_deref(), 80)
        || !valid_optional_text(schedule.to.as_deref(), 80)
        || !matches!(
            schedule.parse_status.as_str(),
            "parsed" | "needs_review" | "image_only"
        )
        || !schedule.parse_confidence.is_finite()
        || !(0.0..=1.0).contains(&schedule.parse_confidence)
        || !valid_text(&schedule.parse_engine, 80)
        || schedule.rows.len() > 96
    {
        return Err(ServiceError::new("班车时刻表字段不符合接口规范。"));
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
    if start.zip(end).is_some_and(|(from, to)| from > to) {
        return Err(ServiceError::new("班车运行日期范围无效。"));
    }

    for row in &schedule.rows {
        if NaiveTime::parse_from_str(&row.departure_time, "%H:%M").is_err()
            || row
                .services
                .keys()
                .any(|key| !WEEKDAYS.contains(&key.as_str()))
        {
            return Err(ServiceError::new("班车发车时间或星期字段无效。"));
        }
        for service in row.services.values().flatten() {
            if !valid_text(&service.vehicle, 24) || !(1..=20).contains(&service.count) {
                return Err(ServiceError::new("班车车型或车辆数量无效。"));
            }
        }
    }
    Ok(())
}

fn parse_payload(bytes: &[u8]) -> ServiceResult<ShuttleBusResponse> {
    let response: ShuttleBusResponse = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("班车数据解析失败：{error}")))?;
    if response.schema_version != "1.0"
        || !matches!(response.status.as_str(), "healthy" | "stale")
        || DateTime::parse_from_rfc3339(&response.generated_at).is_err()
        || !valid_text(&response.source.name, 80)
        || !trusted_https_url(&response.source.page_url, SOURCE_HOST)
        || response.items.len() > 100
    {
        return Err(ServiceError::new("班车数据不符合 Schema 1.0。"));
    }

    for notice in &response.items {
        if !valid_text(&notice.id, 128)
            || !valid_text(&notice.title, 240)
            || NaiveDate::parse_from_str(&notice.published_at, "%Y-%m-%d").is_err()
            || !trusted_https_url(&notice.source_url, SOURCE_HOST)
            || !matches!(
                notice.parse_status.as_str(),
                "parsed" | "partial" | "needs_review" | "text_only"
            )
            || notice.stops.len() > 20
            || notice.notes.len() > 40
            || notice.schedules.len() > 32
        {
            return Err(ServiceError::new("班车通知字段不符合接口规范。"));
        }
        if notice
            .stops
            .iter()
            .any(|stop| !valid_text(&stop.campus, 80) || !valid_text(&stop.location, 160))
            || notice.notes.iter().any(|note| !valid_text(note, 600))
        {
            return Err(ServiceError::new("班车站点或乘车提示字段无效。"));
        }
        for schedule in &notice.schedules {
            validate_schedule(schedule)?;
        }
    }
    Ok(response)
}

async fn read_limited(mut response: reqwest::Response) -> ServiceResult<Vec<u8>> {
    if response
        .content_length()
        .is_some_and(|length| length > MAX_RESPONSE_BYTES as u64)
    {
        return Err(ServiceError::new("班车数据响应过大。"));
    }
    let mut body = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| ServiceError::new(format!("无法读取班车数据：{error}")))?
    {
        if body.len() + chunk.len() > MAX_RESPONSE_BYTES {
            return Err(ServiceError::new("班车数据响应过大。"));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

pub async fn fetch_shuttle_bus() -> ServiceResult<ShuttleBusResponse> {
    if let Some(response) = cached_response() {
        return Ok(response);
    }
    let url = validate_fixed_endpoint()?;
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(15))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|error| ServiceError::new(format!("无法创建班车请求：{error}")))?;
    let response = client
        .get(url)
        .header(reqwest::header::ACCEPT, "application/json")
        .header(reqwest::header::USER_AGENT, USER_AGENT)
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法获取班车数据：{error}")))?;
    if response.status().is_redirection() {
        return Err(ServiceError::new("班车接口返回了不受信任的重定向。"));
    }
    let response = response
        .error_for_status()
        .map_err(|error| ServiceError::new(format!("班车接口返回错误：{error}")))?;
    let parsed = parse_payload(&read_limited(response).await?)?;
    save_cache(&parsed);
    Ok(parsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn fixture() -> Vec<u8> {
        serde_json::to_vec(&serde_json::json!({
            "schema_version": "1.0",
            "generated_at": "2026-08-31T00:59:26.123Z",
            "status": "healthy",
            "source": {"name":"北京邮电大学后勤部","page_url":"https://hq.bupt.edu.cn/tzgg.htm"},
            "stats": {"notices":1,"images":1,"parsed_schedules":1,"needs_review":0},
            "last_parsed_notice_id": "notice-1",
            "items": [{
                "id":"notice-1",
                "title":"关于两校区班车运行调整的通知",
                "published_at":"2026-08-19",
                "source_url":"https://hq.bupt.edu.cn/info/1010/1541.htm",
                "parse_status":"parsed",
                "stops":[{"campus":"西土城路校区","location":"教三楼西侧"}],
                "notes":["请提前五分钟候车。"],
                "schedules":[{
                    "period":{"label":"第一时段","start_date":"2026-08-27","end_date":"2026-09-04"},
                    "from":"西土城路校区",
                    "to":"沙河校区",
                    "parse_status":"parsed",
                    "parse_confidence":0.98,
                    "parse_engine":"paddleocr-vl-1.6-shuttle-v1",
                    "rows":[{"departure_time":"06:30","services":{"monday":{"vehicle":"大巴","count":1},"sunday":null}}]
                }]
            }]
        }))
        .unwrap()
    }

    #[test]
    fn parses_the_pinned_schema_and_weekday_services() {
        let parsed = parse_payload(&fixture()).unwrap();
        assert_eq!(parsed.schema_version, "1.0");
        assert_eq!(parsed.items[0].schedules[0].rows[0].departure_time, "06:30");
        assert_eq!(
            parsed.items[0].schedules[0].rows[0].services["monday"]
                .as_ref()
                .unwrap()
                .count,
            1
        );
    }

    #[test]
    fn rejects_unknown_schema_weekdays_and_untrusted_source_urls() {
        let mut value: serde_json::Value = serde_json::from_slice(&fixture()).unwrap();
        value["schema_version"] = serde_json::json!("2.0");
        assert!(parse_payload(&serde_json::to_vec(&value).unwrap()).is_err());

        let mut value: serde_json::Value = serde_json::from_slice(&fixture()).unwrap();
        value["items"][0]["schedules"][0]["rows"][0]["services"]["holiday"] =
            serde_json::json!({"vehicle":"大巴","count":1});
        assert!(parse_payload(&serde_json::to_vec(&value).unwrap()).is_err());

        let mut value: serde_json::Value = serde_json::from_slice(&fixture()).unwrap();
        value["items"][0]["source_url"] = serde_json::json!("https://example.com/notice");
        assert!(parse_payload(&serde_json::to_vec(&value).unwrap()).is_err());
    }

    #[test]
    fn canonical_endpoint_avoids_the_www_redirect() {
        let url = validate_fixed_endpoint().unwrap();
        assert_eq!(url.as_str(), SHUTTLE_URL);
        assert_eq!(url.host_str(), Some(SHUTTLE_HOST));
        assert!(!url.as_str().contains("www."));
    }

    #[test]
    #[ignore = "requires the live public Where To Study shuttle service"]
    fn live_public_api_matches_the_pinned_schema() {
        let response = tauri::async_runtime::block_on(fetch_shuttle_bus()).unwrap();
        assert_eq!(response.schema_version, "1.0");
        assert!(!response.items.is_empty());
        assert!(response.items.iter().any(|notice| {
            notice
                .schedules
                .iter()
                .any(|schedule| schedule.parse_status == "parsed" && !schedule.rows.is_empty())
        }));
    }
}
