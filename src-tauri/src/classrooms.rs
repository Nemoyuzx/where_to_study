use std::collections::HashMap;
use std::time::Duration;

use chrono::NaiveDate;
use regex::Regex;
use serde_json::Value;

use crate::auth::resolve_credentials;
use crate::config::{
    campus_name, normalize_campus_id, now_in_app_tz, today_in_app_tz, EMPTY_CLASSROOM_LOGIN_URL,
    EMPTY_CLASSROOM_QUERY_URL, PUBLIC_EMPTY_CLASSROOM_API,
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
    let (building, room) = clean
        .split_once('-')
        .map(|(building, room)| (building.trim(), room.trim()))
        .unwrap_or(("未知教学楼", clean.trim()));
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

fn parse_classrooms(raw: &str) -> Vec<(String, String, Option<usize>)> {
    Regex::new(r"[,，;；]\s*")
        .expect("valid regex")
        .split(raw)
        .filter_map(parse_classroom)
        .collect()
}

fn http_client(timeout_secs: u64) -> ServiceResult<reqwest::Client> {
    reqwest::Client::builder()
        .timeout(Duration::from_secs(timeout_secs))
        .redirect(reqwest::redirect::Policy::limited(10))
        .build()
        .map_err(|error| ServiceError::new(format!("无法初始化网络客户端：{error}")))
}

async fn login_empty_classroom(account: &str, password: &str) -> ServiceResult<String> {
    let client = http_client(20)?;
    let response = client
        .post(EMPTY_CLASSROOM_LOGIN_URL)
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
    if payload
        .get("code")
        .and_then(Value::as_i64)
        .map(|code| code.to_string())
        != Some("1".to_string())
        && payload.get("code").and_then(Value::as_str) != Some("1")
    {
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

pub async fn fetch_classrooms(payload: &ClassroomsRequest) -> ServiceResult<ClassroomsResponse> {
    let normalized_campus_id = normalize_campus_id(payload.campus_id.as_deref());
    let service_date = today_in_app_tz();
    if let Some(target_date) = payload
        .target_date
        .as_deref()
        .filter(|value| !value.trim().is_empty())
    {
        let parsed_date = NaiveDate::parse_from_str(target_date.trim(), "%Y-%m-%d")
            .map_err(|_| ServiceError::with_status("查询日期格式不正确。", 400))?;
        if parsed_date != service_date {
            return Err(ServiceError::with_status(
                "空教室实时服务目前只提供当天数据，请选择今天查询。",
                400,
            ));
        }
    }

    let credentials = resolve_credentials(&payload.account, &payload.password);
    let (user, secret) = match credentials {
        Ok(credentials) => credentials,
        Err(_) => return fetch_public_classrooms(Some(normalized_campus_id.as_str())).await,
    };
    let token = match login_empty_classroom(&user, &secret).await {
        Ok(token) => token,
        Err(_) => return fetch_public_classrooms(Some(normalized_campus_id.as_str())).await,
    };

    let client = http_client(30)?;
    let response = client
        .get(EMPTY_CLASSROOM_QUERY_URL)
        .query(&[("campusId", normalized_campus_id.as_str())])
        .header("token", token)
        .send()
        .await
        .map_err(|_| ServiceError::new("空教室数据获取失败，请稍后重试。"))?;
    if response.status().as_u16() >= 400 {
        return Err(ServiceError::new(format!(
            "空教室数据获取失败，HTTP {}。",
            response.status().as_u16()
        )));
    }
    let payload: Value = response
        .json()
        .await
        .map_err(|_| ServiceError::new("空教室服务返回了无法识别的数据。"))?;
    if payload
        .get("code")
        .and_then(Value::as_i64)
        .map(|code| code.to_string())
        != Some("1".to_string())
        && payload.get("code").and_then(Value::as_str) != Some("1")
    {
        let message = payload
            .get("Msg")
            .or_else(|| payload.get("msg"))
            .and_then(Value::as_str)
            .unwrap_or("空教室数据获取失败。");
        return Err(ServiceError::new(message));
    }

    let mut room_map: HashMap<String, RoomAccumulator> = HashMap::new();
    for item in payload
        .get("data")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
    {
        let slot = item
            .get("NODENAME")
            .or_else(|| item.get("nodeName"))
            .and_then(|value| {
                value
                    .as_str()
                    .map(ToOwned::to_owned)
                    .or_else(|| value.as_i64().map(|num| num.to_string()))
            })
            .and_then(|value| value.parse::<isize>().ok())
            .map(|value| value - 1);
        let Some(slot) = slot else {
            continue;
        };
        if !(0..14).contains(&slot) {
            continue;
        }
        let raw_rooms = item
            .get("CLASSROOMS")
            .or_else(|| item.get("classrooms"))
            .and_then(Value::as_str)
            .unwrap_or_default();
        for (building, room, size) in parse_classrooms(raw_rooms) {
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
            if !entry.available_slots.contains(&(slot as usize)) {
                entry.available_slots.push(slot as usize);
            }
        }
    }

    let mut rooms: Vec<ClassroomStatus> = room_map
        .into_values()
        .map(|mut item| {
            item.available_slots.sort_unstable();
            ClassroomStatus {
                id: item.id,
                building: item.building,
                room: item.room,
                name: item.name,
                size: item.size,
                r#type: String::new(),
                available_slots: item.available_slots,
                source: "jwglweixin".to_string(),
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
        provider: "jwglweixin".to_string(),
        rooms,
    })
}

pub async fn fetch_public_classrooms(campus_id: Option<&str>) -> ServiceResult<ClassroomsResponse> {
    let normalized_campus_id = normalize_campus_id(campus_id);
    let wanted_campus = campus_name(&normalized_campus_id);
    let client = http_client(30)?;
    let response = client
        .get(
            std::env::var("PUBLIC_EMPTY_CLASSROOM_API")
                .unwrap_or_else(|_| PUBLIC_EMPTY_CLASSROOM_API.to_string()),
        )
        .send()
        .await
        .map_err(|_| ServiceError::new("公共空教室数据源不可用，请稍后重试。"))?;
    if response.status().as_u16() >= 400 {
        return Err(ServiceError::new(format!(
            "公共空教室数据源获取失败，HTTP {}。",
            response.status().as_u16()
        )));
    }
    let payload: Value = response
        .json()
        .await
        .map_err(|_| ServiceError::new("公共空教室数据源返回了无法识别的数据。"))?;
    if payload.get("code").and_then(Value::as_i64) != Some(0) {
        return Err(ServiceError::new("公共空教室数据源返回失败。"));
    }

    let campus_map = payload
        .get("data")
        .and_then(|data| data.get("campus_info_map"))
        .and_then(Value::as_object)
        .ok_or_else(|| ServiceError::new("公共空教室数据源缺少校区数据。"))?;
    let campus_payload = campus_map.get(&wanted_campus).ok_or_else(|| {
        let available = campus_map.keys().cloned().collect::<Vec<_>>().join("、");
        ServiceError::new(format!(
            "公共空教室数据源没有 {wanted_campus} 数据，可用校区：{}。",
            if available.is_empty() {
                "无".to_string()
            } else {
                available
            }
        ))
    })?;

    let mut rooms = Vec::new();
    for building in campus_payload
        .get("building_info_map")
        .and_then(Value::as_object)
        .into_iter()
        .flat_map(|buildings| buildings.values())
    {
        let building_name = building
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("未知教学楼")
            .to_string();
        let class_matrix = building
            .get("class_matrix")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        let classroom_map = building
            .get("classroom_info_map")
            .and_then(Value::as_object)
            .cloned()
            .unwrap_or_default();

        for (classroom_id, classroom) in classroom_map {
            let room_index = classroom_id
                .parse::<usize>()
                .ok()
                .or_else(|| {
                    classroom
                        .get("building_id")
                        .and_then(Value::as_u64)
                        .map(|value| value as usize)
                })
                .unwrap_or(0);
            let mut available_slots = Vec::new();
            for (slot_index, row) in class_matrix.iter().take(14).enumerate() {
                if row
                    .as_array()
                    .and_then(|row_values| row_values.get(room_index))
                    .and_then(Value::as_i64)
                    == Some(0)
                {
                    available_slots.push(slot_index);
                }
            }
            let room_name = classroom
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or(classroom_id.as_str())
                .to_string();
            let full_name = format!("{building_name}-{room_name}");
            rooms.push(ClassroomStatus {
                id: full_name.clone(),
                building: building_name.clone(),
                room: room_name,
                name: full_name,
                size: classroom
                    .get("size")
                    .and_then(Value::as_u64)
                    .map(|value| value as usize),
                r#type: classroom
                    .get("type")
                    .and_then(Value::as_str)
                    .unwrap_or_default()
                    .to_string(),
                available_slots,
                source: "jray_public".to_string(),
            });
        }
    }

    rooms.sort_by(|left, right| {
        (left.building.as_str(), left.room.as_str())
            .cmp(&(right.building.as_str(), right.room.as_str()))
    });
    Ok(ClassroomsResponse {
        campus_id: normalized_campus_id,
        campus_name: wanted_campus,
        target_date: today_in_app_tz().to_string(),
        fetched_at: now_in_app_tz(),
        realtime: true,
        provider: "jray_public".to_string(),
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
    }
}
