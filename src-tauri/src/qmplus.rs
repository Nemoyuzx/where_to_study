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
const MS_VERIFICATION_PATH: &str = "/common/deviceauthtls/reprocess";
const MAXIMUM_INITIAL_ACCOUNT_SETTLING_POLLS: u8 = 16;
const MAXIMUM_ACCOUNT_SETTLING_POLLS: u8 = 12;
const MAXIMUM_SUBMISSION_SETTLING_POLLS: u8 = 24;
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
    pub(crate) fn is_assessment(&self) -> bool {
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
    new_assignment_ids: Mutex<(String, Vec<String>)>,
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
    profile_id: Mutex<Option<String>>,
    background_owner: AtomicBool,
    challenge_presented: AtomicBool,
    manual_presented: AtomicBool,
    auth_suspended: AtomicBool,
    login_entry_started: Mutex<bool>,
    cache_warning: AtomicBool,
    sync_in_progress: AtomicBool,
    sync_deadline: Mutex<Option<tauri::async_runtime::JoinHandle<()>>>,
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
    initial_account_settling_polls: u8,
    account_settling_polls: u8,
    username_claimed_document: Option<String>,
    username_submitted_document: Option<String>,
    password_claimed_document: Option<String>,
    verified_password_document: Option<String>,
    verified_continue_document: Option<String>,
    password_submitted: bool,
    continue_attempted: bool,
    continue_claimed_document: Option<String>,
    continue_submitted: bool,
    submission_settling_polls: u8,
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
    fn identity_acknowledged(&self, credential_revision: u64) -> bool {
        self.accepts(credential_revision)
            && (self.username_submitted_document.is_some()
                || self.account_selected_document.is_some()
                || (self.password_submitted && self.verified_password_document.is_some()))
    }
    fn verify_current_identity(
        &mut self,
        stage: &str,
        nonce: &str,
        account_match: bool,
        credential_revision: u64,
    ) -> bool {
        if !self.accepts(credential_revision)
            || !valid_nonce(nonce)
            || !account_match
            || self.continue_attempted
        {
            return false;
        }
        match stage {
            "password" if !self.password_attempted => {
                self.verified_password_document = Some(nonce.to_owned());
                true
            }
            "continue" => {
                self.verified_continue_document = Some(nonce.to_owned());
                true
            }
            _ => false,
        }
    }
    fn can_begin_sso(&self, credential_revision: u64) -> bool {
        self.accepts(credential_revision)
            && !self.account_attempted
            && !self.username_attempted
            && !self.password_attempted
            && !self.continue_attempted
    }
    fn stop(&mut self) {
        self.active = false;
        self.account_claimed_document = None;
        self.account_selected_document = None;
        self.username_claimed_document = None;
        self.username_submitted_document = None;
        self.password_claimed_document = None;
        self.verified_password_document = None;
        self.verified_continue_document = None;
        self.continue_claimed_document = None;
    }
    fn claim_initial_account_settling(
        &mut self,
        stage: &str,
        reason: &str,
        nonce: &str,
        credential_revision: u64,
    ) -> bool {
        if !self.accepts(credential_revision)
            || !valid_nonce(nonce)
            || stage != "manual"
            || reason != "ACCOUNT_CHOOSER"
            || self.account_attempted
            || self.username_attempted
            || self.password_attempted
            || self.continue_attempted
            || self.initial_account_settling_polls >= MAXIMUM_INITIAL_ACCOUNT_SETTLING_POLLS
        {
            return false;
        }
        // The holder can render before its exact matching tile. This only
        // spends a read-only owner budget; it grants no identity or input claim.
        self.initial_account_settling_polls += 1;
        true
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
    fn is_awaiting_navigation(&self, nonce: &str, credential_revision: u64) -> bool {
        self.accepts(credential_revision)
            && ((self.password_submitted
                && self.password_claimed_document.as_deref() == Some(nonce))
                || (self.continue_submitted
                    && self.continue_claimed_document.as_deref() == Some(nonce)))
    }
    fn claim_submission_settling(&mut self, nonce: &str, credential_revision: u64) -> bool {
        if !self.is_awaiting_navigation(nonce, credential_revision)
            || self.submission_settling_polls >= MAXIMUM_SUBMISSION_SETTLING_POLLS
        {
            return false;
        }
        self.submission_settling_polls += 1;
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
                    && !self.continue_attempted
                    && account_match =>
            {
                self.account_attempted = true;
                self.account_claimed_document = Some(nonce.to_owned());
                true
            }
            "username"
                if !self.username_attempted
                    && !self.password_attempted
                    && !self.continue_attempted =>
            {
                self.username_attempted = true;
                self.username_claimed_document = Some(nonce.to_owned());
                true
            }
            "password"
                if !self.password_attempted
                    && !self.continue_attempted
                    && account_match
                    && (self.identity_acknowledged(credential_revision)
                        || self.verified_password_document.as_deref() == Some(nonce)) =>
            {
                self.password_attempted = true;
                self.password_claimed_document = Some(nonce.to_owned());
                true
            }
            "continue"
                if !self.continue_attempted
                    && account_match
                    && (self.identity_acknowledged(credential_revision)
                        || self.verified_continue_document.as_deref() == Some(nonce)) =>
            {
                self.continue_attempted = true;
                self.continue_claimed_document = Some(nonce.to_owned());
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
                self.password_submitted = true;
                true
            }
            "CONTINUE_SUBMITTED"
                if self.continue_attempted
                    && self.continue_claimed_document.as_deref() == Some(nonce) =>
            {
                self.continue_submitted = true;
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
    #[serde(
        rename = "identityAcknowledged",
        skip_serializing_if = "Option::is_none"
    )]
    identity_acknowledged: Option<bool>,
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
    trusted_microsoft_origin(url) && (MS_PATHS.contains(&url.path()) || url.path() == "/kmsi")
}
fn trusted_microsoft_origin(url: &tauri::Url) -> bool {
    url.username().is_empty()
        && url.password().is_none()
        && url.scheme() == "https"
        && (url.port().is_none() || url.port() == Some(443))
        && url.origin().ascii_serialization() == MS_ORIGIN
}
fn trusted_verification_page(url: &tauri::Url) -> bool {
    trusted_microsoft_origin(url) && url.path().eq_ignore_ascii_case(MS_VERIFICATION_PATH)
}
fn passive_microsoft_transit(url: &tauri::Url) -> bool {
    let device_transport = url.username().is_empty()
        && url.password().is_none()
        && url.scheme() == "https"
        && (url.port().is_none() || url.port() == Some(443))
        && url.origin().ascii_serialization() == "https://device.login.microsoftonline.com";
    (trusted_microsoft_origin(url) || device_transport)
        && !trusted_auth_page(url)
        && !trusted_verification_page(url)
}
fn verification_report_allowed(report: &AuthReport) -> bool {
    !report.account_match
        && match report.stage.as_str() {
            "challenge" => ["CAPTCHA_REQUIRED", "MFA_REQUIRED"].contains(&report.reason.as_str()),
            "loading" => report.reason == "LOADING",
            _ => false,
        }
}
fn official_qm_page(url: &tauri::Url) -> bool {
    url.origin().ascii_serialization() == ORIGIN
        && url.username().is_empty()
        && url.password().is_none()
}
fn guest_entry(url: &tauri::Url) -> bool {
    official_qm_page(url)
        && url.fragment().is_none()
        && ((["/", "/my", "/my/"].contains(&url.path())
            && matches!(url.query(), None | Some("redirect=0")))
            || (url.path() == "/login/index.php" && url.query().is_none()))
}
fn page_allows_sync(url: &tauri::Url, kind: &str) -> bool {
    kind == "authenticated" && valid_business_page(url)
}
const APPROVED_SSO: &str = "(()=>{const targets=new Set(Array.from(document.querySelectorAll('a[href]')).flatMap(a=>{try{const u=new URL(a.getAttribute('href'),location.href);return u.href==='https://qmplus.qmul.ac.uk/auth/saml2/login.php'&&!u.username&&!u.password&&!u.search&&!u.hash?[u.href]:[];}catch{return[];}}));return targets.size===1;})()";
const APPROVED_LOGIN_ENTRY: &str = "(()=>{const targets=new Set(Array.from(document.querySelectorAll('a[href]')).flatMap(a=>{try{const u=new URL(a.getAttribute('href'),location.href);return u.href==='https://qmplus.qmul.ac.uk/login/index.php'&&!u.username&&!u.password&&!u.search&&!u.hash?[u.href]:[];}catch{return[];}}));return targets.size===1;})()";
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
            self.retire_connection_preserving_snapshot();
        }
    }
    fn retire_connection_preserving_snapshot(&self) {
        self.owner_active.store(false, Ordering::SeqCst);
        self.quiet_owner.store(false, Ordering::SeqCst);
        self.challenge_presented.store(false, Ordering::SeqCst);
        self.manual_presented.store(false, Ordering::SeqCst);
        self.auth_suspended.store(false, Ordering::SeqCst);
        self.revision.fetch_add(1, Ordering::SeqCst);
        self.stop_autofill();
        *self
            .page_kind
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = "unknown";
        self.dashboard_started.store(false, Ordering::SeqCst);
        self.sync_in_progress.store(false, Ordering::SeqCst);
        if let Some(deadline) = self
            .sync_deadline
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
        {
            deadline.abort();
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
        self.cache_warning.store(false, Ordering::SeqCst);
        self.revision.fetch_add(1, Ordering::SeqCst);
        *self
            .new_assignment_ids
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Default::default();
        *self
            .snapshot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
        self.stop_autofill();
        self.sync_in_progress.store(false, Ordering::SeqCst);
        if let Some(deadline) = self
            .sync_deadline
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
        {
            deadline.abort();
        }
        *self
            .profile_id
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
        *self
            .sso_started
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = false;
    }

    fn quiet_timeout_is_current(&self, revision: u64) -> bool {
        !self.feature_blocked.load(Ordering::SeqCst)
            && self.owner_active.load(Ordering::SeqCst)
            && self.quiet_owner.load(Ordering::SeqCst)
            && !self.auth_suspended.load(Ordering::SeqCst)
            && !self.challenge_presented.load(Ordering::SeqCst)
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
        if window
            .url()
            .ok()
            .is_some_and(|url| trusted_auth_page(&url) || trusted_verification_page(&url))
        {
            let _ = window.eval(
                "if(window.top===window)window.dispatchEvent(new Event('wts-qm-auth-stop'));"
                    .to_string(),
            );
        }
    }
}

fn require_manual(app: &tauri::AppHandle, window: &tauri::WebviewWindow, reason: &'static str) {
    cancel_autofill(app);
    let state = app.state::<QmState>();
    state.sync_in_progress.store(false, Ordering::SeqCst);
    if let Some(deadline) = state
        .sync_deadline
        .lock()
        .ok()
        .and_then(|mut value| value.take())
    {
        deadline.abort();
    }
    record_connection_status(app, "manual", reason);
    state.challenge_presented.store(false, Ordering::SeqCst);
    if !state.manual_presented.load(Ordering::SeqCst) {
        let _ = window.hide();
    }
}

fn require_challenge(app: &tauri::AppHandle, window: &tauri::WebviewWindow, reason: &'static str) {
    let state = app.state::<QmState>();
    if let Some(deadline) = state
        .quiet_deadline
        .lock()
        .ok()
        .and_then(|mut value| value.take())
    {
        deadline.abort();
    }
    record_connection_status(app, "challenge", reason);
    state.challenge_presented.store(true, Ordering::SeqCst);
    if !app_is_backgrounded(app) && !window.is_visible().unwrap_or(false) {
        show_login(window);
    }
}

fn suspend_autofill(app: &tauri::AppHandle) {
    let state = app.state::<QmState>();
    state.auth_suspended.store(true, Ordering::SeqCst);
    if let Some(deadline) = state
        .quiet_deadline
        .lock()
        .ok()
        .and_then(|mut value| value.take())
    {
        deadline.abort();
    }
    record_connection_status(app, "checking", "APP_BACKGROUNDED");
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
                    suspend_autofill(&owner);
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
pub async fn load_qmplus(app: tauri::AppHandle) -> Option<serde_json::Value> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<QmState>();
        if state.feature_blocked.load(Ordering::SeqCst)
            || !crate::qmplus_feature::enabled(&app).unwrap_or(false)
        {
            return None;
        }
        let revision = state.revision.load(Ordering::SeqCst);
        let profile = crate::qmplus_profile::active_id(&app).ok().flatten()?;
        if state.assessment_snapshot().is_none() {
            let restored = crate::course_cache_store::load_qm(&app, &profile)
                .ok()
                .flatten()?;
            let mut snapshot = state.snapshot.lock().ok()?;
            if revision != state.revision.load(Ordering::SeqCst)
                || state.feature_blocked.load(Ordering::SeqCst)
                || !crate::qmplus_profile::current(&app, Some(&profile))
            {
                return None;
            }
            if snapshot.is_none() {
                *snapshot = Some(restored);
            }
            *state.profile_id.lock().ok()? = Some(profile.clone());
        }
        if state.feature_blocked.load(Ordering::SeqCst)
            || !crate::qmplus_profile::current(&app, Some(&profile))
        {
            return None;
        }
        let mut value = serde_json::to_value(state.assessment_snapshot()?).ok()?;
        value.as_object_mut()?.insert(
            "cache_warning".into(),
            serde_json::Value::Bool(state.cache_warning.load(Ordering::SeqCst)),
        );
        // A concurrent read of the preceding DTO must not consume IDs from
        // the newly published snapshot. Only its matching timestamp may take.
        let mut pending = state.new_assignment_ids.lock().ok()?;
        let fresh = if value.get("fetched_at").and_then(|v| v.as_str()) == Some(pending.0.as_str())
        {
            std::mem::take(&mut pending.1)
        } else {
            Vec::new()
        };
        value.as_object_mut()?.insert(
            "new_assignment_ids".into(),
            serde_json::to_value(fresh).ok()?,
        );
        Some(value)
    })
    .await
    .ok()
    .flatten()
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
    // snapshot or cookie store. Park a blank document to stop page timers.
    if !payload.enabled {
        state.set_feature_enabled(false);
        crate::qmplus_feature::disable_for_session();
        if let Some(window) = app.get_webview_window("qmplus") {
            let _ = window.eval("if(location.origin==='https://qmplus.qmul.ac.uk'&&typeof WTSQmCancel==='function')WTSQmCancel();");
            let _ = window.hide();
            if let Ok(blank) = tauri::Url::parse("about:blank") {
                let _ = window.navigate(blank);
            }
        }
    }
    crate::qmplus_feature::set(&app, payload.enabled)?;
    state.set_feature_enabled(payload.enabled);
    let settings = crate::settings_store::load_preferences(&app).map_err(|e| e.message)?;
    let _ = app.emit("qmplus:changed", ());
    Ok(settings)
}
#[tauri::command]
pub async fn disconnect_qmplus(app: tauri::AppHandle) -> Result<(), String> {
    let (sent, received) = tokio::sync::oneshot::channel();
    let (destroyed, destruction) = tokio::sync::oneshot::channel();
    let owner = app.clone();
    app.run_on_main_thread(move || {
        owner.state::<QmState>().revoke();
        let marked = crate::qmplus_profile::mark_for_removal(&owner).and_then(|_| crate::course_cache_store::clear_qm(&owner));
        if let Some(window) = owner.get_webview_window("qmplus") {
            let destroyed = Mutex::new(Some(destroyed));
            window.on_window_event(move |event| {
                if matches!(event, tauri::WindowEvent::Destroyed) {
                    if let Some(sent) = destroyed.lock().ok().and_then(|mut sent| sent.take()) { let _ = sent.send(()); }
                }
            });
            let _ = window.eval("if(typeof WTSQmCancel==='function')WTSQmCancel();window.dispatchEvent(new Event('wts-qm-auth-stop'));");
            // This is only an asynchronous clear request; the profile manager
            // verifies actual removal before releasing its durable barrier.
            let _ = window.clear_all_browsing_data();
            let _ = window.close();
        } else { let _ = destroyed.send(()); }
        let _ = owner.emit("qmplus:changed", ());
        let _ = sent.send(marked);
    }).map_err(|_| "QMplus 页面不可用。")?;
    received.await.map_err(|_| "QMplus 页面不可用。")??;
    tokio::time::timeout(std::time::Duration::from_secs(10), destruction)
        .await
        .map_err(|_| "QMplus 页面不可用。")?
        .map_err(|_| "QMplus 页面不可用。")?;
    crate::qmplus_profile::recover_pending(&app).await?;
    let _ = app.emit("qmplus:changed", ());
    Ok(())
}

pub(crate) fn pause_qmplus_connection(app: &tauri::AppHandle) -> Result<(), String> {
    let owner = app.clone();
    app.run_on_main_thread(move || {
        owner.state::<QmState>().retire_connection_preserving_snapshot();
        if let Some(window) = owner.get_webview_window("qmplus") {
            let _ = window.eval("if(typeof WTSQmCancel==='function')WTSQmCancel();window.dispatchEvent(new Event('wts-qm-auth-stop'));");
            let _ = window.hide();
            if let Ok(blank) = tauri::Url::parse("about:blank") { let _ = window.navigate(blank); }
        }
    }).map_err(|_| "QMplus 页面不可用。".into())
}
fn require_current_profile(app: &tauri::AppHandle, state: &QmState) -> Result<(), String> {
    let id = state.profile_id.lock().map_err(|_| "QMplus 页面不可用。")?;
    if crate::qmplus_profile::current(app, id.as_deref()) {
        Ok(())
    } else {
        Err("QMplus 会话已失效。".into())
    }
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
    require_current_profile(&app, &state)?;
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
        require_manual(&app, &window, "SYNC_FAILED");
        record_connection_status(&app, "failed", "SYNC_FAILED");
        return Err(error);
    }
    state.sync_in_progress.store(false, Ordering::SeqCst);
    if let Some(deadline) = state
        .sync_deadline
        .lock()
        .ok()
        .and_then(|mut value| value.take())
    {
        deadline.abort();
    }
    cancel_autofill(&app);
    let partial = state
        .snapshot
        .lock()
        .ok()
        .and_then(|data| data.as_ref().map(|s| s.partial))
        .unwrap_or(false);
    if let (Some(profile), Some(snapshot)) = (
        state.profile_id.lock().ok().and_then(|value| value.clone()),
        state.assessment_snapshot(),
    ) {
        let (stored, fresh) = crate::course_cache_store::save_qm(&app, &profile, &snapshot, || {
            revision == state.revision.load(Ordering::SeqCst)
                && !state.feature_blocked.load(Ordering::SeqCst)
        })
        .unwrap_or_default();
        if let Ok(mut pending) = state.new_assignment_ids.lock() {
            if revision == state.revision.load(Ordering::SeqCst)
                && !state.feature_blocked.load(Ordering::SeqCst)
            {
                if pending.0 != snapshot.fetched_at {
                    pending.1.clear();
                }
                pending.0 = snapshot.fetched_at.clone();
                pending.1.extend(fresh);
            }
        }
        state.cache_warning.store(!stored, Ordering::SeqCst);
    }
    record_connection_status(
        &app,
        if partial { "partial" } else { "synced" },
        "SYNC_VALIDATED",
    );
    let _ = app.emit("qmplus:changed", ());
    // Keep the owned browser context so another sync can reuse its web session.
    // The blank document stops dashboard timers without clearing cookies.
    if *state
        .close_after_sync
        .lock()
        .map_err(|_| "QMplus 页面不可用。")?
        && ["/my", "/my/"].contains(&current.path())
    {
        state.retire_connection_preserving_snapshot();
        let _ = window.hide();
        let _ =
            window.navigate(tauri::Url::parse("about:blank").map_err(|_| "QMplus 页面不可用。")?);
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
    require_current_profile(&app, &state)?;
    if window.label() != "qmplus"
        || revision != state.revision.load(Ordering::SeqCst)
        || !state.owner_active.load(Ordering::SeqCst)
        || report.v != 1
        || !valid_nonce(&report.document)
        || report.reason.len() > 32
        || ![
            "page",
            "loading",
            "account",
            "username",
            "password",
            "continue",
            "challenge",
            "manual",
            "unknown",
            "submitted",
        ]
        .contains(&report.stage.as_str())
    {
        return Err("QMplus 登录状态已失效。".into());
    }
    let url = window.url().map_err(|_| "QMplus 页面不可用。")?;
    let credential_revision = crate::qmplus_login::revision();
    // This exact common endpoint is a read-only verification surface. It must
    // never become a route to identity claims, saved secrets or submissions.
    if trusted_verification_page(&url) && !verification_report_allowed(&report) {
        return Err("QMplus 登录状态已失效。".into());
    }
    if report.stage == "submitted" {
        // A real navigation can retire its source document before the IPC ACK
        // arrives. Only a claim made by this live owner and credential revision
        // can acknowledge a submission; it never creates a new input budget.
        if !trusted_auth_page(&url) && !official_qm_page(&url) {
            return Err("QMplus 登录状态已失效。".into());
        }
        let accepted = state
            .auth
            .lock()
            .map_err(|_| "QMplus 页面不可用。")?
            .ledger
            .submitted(&report.document, &report.reason, credential_revision);
        if !accepted {
            // Late or forged ACKs cannot stop an already-running business sync.
            // A failed fill on the still-current document may pause its owner.
            let current_failure = ![
                "ACCOUNT_SELECTED",
                "USERNAME_SUBMITTED",
                "PASSWORD_SUBMITTED",
                "CONTINUE_SUBMITTED",
            ]
            .contains(&report.reason.as_str())
                && state.auth.lock().ok().is_some_and(|auth| {
                    auth.document_for_report(&report.document, &url, credential_revision)
                        .is_some()
                });
            if current_failure {
                require_manual(&app, &window, "MANUAL_REQUIRED");
            }
            return Err("QMplus 登录状态已失效。".into());
        }
        let reason = match report.reason.as_str() {
            "ACCOUNT_SELECTED" => "ACCOUNT_SELECTED",
            "USERNAME_SUBMITTED" => "USERNAME_SUBMITTED",
            "PASSWORD_SUBMITTED" => "PASSWORD_SUBMITTED",
            "CONTINUE_SUBMITTED" => "CONTINUE_SUBMITTED",
            _ => "MANUAL_REQUIRED",
        };
        record_connection_status(&app, "submitted", reason);
        return Ok(false);
    }
    if report.stage == "page" {
        let auth = state.auth.lock().map_err(|_| "QMplus 页面不可用。")?;
        if !official_qm_page(&url)
            || !state.owner_active.load(Ordering::SeqCst)
            || !auth
                .document
                .as_ref()
                .is_some_and(|doc| doc.nonce == report.document && doc.url == url)
        {
            return Err("QMplus 来源或会话已失效。".into());
        }
        drop(auth);
        let kind = match report.reason.as_str() {
            "authenticated" => "authenticated",
            "guest" | "guest_sso" | "guest_login" => "guest",
            "error" => "error",
            "loading" => "loading",
            _ => "unknown",
        };
        *state.page_kind.lock().map_err(|_| "QMplus 页面不可用。")? = kind;
        if kind == "error" {
            require_manual(&app, &window, "QM_ERROR_PAGE");
            return Ok(false);
        }
        if kind == "loading" {
            return Ok(false);
        }
        if kind == "guest"
            && guest_entry(&url)
            && ["guest_sso", "guest_login"].contains(&report.reason.as_str())
            && (crate::qmplus_login::authorized(&app).is_some()
                || !state.background_owner.load(Ordering::SeqCst))
            && state
                .auth
                .lock()
                .ok()
                .is_some_and(|a| a.ledger.can_begin_sso(crate::qmplus_login::revision()))
        {
            let saml = report.reason == "guest_sso";
            let mut started = if saml {
                &state.sso_started
            } else {
                &state.login_entry_started
            }
            .lock()
            .map_err(|_| "QMplus 页面不可用。")?;
            if !*started {
                *started = true;
                let current =
                    serde_json::to_string(url.as_str()).map_err(|_| "QMplus 页面不可用。")?;
                let proof = if saml {
                    APPROVED_SSO
                } else {
                    APPROVED_LOGIN_ENTRY
                };
                let target = if saml {
                    "https://qmplus.qmul.ac.uk/auth/saml2/login.php"
                } else {
                    "https://qmplus.qmul.ac.uk/login/index.php"
                };
                let _ = window.eval(format!("(()=>{{if(location.href!=={current})return;const kind={PAGE_SCRIPT};if(kind==='guest'&&{proof})location.assign('{target}');}})()"));
                return Ok(false);
            }
        }
        if kind == "authenticated"
            && ["/", "/login/index.php"].contains(&url.path())
            && guest_entry(&url)
        {
            if !state.dashboard_started.swap(true, Ordering::SeqCst) {
                window
                    .navigate(
                        tauri::Url::parse("https://qmplus.qmul.ac.uk/my/")
                            .map_err(|_| "QMplus 地址无效。")?,
                    )
                    .map_err(|_| "QMplus 页面不可用。")?;
            } else {
                require_manual(&app, &window, "UNSUPPORTED_PAGE");
            }
            return Ok(false);
        }
        if page_allows_sync(&url, kind) {
            let _ = window.eval(format!("if({DOCUMENT_GUARD}){{{SCRIPT}}}"));
            let _ = window.eval(sync_bridge(revision));
        } else if url.path() != "/auth/saml2/login.php" {
            require_manual(&app, &window, "UNSUPPORTED_PAGE");
        }
        return Ok(false);
    }
    let mut auth = state.auth.lock().map_err(|_| "QMplus 页面不可用。")?;
    let document = auth
        .document_for_report(&report.document, &url, credential_revision)
        .ok_or("QMplus 登录状态已失效。")?;
    if (!trusted_auth_page(&url) && !trusted_verification_page(&url))
        || (url.path() == "/kmsi"
            && ["account", "username", "password"].contains(&report.stage.as_str()))
    {
        return Err("QMplus 登录状态已失效。".into());
    }
    let nonce = document.nonce.clone();
    if report.stage == "challenge" {
        let reason = match report.reason.as_str() {
            "CAPTCHA_REQUIRED" => "CAPTCHA_REQUIRED",
            "MFA_REQUIRED" => "MFA_REQUIRED",
            _ => return Err("QMplus 登录状态已失效。".into()),
        };
        drop(auth);
        require_challenge(&app, &window, reason);
        return Ok(false);
    }
    if app_is_backgrounded(&app) {
        drop(auth);
        suspend_autofill(&app);
        return Ok(true);
    }
    let resumed = state.auth_suspended.swap(false, Ordering::SeqCst);
    let challenge_finished = state.challenge_presented.swap(false, Ordering::SeqCst);
    if challenge_finished && !state.manual_presented.load(Ordering::SeqCst) {
        let _ = window.hide();
    }
    if resumed || challenge_finished {
        drop(auth);
        arm_quiet_deadline(&app, &state, revision)?;
        auth = state.auth.lock().map_err(|_| "QMplus 页面不可用。")?;
        if auth
            .document_for_report(&nonce, &url, credential_revision)
            .is_none()
        {
            return Err("QMplus 登录状态已失效。".into());
        }
    }
    // Wait finitely for the first exact tile, or for the old chooser to settle
    // after its ACK. Neither path extends a deadline or renews an input budget.
    if auth.ledger.claim_initial_account_settling(
        &report.stage,
        &report.reason,
        &nonce,
        credential_revision,
    ) || auth.ledger.claim_account_settling(
        &report.stage,
        &report.reason,
        &nonce,
        credential_revision,
    ) {
        drop(auth);
        record_connection_status(&app, "checking", "ACCOUNT_CHOOSER");
        return Ok(true);
    }
    if auth
        .ledger
        .is_awaiting_navigation(&nonce, credential_revision)
        && report.stage == "manual"
        && [
            "ALREADY_ATTEMPTED",
            "FORM_UNTRUSTED",
            "KNOWN_FORM_ABSENT",
            "INTERFERENCE",
        ]
        .contains(&report.reason.as_str())
    {
        // The acknowledged submit can leave its old form visible while the
        // official page prepares MFA/KMSI. Observe finitely without new claims.
        let wait = auth
            .ledger
            .claim_submission_settling(&nonce, credential_revision);
        drop(auth);
        if wait {
            record_connection_status(&app, "checking", "SUBMISSION_SETTLING");
            return Ok(true);
        }
        require_manual(&app, &window, "POLL_EXHAUSTED");
        return Ok(false);
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
        "CONTINUE_SUBMITTED" => "CONTINUE_SUBMITTED",
        "USERNAME_NOT_SUBMITTED" => "USERNAME_NOT_SUBMITTED",
        "CURRENT_ACCOUNT_VERIFIED" => "CURRENT_ACCOUNT_VERIFIED",
        "POLL_EXHAUSTED" => "POLL_EXHAUSTED",
        _ => "MANUAL_REQUIRED",
    };
    let phase = match report.stage.as_str() {
        "account" => "username",
        "username" => "username",
        "password" => "password",
        "continue" => "checking",
        "submitted" => "submitted",
        "loading" => "checking",
        "manual" if report.reason == "ALREADY_ATTEMPTED" => "checking",
        _ => "manual",
    };
    record_connection_status(&app, phase, reason);
    if report.stage == "loading" {
        return Ok(false);
    }
    if report.reason == "ALREADY_ATTEMPTED" {
        return Ok(false);
    }
    let identity_acknowledged = auth.ledger.identity_acknowledged(credential_revision);
    let current_identity_proof = report.reason == "CURRENT_ACCOUNT_VERIFIED"
        && ["password", "continue"].contains(&report.stage.as_str())
        && report.account_match;
    if report.reason != "READY"
        && !current_identity_proof
        && !(["password", "continue"].contains(&report.stage.as_str())
            && report.reason == "USERNAME_NOT_SUBMITTED"
            && identity_acknowledged)
    {
        drop(auth);
        require_manual(&app, &window, reason);
        return Ok(false);
    }
    let Some(credentials) = crate::qmplus_login::authorized(&app) else {
        drop(auth);
        require_manual(&app, &window, "AUTHORIZATION_REVOKED");
        return Ok(false);
    };
    let current_identity_verified = current_identity_proof
        && auth.ledger.verify_current_identity(
            &report.stage,
            &nonce,
            report.account_match,
            credential_revision,
        );
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
        identity_acknowledged: ["password", "continue"]
            .contains(&report.stage.as_str())
            .then_some(identity_acknowledged || current_identity_verified),
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
        r#"(async()=>{{if(!({DOCUMENT_GUARD})||!['/my','/my/'].includes(location.pathname))return;
      const kind={PAGE_SCRIPT};if(kind!=='authenticated'||Object.prototype.hasOwnProperty.call(globalThis,'WTSQmAutoSyncStarted'))return;
      Object.defineProperty(globalThis,'WTSQmAutoSyncStarted',{{value:true,writable:false,configurable:false}});
      try{{const current={PAGE_SCRIPT};if(current!=='authenticated')return;
        await window.__TAURI_INTERNALS__.invoke('begin_qmplus_sync',{{revision:{revision}}});
        const result=await WTSQmSync();
        await window.__TAURI_INTERNALS__.invoke('accept_qmplus_snapshot',{{payload:JSON.stringify(result),revision:{revision}}});
      }}catch{{/* The native owner retains its previous snapshot and bounded sync watchdog. */}}
    }})()"#
    )
}
#[tauri::command]
pub fn begin_qmplus_sync(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    state: tauri::State<'_, QmState>,
    revision: u64,
) -> Result<(), String> {
    require_current_profile(&app, &state)?;
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
    state.sync_in_progress.store(true, Ordering::SeqCst);
    let handle = app.clone();
    let mut timer = state
        .sync_deadline
        .lock()
        .map_err(|_| "QMplus 页面不可用。")?;
    if let Some(previous) = timer.take() {
        previous.abort();
    }
    *timer = Some(tauri::async_runtime::spawn(async move {
        tokio::time::sleep(std::time::Duration::from_secs(130)).await;
        let owner = handle.clone();
        let _ = handle.run_on_main_thread(move || {
            let state = owner.state::<QmState>();
            if state.revision.load(Ordering::SeqCst) == revision
                && state.owner_active.load(Ordering::SeqCst)
                && state.sync_in_progress.load(Ordering::SeqCst)
                && !state.feature_blocked.load(Ordering::SeqCst)
            {
                if let Some(window) = owner.get_webview_window("qmplus") {
                    require_manual(&owner, &window, "SYNC_TIMEOUT");
                }
            }
        });
    }));
    drop(timer);
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
pub async fn connect_qmplus(
    app: tauri::AppHandle,
    payload: Option<ConnectRequest>,
) -> Result<(), String> {
    let request = payload.unwrap_or_default();
    crate::qmplus_profile::recover_pending(&app).await?;
    let (sent, received) = tokio::sync::oneshot::channel();
    let owner = app.clone();
    app.run_on_main_thread(move || {
        let state = owner.state::<QmState>();
        let _ = sent.send(connect_qmplus_on_main(
            owner.clone(),
            state,
            request.background,
            request.manual,
        ));
    })
    .map_err(|_| "QMplus 页面不可用。")?;
    received.await.map_err(|_| "QMplus 页面不可用。")?
}
#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConnectRequest {
    #[serde(default)]
    background: bool,
    #[serde(default)]
    manual: bool,
}
fn connect_qmplus_on_main(
    app: tauri::AppHandle,
    state: tauri::State<'_, QmState>,
    background: bool,
    manual: bool,
) -> Result<(), String> {
    if !crate::qmplus_feature::enabled(&app).unwrap_or(false) {
        state.set_feature_enabled(false);
        return Err("QMplus 尚未启用。".into());
    }
    let profile = crate::qmplus_profile::prepare(&app)?;
    if let Some(window) = app.get_webview_window("qmplus") {
        let bound = state.profile_id.lock().map_err(|_| "QMplus 页面不可用。")?;
        if bound.as_deref() != Some(profile.id()) {
            drop(bound);
            state.retire_connection_preserving_snapshot();
            let _ = window.close();
            return Err("QMplus 会话已失效。".into());
        }
    }
    *state.profile_id.lock().map_err(|_| "QMplus 页面不可用。")? = Some(profile.id().to_owned());
    state.set_feature_enabled(true);
    if manual {
        if let Some(window) = app
            .get_webview_window("qmplus")
            .filter(|_| state.owner_active.load(Ordering::SeqCst))
        {
            cancel_autofill(&app);
            state.background_owner.store(false, Ordering::SeqCst);
            state.manual_presented.store(true, Ordering::SeqCst);
            record_connection_status(&app, "manual", "USER_CONTINUE");
            show_login(&window);
            return Ok(());
        }
    }
    if app.get_webview_window("qmplus").is_some_and(|_| {
        state.owner_active.load(Ordering::SeqCst)
            && state
                .page_kind
                .lock()
                .ok()
                .is_none_or(|kind| *kind != "error")
    }) {
        if !background {
            state.background_owner.store(false, Ordering::SeqCst);
        }
        let active = state
            .auth
            .lock()
            .ok()
            .is_some_and(|auth| auth.ledger.active);
        if active || state.sync_in_progress.load(Ordering::SeqCst) {
            return Ok(());
        }
        // Connect/sync always retries quietly. Only the explicit manual action
        // may expose a non-challenge page.
        state.retire_connection_preserving_snapshot();
    }
    let revision = state.revision.fetch_add(1, Ordering::SeqCst) + 1;
    state.stop_autofill();
    state.sync_in_progress.store(false, Ordering::SeqCst);
    if let Some(deadline) = state
        .sync_deadline
        .lock()
        .ok()
        .and_then(|mut value| value.take())
    {
        deadline.abort();
    }
    state.dashboard_started.store(false, Ordering::SeqCst);
    state.background_owner.store(background, Ordering::SeqCst);
    *state
        .login_entry_started
        .lock()
        .map_err(|_| "QMplus 页面不可用。")? = false;
    *state.page_kind.lock().map_err(|_| "QMplus 页面不可用。")? = "unknown";
    *state
        .sso_started
        .lock()
        .map_err(|_| "QMplus 页面不可用。")? = false;
    let credential_revision = crate::qmplus_login::revision();
    let quiet = !manual;
    state.owner_active.store(true, Ordering::SeqCst);
    state.quiet_owner.store(quiet, Ordering::SeqCst);
    state.challenge_presented.store(false, Ordering::SeqCst);
    state.manual_presented.store(manual, Ordering::SeqCst);
    state.auth_suspended.store(false, Ordering::SeqCst);
    {
        state
            .auth
            .lock()
            .map_err(|_| "QMplus 页面不可用。")?
            .ledger
            .begin(credential_revision);
    }
    if manual {
        state.stop_autofill();
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
    let builder = tauri::WebviewWindowBuilder::new(
        &app,
        "qmplus",
        tauri::WebviewUrl::External(
            tauri::Url::parse("https://qmplus.qmul.ac.uk/my/").map_err(|_| "QMplus 地址无效。")?,
        ),
    )
    .title("QMplus — 官方登录与课程同步")
    .visible(!quiet)
    .inner_size(1000.0, 760.0)
    .on_page_load(move |w, p| {
        let handle = w.app_handle();
        let state = handle.state::<QmState>();
        if state.feature_blocked.load(Ordering::SeqCst) || !state.owner_active.load(Ordering::SeqCst) || state.window_revision.load(Ordering::SeqCst) != window_revision || require_current_profile(handle, &state).is_err() { return; }
        let revision = state.revision.load(Ordering::SeqCst);
        if p.event() == tauri::webview::PageLoadEvent::Started {
            *state.page_kind.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = "unknown";
            state.auth.lock().unwrap_or_else(std::sync::PoisonError::into_inner).document = None;
            if state.challenge_presented.swap(false, Ordering::SeqCst) && !state.manual_presented.load(Ordering::SeqCst) {
                if let Some(window) = handle.get_webview_window("qmplus") { let _ = window.hide(); }
                let _ = arm_quiet_deadline(handle, &state, revision);
            }
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
                let _ = window.eval(format!("(()=>{{if(location.href!=={encoded_url})return;const kind={PAGE_SCRIPT};const reason=kind==='guest'&&{APPROVED_SSO}?'guest_sso':kind==='guest'&&{APPROVED_LOGIN_ENTRY}?'guest_login':kind;window.__TAURI_INTERNALS__.invoke('accept_qmplus_auth',{{revision:{revision},report:{{v:1,stage:'page',document:{encoded_nonce},accountMatch:false,reason}}}}).catch(()=>{{}});}})()"));
                return;
            }
            let active = state.auth.lock().unwrap_or_else(std::sync::PoisonError::into_inner).ledger.accepts(crate::qmplus_login::revision());
            let verification_only = trusted_verification_page(&current);
            if active && passive_microsoft_transit(&current)
                && state.quiet_timeout_is_current(revision)
                && state.quiet_deadline.lock().ok().is_some_and(|deadline| deadline.is_some())
            {
                // Microsoft may traverse a transport document before its MFA
                // page. Preserve this owner's ledger only under the existing
                // deadline: no new nonce, script, vault read, action or renewal.
                record_connection_status(handle, "checking", "MICROSOFT_TRANSIT");
                return;
            }
            if (!trusted_auth_page(&current) && !verification_only) || !active { require_manual(handle,&window,"UNSUPPORTED_PAGE"); return; }
            // Verification inspection receives no saved identity or password,
            // and does not even read the secure record for this document.
            let credentials = if verification_only { None } else { crate::qmplus_login::authorized(handle) };
            let nonce = match crate::scoped_cache::new_account_scope() {
                Ok(v) => v.trim_start_matches("opaque-v1:").to_string(),
                Err(_) => { require_manual(handle,&window,"DOCUMENT_UNAVAILABLE"); return; }
            };
            state.auth.lock().unwrap_or_else(std::sync::PoisonError::into_inner).document = Some(AuthDocument {
                nonce: nonce.clone(), url: current.clone(),
            });
            let account = credentials.as_ref().map(|v| v.account.as_str()).unwrap_or("");
            let identity_acknowledged = !verification_only && state.auth.lock().unwrap_or_else(std::sync::PoisonError::into_inner).ledger.identity_acknowledged(crate::qmplus_login::revision());
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
                const report=WTSQmAuth.inspect({nonce},accountHint,{identity_acknowledged});if(report.stage==='challenge')attempts=0;if(report.stage==='manual'&&['FORM_UNTRUSTED','KNOWN_FORM_ABSENT'].includes(report.reason)&&settling++<16){{if(settling===8)send({{...report,stage:'loading'}});schedule(250);return;}}
                const accountWait=await send(report);if(cancelled)return;if(location.href!=={url}){{finish();return;}}
                if(accountWait===true&&report.stage==='manual'&&report.reason==='ACCOUNT_CHOOSER'){{attempts=0;schedule(250);return;}}
                if(accountWait===true){{attempts=0;schedule(750);return;}}
                if(report.stage==='manual'&&report.reason!=='ALREADY_ATTEMPTED'){{finish();return;}}schedule(report.stage==='challenge'?750:350);}};poll();}})()"#,
                nonce=serde_json::to_string(&nonce).unwrap_or_default(), url=serde_json::to_string(current.as_str()).unwrap_or_default(),
                account=serde_json::to_string(account).unwrap_or_default()));
            if w.eval(&*script).is_err() { require_manual(handle,&window,"SCRIPT_UNAVAILABLE"); }
        }
    });
    let window = profile
        .configure(builder)
        .build()
        .map_err(|_| "无法创建 QMplus 官方登录窗口。")?;
    let handle = app.clone();
    window.on_window_event(move |event| {
        let state = handle.state::<QmState>();
        if let tauri::WindowEvent::CloseRequested { api, .. } = event {
            if state.owner_active.load(Ordering::SeqCst)
                && state.window_revision.load(Ordering::SeqCst) == window_revision
            {
                // A user's close dismisses this task, not the browser profile.
                // Keep session-only engine state alive until the app exits.
                // Explicit disconnect revokes the owner before requesting a
                // real close, so profile erasure still crosses its barrier.
                api.prevent_close();
                cancel_autofill(&handle);
                state.retire_connection_preserving_snapshot();
                if let Some(window) = handle.get_webview_window("qmplus") {
                    if window.url().ok().is_some_and(|url| official_qm_page(&url)) {
                        let _ = window.eval("if(typeof WTSQmCancel==='function')WTSQmCancel();");
                    }
                    let _ = window.hide();
                    if let Ok(blank) = tauri::Url::parse("about:blank") {
                        let _ = window.navigate(blank);
                    }
                }
                record_connection_status(&handle, "cancelled", "WINDOW_CLOSED");
                return;
            }
        }
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
    // Give a main/official-window focus transfer time to settle, then pause
    // injection while retaining this owner's once-only submission budgets.
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
    fn parking_retires_connection_callbacks_without_deleting_the_verified_snapshot() {
        let state = QmState::default();
        state.publish(sample(), 0).unwrap();
        *state.profile_id.lock().unwrap() = Some("existing-browser-profile".into());
        state.window_revision.store(42, Ordering::SeqCst);
        state.owner_active.store(true, Ordering::SeqCst);
        state.quiet_owner.store(true, Ordering::SeqCst);
        state.auth.lock().unwrap().ledger.begin(7);
        *state.page_kind.lock().unwrap() = "authenticated";
        state.retire_connection_preserving_snapshot();
        assert!(!state.owner_active.load(Ordering::SeqCst));
        assert!(!state.quiet_owner.load(Ordering::SeqCst));
        assert!(!state.auth.lock().unwrap().ledger.accepts(7));
        assert_eq!(*state.page_kind.lock().unwrap(), "unknown");
        assert!(state.assessment_snapshot().is_some());
        assert_eq!(
            state.profile_id.lock().unwrap().as_deref(),
            Some("existing-browser-profile")
        );
        assert_eq!(state.window_revision.load(Ordering::SeqCst), 42);
        assert!(state.publish(sample(), 0).is_err());
    }

    #[test]
    fn initial_chooser_wait_is_readonly_and_document_changes_do_not_reset_its_budget() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        for index in 0..MAXIMUM_INITIAL_ACCOUNT_SETTLING_POLLS {
            let nonce = if index % 2 == 0 {
                "nonceA123"
            } else {
                "nonceB456"
            };
            assert!(ledger.claim_initial_account_settling("manual", "ACCOUNT_CHOOSER", nonce, 7));
        }
        assert!(!ledger.claim_initial_account_settling(
            "manual",
            "ACCOUNT_CHOOSER",
            "nonceC789",
            7
        ));
        assert_eq!(
            ledger.initial_account_settling_polls,
            MAXIMUM_INITIAL_ACCOUNT_SETTLING_POLLS
        );
        assert!(
            !ledger.account_attempted
                && !ledger.username_attempted
                && !ledger.password_attempted
                && !ledger.continue_attempted
        );
        assert!(!ledger.identity_acknowledged(7));
        assert!(!ledger.claim("account", "nonceC789", false, 7));
        assert!(ledger.claim("account", "nonceC789", true, 7));
        assert!(!ledger.claim("account", "nonceC789", true, 7));
        assert!(ledger.submitted("nonceC789", "ACCOUNT_SELECTED", 7));
        assert_eq!(
            ledger.initial_account_settling_polls,
            MAXIMUM_INITIAL_ACCOUNT_SETTLING_POLLS
        );
    }

    #[test]
    fn initial_chooser_wait_rejects_mismatch_other_stages_stale_revisions_and_prior_claims() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        for (stage, reason, nonce, revision) in [
            ("account", "ACCOUNT_CHOOSER", "nonceA123", 7),
            ("manual", "ACCOUNT_MISMATCH", "nonceA123", 7),
            ("manual", "INTERFERENCE", "nonceA123", 7),
            ("manual", "ACCOUNT_CHOOSER", "bad!nonce", 7),
            ("manual", "ACCOUNT_CHOOSER", "nonceA123", 8),
        ] {
            assert!(!ledger.claim_initial_account_settling(stage, reason, nonce, revision));
        }
        assert_eq!(ledger.initial_account_settling_polls, 0);
        assert!(ledger.claim("username", "nonceA123", false, 7));
        assert!(!ledger.claim_initial_account_settling(
            "manual",
            "ACCOUNT_CHOOSER",
            "nonceA123",
            7
        ));
        ledger.stop();
        assert!(!ledger.claim_initial_account_settling(
            "manual",
            "ACCOUNT_CHOOSER",
            "nonceA123",
            7
        ));
    }

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
    fn account_ack_is_source_bound_and_allows_a_matched_password_in_the_next_document() {
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
        assert!(auth.ledger.claim("password", "nonceB456", true, 7));
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
    fn autofill_requires_a_claimed_username_ack_and_claims_password_once_across_documents() {
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
        assert!(!ledger.claim("password", "nonceA123", false, 7));
        assert!(!ledger.claim("password", "nonceA123", true, 8));
        assert!(ledger.claim("password", "nonceB456", true, 7));
        assert!(!ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.submitted("nonceA123", "PASSWORD_SUBMITTED", 7));
        assert!(ledger.submitted("nonceB456", "PASSWORD_SUBMITTED", 7));
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

    #[test]
    fn continuation_needs_identity_ack_and_account_match_and_never_rearms_credentials() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(!ledger.claim("continue", "nonceA123", true, 7));
        assert!(ledger.claim("username", "nonceA123", false, 7));
        assert!(!ledger.identity_acknowledged(7));
        assert!(ledger.submitted("nonceA123", "USERNAME_SUBMITTED", 7));
        assert!(ledger.identity_acknowledged(7));
        assert!(!ledger.identity_acknowledged(8));
        assert!(!ledger.claim("continue", "nonceB456", false, 7));
        assert!(ledger.claim("continue", "nonceB456", true, 7));
        assert!(!ledger.claim("continue", "nonceC789", true, 7));
        assert!(!ledger.claim("password", "nonceC789", true, 7));
        assert!(!ledger.submitted("nonceA123", "CONTINUE_SUBMITTED", 7));
        assert!(ledger.submitted("nonceB456", "CONTINUE_SUBMITTED", 7));
        ledger.stop();
        assert!(!ledger.identity_acknowledged(7));
        assert!(!ledger.submitted("nonceB456", "CONTINUE_SUBMITTED", 7));
        ledger.begin(8);
        assert!(!ledger.identity_acknowledged(8));
        assert!(!ledger.claim("continue", "nonceC789", true, 8));
    }

    #[test]
    fn a_claimed_identity_ack_can_arrive_after_its_document_is_retired() {
        let mut auth = AuthState::default();
        auth.ledger.begin(7);
        assert!(auth.ledger.claim("account", "nonceA123", true, 7));
        auth.document = None;
        assert!(!auth.ledger.submitted("nonceB456", "ACCOUNT_SELECTED", 7));
        assert!(!auth.ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 8));
        assert!(auth.ledger.submitted("nonceA123", "ACCOUNT_SELECTED", 7));
        assert!(auth.ledger.claim("password", "nonceB456", true, 7));
        assert!(!auth.ledger.claim("password", "nonceC789", true, 7));
        auth.ledger.stop();
        assert!(!auth.ledger.submitted("nonceB456", "PASSWORD_SUBMITTED", 7));
    }

    #[test]
    fn old_form_wait_requires_its_real_ack_and_is_bounded_without_rearming_password() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(ledger.verify_current_identity("password", "nonceA123", true, 7));
        assert!(ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.claim_submission_settling("nonceA123", 7));
        assert!(ledger.submitted("nonceA123", "PASSWORD_SUBMITTED", 7));
        assert!(!ledger.claim_submission_settling("nonceB456", 7));
        assert!(!ledger.claim_submission_settling("nonceA123", 8));
        for _ in 0..MAXIMUM_SUBMISSION_SETTLING_POLLS {
            assert!(ledger.claim_submission_settling("nonceA123", 7));
            assert!(ledger.submitted("nonceA123", "PASSWORD_SUBMITTED", 7));
        }
        assert!(!ledger.claim_submission_settling("nonceA123", 7));
        assert!(!ledger.claim("password", "nonceA123", true, 7));
        ledger.stop();
        assert!(!ledger.is_awaiting_navigation("nonceA123", 7));
        ledger.begin(8);
        assert!(ledger.verify_current_identity("continue", "nonceC789", true, 8));
        assert!(ledger.claim("continue", "nonceC789", true, 8));
        assert!(!ledger.claim_submission_settling("nonceC789", 8));
        assert!(ledger.submitted("nonceC789", "CONTINUE_SUBMITTED", 8));
        assert!(ledger.claim_submission_settling("nonceC789", 8));
        assert!(!ledger.can_begin_sso(8));
        assert!(!ledger.claim("continue", "nonceC789", true, 8));
    }

    #[test]
    fn directly_verified_identity_is_stage_and_document_bound_until_a_real_password_ack() {
        let mut ledger = AuthLedger::default();
        ledger.begin(7);
        assert!(!ledger.verify_current_identity("password", "nonceA123", false, 7));
        assert!(!ledger.verify_current_identity("password", "nonceA123", true, 8));
        assert!(!ledger.verify_current_identity("username", "nonceA123", true, 7));
        assert!(ledger.verify_current_identity("password", "nonceA123", true, 7));
        assert!(!ledger.identity_acknowledged(7));
        assert!(!ledger.claim("password", "nonceB456", true, 7));
        assert!(!ledger.claim("continue", "nonceA123", true, 7));
        assert!(ledger.claim("password", "nonceA123", true, 7));
        assert!(!ledger.verify_current_identity("password", "nonceB456", true, 7));
        assert!(!ledger.submitted("nonceB456", "PASSWORD_SUBMITTED", 7));
        assert!(ledger.submitted("nonceA123", "PASSWORD_SUBMITTED", 7));
        assert!(ledger.identity_acknowledged(7));
        assert!(ledger.claim("continue", "nonceB456", true, 7));
        ledger.begin(8);
        assert!(ledger.verify_current_identity("continue", "nonceC789", true, 8));
        assert!(!ledger.claim("password", "nonceC789", true, 8));
        assert!(!ledger.claim("continue", "nonceB456", true, 8));
        assert!(ledger.claim("continue", "nonceC789", true, 8));
        assert!(!ledger.claim("continue", "nonceC789", true, 8));
    }

    #[test]
    fn background_suspension_keeps_identity_and_attempt_budgets_but_disarms_quiet_timeout() {
        let state = QmState::default();
        state.owner_active.store(true, Ordering::SeqCst);
        state.quiet_owner.store(true, Ordering::SeqCst);
        state.auth.lock().unwrap().ledger.begin(7);
        assert!(state
            .auth
            .lock()
            .unwrap()
            .ledger
            .claim("username", "nonceA123", false, 7));
        assert!(state
            .auth
            .lock()
            .unwrap()
            .ledger
            .submitted("nonceA123", "USERNAME_SUBMITTED", 7));
        state.auth_suspended.store(true, Ordering::SeqCst);
        assert!(!state.quiet_timeout_is_current(0));
        assert!(state.auth.lock().unwrap().ledger.identity_acknowledged(7));
        assert!(!state
            .auth
            .lock()
            .unwrap()
            .ledger
            .claim("username", "nonceB456", false, 7));
        state.auth_suspended.store(false, Ordering::SeqCst);
        assert!(state.quiet_timeout_is_current(0));
        assert!(state
            .auth
            .lock()
            .unwrap()
            .ledger
            .claim("password", "nonceB456", true, 7));
        state.challenge_presented.store(true, Ordering::SeqCst);
        assert!(!state.quiet_timeout_is_current(0));
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
        assert!(trusted_auth_page(
            &tauri::Url::parse(&format!("{MS_ORIGIN}/kmsi")).unwrap()
        ));
        for url in [
            "https://login.microsoftonline.com/common/login",
            "https://login.microsoftonline.com/other/saml2",
            "https://login.microsoftonline.com.evil.test/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "http://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "https://login.microsoftonline.com:444/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "https://name@login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "https://qmplus.qmul.ac.uk/auth/saml2/login.php",
            "https://login.microsoftonline.com/kmsi/",
            "https://login.microsoftonline.com/common/kmsi",
            "https://login.microsoftonline.com.evil.test/kmsi",
        ] { assert!(!trusted_auth_page(&tauri::Url::parse(url).unwrap())); }
    }
    #[test]
    fn device_auth_verification_is_an_exact_readonly_path_not_a_credential_surface() {
        for path in ["/common/DeviceAuthTls/reprocess", MS_VERIFICATION_PATH] {
            let url = tauri::Url::parse(&format!("{MS_ORIGIN}{path}?flow=synthetic")).unwrap();
            assert!(trusted_verification_page(&url));
            assert!(!trusted_auth_page(&url));
            assert!(!official_qm_page(&url));
            assert!(!valid_source("qmplus", &url));
        }
        for url in [
            "https://login.microsoftonline.com/common/DeviceAuthTls/reprocess/",
            "https://login.microsoftonline.com/common/DeviceAuthTls/reprocess/next",
            "https://login.microsoftonline.com/common/DeviceAuthTls/reprocess-other",
            "https://login.microsoftonline.com/common/DeviceAuthTls/%72eprocess",
            "https://login.microsoftonline.com/common/login",
            "https://login.microsoftonline.com/other/DeviceAuthTls/reprocess",
            "https://login.microsoftonline.com:444/common/DeviceAuthTls/reprocess",
            "https://user@login.microsoftonline.com/common/DeviceAuthTls/reprocess",
            "http://login.microsoftonline.com/common/DeviceAuthTls/reprocess",
            "https://login.microsoftonline.com.evil.test/common/DeviceAuthTls/reprocess",
            "https://qmplus.qmul.ac.uk/common/DeviceAuthTls/reprocess",
        ] {
            assert!(
                !trusted_verification_page(&tauri::Url::parse(url).unwrap()),
                "{url}"
            );
        }
    }
    #[test]
    fn microsoft_transit_classification_never_expands_automation_or_verification_paths() {
        let transit =
            tauri::Url::parse("https://login.microsoftonline.com/common/transport-fixture")
                .unwrap();
        assert!(passive_microsoft_transit(&transit));
        assert!(!trusted_auth_page(&transit));
        assert!(!trusted_verification_page(&transit));
        for url in [
            "https://login.microsoftonline.com/569df091-b013-40e3-86ee-bd9cb9e25814/login",
            "https://login.microsoftonline.com/kmsi",
            "https://login.microsoftonline.com/common/DeviceAuthTls/reprocess",
            "http://login.microsoftonline.com/common/transport-fixture",
            "https://login.microsoftonline.com:444/common/transport-fixture",
            "https://name@login.microsoftonline.com/common/transport-fixture",
            "https://login.microsoftonline.com.evil.test/common/transport-fixture",
            "https://qmplus.qmul.ac.uk/common/transport-fixture",
        ] {
            assert!(
                !passive_microsoft_transit(&tauri::Url::parse(url).unwrap()),
                "{url}"
            );
        }
    }
    #[test]
    fn device_login_host_is_passive_only_with_exact_https_origin() {
        for path in ["/", "/common/DeviceAuthTls/reprocess", MS_PATHS[1], "/kmsi"] {
            let url = tauri::Url::parse(&format!("https://device.login.microsoftonline.com{path}"))
                .unwrap();
            assert!(passive_microsoft_transit(&url));
            assert!(!trusted_auth_page(&url));
            assert!(!trusted_verification_page(&url));
        }
        for url in [
            "http://device.login.microsoftonline.com/",
            "https://device.login.microsoftonline.com:444/",
            "https://name@device.login.microsoftonline.com/",
            "https://device.login.microsoftonline.com.evil.test/",
            "https://evil-device.login.microsoftonline.com/",
        ] {
            assert!(
                !passive_microsoft_transit(&tauri::Url::parse(url).unwrap()),
                "{url}"
            );
        }
    }
    #[test]
    fn verification_metadata_rejects_identity_proofs_submissions_and_business_reports() {
        let report = |stage: &str, reason: &str, account_match: bool| AuthReport {
            v: 1,
            stage: stage.into(),
            document: "nonceA123".into(),
            account_match,
            reason: reason.into(),
        };
        assert!(verification_report_allowed(&report(
            "challenge",
            "MFA_REQUIRED",
            false
        )));
        assert!(verification_report_allowed(&report(
            "challenge",
            "CAPTCHA_REQUIRED",
            false
        )));
        assert!(verification_report_allowed(&report(
            "loading", "LOADING", false
        )));
        for (stage, reason) in [
            ("account", "READY"),
            ("username", "READY"),
            ("password", "READY"),
            ("continue", "READY"),
            ("password", "CURRENT_ACCOUNT_VERIFIED"),
            ("continue", "CURRENT_ACCOUNT_VERIFIED"),
            ("submitted", "ACCOUNT_SELECTED"),
            ("submitted", "USERNAME_SUBMITTED"),
            ("submitted", "PASSWORD_SUBMITTED"),
            ("submitted", "CONTINUE_SUBMITTED"),
            ("page", "authenticated"),
            ("challenge", "READY"),
            ("loading", "CURRENT_ACCOUNT_VERIFIED"),
        ] {
            assert!(
                !verification_report_allowed(&report(stage, reason, false)),
                "{stage}: {reason}"
            );
        }
        assert!(!verification_report_allowed(&report(
            "challenge",
            "MFA_REQUIRED",
            true
        )));
    }
    #[test]
    fn verification_capability_grants_only_auth_metadata_on_the_exact_verified_url() {
        let capability: serde_json::Value =
            serde_json::from_str(include_str!("../capabilities/qmplus-verification.json")).unwrap();
        assert_eq!(capability["windows"], serde_json::json!(["qmplus"]));
        assert_eq!(capability["local"], false);
        assert_eq!(
            capability["permissions"],
            serde_json::json!(["allow-accept-qmplus-auth"])
        );
        let urls = capability["remote"]["urls"].as_array().unwrap();
        assert_eq!(urls.len(), 2);
        for value in urls {
            let raw = value.as_str().unwrap();
            assert!(!raw.contains('*'));
            let url = tauri::Url::parse(raw).unwrap();
            assert!(trusted_verification_page(&url));
            assert!(!trusted_auth_page(&url));
        }
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
        ] {
            assert!(!guest_entry(&tauri::Url::parse(url).unwrap()));
        }
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
            identity_acknowledged: None,
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
