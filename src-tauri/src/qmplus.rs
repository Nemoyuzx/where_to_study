use serde::{Deserialize, Serialize};
use std::collections::BTreeSet;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Mutex,
};
use tauri::{Emitter, Manager};

pub const SCRIPT: &str = include_str!("../../contracts/qmplus/qmplus-sync.js");
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
    fn revoke(&self) {
        self.revision.fetch_add(1, Ordering::SeqCst);
        *self
            .snapshot
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = None;
    }

    fn publish(&self, snapshot: Snapshot, revision: u64) -> Result<(), String> {
        snapshot.validate()?;
        if !snapshot.ok {
            return Err("QMplus 需要重新登录或同步失败；上次数据保留。".into());
        }
        let mut data = self.snapshot.lock().map_err(|_| "QMplus 缓存不可用。")?;
        if revision != self.revision.load(Ordering::SeqCst) {
            return Err("QMplus 会话已失效。".into());
        }
        if snapshot.partial && data.is_some() {
            if let Some(previous) = data.as_mut() {
                previous.partial = true;
                previous.warnings = vec!["QM_LAST_GOOD_RETAINED".into()];
            }
        } else {
            *data = Some(snapshot);
        }
        Ok(())
    }
}

#[tauri::command]
pub fn load_qmplus(state: tauri::State<'_, QmState>) -> Option<Snapshot> {
    state.snapshot.lock().ok()?.clone()
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
    let u = window.url().map_err(|_| "QMplus 页面不可用。")?;
    if !valid_source(window.label(), &u)
        || revision != state.revision.load(Ordering::SeqCst)
        || payload.len() > MAXIMUM_SNAPSHOT_BYTES
    {
        return Err("QMplus 来源或会话已失效。".into());
    }
    let snapshot: Snapshot = serde_json::from_str(&payload).map_err(|_| "QMplus 快照格式无效。")?;
    // Recheck the current document after parsing, not just the navigation payload.
    let current = window.url().map_err(|_| "QMplus 页面不可用。")?;
    if !valid_source(window.label(), &current) {
        return Err("QMplus 来源或会话已失效。".into());
    }
    state.publish(snapshot, revision)?;
    let _ = app.emit("qmplus:changed", ());
    Ok(())
}
#[tauri::command]
pub fn connect_qmplus(
    app: tauri::AppHandle,
    state: tauri::State<'_, QmState>,
) -> Result<(), String> {
    if let Some(w) = app.get_webview_window("qmplus") {
        w.set_focus().map_err(|_| "无法打开 QMplus。")?;
        return Ok(());
    }
    let revision = state.revision.fetch_add(1, Ordering::SeqCst) + 1;
    let bridge = format!(
        r#"if({DOCUMENT_GUARD}){{
      const button=document.createElement('button');button.textContent='同步课程 / Sync courses';
      button.style='position:fixed;right:12px;top:12px;z-index:2147483647;padding:12px';
      button.onclick=async()=>{{button.disabled=true;try{{const result=await WTSQmSync();await window.__TAURI_INTERNALS__.invoke('accept_qmplus_snapshot',{{payload:JSON.stringify(result),revision:{revision}}});button.textContent='同步完成 / Synced';}}catch(e){{button.textContent='请重新登录或重试 / Retry';}}finally{{button.disabled=false;}}}};document.body.appendChild(button);
    }}"#
    );
    tauri::WebviewWindowBuilder::new(
        &app,
        "qmplus",
        tauri::WebviewUrl::External(
            tauri::Url::parse("https://qmplus.qmul.ac.uk/my/").map_err(|_| "QMplus 地址无效。")?,
        ),
    )
    .title("QMplus — 官方登录与课程同步")
    .incognito(true)
    .inner_size(1000.0, 760.0)
    .on_page_load(move |w, p| {
        if p.event() == tauri::webview::PageLoadEvent::Finished
            && valid_business_page(p.url())
            && w.url().ok().is_some_and(|url| valid_business_page(&url))
        {
            let _ = w.eval(format!("if({DOCUMENT_GUARD}){{{SCRIPT}}}"));
            let _ = w.eval(&bridge);
        }
    })
    .build()
    .map_err(|_| "无法创建 QMplus 官方登录窗口。")?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

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
    fn reject_unknown_private_fields() {
        assert!(serde_json::from_str::<Snapshot>(r#"{"schema_version":1,"source":"qmplus","fetched_at":"2026-10-03T00:00:00Z","ok":true,"partial":false,"courses":[],"activities":[],"warnings":[],"cookie":"secret"}"#).is_err());
    }
}
