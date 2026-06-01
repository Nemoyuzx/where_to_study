use std::collections::HashMap;
use std::time::Duration;

use chrono::NaiveDate;
use regex::Regex;
use reqwest::header::{HeaderMap, HeaderValue, ORIGIN, REFERER, USER_AGENT};
use serde_json::Value;

use crate::auth::resolve_credentials;
use crate::config::{
    campus_name, now_in_app_tz, today_in_app_tz, CAMPUSES, EMPTY_CLASSROOM_LOGIN_URL,
    EMPTY_CLASSROOM_TODAY_URL, SJD_LOGIN_PAGE_URL, SJD_ORIGIN, SJD_REST_CLASSROOM_PAGE_URL,
};
use crate::error::{ServiceError, ServiceResult};
use crate::models::{
    ClassroomStatus, ClassroomsCacheResponse, ClassroomsRequest, ClassroomsResponse,
    CLASSROOMS_CACHE_VERSION,
};

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
        .form(&[("userNo", account), ("pwd", password)])
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

    let compact = clean.replace(' ', "").replace('　', "");

    match compact.as_str() {
        "1" | "教一楼" => "教1".to_string(),
        "2" | "教二楼" => "教2".to_string(),
        "3" | "教三楼" => "教3".to_string(),
        "4" | "教四楼" => "教4".to_string(),
        "未来学习大楼" => "主楼".to_string(),
        "N"
        | "N楼"
        | "N座"
        | "北楼"
        | "综合教学楼N"
        | "综合教学楼N楼"
        | "综合教学楼N座"
        | "综合楼N"
        | "综合楼N楼"
        | "综合N" => "综合教学楼N".to_string(),
        "S"
        | "S楼"
        | "S座"
        | "南楼"
        | "综合教学楼S"
        | "综合教学楼S楼"
        | "综合教学楼S座"
        | "综合楼S"
        | "综合楼S楼"
        | "综合S" => "综合教学楼S".to_string(),
        "教学实验综合楼N"
        | "教学实验综合楼N楼"
        | "教学实验综合楼N座"
        | "教学实验综合楼北"
        | "教学实验综合楼北楼"
        | "教学实验综合楼-N"
        | "教学实验综合楼-N楼"
        | "教学实验综合楼(综教)N"
        | "教学实验综合楼（综教）N"
        | "教学实验综合楼N(综教)"
        | "教学实验综合楼N（综教）"
        | "综教N"
        | "综教N楼"
        | "综教N座"
        | "综教北"
        | "综教北楼"
        | "综教-N"
        | "综教-N楼" => "教学实验综合楼N".to_string(),
        "教学实验综合楼S"
        | "教学实验综合楼S楼"
        | "教学实验综合楼S座"
        | "教学实验综合楼南"
        | "教学实验综合楼南楼"
        | "教学实验综合楼-S"
        | "教学实验综合楼-S楼"
        | "教学实验综合楼(综教)S"
        | "教学实验综合楼（综教）S"
        | "教学实验综合楼S(综教)"
        | "教学实验综合楼S（综教）"
        | "综教S"
        | "综教S楼"
        | "综教S座"
        | "综教南"
        | "综教南楼"
        | "综教-S"
        | "综教-S楼" => "教学实验综合楼S".to_string(),
        "智慧楼" | "智慧教室楼" | "智慧教室" => "智慧教学楼".to_string(),
        _ if clean.is_empty() => "未知教学楼".to_string(),
        _ => clean.to_string(),
    }
}

fn original_building_name(name: &str) -> bool {
    matches!(
        name,
        "教1"
            | "教2"
            | "教3"
            | "教4"
            | "主楼"
            | "综合教学楼N"
            | "综合教学楼S"
            | "教学实验综合楼N"
            | "教学实验综合楼S"
            | "智慧教学楼"
    )
}

fn infer_teaching_experiment_side(building: String, room_name: String) -> (String, String) {
    if building != "教学实验综合楼" {
        return (building, room_name);
    }

    let clean_room = room_name
        .trim()
        .replace('－', "-")
        .replace('—', "-")
        .replace('–', "-")
        .replace(' ', "")
        .replace('　', "");
    let Some(side) = clean_room.chars().next() else {
        return (building, room_name);
    };
    let rest = clean_room[side.len_utf8()..].trim_start_matches('-');
    if rest.is_empty()
        || !rest
            .chars()
            .next()
            .is_some_and(|value| value.is_ascii_digit())
    {
        return (building, room_name);
    }

    match side {
        'N' | 'n' | '北' => ("教学实验综合楼N".to_string(), rest.to_string()),
        'S' | 's' | '南' => ("教学实验综合楼S".to_string(), rest.to_string()),
        _ => (building, room_name),
    }
}

fn extract_room_name(value: &str, building: &str) -> Option<String> {
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

    Regex::new(r"\d{3}(?:-\d{3})?")
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

fn parse_available_classrooms(items: &[Value], room_map: &mut HashMap<String, RoomAccumulator>) {
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
            let (building, room_name) =
                infer_teaching_experiment_side(normalize_building_name(&building_name), room_name);
            if !original_building_name(&building) {
                continue;
            }
            let Some(room) = extract_room_name(&room_name, &building) else {
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

async fn fetch_realtime_classrooms(
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

fn service_date_from_payload(payload: &ClassroomsRequest) -> ServiceResult<NaiveDate> {
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

    Ok(service_date)
}

fn classrooms_response_from_items(
    campus_id: &str,
    service_date: NaiveDate,
    available_classrooms: &[Value],
) -> ClassroomsResponse {
    let mut room_map = HashMap::new();
    parse_available_classrooms(available_classrooms, &mut room_map);

    let mut rooms: Vec<ClassroomStatus> = room_map
        .into_values()
        .map(|mut item| {
            item.available_slots.sort_unstable();
            item.available_slots.dedup();
            ClassroomStatus {
                id: item.id,
                building: item.building,
                room: item.room,
                name: item.name,
                size: item.size,
                r#type: String::new(),
                available_slots: item.available_slots,
                source: "sjd".to_string(),
            }
        })
        .collect();
    rooms.sort_by(|left, right| {
        (left.building.as_str(), left.room.as_str())
            .cmp(&(right.building.as_str(), right.room.as_str()))
    });

    ClassroomsResponse {
        campus_id: campus_id.to_string(),
        campus_name: campus_name(campus_id),
        target_date: service_date.to_string(),
        fetched_at: now_in_app_tz(),
        realtime: true,
        provider: "sjd".to_string(),
        rooms,
    }
}

async fn fetch_classrooms_for_campus(
    client: &reqwest::Client,
    token: &str,
    campus_id: &str,
    service_date: NaiveDate,
) -> ServiceResult<ClassroomsResponse> {
    let available_classrooms = fetch_realtime_classrooms(client, token, campus_id).await?;
    Ok(classrooms_response_from_items(
        campus_id,
        service_date,
        &available_classrooms,
    ))
}

pub async fn fetch_all_classrooms(
    payload: &ClassroomsRequest,
) -> ServiceResult<ClassroomsCacheResponse> {
    let service_date = service_date_from_payload(payload)?;
    let (user, secret) = resolve_credentials(&payload.account, &payload.password)?;
    let token = login_empty_classroom(&user, &secret).await?;
    let client = http_client(30)?;

    let mut campuses = Vec::with_capacity(CAMPUSES.len());
    for campus in CAMPUSES {
        let response = fetch_classrooms_for_campus(&client, &token, campus.id, service_date)
            .await
            .map_err(|error| {
                ServiceError::new(format!(
                    "{}校区实时教室数据获取失败：{}",
                    campus.name, error
                ))
            })?;
        campuses.push(response);
    }

    Ok(ClassroomsCacheResponse {
        cache_version: CLASSROOMS_CACHE_VERSION,
        target_date: service_date.to_string(),
        fetched_at: now_in_app_tz(),
        realtime: true,
        provider: "sjd".to_string(),
        campuses,
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
    fn parse_available_classrooms_merges_slots() {
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

        parse_available_classrooms(items, &mut room_map);

        let room = room_map.get("教3-335").unwrap();
        assert_eq!(room.building, "教3");
        assert_eq!(room.room, "335");
        assert_eq!(room.size, Some(90));
        assert_eq!(room.available_slots, vec![0, 2]);
    }

    #[test]
    fn parse_available_classrooms_uses_three_digit_room_number() {
        let mut room_map = HashMap::new();
        let items = serde_json::json!([
            {
                "NODENAME": "1",
                "CLASSROOMS": "校本部-教二楼-101A441(60),教二楼-406（信通实验室）(30),教二楼-107343(60)"
            }
        ]);
        let items = items.as_array().unwrap();

        parse_available_classrooms(items, &mut room_map);

        assert!(room_map.get("教2-101").is_some());
        assert!(room_map.get("教2-406").is_some());
        assert!(room_map.get("教2-107").is_some());
        assert!(room_map.get("教2-101A441").is_none());
        assert!(room_map.get("教2-107343").is_none());
    }

    #[test]
    fn parse_available_classrooms_keeps_original_buildings_only() {
        let mut room_map = HashMap::new();
        let items = serde_json::json!([
            {
                "NODENAME": "1",
                "CLASSROOMS": "校本部-教师自行安排-x(0),未来学习大楼-101(80)"
            }
        ]);
        let items = items.as_array().unwrap();

        parse_available_classrooms(items, &mut room_map);

        assert!(room_map.get("教师自行安排-x").is_none());
        assert!(room_map.get("主楼-101").is_some());
    }

    #[test]
    fn parse_available_classrooms_keeps_future_building_door_ranges() {
        let mut room_map = HashMap::new();
        let items = serde_json::json!([
            {
                "NODENAME": "10",
                "CLASSROOMS": "未来学习大楼-105(36),未来学习大楼-115(34),未来学习大楼-119(36),未来学习大楼-201(64),未来学习大楼-202-203(60),未来学习大楼-205(64),未来学习大楼-215(64),未来学习大楼-217-218(60),未来学习大楼-301(64),未来学习大楼-302-303(60),未来学习大楼-305(64),未来学习大楼-315(64),未来学习大楼-317-318(58),未来学习大楼-319(64),未来学习大楼-321-322(70)"
            }
        ]);
        let items = items.as_array().unwrap();

        parse_available_classrooms(items, &mut room_map);

        for room in [
            "主楼-105",
            "主楼-202-203",
            "主楼-217-218",
            "主楼-302-303",
            "主楼-317-318",
            "主楼-321-322",
        ] {
            assert_eq!(room_map.get(room).unwrap().available_slots, vec![9]);
        }
        assert!(room_map.get("主楼-217").is_none());
        assert!(room_map.get("主楼-218").is_none());
    }

    #[test]
    fn parse_available_classrooms_keeps_shahe_buildings() {
        let mut room_map = HashMap::new();
        let items = serde_json::json!([
            {
                "NODENAME": "2",
                "CLASSROOMS": "沙河-N-101(90),沙河-S楼-202(80),智慧教学楼-305-306(60)"
            },
            {
                "NODENAME": "4",
                "CLASSROOMS": "沙河-智慧教室楼-101(64),沙河-综合教学楼N-120(90),综合教学楼S-211(80)"
            },
            {
                "NODENAME": "6",
                "CLASSROOMS": "沙河-教学实验综合楼-N101(90),教学实验综合楼-N110(117),沙河-教学实验综合楼-北305(60),沙河-教学实验综合楼-S101(90),教学实验综合楼-S202(208),沙河-教学实验综合楼-南305(60),沙河-教学实验综合楼-999(10)"
            },
            {
                "NODENAME": "8",
                "CLASSROOMS": "沙河-教学实验综合楼N-101(90),沙河-综教N楼-202(80),教学实验综合楼（综教）N-305-306(60),沙河-教学实验综合楼S-101(90),沙河-综教S楼-202(80),教学实验综合楼（综教）S-305-306(60)"
            }
        ]);
        let items = items.as_array().unwrap();

        parse_available_classrooms(items, &mut room_map);

        assert_eq!(
            room_map.get("综合教学楼N-101").unwrap().available_slots,
            vec![1]
        );
        assert_eq!(
            room_map.get("综合教学楼S-202").unwrap().available_slots,
            vec![1]
        );
        assert_eq!(
            room_map.get("智慧教学楼-305-306").unwrap().available_slots,
            vec![1]
        );
        assert_eq!(
            room_map.get("智慧教学楼-101").unwrap().available_slots,
            vec![3]
        );
        assert_eq!(
            room_map.get("综合教学楼N-120").unwrap().available_slots,
            vec![3]
        );
        assert_eq!(
            room_map.get("综合教学楼S-211").unwrap().available_slots,
            vec![3]
        );
        assert_eq!(
            room_map.get("教学实验综合楼N-101").unwrap().available_slots,
            vec![5, 7]
        );
        assert_eq!(
            room_map.get("教学实验综合楼N-110").unwrap().available_slots,
            vec![5]
        );
        assert_eq!(
            room_map.get("教学实验综合楼N-305").unwrap().available_slots,
            vec![5]
        );
        assert_eq!(
            room_map.get("教学实验综合楼N-202").unwrap().available_slots,
            vec![7]
        );
        assert_eq!(
            room_map
                .get("教学实验综合楼N-305-306")
                .unwrap()
                .available_slots,
            vec![7]
        );
        assert_eq!(
            room_map.get("教学实验综合楼S-101").unwrap().available_slots,
            vec![5, 7]
        );
        assert_eq!(
            room_map.get("教学实验综合楼S-202").unwrap().available_slots,
            vec![5, 7]
        );
        assert_eq!(
            room_map.get("教学实验综合楼S-305").unwrap().available_slots,
            vec![5]
        );
        assert_eq!(
            room_map
                .get("教学实验综合楼S-305-306")
                .unwrap()
                .available_slots,
            vec![7]
        );
        assert!(room_map.get("教学实验综合楼-999").is_none());
    }

    #[test]
    fn node_name_to_slot_uses_one_based_nodes() {
        assert_eq!(node_name_to_slot("1"), Some(0));
        assert_eq!(node_name_to_slot("第14节"), Some(13));
        assert_eq!(node_name_to_slot("15"), None);
    }
}
