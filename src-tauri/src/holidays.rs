use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::Duration as StdDuration;

use chrono::{DateTime, Datelike, Duration, NaiveDate, SecondsFormat};
use serde::Deserialize;
use tauri::{AppHandle, Manager};
use tempfile::NamedTempFile;

use crate::config::now_in_app_tz;
use crate::error::{ServiceError, ServiceResult};
use crate::models::{HolidayItem, HolidaysResponse};

const HOLIDAY_CACHE_PREFIX: &str = "holidays";
const HOLIDAY_DATA_SOURCE: &str = "https://unpkg.com/holiday-calendar@1.3.3/data/CN";
const HOLIDAY_FALLBACK_SOURCE: &str =
    "https://www.gov.cn/yaowen/liebiao/202511/content_7047099.htm";
const HOLIDAY_USER_AGENT: &str = concat!("WhereToStudyNative/", env!("CARGO_PKG_VERSION"));
const MAX_HOLIDAY_RESPONSE_BYTES: usize = 256 * 1024;
const MIN_HOLIDAY_YEAR: i32 = 1900;
const MAX_HOLIDAY_YEAR: i32 = 2100;
const MAX_HOLIDAY_SOURCE_LENGTH: usize = 512;
const MAX_HOLIDAY_FETCHED_AT_LENGTH: usize = 64;
const MAX_HOLIDAY_RECORDS: usize = 128;
const MAX_HOLIDAY_NAME_LENGTH: usize = 80;
const MAX_EXPANDED_HOLIDAY_ITEMS: usize = 512;

#[derive(Debug, Deserialize)]
struct SourceHolidaysResponse {
    year: i32,
    region: String,
    dates: Vec<SourceHoliday>,
}

#[derive(Debug, Deserialize)]
struct SourceHoliday {
    date: String,
    name: Option<String>,
    name_cn: Option<String>,
    #[serde(rename = "name_en")]
    _name_en: Option<String>,
    #[serde(rename = "type")]
    kind: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CachedHolidayItem {
    date: String,
    name: String,
    #[serde(rename = "type")]
    kind: String,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct CachedHolidaysResponse {
    year: i32,
    source: String,
    fetched_at: String,
    items: Vec<CachedHolidayItem>,
}

fn cache_path(app: &AppHandle, year: i32) -> ServiceResult<PathBuf> {
    let directory = app
        .path()
        .app_config_dir()
        .map_err(|error| ServiceError::new(format!("无法定位本地节假日目录：{error}")))?;
    Ok(directory.join(format!("{HOLIDAY_CACHE_PREFIX}_{year}.json")))
}

fn normalize_kind(kind: &str) -> Option<&'static str> {
    match kind {
        "public_holiday" => Some("holiday"),
        "transfer_workday" => Some("workday"),
        _ => None,
    }
}

fn parse_contract_date(value: &str) -> ServiceResult<NaiveDate> {
    let bytes = value.as_bytes();
    let has_contract_shape = bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit());
    if !has_contract_shape {
        return Err(ServiceError::new("节假日数据日期格式不正确。"));
    }
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ServiceError::new("节假日数据日期格式不正确。"))
}

fn validate_requested_year(year: i32) -> ServiceResult<()> {
    if !(MIN_HOLIDAY_YEAR..=MAX_HOLIDAY_YEAR).contains(&year) {
        return Err(ServiceError::new("节假日年份不在支持范围内。"));
    }
    Ok(())
}

fn parse_contract_timestamp(value: &str) -> ServiceResult<DateTime<chrono::FixedOffset>> {
    let bytes = value.as_bytes();
    let date_time_shape = bytes.len() >= 19
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes[10] == b'T'
        && bytes[13] == b':'
        && bytes[16] == b':'
        && [
            &bytes[0..4],
            &bytes[5..7],
            &bytes[8..10],
            &bytes[11..13],
            &bytes[14..16],
            &bytes[17..19],
        ]
        .iter()
        .all(|part| part.iter().all(u8::is_ascii_digit));
    let timezone_shape = (bytes.len() == 20 && bytes[19] == b'Z')
        || (bytes.len() == 25
            && matches!(bytes[19], b'+' | b'-')
            && bytes[22] == b':'
            && bytes[20..22].iter().all(u8::is_ascii_digit)
            && bytes[23..25].iter().all(u8::is_ascii_digit));

    if value.chars().count() > MAX_HOLIDAY_FETCHED_AT_LENGTH || !date_time_shape || !timezone_shape
    {
        return Err(ServiceError::new("本地节假日缓存的获取时间不正确。"));
    }

    DateTime::parse_from_rfc3339(value)
        .map_err(|_| ServiceError::new("本地节假日缓存的获取时间不正确。"))
}

fn now_contract_timestamp() -> ServiceResult<String> {
    let current = now_in_app_tz();
    let timestamp = DateTime::parse_from_rfc3339(&current)
        .map_err(|_| ServiceError::new("无法生成节假日数据获取时间。"))?
        .to_rfc3339_opts(SecondsFormat::Secs, false);
    parse_contract_timestamp(&timestamp)?;
    Ok(timestamp)
}

fn validate_holidays_response(
    response: &HolidaysResponse,
    expected_year: Option<i32>,
) -> ServiceResult<()> {
    validate_requested_year(response.year)?;
    if expected_year.is_some_and(|year| year != response.year) {
        return Err(ServiceError::new("本地节假日缓存年份与请求不一致。"));
    }
    if response.source.trim().is_empty()
        || response.source.chars().count() > MAX_HOLIDAY_SOURCE_LENGTH
    {
        return Err(ServiceError::new("本地节假日缓存的数据源不正确。"));
    }
    parse_contract_timestamp(&response.fetched_at)?;
    if response.items.len() > MAX_EXPANDED_HOLIDAY_ITEMS {
        return Err(ServiceError::new("本地节假日缓存的条目数量超过限制。"));
    }

    for item in &response.items {
        let date = parse_contract_date(&item.date)?;
        if date.year() != response.year {
            return Err(ServiceError::new("本地节假日缓存包含其他年份的日期。"));
        }
        if item.name.trim().is_empty() || item.name.chars().count() > MAX_HOLIDAY_NAME_LENGTH {
            return Err(ServiceError::new("本地节假日缓存的名称不正确。"));
        }
        if !matches!(item.kind.as_str(), "holiday" | "workday") {
            return Err(ServiceError::new("本地节假日缓存的类型不正确。"));
        }
    }

    Ok(())
}

fn parse_source_item(item: SourceHoliday, year: i32) -> ServiceResult<Option<HolidayItem>> {
    let name = item
        .name_cn
        .as_deref()
        .filter(|value| !value.trim().is_empty())
        .or(item.name.as_deref())
        .map(str::trim)
        .unwrap_or_default();
    if name.is_empty() {
        return Err(ServiceError::new("节假日名称不能为空。"));
    }
    if name.chars().count() > MAX_HOLIDAY_NAME_LENGTH {
        return Err(ServiceError::new("节假日名称过长。"));
    }
    let date = parse_contract_date(&item.date)?;
    if date.year() != year {
        return Err(ServiceError::new("节假日数据包含其他年份的日期。"));
    }
    let Some(kind) = normalize_kind(item.kind.as_str()) else {
        return Ok(None);
    };

    Ok(Some(HolidayItem {
        date: date.to_string(),
        name: name.to_string(),
        kind: kind.to_string(),
    }))
}

fn parse_source_payload(
    payload: SourceHolidaysResponse,
    year: i32,
) -> ServiceResult<Vec<HolidayItem>> {
    validate_requested_year(year)?;
    if payload.year != year {
        return Err(ServiceError::new("节假日数据年份与请求不一致。"));
    }
    if payload.region != "CN" {
        return Err(ServiceError::new("节假日数据区域不正确。"));
    }
    if payload.dates.len() > MAX_HOLIDAY_RECORDS {
        return Err(ServiceError::new("节假日数据记录过多。"));
    }
    let mut days = Vec::new();
    for item in payload.dates {
        if let Some(item) = parse_source_item(item, year)? {
            if days.len() >= MAX_EXPANDED_HOLIDAY_ITEMS {
                return Err(ServiceError::new("节假日展开记录过多。"));
            }
            days.push(item);
        }
        if days.len() > MAX_EXPANDED_HOLIDAY_ITEMS {
            return Err(ServiceError::new("节假日展开记录过多。"));
        }
    }
    days.sort_by(|left, right| {
        (&left.date, &left.kind, &left.name).cmp(&(&right.date, &right.kind, &right.name))
    });
    if days.is_empty() {
        return Err(ServiceError::new(
            "节假日数据没有可识别的法定节假日或调休记录。",
        ));
    }
    Ok(days)
}

fn decode_source(bytes: &[u8], year: i32) -> ServiceResult<Vec<HolidayItem>> {
    let payload = serde_json::from_slice::<SourceHolidaysResponse>(bytes)
        .map_err(|error| ServiceError::new(format!("节假日数据解析失败：{error}")))?;
    parse_source_payload(payload, year)
}

fn decode_cache(bytes: &[u8], expected_year: i32) -> ServiceResult<Option<HolidaysResponse>> {
    validate_requested_year(expected_year)?;
    if bytes.len() > MAX_HOLIDAY_RESPONSE_BYTES {
        return Err(ServiceError::new("本地节假日缓存过大。"));
    }
    if bytes.is_empty() {
        return Ok(None);
    }

    let cached: CachedHolidaysResponse = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("本地节假日缓存格式不正确：{error}")))?;
    let response = HolidaysResponse {
        year: cached.year,
        source: cached.source,
        fetched_at: cached.fetched_at,
        items: cached
            .items
            .into_iter()
            .map(|item| HolidayItem {
                date: item.date,
                name: item.name,
                kind: item.kind,
            })
            .collect(),
    };
    validate_holidays_response(&response, Some(expected_year))?;
    Ok(Some(response))
}

fn encode_cache(response: &HolidaysResponse) -> ServiceResult<Vec<u8>> {
    validate_holidays_response(response, None)?;
    let bytes = serde_json::to_vec_pretty(response)
        .map_err(|error| ServiceError::new(format!("无法序列化本地节假日缓存：{error}")))?;
    if bytes.len() > MAX_HOLIDAY_RESPONSE_BYTES {
        return Err(ServiceError::new("本地节假日缓存过大。"));
    }
    Ok(bytes)
}

fn load_cache_from_path(path: &Path, year: i32) -> ServiceResult<Option<HolidaysResponse>> {
    validate_requested_year(year)?;
    if !path.exists() {
        return Ok(None);
    }

    let metadata = fs::metadata(path)
        .map_err(|error| ServiceError::new(format!("无法读取本地节假日缓存：{error}")))?;
    if metadata.len() > MAX_HOLIDAY_RESPONSE_BYTES as u64 {
        return Err(ServiceError::new("本地节假日缓存过大。"));
    }
    let bytes = fs::read(path)
        .map_err(|error| ServiceError::new(format!("无法读取本地节假日缓存：{error}")))?;
    decode_cache(&bytes, year)
}

pub(super) fn load_cache(app: &AppHandle, year: i32) -> ServiceResult<Option<HolidaysResponse>> {
    load_cache_from_path(&cache_path(app, year)?, year)
}

pub(super) fn save_cache_to_path(path: &Path, response: &HolidaysResponse) -> ServiceResult<()> {
    let bytes = encode_cache(response)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建本地节假日目录：{error}")))?;
        let mut temporary = NamedTempFile::new_in(parent)
            .map_err(|error| ServiceError::new(format!("无法创建节假日临时缓存：{error}")))?;
        temporary
            .as_file_mut()
            .write_all(&bytes)
            .map_err(|error| ServiceError::new(format!("无法写入节假日临时缓存：{error}")))?;
        temporary
            .as_file_mut()
            .flush()
            .map_err(|error| ServiceError::new(format!("无法刷新节假日临时缓存：{error}")))?;
        temporary
            .as_file()
            .sync_all()
            .map_err(|error| ServiceError::new(format!("无法同步节假日临时缓存：{error}")))?;
        let persisted = temporary
            .persist(path)
            .map_err(|error| ServiceError::new(format!("无法替换本地节假日缓存：{error}")))?;
        persisted
            .sync_all()
            .map_err(|error| ServiceError::new(format!("无法同步本地节假日缓存：{error}")))?;
        return Ok(());
    }

    Err(ServiceError::new("无法定位本地节假日缓存目录。"))
}

pub(super) fn save_cache(app: &AppHandle, response: &HolidaysResponse) -> ServiceResult<()> {
    save_cache_to_path(&cache_path(app, response.year)?, response)
}

pub(super) fn validate_fetch_year(year: i32) -> ServiceResult<()> {
    validate_requested_year(year)
        .map_err(|_| ServiceError::with_status("节假日年份不在支持范围内。", 400))?;
    Ok(())
}

fn fallback_2026_items() -> Vec<HolidayItem> {
    let ranges = [
        ("元旦", "2026-01-01", "2026-01-03", "holiday"),
        ("元旦补班", "2026-01-04", "2026-01-04", "workday"),
        ("春节补班", "2026-02-14", "2026-02-14", "workday"),
        ("春节", "2026-02-15", "2026-02-23", "holiday"),
        ("春节补班", "2026-02-28", "2026-02-28", "workday"),
        ("清明节", "2026-04-04", "2026-04-06", "holiday"),
        ("劳动节", "2026-05-01", "2026-05-05", "holiday"),
        ("劳动节补班", "2026-05-09", "2026-05-09", "workday"),
        ("端午节", "2026-06-19", "2026-06-21", "holiday"),
        ("中秋节", "2026-09-25", "2026-09-27", "holiday"),
        ("国庆节补班", "2026-09-20", "2026-09-20", "workday"),
        ("国庆节", "2026-10-01", "2026-10-07", "holiday"),
        ("国庆节补班", "2026-10-10", "2026-10-10", "workday"),
    ];
    let mut items = Vec::new();
    for (name, start, end, kind) in ranges {
        let (Ok(mut date), Ok(end)) = (parse_contract_date(start), parse_contract_date(end)) else {
            continue;
        };
        while date <= end {
            items.push(HolidayItem {
                date: date.to_string(),
                name: name.to_string(),
                kind: kind.to_string(),
            });
            date += Duration::days(1);
        }
    }
    items
}

pub(super) fn offline_response(year: i32) -> ServiceResult<HolidaysResponse> {
    let response = if year == 2026 {
        HolidaysResponse {
            year,
            source: HOLIDAY_FALLBACK_SOURCE.to_string(),
            fetched_at: now_contract_timestamp()?,
            items: fallback_2026_items(),
        }
    } else {
        HolidaysResponse {
            year,
            source: format!("unavailable: {HOLIDAY_DATA_SOURCE}"),
            fetched_at: now_contract_timestamp()?,
            items: Vec::new(),
        }
    };
    validate_holidays_response(&response, Some(year))?;
    Ok(response)
}

pub(super) async fn fetch_remote(year: i32) -> ServiceResult<HolidaysResponse> {
    let url = format!("{HOLIDAY_DATA_SOURCE}/{year}.json");
    let client = reqwest::Client::builder()
        .connect_timeout(StdDuration::from_secs(15))
        .timeout(StdDuration::from_secs(20))
        .build()
        .map_err(|error| ServiceError::new(format!("无法创建节假日请求：{error}")))?;
    let mut response = client
        .get(url)
        .header(reqwest::header::ACCEPT, "application/json")
        .header(reqwest::header::USER_AGENT, HOLIDAY_USER_AGENT)
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法获取节假日数据：{error}")))?
        .error_for_status()
        .map_err(|error| ServiceError::new(format!("节假日数据源返回错误：{error}")))?;
    if response
        .content_length()
        .is_some_and(|length| length > MAX_HOLIDAY_RESPONSE_BYTES as u64)
    {
        return Err(ServiceError::new("节假日数据响应过大。"));
    }
    let mut body = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| ServiceError::new(format!("无法读取节假日数据：{error}")))?
    {
        if body.len() + chunk.len() > MAX_HOLIDAY_RESPONSE_BYTES {
            return Err(ServiceError::new("节假日数据响应过大。"));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(HolidaysResponse {
        year,
        source: HOLIDAY_DATA_SOURCE.to_string(),
        fetched_at: now_contract_timestamp()?,
        items: decode_source(&body, year)?,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    fn valid_cache_response() -> HolidaysResponse {
        HolidaysResponse {
            year: 2026,
            source: HOLIDAY_DATA_SOURCE.to_string(),
            fetched_at: "2026-08-03T12:34:56+08:00".to_string(),
            items: vec![HolidayItem {
                date: "2026-01-01".to_string(),
                name: "元旦".to_string(),
                kind: "holiday".to_string(),
            }],
        }
    }

    #[test]
    fn parses_public_holiday_and_prefers_chinese_name() {
        let items = decode_source(
            r#"{
                "year": 2026,
                "region": "CN",
                "dates": [{
                    "date": "2026-01-01",
                    "name": "Fallback",
                    "name_cn": "元旦",
                    "name_en": "New Year's Day",
                    "type": "public_holiday"
                }]
            }"#
            .as_bytes(),
            2026,
        )
        .unwrap();

        assert_eq!(items.len(), 1);
        assert_eq!(items[0].date, "2026-01-01");
        assert_eq!(items[0].name, "元旦");
        assert_eq!(items[0].kind, "holiday");
    }

    #[test]
    fn normalizes_transfer_workday_and_falls_back_to_name() {
        let item = SourceHoliday {
            date: "2026-01-04".to_string(),
            name: Some("调休".to_string()),
            name_cn: None,
            _name_en: None,
            kind: "transfer_workday".to_string(),
        };

        let day = parse_source_item(item, 2026).unwrap().unwrap();
        assert_eq!(day.kind, "workday");
        assert_eq!(day.name, "调休");
    }

    #[test]
    fn rejects_mismatched_payload_and_item_years() {
        let wrong_payload_year = br#"{
            "year": 2025,
            "region": "CN",
            "dates": []
        }"#;
        assert_eq!(
            decode_source(wrong_payload_year, 2026).unwrap_err().message,
            "节假日数据年份与请求不一致。"
        );

        let wrong_item_year = r#"{
            "year": 2026,
            "region": "CN",
            "dates": [{
                "date": "2025-12-31",
                "name": "跨年",
                "type": "public_holiday"
            }]
        }"#;
        assert_eq!(
            decode_source(wrong_item_year.as_bytes(), 2026)
                .unwrap_err()
                .message,
            "节假日数据包含其他年份的日期。"
        );
    }

    #[test]
    fn rejects_malformed_source_fields_and_region() {
        let invalid_date = SourceHoliday {
            date: "2026-1-01".to_string(),
            name: Some("测试".to_string()),
            name_cn: None,
            _name_en: None,
            kind: "public_holiday".to_string(),
        };
        assert!(parse_source_item(invalid_date, 2026).is_err());

        let long_name = SourceHoliday {
            date: "2026-01-01".to_string(),
            name: Some("节".repeat(MAX_HOLIDAY_NAME_LENGTH + 1)),
            name_cn: None,
            _name_en: None,
            kind: "public_holiday".to_string(),
        };
        assert!(parse_source_item(long_name, 2026).is_err());

        let too_many_records = (0..=MAX_HOLIDAY_RECORDS)
            .map(|index| SourceHoliday {
                date: "2026-01-01".to_string(),
                name: Some(format!("假期{index}")),
                name_cn: None,
                _name_en: None,
                kind: "public_holiday".to_string(),
            })
            .collect();
        assert!(parse_source_payload(
            SourceHolidaysResponse {
                year: 2026,
                region: "CN".to_string(),
                dates: too_many_records,
            },
            2026
        )
        .is_err());

        assert_eq!(
            parse_source_payload(
                SourceHolidaysResponse {
                    year: 2026,
                    region: "JP".to_string(),
                    dates: Vec::new(),
                },
                2026
            )
            .unwrap_err()
            .message,
            "节假日数据区域不正确。"
        );

        assert!(decode_source(br#"{"year":2026,"region":"CN","dates":{}}"#, 2026).is_err());
    }

    #[test]
    fn rejects_empty_required_fields_before_skipping_unknown_types() {
        let empty_name = SourceHoliday {
            date: "2026-01-01".to_string(),
            name: Some("  ".to_string()),
            name_cn: None,
            _name_en: None,
            kind: "future-type".to_string(),
        };
        assert!(parse_source_item(empty_name, 2026).is_err());

        let invalid_date = SourceHoliday {
            date: "invalid".to_string(),
            name: Some("测试".to_string()),
            name_cn: None,
            _name_en: None,
            kind: "future-type".to_string(),
        };
        assert!(parse_source_item(invalid_date, 2026).is_err());
    }

    #[test]
    fn skips_valid_unknown_types() {
        let item = SourceHoliday {
            date: "2026-01-01".to_string(),
            name: Some("测试".to_string()),
            name_cn: None,
            _name_en: None,
            kind: "future-type".to_string(),
        };

        assert!(parse_source_item(item, 2026).unwrap().is_none());
    }

    #[test]
    fn rejects_empty_or_entirely_unknown_source_payloads() {
        for dates in [
            r#"[]"#,
            r#"[{"date":"2026-01-01","name":"未知记录","type":"future-type"}]"#,
        ] {
            let payload = format!(r#"{{"year":2026,"region":"CN","dates":{dates}}}"#);
            assert_eq!(
                decode_source(payload.as_bytes(), 2026).unwrap_err().message,
                "节假日数据没有可识别的法定节假日或调休记录。"
            );
        }
    }

    #[test]
    fn transport_metadata_uses_licensed_https_source_and_package_version() {
        assert_eq!(
            HOLIDAY_DATA_SOURCE,
            "https://unpkg.com/holiday-calendar@1.3.3/data/CN"
        );
        assert_eq!(HOLIDAY_USER_AGENT, "WhereToStudyNative/0.1.5");
    }

    #[test]
    fn cache_contract_rejects_invalid_fields() {
        let mut response = valid_cache_response();
        response.year = MIN_HOLIDAY_YEAR - 1;
        assert!(validate_holidays_response(&response, None).is_err());

        let response = valid_cache_response();
        assert!(validate_holidays_response(&response, Some(2025)).is_err());

        let mut response = valid_cache_response();
        response.source = "  ".to_string();
        assert!(validate_holidays_response(&response, None).is_err());
        response.source = "源".repeat(MAX_HOLIDAY_SOURCE_LENGTH + 1);
        assert!(validate_holidays_response(&response, None).is_err());

        for fetched_at in [
            "",
            "2026-08-03T12:34:56.1+08:00",
            "2026-08-03T12:34+08:00",
            "2026-02-30T12:34:56+08:00",
            "2026-08-03 12:34:56+08:00",
        ] {
            let mut response = valid_cache_response();
            response.fetched_at = fetched_at.to_string();
            assert!(validate_holidays_response(&response, None).is_err());
        }
        let mut response = valid_cache_response();
        response.fetched_at = "x".repeat(MAX_HOLIDAY_FETCHED_AT_LENGTH + 1);
        assert!(validate_holidays_response(&response, None).is_err());

        let mut response = valid_cache_response();
        response.items = vec![response.items[0].clone(); MAX_EXPANDED_HOLIDAY_ITEMS + 1];
        assert!(validate_holidays_response(&response, None).is_err());

        let mut response = valid_cache_response();
        response.items[0].date = "2026-1-01".to_string();
        assert!(validate_holidays_response(&response, None).is_err());
        response.items[0].date = "2025-01-01".to_string();
        assert!(validate_holidays_response(&response, None).is_err());

        let mut response = valid_cache_response();
        response.items[0].name = "\t".to_string();
        assert!(validate_holidays_response(&response, None).is_err());
        response.items[0].name = "节".repeat(MAX_HOLIDAY_NAME_LENGTH + 1);
        assert!(validate_holidays_response(&response, None).is_err());

        let mut response = valid_cache_response();
        response.items[0].kind = "workingday".to_string();
        assert!(validate_holidays_response(&response, None).is_err());
    }

    #[test]
    fn cache_decode_rejects_unknown_fields() {
        let valid_bytes = encode_cache(&valid_cache_response()).unwrap();
        assert!(decode_cache(&valid_bytes, 2025).is_err());

        let unknown_response_field = br#"{
            "year": 2026,
            "source": "test",
            "fetched_at": "2026-08-03T12:34:56+08:00",
            "items": [],
            "unexpected": true
        }"#;
        assert!(decode_cache(unknown_response_field, 2026).is_err());

        let unknown_item_field = br#"{
            "year": 2026,
            "source": "test",
            "fetched_at": "2026-08-03T12:34:56+08:00",
            "items": [{
                "date": "2026-01-01",
                "name": "New Year",
                "type": "holiday",
                "unexpected": true
            }]
        }"#;
        assert!(decode_cache(unknown_item_field, 2026).is_err());
    }

    #[test]
    fn cache_size_limit_applies_to_load_and_save() {
        let directory = tempdir().unwrap();
        let path = directory.path().join("holidays_2026.json");
        fs::write(&path, vec![b' '; MAX_HOLIDAY_RESPONSE_BYTES + 1]).unwrap();
        assert_eq!(
            load_cache_from_path(&path, 2026).unwrap_err().message,
            "本地节假日缓存过大。"
        );

        let mut response = valid_cache_response();
        response.items = (0..MAX_EXPANDED_HOLIDAY_ITEMS)
            .map(|_| HolidayItem {
                date: "2026-01-01".to_string(),
                name: "\0".repeat(MAX_HOLIDAY_NAME_LENGTH),
                kind: "holiday".to_string(),
            })
            .collect();
        assert_eq!(
            encode_cache(&response).unwrap_err().message,
            "本地节假日缓存过大。"
        );
    }

    #[test]
    fn cache_save_atomically_replaces_existing_file() {
        let directory = tempdir().unwrap();
        let path = directory.path().join("holidays_2026.json");
        let original = valid_cache_response();
        save_cache_to_path(&path, &original).unwrap();

        let mut invalid = original.clone();
        invalid.source = " ".to_string();
        assert!(save_cache_to_path(&path, &invalid).is_err());
        assert_eq!(load_cache_from_path(&path, 2026).unwrap(), Some(original));

        let mut replacement = valid_cache_response();
        replacement.source = "replacement".to_string();
        replacement.items[0].name = "替换后".to_string();
        save_cache_to_path(&path, &replacement).unwrap();
        assert_eq!(
            load_cache_from_path(&path, 2026).unwrap(),
            Some(replacement)
        );

        let entries = fs::read_dir(directory.path()).unwrap().count();
        assert_eq!(entries, 1);
    }

    #[test]
    fn offline_responses_remain_inside_the_cache_contract() {
        let fallback = offline_response(2026).unwrap();
        assert_eq!(fallback.source, HOLIDAY_FALLBACK_SOURCE);
        assert!(!fallback.items.is_empty());

        let unavailable = offline_response(2027).unwrap();
        assert!(unavailable.source.starts_with("unavailable: https://"));
        assert!(unavailable.items.is_empty());
    }

    #[test]
    fn shared_fixture_matches_holiday_contract() {
        let source: SourceHolidaysResponse = serde_json::from_str(include_str!(
            "../../contracts/v1/fixtures/holiday-source.json"
        ))
        .unwrap();
        let expected: HolidaysResponse =
            serde_json::from_str(include_str!("../../contracts/v1/fixtures/holidays.json"))
                .unwrap();

        assert_eq!(
            parse_source_payload(source, expected.year).unwrap(),
            expected.items
        );
    }
}
