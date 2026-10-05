use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::sync::{
    atomic::{AtomicBool, AtomicU64, Ordering},
    Mutex,
};
use tauri::{Emitter, Manager};
use zeroize::Zeroizing;

pub const SCRIPT: &str = include_str!("../../contracts/qmplus/qmplus-sync.js");
const AUTH_SCRIPT: &str = include_str!("../../contracts/qmplus/qmplus-auth.js");
const PAGE_SCRIPT: &str = include_str!("../../contracts/qmplus/qmplus-page.js");
const MS_ORIGIN: &str = "https://login.microsoftonline.com";
const MAXIMUM_ACCOUNT_SETTLING_POLLS: u8 = 12;
const MS_PATHS: [&str; 2] = [
    "/569df091-b013-40e3-86ee-bd9cb9e25814/saml2",
    "/569df091-b013-40e3-86ee-bd9cb9e25814/login",
];
const ORIGIN: &str = "https://qmplus.qmul.ac.uk";
const MAXIMUM_SNAPSHOT_BYTES: usize = 512 * 1024;
const BUSINESS_PATHS: [&str; 5] = [
    "/my",
    "/my/",
    "/course/view.php",
    "/mod/assign/view.php",
    "/mod/quiz/view.php",
];
const DOCUMENT_GUARD: &str = "location.origin==='https://qmplus.qmul.ac.uk'&&['/my','/my/','/course/view.php','/mod/assign/view.php','/mod/quiz/view.php'].includes(location.pathname)";
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Course {
    pub id: String,
    pub name: String,
    pub short_name: String,
    pub url: Option<String>,
    pub start_at: Option<String>,
    pub end_at: Option<String>,
    pub current_term_status: String,
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Activity {
    pub id: String,
    pub course_id: String,
    pub title: String,
    pub kind: String,
    pub url: String,
    pub due_at: Option<String>,
    pub opens_at: Option<String>,
    pub closes_at: Option<String>,
    pub cutoff_at: Option<String>,
    pub time_limit_seconds: Option<u32>,
    pub status: String,
    pub detail_status: String,
    pub raw_time_text: String,
}
impl Activity {
    // Moodle assign modules can also be administrative forms. This mirrors the
    // shared protocol's narrow policy, never a missing-date or broad review filter.
    fn is_assessment(&self) -> bool {
        if self.kind != "assignment" {
            return true;
        }
        let mut normalized = String::with_capacity(self.title.len());
        let mut gap = false;
        for scalar in self.title.chars() {
            let mut cp = u32::from(scalar);
            if (0xFF01..=0xFF5E).contains(&cp) {
                cp -= 0xFEE0;
            }
            if matches!(cp, 9..=13 | 0x20 | 0x85 | 0xA0 | 0x1680 | 0x2000..=0x200A |
                0x2028 | 0x2029 | 0x202F | 0x205F | 0x3000 | 0xFEFF |
                0x5F | 0x2D | 0x2F | 0x3A | 0x2010..=0x2015 | 0x2212)
            {
                gap = !normalized.is_empty();
                continue;
            }
            if gap {
                normalized.push(' ');
            }
            gap = false;
            if (0x61..=0x7A).contains(&cp) {
                cp -= 0x20;
            }
            normalized.push(char::from_u32(cp).unwrap_or(scalar));
        }
        normalized != "COURSEWORK MARK REVIEW REQUEST"
            && normalized != "COURSEWORK MARK REVIEW REQUEST FORM"
    }
}
#[derive(Clone, Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
pub struct Snapshot {
    pub schema_version: u8,
    pub source: String,
    pub fetched_at: String,
    pub ok: bool,
    pub partial: bool,
    pub courses: Vec<Course>,
    pub activities: Vec<Activity>,
    pub warnings: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error_code: Option<String>,
}
#[derive(Default)]
pub struct QmState {
    pub snapshot: Mutex<Option<Snapshot>>,
    pub revision: AtomicU64,
    feature_blocked: AtomicBool,
    owner_active: AtomicBool,
    quiet_owner: AtomicBool,
    window_revision: AtomicU64,
    auth: Mutex<AuthState>,
    sso_started: Mutex<bool>,
    quiet_deadline: Mutex<Option<tauri::async_runtime::JoinHandle<()>>>,
    close_after_sync: Mutex<bool>,
    main_focus_watched: AtomicBool,
    connection_status: Mutex<ConnectionStatus>,
    page_kind: Mutex<&'static str>,
    dashboard_started: AtomicBool,
}
#[derive(Default, Clone, Serialize)]
pub struct ConnectionStatus {
    phase: &'static str,
    reason: &'static str,
}
fn record_connection_status(app: &tauri::AppHandle, phase: &'static str, reason: &'static str) {
    if let Ok(mut value) = app.state::<QmState>().connection_status.lock() {
        *value = ConnectionStatus { phase, reason };
    }
    let _ = app.emit(
        "qmplus:connection-status",
        ConnectionStatus { phase, reason },
    );
}
#[tauri::command]
pub fn load_qmplus_connection_status(state: tauri::State<'_, QmState>) -> ConnectionStatus {
    state
        .connection_status
        .lock()
        .map(|v| v.clone())
        .unwrap_or_default()
}
struct AuthDocument {
    nonce: String,
    url: tauri::Url,
}
#[derive(Default)]
struct AuthState {
    document: Option<AuthDocument>,
    ledger: AuthLedger,
}
impl AuthState {
    fn document_for_report(
        &self,
        nonce: &str,
        url: &tauri::Url,
        credential_revision: u64,
    ) -> Option<&AuthDocument> {
        self.ledger.accepts(credential_revision).then_some(())?;
        self.document
            .as_ref()
            .filter(|document| document.nonce == nonce && &document.url == url)
    }
}
// Presentation-owned, credential-revision-bound claims survive navigation.
// This ledger contains no account, password, URL or server session identifier.
#[derive(Default)]
struct AuthLedger {
    credential_revision: u64,
    active: bool,
    username_attempted: bool,
    password_attempted: bool,
    account_attempted: bool,
    account_claimed_document: Option<String>,
    account_selected_document: Option<String>,
    account_settling_polls: u8,
    username_claimed_document: Option<String>,
    username_submitted_document: Option<String>,
    password_claimed_document: Option<String>,
}
impl AuthLedger {
    fn begin(&mut self, credential_revision: u64) {
        *self = Self {
            credential_revision,
            active: true,
            ..Self::default()
        };
    }
    fn accepts(&self, credential_revision: u64) -> bool {
        self.active && self.credential_revision == credential_revision
    }
    fn can_begin_sso(&self, credential_revision: u64) -> bool {
        self.accepts(credential_revision) && !self.account_attempted && !self.username_attempted && !self.password_attempted
    }
    fn stop(&mut self) {
        self.active = false;
        self.account_claimed_document = None;
        self.account_selected_document = None;
        self.username_claimed_document = None;
        self.username_submitted_document = None;
        self.password_claimed_document = None;
    }
    fn claim_account_settling(
        &mut self,
        stage: &str,
        reason: &str,
        nonce: &str,
        credential_revision: u64,
    ) -> bool {
        if !self.accepts(credential_revision)
            || stage != "manual"
            || reason != "ACCOUNT_CHOOSER"
            || self.password_attempted
            || self.account_selected_document.as_deref() != Some(nonce)
            || self.account_settling_polls >= MAXIMUM_ACCOUNT_SETTLING_POLLS
        {
            return false;
        }
        self.account_settling_polls += 1;
        true
    }
    fn claim(
        &mut self,
        stage: &str,
        nonce: &str,
        account_match: bool,
        credential_revision: u64,
    ) -> bool {
        if !self.accepts(credential_revision) || !valid_nonce(nonce) {
            return false;
        }
        match stage {
            "account"
                if !self.account_attempted
                    && !self.username_attempted
                    && !self.password_attempted
                    && account_match =>
            {
                self.account_attempted = true;
                self.account_claimed_document = Some(nonce.to_owned());
                true
            }
            "username" if !self.username_attempted && !self.password_attempted => {
                self.username_attempted = true;
                self.username_claimed_document = Some(nonce.to_owned());
                true
            }
            "password"
                if !self.password_attempted
                    && account_match
                    && (self.username_submitted_document.as_deref() == Some(nonce)
                        || self.account_selected_document.as_deref() == Some(nonce)) =>
            {
                self.password_attempted = true;
                self.password_claimed_document = Some(nonce.to_owned());
                true
            }
            _ => false,
        }
    }
    fn submitted(&mut self, nonce: &str, reason: &str, credential_revision: u64) -> bool {
        if !self.accepts(credential_revision) || !valid_nonce(nonce) {
            return false;
        }
        match reason {
            "ACCOUNT_SELECTED"
                if self.account_attempted
                    && !self.password_attempted
                    && self.account_claimed_document.as_deref() == Some(nonce) =>
            {
                self.account_selected_document = Some(nonce.to_owned());
                true
            }
            "USERNAME_SUBMITTED"
                if self.username_attempted
                    && !self.password_attempted
                    && self.username_claimed_document.as_deref() == Some(nonce) =>
            {
                self.username_submitted_document = Some(nonce.to_owned());
                true
            }
            "PASSWORD_SUBMITTED"
                if self.password_attempted
                    && self.password_claimed_document.as_deref() == Some(nonce) =>
            {
                true
            }
            _ => false,
        }
    }
}
fn valid_nonce(nonce: &str) -> bool {
    (8..=64).contains(&nonce.len())
        && nonce
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-')
}
#[derive(Serialize)]
struct AuthFill<'a> {
    document: &'a str,
    stage: &'a str,
    account: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    password: Option<&'a str>,
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct AuthReport {
    v: u8,
    stage: String,
    document: String,
    #[serde(rename = "accountMatch")]
    account_match: bool,
    reason: String,
}
fn trusted_auth_page(url: &tauri::Url) -> bool {
    url.username().is_empty()
        && url.password().is_none()
        && url.scheme() == "https"
        && (url.port().is_none() || url.port() == Some(443))
        && url.origin().ascii_serialization() == MS_ORIGIN && MS_PATHS.contains(&url.path())
}
fn official_qm_page(url: &tauri::Url) -> bool {
    url.origin().ascii_serialization() == ORIGIN && url.username().is_empty() && url.password().is_none()
}
fn guest_entry(url: &tauri::Url) -> bool {
    official_qm_page(url) && url.fragment().is_none() &&
        ((url.path() == "/" && matches!(url.query(), None | Some("redirect=0"))) ||
         (url.path() == "/login/index.php" && url.query().is_none()))
}
fn page_allows_sync(url: &tauri::Url, kind: &str) -> bool { kind == "authenticated" && valid_business_page(url) }
const APPROVED_SSO: &str = "(()=>{const targets=new Set(Array.from(document.querySelectorAll('a[href]')).flatMap(a=>{try{const u=new URL(a.getAttribute('href'),location.href);return u.href==='https://qmplus.qmul.ac.uk/auth/saml2/login.php'&&!u.username&&!u.password&&!u.search&&!u.hash?[u.href]:[];}catch{return[];}}));return targets.size===1;})()";
fn show_login(window: &tauri::WebviewWindow) {
    let _ = window.show();
    let _ = window.set_focus();
}
fn valid_url(value: &str) -> bool {
    let Ok(u) = tauri::Url::parse(value) else {
        return false;
    };
    u.origin().ascii_serialization() == ORIGIN
        && u.username().is_empty()
        && u.password().is_none()
        && [
            "/course/view.php",
            "/mod/assign/view.php",
            "/mod/quiz/view.php",
        ]
        .contains(&u.path())
        && u.fragment().is_none()
        && u.query()
            .and_then(|query| query.strip_prefix("id="))
            .is_some_and(valid_id)
        && value
            .strip_prefix(ORIGIN)
            .and_then(|path| path.split_once('?'))
            .is_some_and(|(path, query)| path == u.path() && Some(query) == u.query())
}
fn valid_id(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 16
        && value.as_bytes()[0] != b'0'
        && value.bytes().all(|c| c.is_ascii_digit())
}
fn valid_business_page(url: &tauri::Url) -> bool {
    url.origin().ascii_serialization() == ORIGIN
        && url.username().is_empty()
        && url.password().is_none()
        && BUSINESS_PATHS.contains(&url.path())
}
fn valid_source(label: &str, url: &tauri::Url) -> bool {
    label == "qmplus" && valid_business_page(url)
}
fn valid_utc(value: &str) -> bool {
    value.len() <= 40 && value.ends_with('Z') && chrono::DateTime::parse_from_rfc3339(value).is_ok()
}
fn valid_date(value: &Option<String>) -> bool {
    value.as_ref().is_none_or(|value| valid_utc(value))
}
fn bounded_text(value: &str, maximum_utf16: usize) -> bool {
    !value.contains('\0') && value.encode_utf16().count() <= maximum_utf16
}
fn valid_code(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|c| c.is_ascii_uppercase() || c.is_ascii_digit() || c == b'_')
}
impl Snapshot {
    pub fn validate(&self) -> Result<(), String> {
        if self.schema_version != 1
            || self.source != "qmplus"
            || self.courses.len() > 100
            || self.activities.len() > 500
            || self.warnings.len() > 40
            || !valid_utc(&self.fetched_at)
            || self
                .error_code
                .as_ref()
                .is_some_and(|code| !valid_code(code))
            || (self.ok && self.error_code.is_some())
        {
            return Err("QMplus 快照格式无效。".into());
        }
        let mut course_ids = BTreeSet::new();
        for c in &self.courses {
            if !valid_id(&c.id)
                || !course_ids.insert(&c.id)
                || c.name.trim().is_empty()
                || !bounded_text(&c.name, 512)
                || !bounded_text(&c.short_name, 512)
                || !["current", "other", "unknown"].contains(&c.current_term_status.as_str())
                || c.url.as_ref().is_some_and(|u| {
                    !valid_url(u)
                        || tauri::Url::parse(u).ok().is_none_or(|u| {
                            u.path() != "/course/view.php"
                                || u.query_pairs().next().is_none_or(|(_, v)| v != c.id)
                        })
                })
                || !valid_date(&c.start_at)
                || !valid_date(&c.end_at)
            {
                return Err("QMplus 课程字段无效。".into());
            }
        }
        let mut activity_ids = BTreeSet::new();
        for a in &self.activities {
            if !valid_url(&a.url)
                || !valid_id(&a.id)
                || !activity_ids.insert(&a.id)
                || tauri::Url::parse(&a.url).ok().is_none_or(|u| {
                    u.path()
                        != if a.kind == "assignment" {
                            "/mod/assign/view.php"
                        } else {
                            "/mod/quiz/view.php"
                        }
                        || u.query_pairs().next().is_none_or(|(_, v)| v != a.id)
                })
                || a.title.trim().is_empty()
                || !bounded_text(&a.title, 512)
                || !bounded_text(&a.status, 1000)
                || !bounded_text(&a.raw_time_text, 1000)
                || a.time_limit_seconds
                    .is_some_and(|seconds| seconds > 31_536_000)
                || !["assignment", "quiz"].contains(&a.kind.as_str())
                || !["available", "restricted", "unavailable"].contains(&a.detail_status.as_str())
                || !self.courses.iter().any(|c| c.id == a.course_id)
                || ![&a.due_at, &a.opens_at, &a.closes_at, &a.cutoff_at]
                    .iter()
                    .all(|d| valid_date(d))
            {
                return Err("QMplus 活动字段无效。".into());
            }
        }
        if self.warnings.iter().any(|warning| !valid_code(warning)) {
            return Err("QMplus 警告字段无效。".into());
        }
        if serde_json::to_vec(self)
            .map_err(|_| "QMplus 快照格式无效。")?
            .len()
            > MAXIMUM_SNAPSHOT_BYTES
        {
            return Err("QMplus 快照超过 512 KiB。".into());
        }
        Ok(())
    }
}

impl QmState {
    fn set_feature_enabled(&self, enabled: bool) {
        self.feature_blocked.store(!enabled, Ordering::SeqCst);
        if !enabled {
            self.owner_active.store(false, Ordering::SeqCst);
            self.revision.fetch_add(1, Ordering::SeqCst);
            self.stop_autofill();
        }
    }
    fn assessment_snapshot(&self) -> Option<Snapshot> {
        // Old in-memory snapshots were validated when published by their reader.
        // Filter a clone so a display refresh does not mutate source timestamps.
        self.snapshot.lock().ok()?.clone().map(|mut snapshot| {
            snapshot.activities.retain(Activity::is_assessment);
            snapshot
        })
    }
    fn stop_autofill(&self) {
        let mut auth = self
            .auth
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        auth.document = None;
        auth.ledger.stop();
        drop(auth);
        if let Some(deadline) = self
            .quiet_deadline
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
        {
            deadline.abort();
        }
    }
    fn revoke(&self) {
        self.owner_active.store(false, Ordering::SeqCst);
        self.revision.fetch_add(1, Ordering::SeqCst);
        *self
            .snapshot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
        self.stop_autofill();
        *self
            .sso_started
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = false;
    }

    fn quiet_timeout_is_current(&self, revision: u64) -> bool {
        !self.feature_blocked.load(Ordering::SeqCst)
            && self.owner_active.load(Ordering::SeqCst)
            && self.quiet_owner.load(Ordering::SeqCst)
            && self.revision.load(Ordering::SeqCst) == revision
            && self.auth.lock().ok().is_some_and(|auth| auth.ledger.active)
    }

    fn publish(&self, mut snapshot: Snapshot, revision: u64) -> Result<(), String> {
        snapshot.validate()?;
        if !snapshot.ok {
            return Err("QMplus 需要重新登录或同步失败；上次数据保留。".into());
        }
        snapshot.activities.retain(Activity::is_assessment);
        let mut data = self.snapshot.lock().map_err(|_| "QMplus 缓存不可用。")?;
        if self.feature_blocked.load(Ordering::SeqCst)
            || revision != self.revision.load(Ordering::SeqCst)
        {
            return Err("QMplus 会话已失效。".into());
        }
        if snapshot.partial && data.is_some() {
            if let Some(previous) = data.as_mut() {
                previous.activities.retain(Activity::is_assessment);
                previous.partial = true;
                previous.warnings = vec!["QM_LAST_GOOD_RETAINED".into()];
            }
        } else {
            *data = Some(snapshot);
        }
        Ok(())
    }
}

fn cancel_autofill(app: &tauri::AppHandle) {
    app.state::<QmState>().stop_autofill();
    if let Some(window) = app.get_webview_window("qmplus") {
        if window.url().ok().is_some_and(|url| trusted_auth_page(&url)) {
            let _ = window.eval(
                "if(window.top===window)window.dispatchEvent(new Event('wts-qm-auth-stop'));"
                    .to_string(),
            );
        }
    }
}

fn require_manual(app: &tauri::AppHandle, window: &tauri::WebviewWindow, reason: &'static str) {
    cancel_autofill(app);
    record_connection_status(app, "manual", reason);
    show_login(window);
}

fn watch_background(app: &tauri::AppHandle, window: &tauri::WebviewWindow) {
    let handle = app.clone();
    window.on_window_event(move |event| {
        if !matches!(event, tauri::WindowEvent::Focused(false)) {
            return;
        }
        let revision = handle.state::<QmState>().revision.load(Ordering::SeqCst);
        let handle = handle.clone();
        tauri::async_runtime::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(250)).await;
            let owner = handle.clone();
            let _ = handle.run_on_main_thread(move || {
                let state = owner.state::<QmState>();
                let active = state
                    .auth
                    .lock()
                    .ok()
                    .is_some_and(|auth| auth.ledger.active);
                if active
                    && state.revision.load(Ordering::SeqCst) == revision
                    && app_is_backgrounded(&owner)
                {
                    cancel_autofill(&owner);
                    record_connection_status(&owner, "manual", "APP_BACKGROUNDED");
                }
            });
        });
    });
}

// Called on the UI thread. On macOS Inspector and native dialogs can own focus
// while NSApplication remains active, so window focus alone is insufficient.
fn app_is_backgrounded(app: &tauri::AppHandle) -> bool {
    #[cfg(target_os = "macos")]
    {
        let application: *mut objc2::runtime::AnyObject =
            unsafe { objc2::msg_send![objc2::class!(NSApplication), sharedApplication] };
        if !application.is_null() {
            let active: bool = unsafe { objc2::msg_send![application, isActive] };
            return !active;
        }
    }
    !app.webview_windows()
        .values()
        .any(|w| w.is_focused().unwrap_or(false))
}

#[tauri::command]
pub fn load_qmplus(state: tauri::State<'_, QmState>) -> Option<Snapshot> {
    if state.feature_blocked.load(Ordering::SeqCst) {
        return None;
    }
    state.assessment_snapshot()
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FeatureRequest {
    enabled: bool,
}
#[tauri::command]
pub fn set_qmplus_enabled(
    app: tauri::AppHandle,
    state: tauri::State<'_, QmState>,
    payload: FeatureRequest,
) -> Result<crate::models::SavedSettings, String> {
    // Closing the feature cancels owned callbacks, not the private credentials,
    // snapshot or cookie store. Keep the parked incognito window for reuse.
    if !payload.enabled {
        state.set_feature_enabled(false);
        crate::qmplus_feature::disable_for_session();
        if let Some(window) = app.get_webview_window("qmplus") {
            let _ = window.eval("if(location.origin==='https://qmplus.qmul.ac.uk'&&typeof WTSQmCancel==='function')WTSQmCancel();");
            let _ = window.hide();
        }
    }
    crate::qmplus_feature::set(&app, payload.enabled)?;
    state.set_feature_enabled(payload.enabled);
    let settings = crate::settings_store::load_preferences(&app).map_err(|e| e.message)?;
    let _ = app.emit("qmplus:changed", ());
    Ok(settings)
}
#[tauri::command]
pub fn disconnect_qmplus(app: tauri::AppHandle, state: tauri::State<'_, QmState>) {
    state.revoke();
    if let Some(w) = app.get_webview_window("qmplus") {
        if w.url().ok().is_some_and(|url| valid_business_page(&url)) {
            let _ = w.eval(format!(
                "if({DOCUMENT_GUARD}&&typeof WTSQmCancel==='function')WTSQmCancel();"
            ));
        }
        let _ = w.close();
    }
    let _ = app.emit("qmplus:changed", ());
}
#[tauri::command]
pub fn accept_qmplus_snapshot(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    state: tauri::State<'_, QmState>,
    payload: String,
    revision: u64,
) -> Result<(), String> {
    if !crate::qmplus_feature::enabled(&app).unwrap_or(false) {
        return Err("QMplus 尚未启用。".into());
    }
    let u = window.url().map_err(|_| "QMplus 页面不可用。")?;
    if !valid_source(window.label(), &u)
        || *state.page_kind.lock().map_err(|_| "QMplus 状态不可用。")? != "authenticated"
        || revision != state.revision.load(Ordering::SeqCst)
        || payload.len() > MAXIMUM_SNAPSHOT_BYTES
    {
        return Err("QMplus 来源或会话已失效。".into());
    }
    let snapshot: Snapshot = serde_json::from_str(&payload).map_err(|_| "QMplus 快照格式无效。")?;
    // Recheck the current document after parsing, not just the navigation payload.
    let current = window.url().map_err(|_| "QMplus 页面不可用。")?;
    if !valid_source(window.label(), &current) || current != u {
        return Err("QMplus 来源或会话已失效。".into());
    }
    if let Err(error) = state.publish(snapshot, revision) {
        cancel_autofill(&app);
        record_connection_status(&app, "failed", "SYNC_FAILED");
        show_login(&window);
        return Err(error);
    }
    cancel_autofill(&app);
    let partial = state
        .snapshot
        .lock()
        .ok()
        .and_then(|data| data.as_ref().map(|s| s.partial))
        .unwrap_or(false);
    record_connection_status(
        &app,
        if partial { "partial" } else { "synced" },
        "SYNC_VALIDATED",
    );
    let _ = app.emit("qmplus:changed", ());
    // Close only after a validated business snapshot, not a navigation heuristic.
    if *state
        .close_after_sync
        .lock()
        .map_err(|_| "QMplus 页面不可用。")?
        && ["/my", "/my/"].contains(&current.path())
    {
        let _ = window.close();
    }
    Ok(())
}

#[tauri::command]
pub fn accept_qmplus_auth(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    state: tauri::State<'_, QmState>,
    report: AuthReport,
    revision: u64,
) -> Result<bool, String> {
    if !crate::qmplus_feature::enabled(&app).unwrap_or(false) {
        return Err("QMplus 尚未启用。".into());
    }
    if window.label() != "qmplus"
        || revision != state.revision.load(Ordering::SeqCst)
        || report.v != 1
        || !valid_nonce(&report.document)
        || report.reason.len() > 32
        || ![
            "page",
            "loading",
            "account",
            "username",
            "password",
            "manual",
            "unknown",
            "submitted",
        ]
        .contains(&report.stage.as_str())
    {
        return Err("QMplus 登录状态已失效。".into());
    }
    let url = window.url().map_err(|_| "QMplus 页面不可用。")?;
    if report.stage == "page" {
        let auth = state.auth.lock().map_err(|_| "QMplus 页面不可用。")?;
        if !official_qm_page(&url) || !state.owner_active.load(Ordering::SeqCst) ||
            !auth.document.as_ref().is_some_and(|doc| doc.nonce == report.document && doc.url == url) {
            return Err("QMplus 来源或会话已失效。".into());
        }
        drop(auth);
        let kind = match report.reason.as_str() {
            "authenticated" => "authenticated", "guest" | "guest_sso" => "guest", "error" => "error",
            "loading" => "loading", _ => "unknown",
        };
        *state.page_kind.lock().map_err(|_| "QMplus 页面不可用。")? = kind;
        if kind == "error" { require_manual(&app, &window, "QM_ERROR_PAGE"); return Ok(false); }
        if kind == "loading" { return Ok(false); }
        if kind == "guest" && guest_entry(&url) && report.reason == "guest_sso" &&
            crate::qmplus_login::authorized(&app).is_some() && state.auth.lock().ok().is_some_and(|a| a.ledger.can_begin_sso(crate::qmplus_login::revision())) {
            let mut started = state.sso_started.lock().map_err(|_| "QMplus 页面不可用。")?;
            if !*started {
                *started = true;
                let current = serde_json::to_string(url.as_str()).map_err(|_| "QMplus 页面不可用。")?;
                let _ = window.eval(format!("(()=>{{if(location.href!=={current})return;const kind={PAGE_SCRIPT};if(kind==='guest'&&{APPROVED_SSO})location.assign('https://qmplus.qmul.ac.uk/auth/saml2/login.php');}})()"));
                return Ok(false);
            }
        }
        if kind == "authenticated" && guest_entry(&url) {
            if !state.dashboard_started.swap(true, Ordering::SeqCst) {
                window.navigate(tauri::Url::parse("https://qmplus.qmul.ac.uk/my/").map_err(|_| "QMplus 地址无效。")?)
                    .map_err(|_| "QMplus 页面不可用。")?;
            } else { require_manual(&app, &window, "UNSUPPORTED_PAGE"); }
            return Ok(false);
        }
        if page_allows_sync(&url, kind) {
            let _ = window.eval(format!("if({DOCUMENT_GUARD}){{{SCRIPT}}}"));
            let _ = window.eval(sync_bridge(revision));
        } else if url.path() != "/auth/saml2/login.php" { require_manual(&app, &window, "UNSUPPORTED_PAGE"); }
        return Ok(false);
    }
    let credential_revision = crate::qmplus_login::revision();
    let mut auth = state.auth.lock().map_err(|_| "QMplus 页面不可用。")?;
    let document = auth
        .document_for_report(&report.document, &url, credential_revision)
        .ok_or("QMplus 登录状态已失效。")?;
    if !trusted_auth_page(&url) {
        return Err("QMplus 登录状态已失效。".into());
    }
    let nonce = document.nonce.clone();
    // A successful chooser click can leave an empty SPA chooser briefly.
    // Only a native ACK for this document authorizes bounded read-only polling.
    if auth.ledger.claim_account_settling(
        &report.stage,
        &report.reason,
        &nonce,
        credential_revision,
    ) {
        drop(auth);
        record_connection_status(&app, "checking", "ACCOUNT_CHOOSER");
        return Ok(true);
    }
    let reason = match report.reason.as_str() {
        "READY" => "READY",
        "FORM_UNTRUSTED" => "FORM_UNTRUSTED",
        "AUTH_CONFLICT" => "AUTH_CONFLICT",
        "UNSUPPORTED_PAGE" => "UNSUPPORTED_PAGE",
        "ACCOUNT_CHOOSER" => "ACCOUNT_CHOOSER",
        "ACCOUNT_HINT_REQUIRED" => "ACCOUNT_HINT_REQUIRED",
        "ACCOUNT_SELECTED" => "ACCOUNT_SELECTED",
        "ACCOUNT_MISMATCH" => "ACCOUNT_MISMATCH",
        "INTERFERENCE" => "INTERFERENCE",
        "KNOWN_FORM_ABSENT" => "KNOWN_FORM_ABSENT",
        "ALREADY_ATTEMPTED" => "ALREADY_ATTEMPTED",
        "USERNAME_SUBMITTED" => "USERNAME_SUBMITTED",
        "PASSWORD_SUBMITTED" => "PASSWORD_SUBMITTED",
        "POLL_EXHAUSTED" => "POLL_EXHAUSTED",
        _ => "MANUAL_REQUIRED",
    };
    let phase = match report.stage.as_str() {
        "account" => "username",
        "username" => "username",
        "password" => "password",
        "submitted" => "submitted",
        "loading" => "checking",
        _ => "manual",
    };
    record_connection_status(&app, phase, reason);
    if report.stage == "submitted" {
        let accepted = auth
            .ledger
            .submitted(&nonce, &report.reason, credential_revision);
        drop(auth);
        if !accepted {
            require_manual(&app, &window, "MANUAL_REQUIRED");
        }
        return Ok(false);
    }
    if report.stage == "loading" {
        drop(auth);
        // A hidden platform window may need one visible layout pass. This is
        // still a bounded inspection wait, not a credential submission retry.
        if report.reason == "FORM_UNTRUSTED" || report.reason == "KNOWN_FORM_ABSENT" {
            show_login(&window);
        }
        return Ok(false);
    }
    if report.reason == "ALREADY_ATTEMPTED" {
        return Ok(false);
    }
    if report.reason != "READY" {
        drop(auth);
        require_manual(&app, &window, reason);
        return Ok(false);
    }
    let Some(credentials) = crate::qmplus_login::authorized(&app) else {
        drop(auth);
        require_manual(&app, &window, "AUTHORIZATION_REVOKED");
        return Ok(false);
    };
    if !auth.ledger.claim(
        &report.stage,
        &nonce,
        report.account_match,
        credential_revision,
    ) {
        drop(auth);
        require_manual(&app, &window, "MANUAL_REQUIRED");
        return Ok(false);
    }
    let options = AuthFill {
        document: &nonce,
        stage: &report.stage,
        account: &credentials.account,
        password: (report.stage == "password").then_some(credentials.password.as_str()),
    };
    let encoded =
        Zeroizing::new(serde_json::to_string(&options).map_err(|_| "QMplus 页面不可用。")?);
    if window.url().ok().as_ref() != Some(&url)
        || revision != state.revision.load(Ordering::SeqCst)
        || credential_revision != crate::qmplus_login::revision()
    {
        return Ok(false);
    }
    let script = Zeroizing::new(format!(
        r#"(()=>{{if(location.href!=={}||typeof WTSQmAuth==='undefined'||typeof WTSQmAuthPollActive!=='function'||!WTSQmAuthPollActive({}))return;
      const code=WTSQmAuth.fillAndSubmit({});window.__TAURI_INTERNALS__.invoke('accept_qmplus_auth',{{revision:{revision},report:{{v:1,stage:'submitted',document:{},accountMatch:false,reason:code}}}}).catch(()=>{{}});}})()"#,
        serde_json::to_string(url.as_str()).map_err(|_| "QMplus 页面不可用。")?,
        serde_json::to_string(&nonce).map_err(|_| "QMplus 页面不可用。")?,
        &*encoded,
        serde_json::to_string(&nonce).map_err(|_| "QMplus 页面不可用。")?
    ));
    let result = window.eval(&*script);
    drop(auth);
    if result.is_err() {
        require_manual(&app, &window, "SCRIPT_UNAVAILABLE");
        return Err("QMplus 自动填写未能运行。".into());
    }
    Ok(false)
}
fn sync_bridge(revision: u64) -> String {
    format!(
        r#"(()=>{{if({DOCUMENT_GUARD}){{const kind={PAGE_SCRIPT};if(kind!=='authenticated')return;
      const button=document.createElement('button');button.textContent='同步课程 / Sync courses';
      button.style='position:fixed;right:12px;top:12px;z-index:2147483647;padding:12px';
      button.onclick=async()=>{{button.disabled=true;try{{const current={PAGE_SCRIPT};if(current!=='authenticated')throw new Error('QM_ERROR_PAGE');await window.__TAURI_INTERNALS__.invoke('begin_qmplus_sync',{{revision:{revision}}});const result=await WTSQmSync();await window.__TAURI_INTERNALS__.invoke('accept_qmplus_snapshot',{{payload:JSON.stringify(result),revision:{revision}}});button.textContent='同步完成 / Synced';}}catch(e){{button.textContent='请重新登录或重试 / Retry';}}finally{{button.disabled=false;}}}};document.body.appendChild(button);
      if(['/my','/my/'].includes(location.pathname))button.click();
    }}}})()"#
    )
}
#[tauri::command]
pub fn begin_qmplus_sync(
    window: tauri::WebviewWindow,
    state: tauri::State<'_, QmState>,
    revision: u64,
) -> Result<(), String> {
    if state.feature_blocked.load(Ordering::SeqCst)
        || *state.page_kind.lock().map_err(|_| "QMplus 页面不可用。")? != "authenticated"
        || !state.owner_active.load(Ordering::SeqCst)
        || revision != state.revision.load(Ordering::SeqCst)
        || window
            .url()
            .ok()
            .is_none_or(|u| !valid_source(window.label(), &u))
    {
        return Err("QMplus 会话已失效。".into());
    }
    state.stop_autofill();
    if *state
        .close_after_sync
        .lock()
        .map_err(|_| "QMplus 页面不可用。")?
    {
        let _ = window.hide();
    }
    Ok(())
}
#[tauri::command]
pub fn connect_qmplus(
    app: tauri::AppHandle,
    state: tauri::State<'_, QmState>,
) -> Result<(), String> {
    if !crate::qmplus_feature::enabled(&app).unwrap_or(false) {
        state.set_feature_enabled(false);
        return Err("QMplus 尚未启用。".into());
    }
    state.set_feature_enabled(true);
    if let Some(w) = app
        .get_webview_window("qmplus")
        .filter(|_| state.owner_active.load(Ordering::SeqCst) && state.page_kind.lock().ok().is_none_or(|kind| *kind != "error"))
    {
        let _ = w.show();
        w.set_focus().map_err(|_| "无法打开 QMplus。")?;
        return Ok(());
    }
    let revision = state.revision.fetch_add(1, Ordering::SeqCst) + 1;
    state.stop_autofill();
    state.dashboard_started.store(false, Ordering::SeqCst);
    *state.page_kind.lock().map_err(|_| "QMplus 页面不可用。")? = "unknown";
    *state
        .sso_started
        .lock()
        .map_err(|_| "QMplus 页面不可用。")? = false;
    let credential_revision = crate::qmplus_login::revision();
    let quiet = crate::qmplus_login::authorized(&app).is_some()
        && credential_revision == crate::qmplus_login::revision();
    state.owner_active.store(true, Ordering::SeqCst);
    state.quiet_owner.store(quiet, Ordering::SeqCst);
    if quiet {
        state
            .auth
            .lock()
            .map_err(|_| "QMplus 页面不可用。")?
            .ledger
            .begin(credential_revision);
    }
    *state
        .close_after_sync
        .lock()
        .map_err(|_| "QMplus 页面不可用。")? = true;
    record_connection_status(&app, "checking", "");
    if let Some(window) = app.get_webview_window("qmplus") {
        if quiet {
            let _ = window.hide();
        } else {
            let _ = window.show();
        }
        window
            .navigate(
                tauri::Url::parse("https://qmplus.qmul.ac.uk/my/")
                    .map_err(|_| "QMplus 地址无效。")?,
            )
            .map_err(|_| "无法打开 QMplus。")?;
        if quiet {
            arm_quiet_deadline(&app, &state, revision)?;
        }
        return Ok(());
    }
    let window_revision = state.window_revision.fetch_add(1, Ordering::SeqCst) + 1;
    let window = tauri::WebviewWindowBuilder::new(
        &app,
        "qmplus",
        tauri::WebviewUrl::External(
            tauri::Url::parse("https://qmplus.qmul.ac.uk/my/").map_err(|_| "QMplus 地址无效。")?,
        ),
    )
    .title("QMplus — 官方登录与课程同步")
    .incognito(true)
    .visible(!quiet)
    .inner_size(1000.0, 760.0)
    .on_page_load(move |w, p| {
        let handle = w.app_handle();
        let state = handle.state::<QmState>();
        if state.feature_blocked.load(Ordering::SeqCst) || !state.owner_active.load(Ordering::SeqCst) { return; }
        let revision = state.revision.load(Ordering::SeqCst);
        if p.event() == tauri::webview::PageLoadEvent::Started {
            *state.page_kind.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = "unknown";
            state.auth.lock().unwrap_or_else(std::sync::PoisonError::into_inner).document = None;
            if valid_business_page(p.url()) && !["/my", "/my/"].contains(&p.url().path()) {
                *state.close_after_sync.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = false;
            }
            return;
        }
        if p.event() == tauri::webview::PageLoadEvent::Finished {
            let Some(current) = w.url().ok().filter(|u| u == p.url()) else { return; };
            let Some(window) = handle.get_webview_window("qmplus") else { return; };
            if official_qm_page(&current) {
                let nonce = match crate::scoped_cache::new_account_scope() {
                    Ok(v) => v.trim_start_matches("opaque-v1:").to_string(),
                    Err(_) => { require_manual(handle,&window,"DOCUMENT_UNAVAILABLE"); return; }
                };
                state.auth.lock().unwrap_or_else(std::sync::PoisonError::into_inner).document = Some(AuthDocument { nonce: nonce.clone(), url: current.clone() });
                let encoded_nonce = serde_json::to_string(&nonce).unwrap_or_default();
                let encoded_url = serde_json::to_string(current.as_str()).unwrap_or_default();
                let _ = window.eval(format!("(()=>{{if(location.href!=={encoded_url})return;const kind={PAGE_SCRIPT};const reason=kind==='guest'&&{APPROVED_SSO}?'guest_sso':kind;window.__TAURI_INTERNALS__.invoke('accept_qmplus_auth',{{revision:{revision},report:{{v:1,stage:'page',document:{encoded_nonce},accountMatch:false,reason}}}}).catch(()=>{{}});}})()"));
                return;
            }
            let credentials = crate::qmplus_login::authorized(handle);
            let active = state.auth.lock().unwrap_or_else(std::sync::PoisonError::into_inner).ledger.accepts(crate::qmplus_login::revision());
            if !trusted_auth_page(&current) || credentials.is_none() || !active { require_manual(handle,&window,"UNSUPPORTED_PAGE"); return; }
            let nonce = match crate::scoped_cache::new_account_scope() {
                Ok(v) => v.trim_start_matches("opaque-v1:").to_string(),
                Err(_) => { require_manual(handle,&window,"DOCUMENT_UNAVAILABLE"); return; }
            };
            state.auth.lock().unwrap_or_else(std::sync::PoisonError::into_inner).document = Some(AuthDocument {
                nonce: nonce.clone(), url: current.clone(),
            });
            let account = credentials.as_ref().map(|v| v.account.as_str()).unwrap_or("");
            // No password is sent during helper installation or username inspection.
            let script = Zeroizing::new(format!(r#"(()=>{{const install={AUTH_SCRIPT};if(install!=='AUTH_INSTALLED'){{window.__TAURI_INTERNALS__.invoke('accept_qmplus_auth',{{revision:{revision},report:{{v:1,stage:'manual',document:{nonce},accountMatch:false,reason:'AUTH_CONFLICT'}}}}).catch(()=>{{}});return;}}
              let attempts=0,settling=0,cancelled=false,timer,accountHint={account};
              const finish=()=>{{cancelled=true;accountHint='';clearTimeout(timer);window.removeEventListener('pagehide',finish);window.removeEventListener('wts-qm-auth-stop',finish);}};
              if(Object.prototype.hasOwnProperty.call(globalThis,'WTSQmAuthPollActive')){{window.__TAURI_INTERNALS__.invoke('accept_qmplus_auth',{{revision:{revision},report:{{v:1,stage:'manual',document:{nonce},accountMatch:false,reason:'AUTH_CONFLICT'}}}}).catch(()=>{{}});finish();return;}}
              Object.defineProperty(globalThis,'WTSQmAuthPollActive',{{value:documentNonce=>!cancelled&&documentNonce==={nonce}&&location.href==={url},writable:false,configurable:false}});
              window.addEventListener('pagehide',finish,{{once:true}});window.addEventListener('wts-qm-auth-stop',finish,{{once:true}});
              const send=report=>window.__TAURI_INTERNALS__.invoke('accept_qmplus_auth',{{report,revision:{revision}}}).catch(finish);
              const schedule=delay=>{{if(!cancelled)timer=setTimeout(poll,delay);}};
              const poll=async()=>{{if(cancelled)return;if(location.href!=={url}){{finish();return;}}if(++attempts>70){{send({{v:1,stage:'manual',document:{nonce},accountMatch:false,reason:'POLL_EXHAUSTED'}});finish();return;}}
                const report=WTSQmAuth.inspect({nonce},accountHint);if(report.stage==='manual'&&['FORM_UNTRUSTED','KNOWN_FORM_ABSENT'].includes(report.reason)&&settling++<16){{if(settling===8)send({{...report,stage:'loading'}});schedule(250);return;}}
                const accountWait=await send(report);if(cancelled)return;if(location.href!=={url}){{finish();return;}}
                if(accountWait===true&&report.stage==='manual'&&report.reason==='ACCOUNT_CHOOSER'){{schedule(250);return;}}
                if(report.stage==='manual'&&report.reason!=='ALREADY_ATTEMPTED'){{finish();return;}}schedule(350);}};poll();}})()"#,
                nonce=serde_json::to_string(&nonce).unwrap_or_default(), url=serde_json::to_string(current.as_str()).unwrap_or_default(),
                account=serde_json::to_string(account).unwrap_or_default()));
            if w.eval(&*script).is_err() { require_manual(handle,&window,"SCRIPT_UNAVAILABLE"); }
        }
    })
    .build()
    .map_err(|_| "无法创建 QMplus 官方登录窗口。")?;
    let handle = app.clone();
    window.on_window_event(move |event| {
        let state = handle.state::<QmState>();
        if matches!(event, tauri::WindowEvent::Destroyed)
            && state.window_revision.load(Ordering::SeqCst) == window_revision
        {
            state.owner_active.store(false, Ordering::SeqCst);
            state.revision.fetch_add(1, Ordering::SeqCst);
            state.stop_autofill();
            let completed = state
                .connection_status
                .lock()
                .ok()
                .is_some_and(|v| ["synced", "partial"].contains(&v.phase));
            if !completed {
                record_connection_status(&handle, "cancelled", "WINDOW_CLOSED");
            }
        }
    });
    // A single window losing focus is not the app entering the background.
    // Give a main/official-window focus transfer time to settle, then retire
    // only automation; the official browser and last-good cache stay intact.
    watch_background(&app, &window);
    if let Some(main) = app.get_webview_window("main") {
        if !state.main_focus_watched.swap(true, Ordering::SeqCst) {
            watch_background(&app, &main);
        }
    }
    if quiet {
        arm_quiet_deadline(&app, &state, revision)?;
    }
    Ok(())
}

fn arm_quiet_deadline(
    app: &tauri::AppHandle,
    state: &QmState,
    revision: u64,
) -> Result<(), String> {
    let mut pending = state
        .quiet_deadline
        .lock()
        .map_err(|_| "QMplus 页面不可用。")?;
    if let Some(previous) = pending.take() {
        previous.abort();
    }
    if !state.quiet_timeout_is_current(revision) {
        return Ok(());
    }
    let handle = app.clone();
    *pending = Some(tauri::async_runtime::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(25)).await;
        if handle.state::<QmState>().quiet_timeout_is_current(revision) {
            if let Some(window) = handle.get_webview_window("qmplus") {
                require_manual(&handle, &window, "QUIET_TIMEOUT");
            }
        }
    }));
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn account_chooser_settling_requires_ack_and_never_rearms_an_input_attempt() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(!ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceA123", 7));
        assert!(ledger.claim("account", "nonceA123", true, 7));
        assert!(!ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceA123", 7));
        assert_eq!(ledger.account_settling_polls, 0);
        assert!(ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        assert!(ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceA123", 7));
        assert!(!ledger.claim("account", "nonceA123", true, 7));
        assert!(!ledger.username_attempted);
        assert!(!ledger.password_attempted);
        assert!(ledger.username_submitted_document.is_none());
        assert!(ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceA123", 7));
    }

    #[test]
    fn account_chooser_settling_rejects_other_documents_reasons_revisions_and_retired_owners() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(ledger.claim("account", "nonceA123", true, 7));
        assert!(ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        assert!(!ledger.claim_account_settling("account", "ACCOUNT_CHOOSER", "nonceA123", 7));
        assert!(!ledger.claim_account_settling("manual", "ACCOUNT_MISMATCH", "nonceA123", 7));
        assert!(!ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceB456", 7));
        assert!(!ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceA123", 8));
        assert_eq!(ledger.account_settling_polls, 0);
        ledger.stop();
        assert!(!ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceA123", 7));
    }

    #[test]
    fn account_chooser_settling_is_bounded_and_duplicate_ack_cannot_extend_its_budget() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(ledger.claim("account", "nonceA123", true, 7));
        assert!(ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        for _ in 0..MAXIMUM_ACCOUNT_SETTLING_POLLS {
            assert!(ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceA123", 7));
            assert!(ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        }
        assert!(!ledger.claim_account_settling("manual", "ACCOUNT_CHOOSER", "nonceA123", 7));
        assert_eq!(
            ledger.account_settling_polls,
            MAXIMUM_ACCOUNT_SETTLING_POLLS
        );
        assert!(!ledger.claim("account", "nonceA123", true, 7));
    }

    #[test]
    fn account_selection_ack_allows_one_same_document_password_without_username_ack() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(!ledger.claim("account", "nonceA123", false, 7));
        assert!(ledger.claim("account", "nonceA123", true, 7));
        assert!(!ledger.claim("account", "nonceA123", true, 7));
        assert!(!ledger.claim("password", "nonceA123", true, 7));
        assert!(ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        assert!(
            ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7),
            "ACK replay is idempotent"
        );
        assert!(ledger.username_submitted_document.is_none());
        assert!(!ledger.claim("password", "nonceA123", false, 7));
        assert!(ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.claim("username", "nonceA123", false, 7));
        assert!(!ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        assert!(ledger.submitted("nonceA123", "PASSWORD_SUBMITTED", 7));
        assert!(ledger.submitted("nonceA123", "PASSWORD_SUBMITTED", 7));
        assert!(!ledger.claim("password", "nonceA123", true, 7));
    }

    #[test]
    fn account_then_username_then_password_is_allowed_but_reverse_order_is_not() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(ledger.claim("account", "nonceA123", true, 7));
        assert!(ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        assert!(ledger.claim("username", "nonceA123", false, 7));
        assert!(!ledger.claim("account", "nonceA123", true, 7));
        assert!(ledger.submitted("nonceA123", "USERNAME_SUBMITTED", 7));
        assert!(ledger.submitted("nonceA123", "USERNAME_SUBMITTED", 7));
        assert!(ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.claim("username", "nonceA123", false, 7));
        assert!(!ledger.submitted("nonceA123", "USERNAME_SUBMITTED", 7));
        ledger.begin(8);
        assert!(ledger.claim("username", "nonceB456", false, 8));
        assert!(!ledger.claim("account", "nonceB456", true, 8));
    }

    #[test]
    fn account_claim_and_ack_reject_other_documents_revisions_and_retired_owners() {
        let url = tauri::Url::parse(&format!("{MS_ORIGIN}{}", MS_PATHS[0])).unwrap();
        let mut auth = AuthState::default();
        auth.ledger.begin(7);
        assert!(!auth.ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        assert!(auth.ledger.claim("account", "nonceA123", true, 7));
        assert!(!auth.ledger.submitted("nonceB456", "ACCOUNT_SELECTED", 7));
        assert!(!auth.ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 8));
        assert!(auth.ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        auth.document = Some(AuthDocument {
            nonce: "nonceB456".into(),
            url: url.clone(),
        });
        assert!(auth.document_for_report("nonceA123", &url, 7).is_none());
        assert!(auth.document_for_report("nonceB456", &url, 7).is_some());
        assert!(!auth.ledger.claim("account", "nonceB456", true, 7));
        assert!(!auth.ledger.claim("password", "nonceB456", true, 7));
        auth.ledger.stop();
        assert!(!auth.ledger.claim("password", "nonceA123", true, 7));
        assert!(!auth.ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        auth.ledger.begin(8);
        assert!(!auth.ledger.claim("account", "bad!nonce", true, 8));
        assert!(!auth.ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        assert!(auth.ledger.claim("account", "nonceC789", true, 8));
    }

    #[test]
    fn feature_off_keeps_snapshot_but_rejects_late_publication_after_reenable() {
        let state = QmState::default();
        state.publish(sample(), 0).unwrap();
        let original = serde_json::to_value(state.assessment_snapshot().unwrap()).unwrap();
        state.owner_active.store(true, Ordering::SeqCst);
        state.auth.lock().unwrap().ledger.begin(7);
        state.set_feature_enabled(false);
        assert!(!state.owner_active.load(Ordering::SeqCst));
        assert!(!state.auth.lock().unwrap().ledger.accepts(7));
        assert_eq!(
            serde_json::to_value(state.assessment_snapshot().unwrap()).unwrap(),
            original
        );
        assert!(state.publish(sample(), 0).is_err());
        let revision = state.revision.load(Ordering::SeqCst);
        assert!(state.publish(sample(), revision).is_err());
        state.set_feature_enabled(true);
        assert!(
            !state.owner_active.load(Ordering::SeqCst),
            "On alone never starts a connection"
        );
        assert!(state.publish(sample(), 0).is_err());
        assert_eq!(
            serde_json::to_value(state.assessment_snapshot().unwrap()).unwrap(),
            original
        );
    }

    #[test]
    fn revoke_retires_owner_and_quiet_timeout_requires_the_current_live_owner() {
        let state = QmState::default();
        state.publish(sample(), 0).unwrap();
        state.owner_active.store(true, Ordering::SeqCst);
        state.quiet_owner.store(true, Ordering::SeqCst);
        state.auth.lock().unwrap().ledger.begin(7);
        assert!(state.quiet_timeout_is_current(0));
        assert!(!state.quiet_timeout_is_current(1));
        state.quiet_owner.store(false, Ordering::SeqCst);
        assert!(!state.quiet_timeout_is_current(0));
        state.quiet_owner.store(true, Ordering::SeqCst);
        state.revoke();
        assert!(!state.owner_active.load(Ordering::SeqCst));
        assert!(!state.quiet_timeout_is_current(0));
        assert!(state.assessment_snapshot().is_none());
        assert!(!state.auth.lock().unwrap().ledger.accepts(7));
    }

    #[test]
    fn autofill_requires_a_same_document_username_ack_and_claims_each_stage_once() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(!ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.submitted("nonceA123", "USERNAME_SUBMITTED", 7));
        assert!(ledger.claim("username", "nonceA123", false, 7));
        assert!(!ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.submitted("nonceB456", "USERNAME_SUBMITTED", 7));
        assert!(!ledger.submitted("nonceA123", "USERNAME_SUBMITTED", 8));
        assert!(!ledger.submitted("nonceA123", "PASSWORD_SUBMITTED", 7));
        assert!(ledger.submitted("nonceA123", "USERNAME_SUBMITTED", 7));
        assert!(!ledger.claim("password", "nonceB456", true, 7));
        assert!(!ledger.claim("password", "nonceA123", false, 7));
        assert!(!ledger.claim("password", "nonceA123", true, 8));
        assert!(ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.submitted("nonceB456", "PASSWORD_SUBMITTED", 7));
        assert!(ledger.submitted("nonceA123", "PASSWORD_SUBMITTED", 7));
    }

    #[test]
    fn navigation_retires_the_document_but_never_rearms_a_presentation_claim() {
        let url = tauri::Url::parse(&format!("{MS_ORIGIN}{}", MS_PATHS[0])).unwrap();
        let mut auth = AuthState::default();
        auth.ledger.begin(7);
        auth.document = Some(AuthDocument {
            nonce: "nonceA123".into(),
            url: url.clone(),
        });
        assert!(auth.document_for_report("nonceA123", &url, 7).is_some());
        assert!(auth.ledger.claim("username", "nonceA123", false, 7));
        auth.document = None;
        assert!(auth.document_for_report("nonceA123", &url, 7).is_none());
        auth.document = Some(AuthDocument {
            nonce: "nonceB456".into(),
            url: url.clone(),
        });
        assert!(auth.document_for_report("nonceA123", &url, 7).is_none());
        assert!(auth.document_for_report("nonceB456", &url, 8).is_none());
        assert!(!auth.ledger.claim("username", "nonceB456", false, 7));
        assert!(!auth.ledger.claim("password", "nonceB456", true, 7));
        auth.ledger.stop();
        assert!(auth.document_for_report("nonceB456", &url, 7).is_none());
        auth.ledger.begin(8);
        assert!(!auth.ledger.submitted("nonceA123", "USERNAME_SUBMITTED", 7));
        assert!(!auth.ledger.claim("username", "bad!nonce", false, 8));
        assert!(auth.ledger.claim("username", "nonceC789", false, 8));
    }

    #[test]
    fn cancelling_autofill_does_not_delete_a_validated_snapshot() {
        let state = QmState::default();
        state.publish(sample(), 0).unwrap();
        state.auth.lock().unwrap().ledger.begin(0);
        state.stop_autofill();
        assert!(!state.auth.lock().unwrap().ledger.accepts(0));
        assert!(state.snapshot.lock().unwrap().is_some());
        assert_eq!(state.revision.load(Ordering::SeqCst), 0);
    }

    fn sample() -> Snapshot {
        serde_json::from_value(serde_json::json!({
            "schema_version":1,"source":"qmplus","fetched_at":"2026-10-03T00:00:00.000Z","ok":true,"partial":false,
            "courses":[{"id":"1","name":"设置","short_name":"Raw course","url":"https://qmplus.qmul.ac.uk/course/view.php?id=1",
                "start_at":null,"end_at":null,"current_term_status":"unknown"}],
            "activities":[{"id":"2","course_id":"1","title":"Raw quiz","kind":"quiz","url":"https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=2",
                "due_at":null,"opens_at":"2026-03-29T01:30:00.000Z","closes_at":null,"cutoff_at":null,
                "time_limit_seconds":2700,"status":"unknown","detail_status":"restricted","raw_time_text":"Time limit: 45 minutes"}],
            "warnings":[]
        })).unwrap()
    }

    #[test]
    fn business_source_requires_exact_window_origin_and_readonly_page_path() {
        for path in BUSINESS_PATHS {
            assert!(valid_source(
                "qmplus",
                &tauri::Url::parse(&format!("{ORIGIN}{path}")).unwrap()
            ));
        }
        for url in [
            "https://qmplus.qmul.ac.uk/",
            "https://qmplus.qmul.ac.uk/login/index.php",
            "https://qmplus.qmul.ac.uk/calendar/view.php",
            "https://qmplus.qmul.ac.uk/lib/ajax/service.php",
            "https://login.microsoftonline.com/my/",
            "https://qmplus.qmul.ac.uk:444/my/",
            "https://name@qmplus.qmul.ac.uk/my/",
            "http://qmplus.qmul.ac.uk/my/",
            "https://qmplus.qmul.ac.uk.evil.test/my/",
        ] {
            assert!(
                !valid_source("qmplus", &tauri::Url::parse(url).unwrap()),
                "{url}"
            );
        }
        assert!(!valid_source(
            "main",
            &tauri::Url::parse(&format!("{ORIGIN}/my/")).unwrap()
        ));
    }

    #[test]
    fn utc_dates_raw_names_nullable_deadlines_and_unknown_terms_roundtrip_without_inference() {
        let snapshot = sample();
        snapshot.validate().unwrap();
        let decoded: Snapshot =
            serde_json::from_slice(&serde_json::to_vec(&snapshot).unwrap()).unwrap();
        assert_eq!(decoded.courses[0].name, "设置");
        assert_eq!(decoded.courses[0].current_term_status, "unknown");
        assert!(decoded.activities[0].due_at.is_none());
        assert_eq!(
            decoded.activities[0].opens_at.as_deref(),
            Some("2026-03-29T01:30:00.000Z")
        );
        assert_eq!(decoded.activities[0].time_limit_seconds, Some(2700));
        for date in [
            "2026-10-03T00:00:00+00:00",
            "2026-10-03T01:00:00+01:00",
            "2026-02-30T00:00:00Z",
            "2026-10-03 00:00:00",
        ] {
            let mut invalid = sample();
            invalid.fetched_at = date.into();
            assert!(invalid.validate().is_err(), "{date}");
            invalid = sample();
            invalid.activities[0].due_at = Some(date.into());
            assert!(invalid.validate().is_err(), "{date}");
        }
    }

    #[test]
    fn duplicate_ids_zero_ids_wrong_methods_and_mismatched_link_ids_are_rejected() {
        let mut snapshot = sample();
        snapshot.courses.push(snapshot.courses[0].clone());
        assert!(snapshot.validate().is_err());
        snapshot = sample();
        snapshot.activities.push(snapshot.activities[0].clone());
        assert!(snapshot.validate().is_err());
        snapshot = sample();
        let mut duplicate = snapshot.activities[0].clone();
        duplicate.kind = "assignment".into();
        duplicate.url = format!("{ORIGIN}/mod/assign/view.php?id=2");
        snapshot.activities.push(duplicate);
        assert!(snapshot.validate().is_err());
        for id in ["0", "01", "12345678901234567", "x"] {
            let mut invalid = sample();
            invalid.courses[0].id = id.into();
            assert!(invalid.validate().is_err());
        }
        for url in [
            "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2",
            "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=3",
            "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=0",
            "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=%32",
            "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=02",
            "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=2&sesskey=x",
            "https://qmplus.qmul.ac.uk/mod/quiz/attempt.php?id=2",
        ] {
            let mut invalid = sample();
            invalid.activities[0].url = url.into();
            assert!(invalid.validate().is_err(), "{url}");
        }
        snapshot = sample();
        snapshot.activities[0].course_id = "9".into();
        assert!(snapshot.validate().is_err());
    }

    #[test]
    fn utf16_field_limits_codes_and_total_utf8_budget_are_enforced() {
        let mut snapshot = sample();
        snapshot.courses[0].name = "😀".repeat(256);
        snapshot.validate().unwrap();
        snapshot.courses[0].name.push('a');
        assert!(snapshot.validate().is_err());
        snapshot = sample();
        snapshot.activities[0].raw_time_text = "x".repeat(1001);
        assert!(snapshot.validate().is_err());
        snapshot = sample();
        snapshot.warnings = vec!["".into()];
        assert!(snapshot.validate().is_err());
        snapshot = sample();
        snapshot.error_code = Some("password=untrusted".into());
        assert!(snapshot.validate().is_err());
        snapshot = sample();
        snapshot.activities = (1..=500)
            .map(|index| {
                let mut activity = snapshot.activities[0].clone();
                activity.id = index.to_string();
                activity.url = format!("{ORIGIN}/mod/quiz/view.php?id={index}");
                activity.title = "t".repeat(512);
                activity.status = "s".repeat(1000);
                activity.raw_time_text = "r".repeat(1000);
                activity
            })
            .collect();
        assert!(snapshot.validate().is_err());
    }

    #[test]
    fn disconnected_late_publication_cannot_restore_or_replace_the_new_session() {
        use std::sync::{mpsc, Arc};
        let state = Arc::new(QmState::default());
        state.publish(sample(), 0).unwrap();
        let (ready, received) = mpsc::channel();
        let (release, wait) = mpsc::channel();
        let old_owner = state.clone();
        let old = std::thread::spawn(move || {
            let old_snapshot = sample();
            ready.send(()).unwrap();
            wait.recv_timeout(std::time::Duration::from_secs(5))
                .unwrap();
            old_owner.publish(old_snapshot, 0)
        });
        received
            .recv_timeout(std::time::Duration::from_secs(5))
            .unwrap();
        state.revoke();
        assert!(state.snapshot.lock().unwrap().is_none());
        let current = state.revision.load(Ordering::SeqCst);
        let mut new_snapshot = sample();
        new_snapshot.courses[0].name = "New session".into();
        state.publish(new_snapshot, current).unwrap();
        release.send(()).unwrap();
        assert!(old.join().unwrap().is_err());
        assert_eq!(
            state.snapshot.lock().unwrap().as_ref().unwrap().courses[0].name,
            "New session"
        );
    }

    #[test]
    fn restricted_is_not_partial_but_actual_partial_or_failure_retains_the_last_good_source() {
        let state = QmState::default();
        state.publish(sample(), 0).unwrap();
        let mut available = sample();
        available.courses[0].name = "New restricted course".into();
        state.publish(available, 0).unwrap();
        assert_eq!(
            state.snapshot.lock().unwrap().as_ref().unwrap().courses[0].name,
            "New restricted course"
        );
        let mut partial = sample();
        partial.partial = true;
        partial.activities.clear();
        partial.warnings.push("QM_DETAIL_PARTIAL".into());
        state.publish(partial, 0).unwrap();
        assert_eq!(
            state.snapshot.lock().unwrap().as_ref().unwrap().courses[0].name,
            "New restricted course"
        );
        assert!(state.snapshot.lock().unwrap().as_ref().unwrap().partial);
        let mut failed = sample();
        failed.ok = false;
        failed.error_code = Some("QM_LOGIN_REQUIRED".into());
        assert!(state.publish(failed, 0).is_err());
        assert_eq!(
            state.snapshot.lock().unwrap().as_ref().unwrap().courses[0].name,
            "New restricted course"
        );
    }
    #[test]
    fn administrative_assignments_are_not_assessments_but_undated_work_and_quizzes_are() {
        let mut item = sample().activities.remove(0);
        item.kind = "assignment".into();
        item.due_at = None;
        for title in [
            "COURSEWORK MARK REVIEW REQUEST",
            "  coursework\tmark\u{a0}review request  ",
            "ＣＯＵＲＳＥＷＯＲＫ　ＭＡＲＫ　ＲＥＶＩＥＷ　ＲＥＱＵＥＳＴ",
            "COURSEWORK-MARK/REVIEW:REQUEST",
            "COURSEWORK\u{2011}MARK\u{2212}REVIEW\u{2014}REQUEST FORM",
            "\u{feff}Coursework\u{85}Mark\u{202f}Review\u{205f}Request\u{feff}",
        ] {
            item.title = title.into();
            assert!(!item.is_assessment(), "{title}");
            let mut quiz = item.clone();
            quiz.kind = "quiz".into();
            assert!(quiz.is_assessment(), "{title}");
        }
        for title in [
            "Coursework 1",
            "Coursework mark review essay",
            "Peer review assignment",
            "COURSEWORK MARK REVIEW REQUEST analysis",
            "COURSEWORK MARK REVIEW REQUEST?",
            "(COURSEWORK MARK REVIEW REQUEST)",
            "COURSEWORK|MARK REVIEW REQUEST",
            "ℂOURSEWORK MARK REVIEW REQUEST",
        ] {
            item.title = title.into();
            assert!(item.is_assessment(), "{title}");
        }
    }

    #[test]
    fn administrative_items_are_filtered_after_validation_and_cannot_mask_invalid_dtos() {
        let mut incoming = sample();
        incoming.activities[0].kind = "assignment".into();
        incoming.activities[0].url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2".into();
        incoming.activities[0].title = "COURSEWORK MARK REVIEW REQUEST".into();
        let state = QmState::default();
        state.publish(incoming.clone(), 0).unwrap();
        assert!(state.assessment_snapshot().unwrap().activities.is_empty());
        let mut invalid = incoming.clone();
        invalid.activities[0].url = "https://other.test/mod/assign/view.php?id=2".into();
        assert!(state.publish(invalid, 0).is_err());
        let mut invalid = incoming.clone();
        invalid.activities[0].due_at = Some("not-a-date".into());
        assert!(state.publish(invalid, 0).is_err());
        incoming.activities.push(incoming.activities[0].clone());
        assert!(state.publish(incoming, 0).is_err());
    }

    #[test]
    fn retained_legacy_snapshot_drops_admin_forms_without_losing_undated_work_or_source_time() {
        let state = QmState::default();
        let mut old = sample();
        let old_time = old.fetched_at.clone();
        let mut genuine = old.activities[0].clone();
        genuine.kind = "assignment".into();
        genuine.title = "Coursework 1".into();
        genuine.due_at = None;
        genuine.url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=2".into();
        let mut admin = genuine.clone();
        admin.id = "3".into();
        admin.title = "COURSEWORK MARK REVIEW REQUEST".into();
        admin.url = "https://qmplus.qmul.ac.uk/mod/assign/view.php?id=3".into();
        old.activities = vec![genuine, admin];
        old.validate().unwrap();
        *state.snapshot.lock().unwrap() = Some(old);
        assert_eq!(state.assessment_snapshot().unwrap().activities.len(), 1);
        let mut partial = sample();
        partial.partial = true;
        partial.activities.clear();
        partial.fetched_at = "2026-10-04T00:00:00Z".into();
        state.publish(partial, 0).unwrap();
        let retained = state.assessment_snapshot().unwrap();
        assert_eq!(retained.fetched_at, old_time);
        assert_eq!(retained.activities.len(), 1);
        assert_eq!(retained.activities[0].title, "Coursework 1");
        assert!(retained.activities[0].due_at.is_none());
        assert_eq!(
            state
                .snapshot
                .lock()
                .unwrap()
                .as_ref()
                .unwrap()
                .activities
                .len(),
            1
        );
    }
    #[test]
    fn official_links_only() {
        assert!(valid_url(
            "https://qmplus.qmul.ac.uk/mod/quiz/view.php?id=1"
        ));
        for u in [
            "http://qmplus.qmul.ac.uk/course/view.php?id=1",
            "https://evil.test/course/view.php?id=1",
            "https://qmplus.qmul.ac.uk/mod/quiz/startattempt.php?id=1",
            "https://qmplus.qmul.ac.uk/course/view.php?id=1&sesskey=x",
        ] {
            assert!(!valid_url(u));
        }
    }
    #[test]
    fn login_automation_requires_exact_https_tenant_and_never_accepts_account_picker_other_hosts() {
        for path in MS_PATHS {
            assert!(trusted_auth_page(
                &tauri::Url::parse(&format!("{MS_ORIGIN}{path}")).unwrap()
            ));
        }
        assert!(!trusted_auth_page(
            &tauri::Url::parse(&format!("{ORIGIN}/login/index.php")).unwrap()
        ));
        for url in [
            "https://login.microsoftonline.com/common/login",
            "https://login.microsoftonline.com/other/saml2",
            "https://login.microsoftonline.com.evil.test/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "http://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "https://login.microsoftonline.com:444/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "https://name@login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "https://qmplus.qmul.ac.uk/auth/saml2/login.php",
        ] { assert!(!trusted_auth_page(&tauri::Url::parse(url).unwrap())); }
    }
    #[test]
    fn only_exact_official_guest_entries_and_authenticated_business_pages_are_eligible() {
        for suffix in ["/", "/?redirect=0", "/login/index.php"] {
            let url = tauri::Url::parse(&format!("{ORIGIN}{suffix}")).unwrap();
            assert!(guest_entry(&url));
            assert!(!page_allows_sync(&url, "authenticated"));
        }
        for url in [
            "https://qmplus.qmul.ac.uk/?redirect=1",
            "https://qmplus.qmul.ac.uk/?redirect=0&other=1",
            "https://qmplus.qmul.ac.uk/login/index.php?redirect=0",
            "https://qmplus.qmul.ac.uk/login/index.php#retry",
            "https://qmplus.qmul.ac.uk/course/view.php?id=1",
            "https://name@qmplus.qmul.ac.uk/",
            "https://qmplus.qmul.ac.uk:444/",
            "https://qmplus.qmul.ac.uk.evil.test/",
        ] { assert!(!guest_entry(&tauri::Url::parse(url).unwrap())); }
        let dashboard = tauri::Url::parse(&format!("{ORIGIN}/my/")).unwrap();
        assert!(page_allows_sync(&dashboard, "authenticated"));
        for kind in ["error", "guest", "unknown", "loading"] {
            assert!(!page_allows_sync(&dashboard, kind));
        }
    }
    #[test]
    fn guest_fallback_never_restarts_sso_after_identity_or_password_submission() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(ledger.can_begin_sso(7));
        assert!(!ledger.can_begin_sso(8));
        assert!(ledger.claim("account", "nonceA123", true, 7));
        assert!(!ledger.can_begin_sso(7));
        ledger.stop();
        assert!(!ledger.can_begin_sso(7));
        ledger.begin(8);
        assert!(ledger.can_begin_sso(8));
        assert!(ledger.claim("username", "nonceB456", false, 8));
        assert!(!ledger.can_begin_sso(8));
    }
    #[test]
    fn username_submission_payload_has_no_password_and_reports_reject_unknown_fields() {
        let payload = serde_json::to_string(&AuthFill {
            document: "syntheticnonce",
            stage: "username",
            account: "student@example.org",
            password: None,
        })
        .unwrap();
        assert!(!payload.contains("password"));
        assert!(serde_json::from_str::<AuthReport>(r#"{"v":1,"stage":"username","document":"nonceA123","accountMatch":false,"reason":"READY","cookie":"forbidden"}"#).is_err());
    }
    #[test]
    fn reject_unknown_private_fields() {
        assert!(serde_json::from_str::<Snapshot>(r#"{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-03T00:00:00Z","ok":true,"partial":false,"courses":[],"activities":[],"warnings":[],"cookie":"secret"}"#).is_err());
    }
}
