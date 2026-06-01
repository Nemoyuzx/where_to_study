use std::collections::HashMap;
use std::time::Duration;

use chrono::NaiveDate;
use regex::Regex;
use reqwest::header::{HeaderMap, HeaderValue, ORIGIN, REFERER, USER_AGENT};
use serde_json::Value;

use crate::auth::resolve_credentials;
use crate::config::{
    campus_name, normalize_campus_id, now_in_app_tz, today_in_app_tz, EMPTY_CLASSROOM_LOGIN_URL,
    EMPTY_CLASSROOM_TODAY_URL, SJD_LOGIN_PAGE_URL, SJD_ORIGIN, SJD_REST_CLASSROOM_PAGE_URL,
};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{ClassroomStatus, ClassroomsRequest, ClassroomsResponse};

#[derive(Debug, Clone)]
struct RoomAccumulator {
    id: String,
    building: String,
    room: String,
    name: String,
    size: Option<usize>,
    available_slots: Vec<usize>,
}

pub fn sjd_headers(token: Option<&str>, referer: &str) -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(ORIGIN, HeaderValue::from_static(SJD_ORIGIN));
    headers.insert(
        REFERER,
        HeaderValue::from_str(referer).unwrap_or_else(|_| HeaderValue::from_static(SJD_ORIGIN)),
    );
    headers.insert(USER_AGENT, HeaderValue::from_static("Mozilla/5.0"));
    if let Some(token) = token.filter(|value| !value.trim().is_empty()) {
        if let Ok(value) = HeaderValue::from_str(token) {
            headers.insert("token", value);
        }
    }
    headers
}

#[allow(dead_code)]
pub fn parse_classroom(raw: &str) -> Option<(String, String, Option<usize>)> {
    let mut clean = raw.trim().to_string();
    if clean.is_empty() {
        return None;
    }

    let size_regex = Regex::new(r"[\(（]\s*(\d+)\s*[\)）]").expect("valid regex");
    let mut size = None;
    if let Some(captures) = size_regex.captures(&clean) {
        if let Some(value) = captures
            .get(1)
            .and_then(|item| item.as_str().parse::<usize>().ok())
        {
            size = Some(value);
        }
        if let Some(size_match) = captures.get(0) {
            clean = clean[..size_match.start()].trim().to_string();
        }
    }

    clean = clean.replace('－', "-").replace('—', "-").replace('–', "-");
    let parts: Vec<&str> = clean
        .split('-')
        .map(str::trim)
        .filter(|part| !part.is_empty())
        .collect();
    let (building, room) = if parts.len() >= 3 && matches!(parts[0], "校本部" | "西土城" | "沙河")
    {
        (
            clean[..clean.find(parts[2]).unwrap_or(clean.len())]
                .trim_end_matches('-')
                .trim(),
            clean[clean.find(parts[2]).unwrap_or(0)..].trim(),
        )
    } else {
        clean
            .split_once('-')
            .map(|(building, room)| (building.trim(), room.trim()))
            .unwrap_or(("未知教学楼", clean.trim()))
    };
    let building = if building.is_empty() {
        "未知教学楼"
    } else {
        building
    };
    let room = if room.is_empty() {
        clean.as_str()
    } else {
        room
    };
    Some((building.to_string(), room.to_string(), size))
}

fn http_client(timeout_secs: u64) -> ServiceResult<reqwest::Client> {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(timeout_secs))
        .redirect(reqwest::redirect::Policy::limited(10))
        .build()
        .map_err(|error| ServiceError::new(format!("无法初始化网络客户端：{error}")))
}

pub async fn login_empty_classroom(account: &str, password: &str) -> ServiceResult<String> {
    let client = http_client(20)?;
    let response = client
        .post(EMPTY_CLASSROOM_LOGIN_URL)
        .headers(sjd_headers(None, SJD_LOGIN_PAGE_URL))
        .form(&[
            ("userNo", account),
            ("pwd", password),
            ("encode", "1"),
            ("captchaData", ""),
            ("codeVal", ""),
        ])
        .send()
        .await
        .map_err(|_| {
            ServiceError::new("无法连接空教室服务，请确认网络能访问 jwglweixin.bupt.edu.cn。")
        })?;

    if response.status().as_u16() >= 400 {
        return Err(ServiceError::new(format!(
            "空教室服务登录失败，HTTP {}。",
            response.status().as_u16()
        )));
    }

    let payload: Value = response
        .json()
        .await
        .map_err(|_| ServiceError::new("空教室服务返回了无法识别的数据。"))?;
    if !code_is_success(&payload) {
        let message = payload
            .get("Msg")
            .or_else(|| payload.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or("空教室服务登录失败。");
        return Err(ServiceError::with_status(message, 401));
    }

    let token = payload
        .get("data")
        .and_then(|data| data.get("token"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();
    if token.is_empty() {
        return Err(ServiceError::new("空教室服务登录成功但没有返回 token。"));
    }
    Ok(token)
}

fn code_is_success(payload: &Value) -> bool {
    payload
        .get("code")
        .and_then(Value::as_i64)
        .map(|code| code == 1)
        .unwrap_or(false)
        || payload.get("code").and_then(Value::as_str) == Some("1")
}

fn value_string(value: Option<&Value>) -> String {
    value
        .and_then(|item| {
            item.as_str()
                .map(ToOwned::to_owned)
                .or_else(|| item.as_i64().map(|number| number.to_string()))
                .or_else(|| item.as_u64().map(|number| number.to_string()))
        })
        .unwrap_or_default()
}

fn normalize_building_name(name: &str) -> String {
    let normalized_separator = name
        .trim()
        .replace('－', "-")
        .replace('—', "-")
        .replace('–', "-");
    let clean = ["校本部-", "西土城-", "沙河-"]
        .iter()
        .find_map(|prefix| normalized_separator.strip_prefix(prefix))
        .unwrap_or(&normalized_separator)
        .trim();

    match clean {
        "1" | "教一楼" => "教1".to_string(),
        "2" | "教二楼" => "教2".to_string(),
        "3" | "教三楼" => "教3".to_string(),
        "4" | "教四楼" => "教4".to_string(),
        "未来学习大楼" => "主楼".to_string(),
        value if value.is_empty() => "未知教学楼".to_string(),
        value => value.to_string(),
    }
}

fn original_building_name(name: &str) -> bool {
    matches!(name, "教1" | "教2" | "教3" | "教4" | "主楼")
}

fn extract_three_digit_room(value: &str, building: &str) -> Option<String> {
    let mut clean = value
        .trim()
        .replace('－', "-")
        .replace('—', "-")
        .replace('–', "-");
    if clean.is_empty() {
        return None;
    }

    if let Some(building_number) = building.strip_prefix('教') {
        if let Some(rest) = clean.strip_prefix(&format!("{building_number}-")) {
            clean = rest.trim().to_string();
        } else if let Some(rest) = clean.strip_prefix(&format!("教{building_number}-")) {
            clean = rest.trim().to_string();
        }
    }

    Regex::new(r"\d{3}")
        .expect("valid regex")
        .find(&clean)
        .map(|item| item.as_str().to_string())
}

fn node_name_to_slot(value: &str) -> Option<usize> {
    let node = Regex::new(r"\d+")
        .expect("valid regex")
        .find(value.trim())?
        .as_str()
        .parse::<usize>()
        .ok()?;
    (1..=14).contains(&node).then_some(node - 1)
}

fn parse_occupied_classrooms(items: &[Value], room_map: &mut HashMap<String, RoomAccumulator>) {
    for item in items {
        let Some(slot) = node_name_to_slot(&value_string(
            item.get("NODENAME")
                .or_else(|| item.get("nodeName"))
                .or_else(|| item.get("nodename")),
        )) else {
            continue;
        };
        let classrooms = value_string(
            item.get("CLASSROOMS")
                .or_else(|| item.get("classrooms"))
                .or_else(|| item.get("Classrooms")),
        );

        for classroom in classrooms
            .split(',')
            .map(str::trim)
            .filter(|value| !value.is_empty())
        {
            let Some((building_name, room_name, size)) = parse_classroom(classroom) else {
                continue;
            };
            let building = normalize_building_name(&building_name);
            if !original_building_name(&building) {
                continue;
            }
            let Some(room) = extract_three_digit_room(&room_name, &building) else {
                continue;
            };
            let key = format!("{building}-{room}");
            let entry = room_map
                .entry(key.clone())
                .or_insert_with(|| RoomAccumulator {
                    id: key.clone(),
                    building: building.clone(),
                    room: room.clone(),
                    name: key.clone(),
                    size,
                    available_slots: Vec::new(),
                });
            if entry.size.is_none() && size.is_some() {
                entry.size = size;
            }
            if !entry.available_slots.contains(&slot) {
                entry.available_slots.push(slot);
            }
        }
    }
}

async fn fetch_occupied_classrooms(
    client: &reqwest::Client,
    token: &str,
    campus_id: &str,
) -> ServiceResult<Vec<Value>> {
    let response = client
        .get(EMPTY_CLASSROOM_TODAY_URL)
        .query(&[("campusId", campus_id.to_string())])
        .headers(sjd_headers(Some(token), SJD_REST_CLASSROOM_PAGE_URL))
        .send()
        .await
        .map_err(|_| ServiceError::new("实时教室数据获取失败，请稍后重试。"))?;

    if response.status().as_u16() >= 400 {
        return Err(ServiceError::new(format!(
            "实时教室数据获取失败，HTTP {}。",
            response.status().as_u16()
        )));
    }
    let payload: Value = response
        .json()
        .await
        .map_err(|_| ServiceError::new("实时教室服务返回了无法识别的数据。"))?;
    if !code_is_success(&payload) {
        let message = payload
            .get("Msg")
            .or_else(|| payload.get("msg"))
            .and_then(Value::as_str)
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| "实时教室数据获取失败。".to_string());
        return Err(ServiceError::new(message));
    }

    Ok(payload
        .get("data")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default())
}

pub async fn fetch_classrooms(payload: &ClassroomsRequest) -> ServiceResult<ClassroomsResponse> {
    let normalized_campus_id = normalize_campus_id(payload.campus_id.as_deref());
    let service_date = match payload
        .target_date
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        Some(target_date) => NaiveDate::parse_from_str(target_date.trim(), "%Y-%m-%d")
            .map_err(|_| ServiceError::with_status("查询日期格式不正确。", 400))?,
        None => today_in_app_tz(),
    };

    if service_date != today_in_app_tz() {
        return Err(ServiceError::with_status(
            "空教室实时接口仅支持当天查询。",
            400,
        ));
    }

    let (user, secret) = resolve_credentials(&payload.account, &payload.password)?;
    let token = login_empty_classroom(&user, &secret).await?;
    let client = http_client(30)?;

    let mut room_map = HashMap::new();
    let occupied_classrooms =
        fetch_occupied_classrooms(&client, &token, &normalized_campus_id).await?;
    parse_occupied_classrooms(&occupied_classrooms, &mut room_map);

    let mut rooms: Vec<ClassroomStatus> = room_map
        .into_values()
        .map(|mut item| {
            item.available_slots.sort_unstable();
            item.available_slots.dedup();
            let occupied_slots = item.available_slots;
            let available_slots = (0..14)
                .filter(|slot| !occupied_slots.contains(slot))
                .collect();
            ClassroomStatus {
                id: item.id,
                building: item.building,
                room: item.room,
                name: item.name,
                size: item.size,
                r#type: String::new(),
                available_slots,
                source: "sjd".to_string(),
            }
        })
        .collect();
    rooms.sort_by(|left, right| {
        (left.building.as_str(), left.room.as_str())
            .cmp(&(right.building.as_str(), right.room.as_str()))
    });

    Ok(ClassroomsResponse {
        campus_id: normalized_campus_id.clone(),
        campus_name: campus_name(&normalized_campus_id),
        target_date: service_date.to_string(),
        fetched_at: now_in_app_tz(),
        realtime: true,
        provider: "sjd".to_string(),
        rooms,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_classroom_with_size() {
        assert_eq!(
            parse_classroom("教一楼-101(80)"),
            Some(("教一楼".to_string(), "101".to_string(), Some(80)))
        );
        assert_eq!(
            parse_classroom("校本部-教三楼-3-335(90)"),
            Some(("校本部-教三楼".to_string(), "3-335".to_string(), Some(90)))
        );
    }

    #[test]
    fn parse_occupied_classrooms_merges_slots() {
        let mut room_map = HashMap::new();
        let items = serde_json::json!([
            {
                "NODENAME": "1",
                "CLASSROOMS": "校本部-教三楼-3-335(90)"
            },
            {
                "NODENAME": "3",
                "CLASSROOMS": "教三楼-3-335(90)"
            }
        ]);
        let items = items.as_array().unwrap();

        parse_occupied_classrooms(items, &mut room_map);

        let room = room_map.get("教3-335").unwrap();
        assert_eq!(room.building, "教3");
        assert_eq!(room.room, "335");
        assert_eq!(room.size, Some(90));
        assert_eq!(room.available_slots, vec![0, 2]);
    }

    #[test]
    fn parse_occupied_classrooms_uses_three_digit_room_number() {
        let mut room_map = HashMap::new();
        let items = serde_json::json!([
            {
                "NODENAME": "1",
                "CLASSROOMS": "校本部-教二楼-101A441(60),教二楼-406（信通实验室）(30),教二楼-107343(60)"
            }
        ]);
        let items = items.as_array().unwrap();

        parse_occupied_classrooms(items, &mut room_map);

        assert!(room_map.get("教2-101").is_some());
        assert!(room_map.get("教2-406").is_some());
        assert!(room_map.get("教2-107").is_some());
        assert!(room_map.get("教2-101A441").is_none());
        assert!(room_map.get("教2-107343").is_none());
    }

    #[test]
    fn parse_occupied_classrooms_keeps_original_buildings_only() {
        let mut room_map = HashMap::new();
        let items = serde_json::json!([
            {
                "NODENAME": "1",
                "CLASSROOMS": "校本部-教师自行安排-x(0),未来学习大楼-101(80)"
            }
        ]);
        let items = items.as_array().unwrap();

        parse_occupied_classrooms(items, &mut room_map);

        assert!(room_map.get("教师自行安排-x").is_none());
        assert!(room_map.get("主楼-101").is_some());
    }

    #[test]
    fn node_name_to_slot_uses_one_based_nodes() {
        assert_eq!(node_name_to_slot("1"), Some(0));
        assert_eq!(node_name_to_slot("第14节"), Some(13));
        assert_eq!(node_name_to_slot("15"), None);
    }
}
