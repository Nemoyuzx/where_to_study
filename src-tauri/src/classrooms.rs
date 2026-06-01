use std::collections::HashMap;
use std::time::Duration;

use chrono::NaiveDate;
use regex::Regex;
use reqwest::header::{HeaderMap, HeaderValue, ORIGIN, REFERER, USER_AGENT};
use serde_json::Value;

use crate::auth::resolve_credentials;
use crate::config::{
    campus_name, normalize_campus_id, now_in_app_tz, today_in_app_tz, EMPTY_CLASSROOM_IDLE_URL,
    EMPTY_CLASSROOM_LOGIN_URL, SJD_LOGIN_PAGE_URL, SJD_ORIGIN, SJD_REST_CLASSROOM_PAGE_URL,
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

fn normalize_room_name(room: String, building: &str) -> String {
    let clean = room.trim().to_string();
    let Some(building_number) = building.strip_prefix('教') else {
        return clean;
    };
    let Some((prefix, room_number)) = clean.split_once('-') else {
        return clean;
    };
    if prefix == building_number {
        room_number.trim().to_string()
    } else {
        clean
    }
}

fn format_room_name(classroom: &Value) -> String {
    let room_number = value_string(
        classroom
            .get("classroomnumber")
            .or_else(|| classroom.get("classroomNumber")),
    )
    .trim()
    .to_string();
    let room_label = value_string(
        classroom
            .get("classroomname")
            .or_else(|| classroom.get("classroomName")),
    )
    .trim()
    .to_string();

    if !room_number.is_empty() && !room_label.contains(&room_number) {
        return format!("{room_label}{room_number}");
    }
    if !room_label.is_empty() {
        room_label
    } else if !room_number.is_empty() {
        room_number
    } else {
        value_string(classroom.get("classroomId"))
            .trim()
            .to_string()
    }
}

fn parse_idle_classroom_groups(
    groups: &[Value],
    slot: usize,
    room_map: &mut HashMap<String, RoomAccumulator>,
) {
    for group in groups {
        let building = normalize_building_name(&value_string(
            group
                .get("teachingBuildingName")
                .or_else(|| group.get("buildingName"))
                .or_else(|| group.get("teachingbuildingname")),
        ));
        if !original_building_name(&building) {
            continue;
        }

        for classroom in group
            .get("classroomList")
            .and_then(Value::as_array)
            .into_iter()
            .flatten()
        {
            let room = normalize_room_name(format_room_name(classroom), &building);
            let key = format!("{building}-{room}");
            let size = classroom
                .get("seatnumber")
                .or_else(|| classroom.get("seatNumber"))
                .and_then(|value| {
                    value
                        .as_u64()
                        .or_else(|| value.as_str().and_then(|text| text.parse::<u64>().ok()))
                })
                .and_then(|value| usize::try_from(value).ok())
                .filter(|value| *value > 0);

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

async fn fetch_idle_classroom_slot(
    client: &reqwest::Client,
    token: &str,
    target: NaiveDate,
    campus_id: &str,
    slot: usize,
) -> ServiceResult<(usize, Vec<Value>)> {
    let node = format!("{:02}{:02}", slot + 1, slot + 1);
    let response = client
        .post(EMPTY_CLASSROOM_IDLE_URL)
        .query(&[
            ("date", target.to_string()),
            ("nodeId", node),
            ("buildingId", String::new()),
            ("campusId", campus_id.to_string()),
        ])
        .headers(sjd_headers(Some(token), SJD_REST_CLASSROOM_PAGE_URL))
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
    if !code_is_success(&payload) {
        let message = payload
            .get("Msg")
            .or_else(|| payload.get("msg"))
            .and_then(Value::as_str)
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| format!("第 {} 节空教室数据获取失败。", slot + 1));
        return Err(ServiceError::new(message));
    }

    Ok((
        slot,
        payload
            .get("data")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default(),
    ))
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

    let (user, secret) = resolve_credentials(&payload.account, &payload.password)?;
    let token = login_empty_classroom(&user, &secret).await?;
    let client = http_client(30)?;

    let mut room_map = HashMap::new();
    for slot in 0..14 {
        let (_, groups) =
            fetch_idle_classroom_slot(&client, &token, service_date, &normalized_campus_id, slot)
                .await?;
        parse_idle_classroom_groups(&groups, slot, &mut room_map);
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
    }

    #[test]
    fn parse_idle_classroom_groups_merges_slots() {
        let mut room_map = HashMap::new();
        let groups = serde_json::json!([
            {
                "teachingBuildingName": "校本部-教三楼",
                "classroomList": [
                    {
                        "classroomId": "335",
                        "classroomname": "335",
                        "classroomnumber": "335",
                        "seatnumber": "90"
                    }
                ]
            }
        ]);
        let groups = groups.as_array().unwrap();

        parse_idle_classroom_groups(groups, 0, &mut room_map);
        parse_idle_classroom_groups(groups, 2, &mut room_map);

        let room = room_map.get("教3-335").unwrap();
        assert_eq!(room.building, "教3");
        assert_eq!(room.room, "335");
        assert_eq!(room.size, Some(90));
        assert_eq!(room.available_slots, vec![0, 2]);
    }

    #[test]
    fn parse_idle_classroom_groups_keeps_original_buildings_only() {
        let mut room_map = HashMap::new();
        let groups = serde_json::json!([
            {
                "teachingBuildingName": "校本部-教师自行安排",
                "classroomList": [
                    {
                        "classroomId": "x",
                        "classroomname": "x",
                        "classroomnumber": "x"
                    }
                ]
            },
            {
                "teachingBuildingName": "未来学习大楼",
                "classroomList": [
                    {
                        "classroomId": "101",
                        "classroomname": "101",
                        "classroomnumber": "101"
                    }
                ]
            }
        ]);
        let groups = groups.as_array().unwrap();

        parse_idle_classroom_groups(groups, 0, &mut room_map);

        assert!(room_map.get("教师自行安排-x").is_none());
        assert!(room_map.get("主楼-101").is_some());
    }
}
