use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Datelike, Duration, NaiveDate, SecondsFormat};
use serde::Deserialize;
use tauri::{AppHandle, Manager};
use tempfile::NamedTempFile;

use crate::config::now_in_app_tz;
use crate::error::{ServiceError, ServiceResult};
use crate::models::{HolidayItem, HolidaysResponse};

const HOLIDAY_CACHE_PREFIX: &str = "holidays";
const HOLIDAY_DATA_SOURCE: &str =
    "https://raw.githubusercontent.com/bastengao/chinese-holidays-data/master/data";
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
const MAX_HOLIDAY_RANGE_ENTRIES: usize = 32;
const MAX_HOLIDAY_RANGE_DAYS: i64 = 32;
const MAX_EXPANDED_HOLIDAY_ITEMS: usize = 512;

#[derive(Debug, Deserialize)]
struct SourceHoliday {
    name: String,
    range: Vec<String>,
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
        "holiday" => Some("holiday"),
        "workingday" | "workday" => Some("workday"),
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

fn expand_source_item(item: SourceHoliday, year: i32) -> ServiceResult<Vec<HolidayItem>> {
    let name = item.name.trim();
    if name.is_empty() {
        return Err(ServiceError::new("节假日名称不能为空。"));
    }
    if name.chars().count() > MAX_HOLIDAY_NAME_LENGTH {
        return Err(ServiceError::new("节假日名称过长。"));
    }
    if item.range.len() > MAX_HOLIDAY_RANGE_ENTRIES {
        return Err(ServiceError::new("节假日日期范围记录过多。"));
    }
    if item.range.is_empty() {
        return Err(ServiceError::new("节假日日期范围不能为空。"));
    }
    let range_dates = item
        .range
        .iter()
        .map(|value| parse_contract_date(value))
        .collect::<ServiceResult<Vec<_>>>()?;
    if range_dates.windows(2).any(|dates| dates[1] <= dates[0]) {
        return Err(ServiceError::new("节假日数据日期范围顺序不正确。"));
    }
    let mut current = range_dates[0];
    let end = *range_dates.last().unwrap_or(&current);
    let span = end.signed_duration_since(current).num_days();
    if span >= MAX_HOLIDAY_RANGE_DAYS {
        return Err(ServiceError::new("节假日数据日期跨度过大。"));
    }
    let Some(kind) = normalize_kind(item.kind.as_str()) else {
        return Ok(Vec::new());
    };
    let mut days = Vec::new();

    while current <= end {
        if current.year() == year {
            days.push(HolidayItem {
                date: current.to_string(),
                name: name.to_string(),
                kind: kind.to_string(),
            });
        }
        current += Duration::days(1);
    }

    Ok(days)
}

fn expand_source_items(items: Vec<SourceHoliday>, year: i32) -> ServiceResult<Vec<HolidayItem>> {
    if items.len() > MAX_HOLIDAY_RECORDS {
        return Err(ServiceError::new("节假日数据记录过多。"));
    }
    let mut days = Vec::new();
    for item in items {
        let expanded = expand_source_item(item, year)?;
        if days.len() + expanded.len() > MAX_EXPANDED_HOLIDAY_ITEMS {
            return Err(ServiceError::new("节假日展开记录过多。"));
        }
        days.extend(expanded);
    }
    days.sort_by(|left, right| {
        (&left.date, &left.kind, &left.name).cmp(&(&right.date, &right.kind, &right.name))
    });
    Ok(days)
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
    let source = vec![
        SourceHoliday {
            name: "元旦".to_string(),
            range: vec!["2026-01-01".to_string(), "2026-01-03".to_string()],
            kind: "holiday".to_string(),
        },
        SourceHoliday {
            name: "元旦".to_string(),
            range: vec!["2026-01-04".to_string()],
            kind: "workingday".to_string(),
        },
        SourceHoliday {
            name: "春节".to_string(),
            range: vec!["2026-02-14".to_string()],
            kind: "workingday".to_string(),
        },
        SourceHoliday {
            name: "春节".to_string(),
            range: vec!["2026-02-15".to_string(), "2026-02-23".to_string()],
            kind: "holiday".to_string(),
        },
        SourceHoliday {
            name: "春节".to_string(),
            range: vec!["2026-02-28".to_string()],
            kind: "workingday".to_string(),
        },
        SourceHoliday {
            name: "清明节".to_string(),
            range: vec!["2026-04-04".to_string(), "2026-04-06".to_string()],
            kind: "holiday".to_string(),
        },
        SourceHoliday {
            name: "劳动节".to_string(),
            range: vec!["2026-05-01".to_string(), "2026-05-05".to_string()],
            kind: "holiday".to_string(),
        },
        SourceHoliday {
            name: "劳动节".to_string(),
            range: vec!["2026-05-09".to_string()],
            kind: "workingday".to_string(),
        },
        SourceHoliday {
            name: "端午节".to_string(),
            range: vec!["2026-06-19".to_string(), "2026-06-21".to_string()],
            kind: "holiday".to_string(),
        },
        SourceHoliday {
            name: "中秋节".to_string(),
            range: vec!["2026-09-25".to_string(), "2026-09-27".to_string()],
            kind: "holiday".to_string(),
        },
        SourceHoliday {
            name: "国庆节".to_string(),
            range: vec!["2026-09-20".to_string()],
            kind: "workingday".to_string(),
        },
        SourceHoliday {
            name: "国庆节".to_string(),
            range: vec!["2026-10-01".to_string(), "2026-10-07".to_string()],
            kind: "holiday".to_string(),
        },
        SourceHoliday {
            name: "国庆节".to_string(),
            range: vec!["2026-10-10".to_string()],
            kind: "workingday".to_string(),
        },
    ];

    expand_source_items(source, 2026).unwrap_or_default()
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
    let mut response = reqwest::Client::new()
        .get(url)
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
    let items = serde_json::from_slice::<Vec<SourceHoliday>>(&body)
        .map_err(|error| ServiceError::new(format!("节假日数据解析失败：{error}")))?;

    Ok(HolidaysResponse {
        year,
        source: HOLIDAY_DATA_SOURCE.to_string(),
        fetched_at: now_contract_timestamp()?,
        items: expand_source_items(items, year)?,
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
    fn expands_holiday_range() {
        let item = SourceHoliday {
            name: "测试节日".to_string(),
            range: vec!["2026-01-01".to_string(), "2026-01-03".to_string()],
            kind: "holiday".to_string(),
        };

        let days = expand_source_item(item, 2026).unwrap();
        assert_eq!(days.len(), 3);
        assert_eq!(days[0].date, "2026-01-01");
        assert_eq!(days[2].date, "2026-01-03");
        assert_eq!(days[0].kind, "holiday");
    }

    #[test]
    fn normalizes_workingday_type() {
        let item = SourceHoliday {
            name: "调休".to_string(),
            range: vec!["2026-01-04".to_string()],
            kind: "workingday".to_string(),
        };

        let days = expand_source_item(item, 2026).unwrap();
        assert_eq!(days[0].kind, "workday");
    }

    #[test]
    fn filters_cross_year_ranges_to_requested_year() {
        let item = SourceHoliday {
            name: "跨年假期".to_string(),
            range: vec!["2025-12-31".to_string(), "2026-01-02".to_string()],
            kind: "holiday".to_string(),
        };

        let days = expand_source_item(item, 2026).unwrap();
        assert_eq!(
            days.iter()
                .map(|item| item.date.as_str())
                .collect::<Vec<_>>(),
            vec!["2026-01-01", "2026-01-02"]
        );
    }

    #[test]
    fn rejects_invalid_or_excessive_source_fields() {
        let invalid_date = SourceHoliday {
            name: "测试".to_string(),
            range: vec!["2026-1-01".to_string()],
            kind: "holiday".to_string(),
        };
        assert!(expand_source_item(invalid_date, 2026).is_err());

        let invalid_middle_date = SourceHoliday {
            name: "测试".to_string(),
            range: vec![
                "2026-01-01".to_string(),
                "2026-1-02".to_string(),
                "2026-01-03".to_string(),
            ],
            kind: "holiday".to_string(),
        };
        assert!(expand_source_item(invalid_middle_date, 2026).is_err());

        let excessive_span = SourceHoliday {
            name: "测试".to_string(),
            range: vec!["2026-01-01".to_string(), "2026-02-02".to_string()],
            kind: "holiday".to_string(),
        };
        assert!(expand_source_item(excessive_span, 2026).is_err());

        let long_name = SourceHoliday {
            name: "节".repeat(MAX_HOLIDAY_NAME_LENGTH + 1),
            range: vec!["2026-01-01".to_string()],
            kind: "holiday".to_string(),
        };
        assert!(expand_source_item(long_name, 2026).is_err());

        let too_many_records = (0..=MAX_HOLIDAY_RECORDS)
            .map(|index| SourceHoliday {
                name: format!("假期{index}"),
                range: vec!["2026-01-01".to_string()],
                kind: "holiday".to_string(),
            })
            .collect();
        assert!(expand_source_items(too_many_records, 2026).is_err());
    }

    #[test]
    fn rejects_empty_required_fields_before_skipping_unknown_types() {
        let empty_name = SourceHoliday {
            name: "  ".to_string(),
            range: vec!["2026-01-01".to_string()],
            kind: "future-type".to_string(),
        };
        assert!(expand_source_item(empty_name, 2026).is_err());

        let empty_range = SourceHoliday {
            name: "测试".to_string(),
            range: Vec::new(),
            kind: "future-type".to_string(),
        };
        assert!(expand_source_item(empty_range, 2026).is_err());
    }

    #[test]
    fn skips_valid_unknown_types() {
        let item = SourceHoliday {
            name: "测试".to_string(),
            range: vec!["2026-01-01".to_string()],
            kind: "future-type".to_string(),
        };

        assert!(expand_source_item(item, 2026).unwrap().is_empty());
    }

    #[test]
    fn transport_metadata_uses_raw_https_and_package_version() {
        assert_eq!(
            HOLIDAY_DATA_SOURCE,
            "https://raw.githubusercontent.com/bastengao/chinese-holidays-data/master/data"
        );
        assert_eq!(HOLIDAY_USER_AGENT, "WhereToStudyNative/0.1.1");
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
        let source: Vec<SourceHoliday> = serde_json::from_str(include_str!(
            "../../contracts/v1/fixtures/holiday-source.json"
        ))
        .unwrap();
        let expected: HolidaysResponse =
            serde_json::from_str(include_str!("../../contracts/v1/fixtures/holidays.json"))
                .unwrap();

        assert_eq!(
            expand_source_items(source, expected.year).unwrap(),
            expected.items
        );
    }
}
