use std::time::Duration;

use chrono::{NaiveDate, TimeZone};
use chrono_tz::Asia::Shanghai;
use serde::Deserialize;

use crate::error::{ServiceError, ServiceResult};
use crate::models::{AlmanacRequest, AlmanacResponse, WeatherDay, WeatherRequest, WeatherResponse};

const UAPI_ORIGIN: &str = "https://uapis.cn";
const UAPI_HOST: &str = "uapis.cn";
const TIMELESS_ORIGIN: &str = "https://api.timelessq.com";
const TIMELESS_HOST: &str = "api.timelessq.com";
const USER_AGENT: &str = concat!("WhereToStudy/", env!("CARGO_PKG_VERSION"));
const MAX_RESPONSE_BYTES: usize = 128 * 1024;
const MAX_REDIRECTS: usize = 5;

#[derive(Debug, Deserialize)]
struct SourceWeather {
    district: String,
    weather: String,
    temperature: f64,
    report_time: String,
    forecast: Vec<SourceWeatherDay>,
}

#[derive(Debug, Deserialize)]
struct SourceWeatherDay {
    date: String,
    week: String,
    temp_max: f64,
    temp_min: f64,
    weather_day: String,
    weather_night: String,
    #[serde(default)]
    pop: Option<f64>,
}

#[derive(Debug, Deserialize)]
struct SourceAlmanac {
    datetime: String,
    weekday_cn: String,
    lunar_month_cn: String,
    lunar_day_cn: String,
    ganzhi_year: String,
    ganzhi_month: String,
    ganzhi_day: String,
    zodiac: String,
    #[serde(default)]
    solar_term: Option<String>,
    #[serde(default)]
    lunar_festival: Option<String>,
    #[serde(default)]
    solar_festival: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SourceTimelessResponse {
    errno: i64,
    #[serde(default)]
    errmsg: String,
    data: SourceTimelessDay,
}

#[derive(Debug, Deserialize)]
struct SourceTimelessDay {
    year: i32,
    month: u32,
    day: u32,
    almanac: SourceTimelessAlmanac,
}

#[derive(Debug, Deserialize)]
struct SourceTimelessAlmanac {
    yi: String,
    ji: String,
}

fn campus_weather_target(
    campus_id: &str,
) -> ServiceResult<(&'static str, &'static str, &'static str)> {
    match crate::config::normalize_campus_id(Some(campus_id)).as_str() {
        "01" => Ok(("01", "西土城", "110108")),
        "04" => Ok(("04", "沙河", "110114")),
        _ => Err(ServiceError::with_status("暂不支持该校区的天气查询。", 400)),
    }
}

fn parse_date(value: &str) -> ServiceResult<NaiveDate> {
    if value.len() != 10
        || value.as_bytes().get(4) != Some(&b'-')
        || value.as_bytes().get(7) != Some(&b'-')
    {
        return Err(ServiceError::with_status("黄历日期格式不正确。", 400));
    }
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ServiceError::with_status("黄历日期格式不正确。", 400))
}

fn rounded_temperature(value: f64) -> ServiceResult<i32> {
    if !value.is_finite() || !(-150.0..=100.0).contains(&value) {
        return Err(ServiceError::new("天气温度超出合理范围。"));
    }
    Ok(value.round() as i32)
}

fn rounded_probability(value: f64) -> ServiceResult<u8> {
    if !value.is_finite() || !(0.0..=100.0).contains(&value) {
        return Err(ServiceError::new("天气降水概率超出合理范围。"));
    }
    Ok(value.round() as u8)
}

fn validate_redirect_target(
    url: &reqwest::Url,
    previous_count: usize,
    allowed_host: &str,
) -> ServiceResult<()> {
    if previous_count > MAX_REDIRECTS {
        return Err(ServiceError::new("生活信息接口重定向次数过多。"));
    }
    if url.scheme() != "https" || url.host_str() != Some(allowed_host) {
        return Err(ServiceError::new("生活信息接口重定向目标不受信任。"));
    }
    if !url.username().is_empty() || url.password().is_some() {
        return Err(ServiceError::new("生活信息接口地址不得携带用户信息。"));
    }
    Ok(())
}

fn redirect_policy(allowed_host: &'static str) -> reqwest::redirect::Policy {
    reqwest::redirect::Policy::custom(move |attempt| {
        match validate_redirect_target(attempt.url(), attempt.previous().len(), allowed_host) {
            Ok(()) => attempt.follow(),
            Err(error) => attempt.error(error),
        }
    })
}

async fn fetch_json(url: reqwest::Url, allowed_host: &'static str) -> ServiceResult<Vec<u8>> {
    validate_redirect_target(&url, 0, allowed_host)?;
    let client = reqwest::Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(15))
        .redirect(redirect_policy(allowed_host))
        .build()
        .map_err(|error| ServiceError::new(format!("无法创建生活信息请求：{error}")))?;
    let mut response = client
        .get(url)
        .header(reqwest::header::ACCEPT, "application/json")
        .header(reqwest::header::USER_AGENT, USER_AGENT)
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法获取生活信息：{error}")))?
        .error_for_status()
        .map_err(|error| ServiceError::new(format!("生活信息接口返回错误：{error}")))?;
    if response
        .content_length()
        .is_some_and(|length| length > MAX_RESPONSE_BYTES as u64)
    {
        return Err(ServiceError::new("生活信息响应过大。"));
    }
    let mut body = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| ServiceError::new(format!("无法读取生活信息：{error}")))?
    {
        if body.len() + chunk.len() > MAX_RESPONSE_BYTES {
            return Err(ServiceError::new("生活信息响应过大。"));
        }
        body.extend_from_slice(&chunk);
    }
    Ok(body)
}

fn decode_weather(
    bytes: &[u8],
    campus_id: &str,
    campus_name: &str,
) -> ServiceResult<WeatherResponse> {
    let source: SourceWeather = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("天气数据解析失败：{error}")))?;
    if source.forecast.len() < 2 {
        return Err(ServiceError::new("天气预报缺少今日或明日数据。"));
    }
    let mut days = Vec::with_capacity(2);
    for item in source.forecast.into_iter().take(2) {
        parse_date(&item.date)?;
        days.push(WeatherDay {
            date: item.date,
            weekday: item.week,
            weather_day: item.weather_day,
            weather_night: item.weather_night,
            temp_max: rounded_temperature(item.temp_max)?,
            temp_min: rounded_temperature(item.temp_min)?,
            precipitation_probability: item.pop.map(rounded_probability).transpose()?,
        });
    }
    if source.district.trim().is_empty()
        || source.weather.trim().is_empty()
        || source.report_time.trim().is_empty()
    {
        return Err(ServiceError::new("天气数据缺少必要字段。"));
    }
    Ok(WeatherResponse {
        campus_id: campus_id.to_string(),
        campus_name: campus_name.to_string(),
        district: source.district,
        current_weather: source.weather,
        current_temperature: rounded_temperature(source.temperature)?,
        report_time: source.report_time,
        source: UAPI_ORIGIN.to_string(),
        days,
    })
}

fn decode_almanac(bytes: &[u8], requested_date: NaiveDate) -> ServiceResult<AlmanacResponse> {
    let source: SourceAlmanac = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("黄历数据解析失败：{error}")))?;
    if !source.datetime.starts_with(&requested_date.to_string()) {
        return Err(ServiceError::new("黄历数据日期与请求不一致。"));
    }
    let required = [
        source.weekday_cn.as_str(),
        source.lunar_month_cn.as_str(),
        source.lunar_day_cn.as_str(),
        source.ganzhi_year.as_str(),
        source.ganzhi_month.as_str(),
        source.ganzhi_day.as_str(),
        source.zodiac.as_str(),
    ];
    if required.iter().any(|value| value.trim().is_empty()) {
        return Err(ServiceError::new("黄历数据缺少必要字段。"));
    }
    Ok(AlmanacResponse {
        date: requested_date.to_string(),
        weekday: source.weekday_cn,
        lunar_date: format!("{}{}", source.lunar_month_cn, source.lunar_day_cn),
        ganzhi_year: source.ganzhi_year,
        ganzhi_month: source.ganzhi_month,
        ganzhi_day: source.ganzhi_day,
        zodiac: source.zodiac,
        solar_term: source.solar_term.filter(|value| !value.trim().is_empty()),
        lunar_festival: source
            .lunar_festival
            .filter(|value| !value.trim().is_empty()),
        solar_festival: source
            .solar_festival
            .filter(|value| !value.trim().is_empty()),
        yi: None,
        ji: None,
        source: UAPI_ORIGIN.to_string(),
    })
}

fn decode_almanac_advice(
    bytes: &[u8],
    requested_date: NaiveDate,
) -> ServiceResult<(String, String)> {
    let source: SourceTimelessResponse = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("黄历宜忌解析失败：{error}")))?;
    if source.errno != 0 {
        let message = if source.errmsg.trim().is_empty() {
            "黄历宜忌接口返回失败。".to_string()
        } else {
            format!("黄历宜忌接口返回失败：{}", source.errmsg)
        };
        return Err(ServiceError::new(message));
    }
    let source_date = NaiveDate::from_ymd_opt(source.data.year, source.data.month, source.data.day)
        .ok_or_else(|| ServiceError::new("黄历宜忌返回了无效日期。"))?;
    if source_date != requested_date {
        return Err(ServiceError::new("黄历宜忌日期与请求不一致。"));
    }
    let yi = source.data.almanac.yi.trim().to_string();
    let ji = source.data.almanac.ji.trim().to_string();
    if yi.is_empty() || ji.is_empty() {
        return Err(ServiceError::new("黄历宜忌缺少必要字段。"));
    }
    Ok((yi, ji))
}

pub async fn fetch_weather(payload: &WeatherRequest) -> ServiceResult<WeatherResponse> {
    let (campus_id, campus_name, adcode) = campus_weather_target(&payload.campus_id)?;
    let mut url = reqwest::Url::parse(&format!("{UAPI_ORIGIN}/api/v1/misc/weather"))
        .map_err(|error| ServiceError::new(format!("天气接口地址无效：{error}")))?;
    url.query_pairs_mut()
        .append_pair("adcode", adcode)
        .append_pair("lang", "zh")
        .append_pair("forecast", "true");
    let bytes = fetch_json(url, UAPI_HOST).await?;
    decode_weather(&bytes, campus_id, campus_name)
}

pub async fn fetch_almanac(payload: &AlmanacRequest) -> ServiceResult<AlmanacResponse> {
    let date = parse_date(payload.date.trim())?;
    let noon = date
        .and_hms_opt(12, 0, 0)
        .and_then(|value| Shanghai.from_local_datetime(&value).single())
        .ok_or_else(|| ServiceError::new("无法换算黄历日期。"))?;
    let mut url = reqwest::Url::parse(&format!("{UAPI_ORIGIN}/api/v1/misc/lunartime"))
        .map_err(|error| ServiceError::new(format!("黄历接口地址无效：{error}")))?;
    url.query_pairs_mut()
        .append_pair("ts", &noon.timestamp().to_string())
        .append_pair("timezone", "Asia/Shanghai");
    let bytes = fetch_json(url, UAPI_HOST).await?;
    let mut response = decode_almanac(&bytes, date)?;

    let mut advice_url = reqwest::Url::parse(&format!("{TIMELESS_ORIGIN}/time"))
        .map_err(|error| ServiceError::new(format!("黄历宜忌接口地址无效：{error}")))?;
    advice_url
        .query_pairs_mut()
        .append_pair("datetime", &date.to_string());
    if let Ok(advice_bytes) = fetch_json(advice_url, TIMELESS_HOST).await {
        if let Ok((yi, ji)) = decode_almanac_advice(&advice_bytes, date) {
            response.yi = Some(yi);
            response.ji = Some(ji);
            response.source = format!("{UAPI_ORIGIN} · {TIMELESS_ORIGIN}");
        }
    }
    Ok(response)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn campus_mapping_uses_each_campus_district() {
        assert_eq!(campus_weather_target("01").unwrap().2, "110108");
        assert_eq!(campus_weather_target("4").unwrap().2, "110114");
        assert!(campus_weather_target("99").is_err());
    }

    #[test]
    fn weather_parser_keeps_today_and_tomorrow_only() {
        let data = r#"{
          "district":"海淀区","weather":"多云","temperature":27.4,"report_time":"8 分钟前发布",
          "forecast":[
            {"date":"2026-08-22","week":"星期六","temp_max":32.6,"temp_min":22.6,"weather_day":"雷阵雨","weather_night":"雷阵雨","pop":59.6},
            {"date":"2026-08-23","week":"星期日","temp_max":33,"temp_min":23,"weather_day":"多云","weather_night":"多云","pop":20},
            {"date":"2026-08-24","week":"星期一","temp_max":30,"temp_min":22,"weather_day":"晴","weather_night":"晴","pop":0}
          ]
        }"#.as_bytes();
        let parsed = decode_weather(data, "01", "西土城").unwrap();
        assert_eq!(parsed.district, "海淀区");
        assert_eq!(parsed.current_temperature, 27);
        assert_eq!(parsed.days.len(), 2);
        assert_eq!(parsed.days[0].temp_max, 33);
        assert_eq!(parsed.days[0].temp_min, 23);
        assert_eq!(parsed.days[0].precipitation_probability, Some(60));
        assert_eq!(parsed.days[1].date, "2026-08-23");
    }

    #[test]
    fn almanac_parser_rejects_mismatched_dates() {
        let data = r#"{
          "datetime":"2026-08-22 12:00:00","weekday_cn":"星期六",
          "lunar_month_cn":"七月","lunar_day_cn":"初十","ganzhi_year":"丙午",
          "ganzhi_month":"丙申","ganzhi_day":"戊辰","zodiac":"马"
        }"#
        .as_bytes();
        let date = NaiveDate::from_ymd_opt(2026, 8, 22).unwrap();
        assert_eq!(decode_almanac(data, date).unwrap().lunar_date, "七月初十");
        assert!(decode_almanac(data, NaiveDate::from_ymd_opt(2026, 8, 23).unwrap()).is_err());
    }

    #[test]
    fn redirects_reject_plaintext_and_foreign_hosts() {
        assert!(validate_redirect_target(
            &reqwest::Url::parse("https://uapis.cn/api").unwrap(),
            1,
            UAPI_HOST,
        )
        .is_ok());
        assert!(validate_redirect_target(
            &reqwest::Url::parse("http://uapis.cn/api").unwrap(),
            1,
            UAPI_HOST,
        )
        .is_err());
        assert!(validate_redirect_target(
            &reqwest::Url::parse("https://example.com/api").unwrap(),
            1,
            UAPI_HOST,
        )
        .is_err());
    }

    #[test]
    fn almanac_advice_parser_keeps_yi_and_ji_for_requested_date() {
        let data = r#"{
          "errno":0,"errmsg":"","data":{
            "year":2026,"month":8,"day":22,
            "almanac":{"yi":"祭祀 祈福","ji":"嫁娶 掘井"}
          }
        }"#
        .as_bytes();
        let date = NaiveDate::from_ymd_opt(2026, 8, 22).unwrap();
        let (yi, ji) = decode_almanac_advice(data, date).unwrap();
        assert_eq!(yi, "祭祀 祈福");
        assert_eq!(ji, "嫁娶 掘井");
        assert!(
            decode_almanac_advice(data, NaiveDate::from_ymd_opt(2026, 8, 23).unwrap()).is_err()
        );
    }
}
