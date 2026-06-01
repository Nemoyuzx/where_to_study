use std::fs;
use std::path::PathBuf;

use chrono::{Duration, NaiveDate};
use serde::Deserialize;
use tauri::{AppHandle, Manager};

use crate::config::now_in_app_tz;
use crate::error::{ServiceError, ServiceResult};
use crate::models::{HolidayItem, HolidaysResponse};

const HOLIDAY_CACHE_PREFIX: &str = "holidays";
const HOLIDAY_DATA_SOURCE: &str = "http://chinese-holidays-data.basten.me/data";

#[derive(Debug, Deserialize)]
struct SourceHoliday {
    name: String,
    range: Vec<String>,
    #[serde(rename = "type")]
    kind: String,
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

fn expand_source_item(item: SourceHoliday) -> ServiceResult<Vec<HolidayItem>> {
    let Some(kind) = normalize_kind(item.kind.as_str()) else {
        return Ok(Vec::new());
    };
    let Some(first_date) = item.range.first() else {
        return Ok(Vec::new());
    };
    let last_date = item.range.last().unwrap_or(first_date);
    let mut current = NaiveDate::parse_from_str(first_date, "%Y-%m-%d")
        .map_err(|_| ServiceError::new("节假日数据日期格式不正确。"))?;
    let end = NaiveDate::parse_from_str(last_date, "%Y-%m-%d")
        .map_err(|_| ServiceError::new("节假日数据日期格式不正确。"))?;
    let mut days = Vec::new();

    while current <= end {
        days.push(HolidayItem {
            date: current.to_string(),
            name: item.name.clone(),
            kind: kind.to_string(),
        });
        current += Duration::days(1);
    }

    Ok(days)
}

fn expand_source_items(items: Vec<SourceHoliday>) -> ServiceResult<Vec<HolidayItem>> {
    let mut days = Vec::new();
    for item in items {
        days.extend(expand_source_item(item)?);
    }
    days.sort_by(|left, right| {
        (&left.date, &left.kind, &left.name).cmp(&(&right.date, &right.kind, &right.name))
    });
    Ok(days)
}

fn load_cache(app: &AppHandle, year: i32) -> ServiceResult<Option<HolidaysResponse>> {
    let path = cache_path(app, year)?;
    if !path.exists() {
        return Ok(None);
    }

    let bytes = fs::read(&path)
        .map_err(|error| ServiceError::new(format!("无法读取本地节假日缓存：{error}")))?;
    if bytes.is_empty() {
        return Ok(None);
    }

    let response: HolidaysResponse = serde_json::from_slice(&bytes)
        .map_err(|error| ServiceError::new(format!("本地节假日缓存格式不正确：{error}")))?;
    Ok(Some(response))
}

fn save_cache(app: &AppHandle, response: &HolidaysResponse) -> ServiceResult<()> {
    let path = cache_path(app, response.year)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| ServiceError::new(format!("无法创建本地节假日目录：{error}")))?;
    }

    let bytes = serde_json::to_vec_pretty(response)
        .map_err(|error| ServiceError::new(format!("无法序列化本地节假日缓存：{error}")))?;
    fs::write(&path, bytes)
        .map_err(|error| ServiceError::new(format!("无法保存本地节假日缓存：{error}")))?;
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

    expand_source_items(source).unwrap_or_default()
}

async fn fetch_remote(year: i32) -> ServiceResult<HolidaysResponse> {
    let url = format!("{HOLIDAY_DATA_SOURCE}/{year}.json");
    let items = reqwest::Client::new()
        .get(url)
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法获取节假日数据：{error}")))?
        .error_for_status()
        .map_err(|error| ServiceError::new(format!("节假日数据源返回错误：{error}")))?
        .json::<Vec<SourceHoliday>>()
        .await
        .map_err(|error| ServiceError::new(format!("节假日数据解析失败：{error}")))?;

    Ok(HolidaysResponse {
        year,
        source: HOLIDAY_DATA_SOURCE.to_string(),
        fetched_at: now_in_app_tz(),
        items: expand_source_items(items)?,
    })
}

pub async fn fetch_holidays(app: &AppHandle, year: i32) -> ServiceResult<HolidaysResponse> {
    if !(1900..=2100).contains(&year) {
        return Err(ServiceError::with_status("节假日年份不在支持范围内。", 400));
    }

    match fetch_remote(year).await {
        Ok(response) => {
            save_cache(app, &response)?;
            Ok(response)
        }
        Err(remote_error) => {
            if let Some(cached) = load_cache(app, year)? {
                return Ok(HolidaysResponse {
                    source: format!("cache: {}", cached.source),
                    ..cached
                });
            }

            if year == 2026 {
                return Ok(HolidaysResponse {
                    year,
                    source: format!("fallback: {HOLIDAY_DATA_SOURCE} unavailable ({remote_error})"),
                    fetched_at: now_in_app_tz(),
                    items: fallback_2026_items(),
                });
            }

            Ok(HolidaysResponse {
                year,
                source: format!("unavailable: {remote_error}"),
                fetched_at: now_in_app_tz(),
                items: Vec::new(),
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn expands_holiday_range() {
        let item = SourceHoliday {
            name: "测试节日".to_string(),
            range: vec!["2026-01-01".to_string(), "2026-01-03".to_string()],
            kind: "holiday".to_string(),
        };

        let days = expand_source_item(item).unwrap();
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

        let days = expand_source_item(item).unwrap();
        assert_eq!(days[0].kind, "workday");
    }
}
