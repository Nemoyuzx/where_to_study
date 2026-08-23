use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, Instant};

use chrono::{DateTime, NaiveDate, NaiveDateTime};
use regex::Regex;
use reqwest::header::{
    HeaderMap, HeaderValue, ACCEPT, AUTHORIZATION, CONTENT_TYPE, COOKIE, LOCATION, REFERER,
    SET_COOKIE, USER_AGENT,
};
use reqwest::{Client, Response, Url};
use serde::Deserialize;
use serde_json::{json, Value};
use zeroize::{Zeroize, Zeroizing};

use crate::error::{ServiceError, ServiceResult};
use crate::models::{
    AssignmentCalendarResponse, AssignmentDeadlineItem, AssignmentsRequest, AssignmentsResponse,
    CalendarRangeRequest,
};

const SOURCE_URL: &str = "https://ucloud.bupt.edu.cn/uclass/";
const UCLOUD_ORIGIN: &str = "https://apiucloud.bupt.edu.cn";
const UCLOUD_HOST: &str = "apiucloud.bupt.edu.cn";
const CAS_LOGIN_URL: &str =
    "https://auth.bupt.edu.cn/authserver/login?service=https%3A%2F%2Fucloud.bupt.edu.cn";
const CAS_SERVICE_ORIGIN: &str = "https://ucloud.bupt.edu.cn";
const CAS_SERVICE_HOST: &str = "ucloud.bupt.edu.cn";
// This is the public OAuth client identifier shipped by the official UCloud web app.
// It is not a user credential and matches the deployed where_to_study-site client.
const PORTAL_AUTHORIZATION: &str = "Basic  cG9ydGFsOnBvcnRhbF9zZWNyZXQ=";
const TENANT_ID: &str = "000000";
const USER_AGENT_VALUE: &str = concat!(
    "WhereToStudy/",
    env!("CARGO_PKG_VERSION"),
    " (+https://github.com/Nemoyuzx/where_to_study)"
);
const MAX_LOGIN_HTML_BYTES: usize = 1024 * 1024;
const MAX_TOKEN_BYTES: usize = 512 * 1024;
const MAX_API_BYTES: usize = 8 * 1024 * 1024;
const MAX_COOKIE_BYTES: usize = 16 * 1024;
const MAX_COURSES: usize = 100;
const MAX_ASSIGNMENTS: usize = 5_000;
const COURSE_PAGE_SIZE: usize = 9_999;
const ASSIGNMENT_PAGE_SIZE: usize = 9_999;
const CACHE_TTL: Duration = Duration::from_secs(10 * 60);
const MAX_CALENDAR_RANGE_DAYS: i64 = 370;

#[derive(Deserialize)]
struct TokenPayload {
    access_token: String,
    #[serde(default, alias = "userId")]
    user_id: Value,
}

#[derive(Clone)]
struct CourseRef {
    id: String,
    name: Option<String>,
}

struct AuthenticatedClient {
    client: Client,
    access_token: Zeroizing<String>,
    user_id: String,
}

struct CachedAssignments {
    account_scope: String,
    fetched_at: Instant,
    items: Vec<AssignmentDeadlineItem>,
}

impl Drop for CachedAssignments {
    fn drop(&mut self) {
        self.account_scope.zeroize();
        zeroize_items(&mut self.items);
    }
}

static ASSIGNMENT_CACHE: OnceLock<Mutex<Option<CachedAssignments>>> = OnceLock::new();
static ASSIGNMENT_REVISION: AtomicU64 = AtomicU64::new(0);

fn cache() -> &'static Mutex<Option<CachedAssignments>> {
    ASSIGNMENT_CACHE.get_or_init(|| Mutex::new(None))
}

pub fn clear_cache() {
    ASSIGNMENT_REVISION.fetch_add(1, Ordering::SeqCst);
    let mut cached = cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    *cached = None;
}

fn zeroize_items(items: &mut [AssignmentDeadlineItem]) {
    for item in items {
        item.id.zeroize();
        item.title.zeroize();
        if let Some(course_name) = item.course_name.as_mut() {
            course_name.zeroize();
        }
        item.deadline.zeroize();
        if let Some(status) = item.status.as_mut() {
            status.zeroize();
        }
    }
}

fn parse_date(value: &str) -> ServiceResult<NaiveDate> {
    if value.len() != 10
        || value.as_bytes().get(4) != Some(&b'-')
        || value.as_bytes().get(7) != Some(&b'-')
    {
        return Err(ServiceError::with_status("作业日期格式不正确。", 400));
    }
    NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ServiceError::with_status("作业日期格式不正确。", 400))
}

fn text(value: Option<&Value>) -> String {
    value
        .and_then(|item| {
            item.as_str()
                .map(ToOwned::to_owned)
                .or_else(|| item.as_i64().map(|number| number.to_string()))
                .or_else(|| item.as_u64().map(|number| number.to_string()))
        })
        .unwrap_or_default()
}

fn normalized_deadline(value: &str) -> Option<(NaiveDate, String)> {
    let trimmed = value.trim();
    if let Ok(timestamp) = DateTime::parse_from_rfc3339(trimmed) {
        return Some((timestamp.date_naive(), timestamp.to_rfc3339()));
    }
    for format in ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M"] {
        if let Ok(timestamp) = NaiveDateTime::parse_from_str(trimmed, format) {
            return Some((
                timestamp.date(),
                timestamp.format("%Y-%m-%d %H:%M:%S").to_string(),
            ));
        }
    }
    None
}

fn assignment_status(raw: &Value) -> Option<String> {
    match raw.as_i64() {
        Some(99) => Some("未提交".to_string()),
        Some(0) => Some("已提交".to_string()),
        Some(1) => Some("已批改".to_string()),
        Some(2) => Some("已驳回".to_string()),
        _ => raw
            .as_str()
            .map(str::trim)
            .filter(|value| !value.is_empty())
            .map(ToOwned::to_owned),
    }
}

fn collect_records(payload: &Value) -> Vec<&Value> {
    [
        "/data/records",
        "/data/data/records",
        "/records",
        "/data/undoneList",
        "/data/data/undoneList",
        "/undoneList",
    ]
    .into_iter()
    .find_map(|pointer| payload.pointer(pointer).and_then(Value::as_array))
    .map(|items| items.iter().collect())
    .unwrap_or_default()
}

fn is_assignment_record(raw: &Value) -> bool {
    let Some(kind) = raw.get("type") else {
        return true;
    };
    let numeric = kind
        .as_i64()
        .or_else(|| kind.as_str().and_then(|value| value.parse::<i64>().ok()));
    numeric.is_none_or(|value| matches!(value, 3 | 5))
}

fn parse_assignment_record(
    raw: &Value,
    course_name_override: Option<&str>,
) -> Option<AssignmentDeadlineItem> {
    if !is_assignment_record(raw) {
        return None;
    }
    let deadline_text = text(raw.get("assignmentEndTime").or_else(|| raw.get("endTime")));
    let (_, deadline) = normalized_deadline(&deadline_text)?;
    let id = text(
        raw.get("id")
            .or_else(|| raw.get("assignmentId"))
            .or_else(|| raw.get("activityId")),
    );
    let title = text(
        raw.get("assignmentTitle")
            .or_else(|| raw.get("activityName"))
            .or_else(|| raw.get("title")),
    );
    if id.trim().is_empty() || title.trim().is_empty() {
        return None;
    }
    let embedded_course_name = text(
        raw.get("siteName")
            .or_else(|| raw.get("courseName"))
            .or_else(|| raw.get("siteTitle")),
    );
    let course_name = (!embedded_course_name.trim().is_empty())
        .then_some(embedded_course_name)
        .or_else(|| {
            course_name_override
                .map(str::trim)
                .filter(|value| !value.is_empty())
                .map(ToOwned::to_owned)
        });
    Some(AssignmentDeadlineItem {
        id,
        title,
        course_name,
        deadline,
        status: raw.get("assignmentStatus").and_then(assignment_status),
    })
}

fn parse_all_assignment_deadlines(
    payload: &Value,
    course_name_override: Option<&str>,
) -> Vec<AssignmentDeadlineItem> {
    collect_records(payload)
        .into_iter()
        .filter_map(|raw| parse_assignment_record(raw, course_name_override))
        .collect()
}

pub fn parse_assignment_deadlines(
    payload: &Value,
    requested_date: NaiveDate,
) -> Vec<AssignmentDeadlineItem> {
    let requested = requested_date.to_string();
    let mut items: Vec<_> = parse_all_assignment_deadlines(payload, None)
        .into_iter()
        .filter(|item| item.deadline.get(..10) == Some(requested.as_str()))
        .collect();
    sort_items(&mut items);
    items
}

fn sort_items(items: &mut [AssignmentDeadlineItem]) {
    items.sort_by(|left, right| {
        (&left.deadline, &left.course_name, &left.title, &left.id).cmp(&(
            &right.deadline,
            &right.course_name,
            &right.title,
            &right.id,
        ))
    });
}

fn assignment_items_in_range(
    all_items: Vec<AssignmentDeadlineItem>,
    start: NaiveDate,
    end: NaiveDate,
) -> Vec<AssignmentDeadlineItem> {
    let mut items: Vec<_> = all_items
        .into_iter()
        .filter(|item| {
            item.deadline
                .get(..10)
                .and_then(|value| NaiveDate::parse_from_str(value, "%Y-%m-%d").ok())
                .is_some_and(|date| date >= start && date <= end)
        })
        .collect();
    sort_items(&mut items);
    items
}

fn decode_html_attribute(value: &str) -> String {
    value
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
}

fn parse_execution(html: &str) -> Option<String> {
    let input_pattern = Regex::new(r"(?is)<input\b[^>]*>").expect("valid input regex");
    let attribute_pattern =
        Regex::new(r#"(?is)\b(name|value)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))"#)
            .expect("valid attribute regex");
    for input in input_pattern.find_iter(html) {
        let mut name = None;
        let mut value = None;
        for captures in attribute_pattern.captures_iter(input.as_str()) {
            let attribute_value = captures
                .get(2)
                .or_else(|| captures.get(3))
                .or_else(|| captures.get(4))
                .map(|capture| decode_html_attribute(capture.as_str()))?;
            match captures.get(1)?.as_str().to_ascii_lowercase().as_str() {
                "name" => name = Some(attribute_value),
                "value" => value = Some(attribute_value),
                _ => {}
            }
        }
        if name.as_deref() == Some("execution") {
            return value.filter(|item| !item.trim().is_empty());
        }
    }
    None
}

fn cookies_from(headers: &HeaderMap) -> ServiceResult<Zeroizing<String>> {
    let mut cookies = Vec::new();
    for value in headers.get_all(SET_COOKIE) {
        let value = value
            .to_str()
            .map_err(|_| ServiceError::new("统一认证返回了无效 Cookie。"))?;
        let cookie = value.split(';').next().unwrap_or_default().trim();
        if !cookie.is_empty() {
            cookies.push(cookie);
        }
    }
    let joined = cookies.join("; ");
    if joined.is_empty() || joined.len() > MAX_COOKIE_BYTES {
        return Err(ServiceError::new("统一认证未返回有效会话 Cookie。"));
    }
    Ok(Zeroizing::new(joined))
}

async fn read_limited(
    mut response: Response,
    maximum_bytes: usize,
    label: &str,
) -> ServiceResult<Zeroizing<Vec<u8>>> {
    if response
        .content_length()
        .is_some_and(|length| length > maximum_bytes as u64)
    {
        return Err(ServiceError::new(format!("{label}响应过大。")));
    }
    let mut bytes = Zeroizing::new(Vec::new());
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|error| ServiceError::new(format!("无法读取{label}响应：{error}")))?
    {
        if chunk.len() > maximum_bytes.saturating_sub(bytes.len()) {
            return Err(ServiceError::new(format!("{label}响应过大。")));
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(bytes)
}

fn parse_json(bytes: &[u8], label: &str) -> ServiceResult<Value> {
    serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("{label}没有返回有效 JSON：{error}")))
}

fn business_success(payload: &Value) -> bool {
    match payload.get("code") {
        None => true,
        Some(Value::Number(number)) => number.as_i64() == Some(200),
        Some(Value::String(value)) => value == "200",
        _ => false,
    }
}

fn validate_api_url(url: &Url) -> ServiceResult<()> {
    if url.scheme() != "https"
        || url.host_str() != Some(UCLOUD_HOST)
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(ServiceError::new("教学云接口地址不受信任。"));
    }
    Ok(())
}

fn validate_ticket_location(location: &str) -> ServiceResult<Zeroizing<String>> {
    let base = Url::parse(CAS_SERVICE_ORIGIN).expect("valid CAS service origin");
    let url = base
        .join(location)
        .map_err(|_| ServiceError::new("统一认证返回了无效跳转地址。"))?;
    if url.scheme() != "https"
        || url.host_str() != Some(CAS_SERVICE_HOST)
        || !url.username().is_empty()
        || url.password().is_some()
    {
        return Err(ServiceError::new("统一认证返回了不受信任的跳转地址。"));
    }
    let ticket = url
        .query_pairs()
        .find_map(|(name, value)| (name == "ticket").then(|| value.into_owned()))
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| {
            ServiceError::with_status(
                "统一认证未返回有效票据；请检查账号密码，若官方页面要求验证码请先完成验证。",
                401,
            )
        })?;
    Ok(Zeroizing::new(ticket))
}

fn base_headers() -> HeaderMap {
    let mut headers = HeaderMap::new();
    headers.insert(
        ACCEPT,
        HeaderValue::from_static("application/json, text/plain, */*"),
    );
    headers.insert(
        AUTHORIZATION,
        HeaderValue::from_static(PORTAL_AUTHORIZATION),
    );
    headers.insert("Tenant-Id", HeaderValue::from_static(TENANT_ID));
    headers.insert(USER_AGENT, HeaderValue::from_static(USER_AGENT_VALUE));
    headers.insert(
        REFERER,
        HeaderValue::from_static("https://ucloud.bupt.edu.cn/"),
    );
    headers
}

impl AuthenticatedClient {
    fn api_headers(&self) -> ServiceResult<HeaderMap> {
        let mut headers = base_headers();
        headers.insert(
            "Blade-Auth",
            HeaderValue::from_str(&self.access_token)
                .map_err(|_| ServiceError::new("教学云访问令牌格式不正确。"))?,
        );
        Ok(headers)
    }

    async fn get(&self, path: &str, query: &[(&str, String)]) -> ServiceResult<Value> {
        let mut url = Url::parse(UCLOUD_ORIGIN)
            .expect("valid UCloud origin")
            .join(path)
            .map_err(|error| ServiceError::new(format!("教学云接口地址无效：{error}")))?;
        validate_api_url(&url)?;
        url.query_pairs_mut()
            .extend_pairs(query.iter().map(|(name, value)| (*name, value.as_str())));
        let response = self
            .client
            .get(url)
            .headers(self.api_headers()?)
            .send()
            .await
            .map_err(|error| ServiceError::new(format!("无法连接教学云数据接口：{error}")))?;
        parse_api_response(response).await
    }

    async fn post_json(&self, path: &str, body: &Value) -> ServiceResult<Value> {
        let url = Url::parse(UCLOUD_ORIGIN)
            .expect("valid UCloud origin")
            .join(path)
            .map_err(|error| ServiceError::new(format!("教学云接口地址无效：{error}")))?;
        validate_api_url(&url)?;
        let response = self
            .client
            .post(url)
            .headers(self.api_headers()?)
            .json(body)
            .send()
            .await
            .map_err(|error| ServiceError::new(format!("无法连接教学云作业接口：{error}")))?;
        parse_api_response(response).await
    }
}

async fn parse_api_response(response: Response) -> ServiceResult<Value> {
    if response.status().is_redirection() {
        return Err(ServiceError::new("教学云接口返回了不受信任的重定向。"));
    }
    let status = response.status();
    let bytes = read_limited(response, MAX_API_BYTES, "教学云数据接口").await?;
    if !status.is_success() {
        return Err(ServiceError::new(format!(
            "教学云数据接口返回 HTTP {}。",
            status.as_u16()
        )));
    }
    let payload = parse_json(&bytes, "教学云数据接口")?;
    if !business_success(&payload) {
        return Err(ServiceError::new(format!(
            "教学云数据接口返回业务状态 {}。",
            text(payload.get("code")).trim()
        )));
    }
    Ok(payload)
}

async fn authenticate(account: &str, password: &str) -> ServiceResult<AuthenticatedClient> {
    if account.trim().is_empty() || password.is_empty() {
        return Err(ServiceError::with_status(
            "请先在设置中保存教务账号和密码。",
            401,
        ));
    }
    let client = Client::builder()
        .connect_timeout(Duration::from_secs(8))
        .timeout(Duration::from_secs(20))
        .redirect(reqwest::redirect::Policy::none())
        .build()
        .map_err(|error| ServiceError::new(format!("无法创建教学云请求：{error}")))?;

    let login_page = client
        .get(CAS_LOGIN_URL)
        .header(ACCEPT, "text/html")
        .header(USER_AGENT, USER_AGENT_VALUE)
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法连接统一认证登录页：{error}")))?;
    if !login_page.status().is_success() {
        return Err(ServiceError::new(format!(
            "统一认证登录页返回 HTTP {}。",
            login_page.status().as_u16()
        )));
    }
    let cookies = cookies_from(login_page.headers())?;
    let login_html = read_limited(login_page, MAX_LOGIN_HTML_BYTES, "统一认证登录页").await?;
    let login_html = std::str::from_utf8(&login_html)
        .map_err(|_| ServiceError::new("统一认证登录页编码不正确。"))?;
    let execution = Zeroizing::new(
        parse_execution(login_html)
            .ok_or_else(|| ServiceError::new("统一认证登录页缺少 execution 参数。"))?,
    );

    let login_response = client
        .post(CAS_LOGIN_URL)
        .header(CONTENT_TYPE, "application/x-www-form-urlencoded")
        .header(COOKIE, cookies.as_str())
        .header(REFERER, CAS_LOGIN_URL)
        .header(USER_AGENT, USER_AGENT_VALUE)
        .form(&[
            ("username", account.trim()),
            ("password", password),
            ("type", "username_password"),
            ("execution", execution.as_str()),
            ("_eventId", "submit"),
        ])
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法提交统一认证登录：{error}")))?;
    let location = login_response
        .headers()
        .get(LOCATION)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default();
    let ticket = validate_ticket_location(location)?;

    let token_url = Url::parse(UCLOUD_ORIGIN)
        .expect("valid UCloud origin")
        .join("/ykt-basics/oauth/token")
        .expect("valid token endpoint");
    validate_api_url(&token_url)?;
    let token_response = client
        .post(token_url)
        .headers(base_headers())
        .form(&[("ticket", ticket.as_str()), ("grant_type", "third")])
        .send()
        .await
        .map_err(|error| ServiceError::new(format!("无法换取教学云访问令牌：{error}")))?;
    if token_response.status().is_redirection() {
        return Err(ServiceError::new("教学云令牌接口返回了不受信任的重定向。"));
    }
    let status = token_response.status();
    let token_bytes = read_limited(token_response, MAX_TOKEN_BYTES, "教学云令牌接口").await?;
    if !status.is_success() {
        return Err(ServiceError::new(format!(
            "教学云令牌接口返回 HTTP {}。",
            status.as_u16()
        )));
    }
    let token_payload: TokenPayload = serde_json::from_slice(&token_bytes)
        .map_err(|error| ServiceError::new(format!("教学云令牌接口数据格式不正确：{error}")))?;
    if token_payload.access_token.trim().is_empty() {
        return Err(ServiceError::new("教学云令牌接口未返回访问令牌。"));
    }
    let user_id = text(Some(&token_payload.user_id));
    if user_id.trim().is_empty() {
        return Err(ServiceError::new("教学云令牌接口未返回用户标识。"));
    }
    Ok(AuthenticatedClient {
        client,
        access_token: Zeroizing::new(token_payload.access_token),
        user_id,
    })
}

fn parse_courses(payload: &Value) -> Vec<CourseRef> {
    collect_records(payload)
        .into_iter()
        .filter_map(|record| {
            let id = text(
                record
                    .get("id")
                    .or_else(|| record.get("siteId"))
                    .or_else(|| record.get("courseId")),
            );
            if id.trim().is_empty() {
                return None;
            }
            let name = text(
                record
                    .get("siteName")
                    .or_else(|| record.get("courseName"))
                    .or_else(|| record.get("siteTitle"))
                    .or_else(|| record.get("name")),
            );
            Some(CourseRef {
                id,
                name: (!name.trim().is_empty()).then_some(name),
            })
        })
        .take(MAX_COURSES)
        .collect()
}

fn merge_items(items: Vec<AssignmentDeadlineItem>) -> Vec<AssignmentDeadlineItem> {
    let mut merged = BTreeMap::<String, AssignmentDeadlineItem>::new();
    for item in items.into_iter().take(MAX_ASSIGNMENTS) {
        let key = format!("{}\u{1f}{}", item.id, item.deadline);
        match merged.get_mut(&key) {
            Some(existing) if existing.course_name.is_none() && item.course_name.is_some() => {
                *existing = item;
            }
            Some(_) => {}
            None => {
                merged.insert(key, item);
            }
        }
    }
    let mut result: Vec<_> = merged.into_values().collect();
    sort_items(&mut result);
    result
}

async fn fetch_all_assignments(
    account: &str,
    password: &str,
) -> ServiceResult<Vec<AssignmentDeadlineItem>> {
    let authenticated = authenticate(account, password).await?;
    let courses_payload = authenticated
        .get(
            "/ykt-site/site/list/student/current",
            &[
                ("size", COURSE_PAGE_SIZE.to_string()),
                ("current", "1".to_string()),
                ("userId", authenticated.user_id.clone()),
                ("siteRoleCode", "2".to_string()),
            ],
        )
        .await?;
    let courses = parse_courses(&courses_payload);
    let mut all_items = Vec::new();
    let mut successful_course_requests = 0usize;
    let mut first_course_error = None;
    for course in &courses {
        let body = json!({
            "siteId": course.id,
            "userId": authenticated.user_id,
            "keyword": "",
            "chapterId": "",
            "nodeId": "",
            "current": 1,
            "size": ASSIGNMENT_PAGE_SIZE,
            "studentAssignmentStatus": "",
            "status": "",
            "sortColumn": "",
            "sortType": ""
        });
        match authenticated
            .post_json("/ykt-site/work/student/list", &body)
            .await
        {
            Ok(payload) => {
                successful_course_requests += 1;
                all_items.extend(parse_all_assignment_deadlines(
                    &payload,
                    course.name.as_deref(),
                ));
            }
            Err(error) => {
                first_course_error.get_or_insert(error);
            }
        }
        if all_items.len() >= MAX_ASSIGNMENTS {
            break;
        }
    }
    if !courses.is_empty() && successful_course_requests == 0 {
        return Err(first_course_error
            .unwrap_or_else(|| ServiceError::new("教学云课程作业接口暂时不可用。")));
    }

    // The homepage list is merged after course lists. It covers pending
    // assignments that UCloud occasionally omits from a course page.
    if let Ok(undone_payload) = authenticated
        .get(
            "/ykt-site/site/student/undone",
            &[("userId", authenticated.user_id.clone())],
        )
        .await
    {
        all_items.extend(parse_all_assignment_deadlines(&undone_payload, None));
    }
    Ok(merge_items(all_items))
}

fn cached_items(account_scope: &str) -> Option<Vec<AssignmentDeadlineItem>> {
    let cached = cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    cached.as_ref().and_then(|snapshot| {
        (snapshot.account_scope == account_scope && snapshot.fetched_at.elapsed() < CACHE_TTL)
            .then(|| snapshot.items.clone())
    })
}

fn save_cache(account_scope: &str, items: &[AssignmentDeadlineItem], request_revision: u64) {
    let mut cached = cache()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if ASSIGNMENT_REVISION.load(Ordering::SeqCst) != request_revision {
        return;
    }
    *cached = Some(CachedAssignments {
        account_scope: account_scope.to_string(),
        fetched_at: Instant::now(),
        items: items.to_vec(),
    });
}

pub async fn fetch_assignments(
    payload: &AssignmentsRequest,
    account: &str,
    password: &str,
    account_scope: &str,
) -> ServiceResult<AssignmentsResponse> {
    let date = parse_date(payload.date.trim())?;
    let all_items = match cached_items(account_scope) {
        Some(items) => items,
        None => {
            let request_revision = ASSIGNMENT_REVISION.load(Ordering::SeqCst);
            let items = fetch_all_assignments(account, password).await?;
            save_cache(account_scope, &items, request_revision);
            items
        }
    };
    let requested = date.to_string();
    let items = all_items
        .into_iter()
        .filter(|item| item.deadline.get(..10) == Some(requested.as_str()))
        .collect();
    Ok(AssignmentsResponse {
        date: requested,
        source: SOURCE_URL.to_string(),
        items,
        unavailable_reason: None,
    })
}

pub async fn fetch_assignment_calendar(
    payload: &CalendarRangeRequest,
    account: &str,
    password: &str,
    account_scope: &str,
) -> ServiceResult<AssignmentCalendarResponse> {
    let start = parse_date(payload.start_date.trim())?;
    let end = parse_date(payload.end_date.trim())?;
    let day_count = end.signed_duration_since(start).num_days() + 1;
    if !(1..=MAX_CALENDAR_RANGE_DAYS).contains(&day_count) {
        return Err(ServiceError::with_status(
            "作业日历查询范围必须在 1 至 370 天内。",
            400,
        ));
    }

    let all_items = match cached_items(account_scope) {
        Some(items) => items,
        None => {
            let request_revision = ASSIGNMENT_REVISION.load(Ordering::SeqCst);
            let items = fetch_all_assignments(account, password).await?;
            save_cache(account_scope, &items, request_revision);
            items
        }
    };
    let items = assignment_items_in_range(all_items, start, end);

    Ok(AssignmentCalendarResponse {
        start_date: start.to_string(),
        end_date: end.to_string(),
        source: SOURCE_URL.to_string(),
        items,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_confirmed_student_assignment_list_contract() {
        let payload = serde_json::json!({
          "code": 200,
          "data": {
            "records": [
              {"id": 7, "assignmentTitle": "第四次作业", "siteName": "神经网络与深度学习", "assignmentEndTime": "2026-06-30 23:59:00", "assignmentStatus": 99},
              {"id": 8, "assignmentTitle": "第三次作业", "assignmentEndTime": "2026-06-21 23:59:00", "assignmentStatus": 0}
            ]
          }
        });
        let requested = NaiveDate::from_ymd_opt(2026, 6, 30).unwrap();
        let parsed = parse_assignment_deadlines(&payload, requested);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].title, "第四次作业");
        assert_eq!(parsed[0].course_name.as_deref(), Some("神经网络与深度学习"));
        assert_eq!(parsed[0].status.as_deref(), Some("未提交"));
    }

    #[test]
    fn parses_homepage_undone_assignments_and_skips_other_task_types() {
        let payload = serde_json::json!({
          "data": {
            "undoneList": [
              {"activityId":"a1","activityName":"课程作业","type":3,"endTime":"2026-08-22 18:00:00"},
              {"activityId":"q1","activityName":"课程测验","type":"4","endTime":"2026-08-22 20:00:00"}
            ]
          }
        });
        let requested = NaiveDate::from_ymd_opt(2026, 8, 22).unwrap();
        let parsed = parse_assignment_deadlines(&payload, requested);
        assert_eq!(parsed.len(), 1);
        assert_eq!(parsed[0].id, "a1");
    }

    #[test]
    fn execution_parser_accepts_attribute_order_and_escapes() {
        assert_eq!(
            parse_execution(r#"<input value='e1&amp;s1' type='hidden' name='execution'>"#)
                .as_deref(),
            Some("e1&s1")
        );
        assert_eq!(
            parse_execution(r#"<input name=execution value=token-2>"#).as_deref(),
            Some("token-2")
        );
    }

    #[test]
    fn ticket_redirect_is_https_and_host_pinned() {
        assert_eq!(
            validate_ticket_location("https://ucloud.bupt.edu.cn/?ticket=ST-test")
                .unwrap()
                .as_str(),
            "ST-test"
        );
        assert!(validate_ticket_location("http://ucloud.bupt.edu.cn/?ticket=ST-test").is_err());
        assert!(validate_ticket_location("https://evil.example/?ticket=ST-test").is_err());
        assert!(validate_ticket_location("https://ucloud.bupt.edu.cn/").is_err());
    }

    #[test]
    fn course_name_is_injected_and_homepage_duplicate_does_not_replace_it() {
        let course_payload = json!({"data":{"records":[
            {"id":"a1","assignmentTitle":"作业一","assignmentEndTime":"2026-08-22 23:59:00","assignmentStatus":99}
        ]}});
        let homepage_payload = json!({"data":{"undoneList":[
            {"activityId":"a1","activityName":"作业一","type":3,"endTime":"2026-08-22 23:59:00"}
        ]}});
        let mut items = parse_all_assignment_deadlines(&course_payload, Some("示例课程"));
        items.extend(parse_all_assignment_deadlines(&homepage_payload, None));
        let merged = merge_items(items);
        assert_eq!(merged.len(), 1);
        assert_eq!(merged[0].course_name.as_deref(), Some("示例课程"));
    }

    #[test]
    fn parses_current_course_contract_and_discards_invalid_rows() {
        let payload = json!({"data":{"records":[
            {"id":1,"siteName":"课程一"},
            {"siteId":"2","courseName":"课程二"},
            {"id":"","siteName":"无效课程"}
        ]}});
        let courses = parse_courses(&payload);
        assert_eq!(courses.len(), 2);
        assert_eq!(courses[0].id, "1");
        assert_eq!(courses[1].name.as_deref(), Some("课程二"));
    }

    #[test]
    fn calendar_range_keeps_only_assignments_inside_the_visible_dates() {
        let items = vec![
            AssignmentDeadlineItem {
                id: "before".to_string(),
                title: "范围前".to_string(),
                course_name: None,
                deadline: "2026-08-16T23:59:00+08:00".to_string(),
                status: None,
            },
            AssignmentDeadlineItem {
                id: "inside".to_string(),
                title: "范围内".to_string(),
                course_name: Some("课程".to_string()),
                deadline: "2026-08-18T23:59:00+08:00".to_string(),
                status: None,
            },
            AssignmentDeadlineItem {
                id: "after".to_string(),
                title: "范围后".to_string(),
                course_name: None,
                deadline: "2026-08-24T23:59:00+08:00".to_string(),
                status: None,
            },
        ];
        let start = NaiveDate::from_ymd_opt(2026, 8, 17).unwrap();
        let end = NaiveDate::from_ymd_opt(2026, 8, 23).unwrap();
        let filtered = assignment_items_in_range(items, start, end);
        assert_eq!(filtered.len(), 1);
        assert_eq!(filtered[0].id, "inside");
    }

    #[test]
    #[ignore = "requires the current user's saved Keychain credentials and live BUPT services"]
    fn live_saved_credentials_can_fetch_assignments_without_browser_state() {
        let credentials = crate::credential_store::load()
            .expect("saved credentials should be readable")
            .expect("saved credentials should exist");
        let items = tauri::async_runtime::block_on(fetch_all_assignments(
            &credentials.account,
            &credentials.password,
        ))
        .expect("native UCloud assignment sync should succeed");
        assert!(
            !items.is_empty(),
            "the saved account should return at least one assignment"
        );
    }
}
