//! Process-local, credential-scoped sessions. No tokens or credential hashes are
//! written to disk. Expiry is independent from the lifetime of cached results.
use crate::error::{ServiceError, ServiceResult};
use base64::Engine;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::future::Future;
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Mutex,
};
use std::time::{Duration, Instant};

struct Entry<T> {
    key: [u8; 32],
    id: u64,
    deadline: Instant,
    value: T,
}

/// Capture under the same account gate as the credentials, before any await.
/// A revoked request must never obtain a new epoch using its old credentials.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct SessionEpoch(u64);

pub struct SessionCache<T> {
    generation: AtomicU64,
    sequence: AtomicU64,
    entry: Mutex<Option<Entry<T>>>,
    login: tokio::sync::Mutex<()>,
}

impl<T: Clone> Default for SessionCache<T> {
    fn default() -> Self {
        Self::new()
    }
}

impl<T: Clone> SessionCache<T> {
    pub const fn new() -> Self {
        Self {
            generation: AtomicU64::new(0),
            sequence: AtomicU64::new(0),
            entry: Mutex::new(None),
            login: tokio::sync::Mutex::const_new(()),
        }
    }

    pub fn clear(&self) {
        let mut entry = self
            .entry
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.generation.fetch_add(1, Ordering::SeqCst);
        *entry = None;
    }

    pub fn epoch(&self) -> SessionEpoch {
        SessionEpoch(self.generation.load(Ordering::SeqCst))
    }

    fn invalidate(&self, id: u64) {
        let mut entry = self
            .entry
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if entry.as_ref().is_some_and(|e| e.id == id) {
            *entry = None;
        }
    }

    fn current(&self, generation: u64) -> ServiceResult<()> {
        if self.generation.load(Ordering::SeqCst) == generation {
            Ok(())
        } else {
            Err(ServiceError::new("账户已更改，请重新获取。"))
        }
    }

    async fn get<F, Fut>(
        &self,
        key: [u8; 32],
        generation: u64,
        login: &mut F,
    ) -> ServiceResult<(u64, T)>
    where
        F: FnMut() -> Fut,
        Fut: Future<Output = ServiceResult<(T, Duration)>>,
    {
        // Serialize only the login path, not authenticated HTTP requests.
        let _guard = self.login.lock().await;
        self.current(generation)?;
        {
            let entry = self
                .entry
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(entry) = entry
                .as_ref()
                .filter(|e| e.key == key && e.deadline > Instant::now())
            {
                return Ok((entry.id, entry.value.clone()));
            }
        }
        let (value, ttl) = login().await?;
        let mut entry = self
            .entry
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.current(generation)?;
        let id = self.sequence.fetch_add(1, Ordering::SeqCst) + 1;
        *entry = Some(Entry {
            key,
            id,
            deadline: Instant::now() + ttl,
            value: value.clone(),
        });
        Ok((id, value))
    }

    // Capture synchronously: creating a future before clear() and polling it
    // afterward cannot turn the old request into a new one. Account-managed
    // callers must additionally pass the epoch captured with their credentials.
    pub fn run<'a, R, L, LF, F, FF>(
        &'a self,
        account: &'a str,
        password: &'a str,
        login: L,
        request: F,
    ) -> impl Future<Output = ServiceResult<R>> + 'a
    where
        L: FnMut() -> LF + 'a,
        LF: Future<Output = ServiceResult<(T, Duration)>> + 'a,
        F: FnMut(T) -> FF + 'a,
        FF: Future<Output = ServiceResult<R>> + 'a,
        R: 'a,
    {
        self.run_at(self.epoch(), account, password, login, request)
    }

    pub async fn run_at<R, L, LF, F, FF>(
        &self,
        epoch: SessionEpoch,
        account: &str,
        password: &str,
        mut login: L,
        mut request: F,
    ) -> ServiceResult<R>
    where
        L: FnMut() -> LF,
        LF: Future<Output = ServiceResult<(T, Duration)>>,
        F: FnMut(T) -> FF,
        FF: Future<Output = ServiceResult<R>>,
    {
        let generation = epoch.0;
        self.current(generation)?;
        let mut hash = Sha256::new();
        hash.update((account.len() as u64).to_be_bytes());
        hash.update(account.as_bytes());
        hash.update((password.len() as u64).to_be_bytes());
        hash.update(password.as_bytes());
        let key: [u8; 32] = hash.finalize().into();
        let (id, value) = self.get(key, generation, &mut login).await?;
        self.current(generation)?;
        let result = request(value).await;
        self.current(generation)?;
        match result {
            Err(error) if error.authentication_expired => {
                // An older failed request must not evict a newer session.
                self.invalidate(id);
                let (retry_id, value) = self.get(key, generation, &mut login).await?;
                self.current(generation)?;
                let result = request(value).await;
                self.current(generation)?;
                if result.as_ref().is_err_and(|e| e.authentication_expired) {
                    self.invalidate(retry_id);
                }
                result
            }
            result => result,
        }
    }
}

/// Recognize explicit authentication responses, never arbitrary business errors,
/// permission-denied responses, network failures, or parse errors.
pub fn check_auth_payload(payload: &Value) -> ServiceResult<()> {
    let code = payload
        .get("code")
        .and_then(|v| v.as_i64().or_else(|| v.as_str()?.parse().ok()));
    if matches!(code, Some(403 | 423 | 500..=599)) {
        return Ok(());
    }
    let message = payload
        .get("msg")
        .or_else(|| payload.get("Msg"))
        .or_else(|| payload.get("message"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .to_lowercase();
    if code == Some(401)
        || [
            "token expired",
            "invalid token",
            "token失效",
            "token过期",
            "登录已过期",
            "登录超时",
            "请先登录",
            "未登录",
            "登录失效",
        ]
        .iter()
        .any(|needle| message.contains(needle))
    {
        Err(ServiceError::expired())
    } else {
        Ok(())
    }
}

pub fn session_ttl(seconds: Option<u64>) -> Duration {
    // With no expiry metadata use a conservative 20-minute session bound.
    // Data-cache refresh and UI navigation never themselves invalidate it.
    let seconds = seconds.unwrap_or(20 * 60).min(7 * 24 * 60 * 60);
    Duration::from_secs(seconds.saturating_sub(seconds.min(30)))
}

pub fn token_ttl(token: &str, declared: Option<u64>) -> Duration {
    // JWT expiry is only a cache lifetime hint, not a signature/auth decision.
    let jwt_seconds = token
        .split('.')
        .nth(1)
        .filter(|s| s.len() <= 32_768)
        .and_then(|s| {
            base64::engine::general_purpose::URL_SAFE_NO_PAD
                .decode(s.trim_end_matches('='))
                .ok()
        })
        .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
        .and_then(|v| v.get("exp").and_then(Value::as_i64))
        .map(|expiry| expiry.saturating_sub(chrono::Utc::now().timestamp()).max(0) as u64);
    session_ttl(match (declared, jwt_seconds) {
        (Some(a), Some(b)) => Some(a.min(b)),
        (a, b) => a.or(b),
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::AtomicUsize;
    #[tokio::test]
    async fn reuses_and_refreshes_only_auth_expiry() {
        let cache = SessionCache::new();
        let logins = AtomicUsize::new(0);
        for _ in 0..3 {
            assert_eq!(
                cache
                    .run(
                        "u",
                        "p",
                        || async {
                            Ok((
                                logins.fetch_add(1, Ordering::SeqCst),
                                Duration::from_secs(60),
                            ))
                        },
                        |token| async move { Ok(token) }
                    )
                    .await
                    .unwrap(),
                0
            );
        }
        assert_eq!(logins.load(Ordering::SeqCst), 1);
        let calls = AtomicUsize::new(0);
        cache
            .run(
                "u",
                "p",
                || async {
                    Ok((
                        logins.fetch_add(1, Ordering::SeqCst),
                        Duration::from_secs(60),
                    ))
                },
                |_| async {
                    if calls.fetch_add(1, Ordering::SeqCst) == 0 {
                        Err(ServiceError::expired())
                    } else {
                        Ok(())
                    }
                },
            )
            .await
            .unwrap();
        assert_eq!(logins.load(Ordering::SeqCst), 2);
        let result: ServiceResult<()> = cache
            .run(
                "u",
                "p",
                || async { panic!("must reuse") },
                |_| async { Err(ServiceError::new("network")) },
            )
            .await;
        assert!(result.is_err());
        cache
            .run(
                "u",
                "changed",
                || async {
                    Ok((
                        logins.fetch_add(1, Ordering::SeqCst),
                        Duration::from_secs(60),
                    ))
                },
                |_| async { Ok(()) },
            )
            .await
            .unwrap();
        assert_eq!(logins.load(Ordering::SeqCst), 3);
    }
    #[tokio::test]
    async fn concurrent_login_and_stale_clear() {
        let cache = SessionCache::new();
        let count = AtomicUsize::new(0);
        let fetch = || {
            cache.run(
                "u",
                "p",
                || async {
                    tokio::task::yield_now().await;
                    Ok((
                        count.fetch_add(1, Ordering::SeqCst),
                        Duration::from_secs(60),
                    ))
                },
                |v| async move { Ok(v) },
            )
        };
        let (a, b) = tokio::join!(fetch(), fetch());
        assert_eq!(a.unwrap(), b.unwrap());
        assert_eq!(count.load(Ordering::SeqCst), 1);
        cache.clear();
        let result = cache
            .run(
                "u",
                "p",
                || async {
                    cache.clear();
                    Ok((5, Duration::from_secs(60)))
                },
                |v| async move { Ok(v) },
            )
            .await;
        assert!(result.is_err());
    }
    #[test]
    fn expiry_is_not_generic_failure() {
        assert!(check_auth_payload(&serde_json::json!({"code":401})).is_err());
        assert!(check_auth_payload(&serde_json::json!({"code":403,"msg":"not permitted"})).is_ok());
        assert!(check_auth_payload(&serde_json::json!({"code":500})).is_ok());
        for code in [403, 423, 500, 503, 599] {
            for value in [serde_json::json!(code), serde_json::json!(code.to_string())] {
                assert!(check_auth_payload(
                    &serde_json::json!({"code":value,"msg":"token expired, 请先登录"})
                )
                .is_ok());
            }
        }
        assert_eq!(session_ttl(Some(0)), Duration::ZERO);
        assert_eq!(
            token_ttl("header.eyJleHAiOjF9.signature", None),
            Duration::ZERO
        );
        assert_eq!(token_ttl("opaque", Some(3600)), Duration::from_secs(3570));
        assert_eq!(token_ttl("opaque", None), Duration::from_secs(1170));
    }

    #[tokio::test]
    async fn retry_is_bounded_and_stale_failure_keeps_newer_session() {
        let cache = SessionCache::new();
        let count = AtomicUsize::new(0);
        let result: ServiceResult<()> = cache
            .run(
                "u",
                "p",
                || async {
                    Ok((
                        count.fetch_add(1, Ordering::SeqCst),
                        Duration::from_secs(60),
                    ))
                },
                |_| async { Err(ServiceError::expired()) },
            )
            .await;
        assert!(result.is_err());
        assert_eq!(count.load(Ordering::SeqCst), 2);
        assert!(cache.entry.lock().unwrap().is_none());
        cache
            .run(
                "u",
                "p",
                || async { Ok((3, Duration::from_secs(60))) },
                |v| async move { Ok(v) },
            )
            .await
            .unwrap();
        let current = cache.entry.lock().unwrap().as_ref().unwrap().id;
        cache.invalidate(current - 1);
        assert_eq!(cache.entry.lock().unwrap().as_ref().unwrap().id, current);
        let result = cache
            .run(
                "u",
                "p",
                || async { panic!("still valid") },
                |v| {
                    cache.clear();
                    async move { Ok(v) }
                },
            )
            .await;
        assert!(result.is_err());
    }

    #[tokio::test]
    async fn unpolled_future_cannot_adopt_epoch_after_clear() {
        let cache = SessionCache::new();
        let logins = AtomicUsize::new(0);
        let old = cache.run(
            "old-account",
            "fixture-password",
            || async {
                logins.fetch_add(1, Ordering::SeqCst);
                Ok(("old-token", Duration::from_secs(60)))
            },
            |token| async move { Ok(token) },
        );
        cache.clear();
        assert!(old.await.is_err());
        assert_eq!(logins.load(Ordering::SeqCst), 0);
        assert!(cache.entry.lock().unwrap().is_none());
    }

    #[tokio::test]
    async fn credential_snapshot_epoch_is_not_recaptured_at_request_creation() {
        let cache = SessionCache::new();
        let captured_with_credentials = cache.epoch();
        cache.clear();
        let result = cache
            .run_at(
                captured_with_credentials,
                "old",
                "fixture",
                || async { panic!("revoked credentials must never log in") },
                |token: usize| async move { Ok(token) },
            )
            .await;
        assert!(result.is_err());
        assert!(cache.entry.lock().unwrap().is_none());
        assert_eq!(
            cache
                .run_at(
                    cache.epoch(),
                    "new",
                    "fixture",
                    || async { Ok((7, Duration::from_secs(60))) },
                    |token| async move { Ok(token) }
                )
                .await
                .unwrap(),
            7
        );
    }

    #[tokio::test]
    async fn cleared_login_and_queued_request_cannot_repopulate_new_epoch() {
        let cache = SessionCache::new();
        let epoch = cache.epoch();
        let started = tokio::sync::Notify::new();
        let release = tokio::sync::Notify::new();
        let logins = AtomicUsize::new(0);
        let old = cache.run_at(
            epoch,
            "old",
            "fixture",
            || async {
                logins.fetch_add(1, Ordering::SeqCst);
                started.notify_one();
                release.notified().await;
                Ok((1, Duration::from_secs(60)))
            },
            |token| async move { Ok(token) },
        );
        let queued = cache.run_at(
            epoch,
            "old",
            "fixture",
            || async { panic!("queued revoked login must not run") },
            |token| async move { Ok(token) },
        );
        let replacement = async {
            started.notified().await;
            cache.clear();
            release.notify_one();
            cache
                .run_at(
                    cache.epoch(),
                    "new",
                    "fixture",
                    || async {
                        logins.fetch_add(1, Ordering::SeqCst);
                        Ok((2, Duration::from_secs(60)))
                    },
                    |token| async move { Ok(token) },
                )
                .await
        };
        let (old, queued, replacement) = tokio::join!(old, queued, replacement);
        assert!(old.is_err());
        assert!(queued.is_err());
        assert_eq!(replacement.unwrap(), 2);
        assert_eq!(logins.load(Ordering::SeqCst), 2);
        assert_eq!(cache.entry.lock().unwrap().as_ref().unwrap().value, 2);
    }

    #[tokio::test]
    async fn second_stage_expiry_after_clear_cannot_reauthenticate() {
        let cache = SessionCache::new();
        let logins = AtomicUsize::new(0);
        let result: ServiceResult<()> = cache
            .run_at(
                cache.epoch(),
                "old",
                "fixture",
                || async {
                    logins.fetch_add(1, Ordering::SeqCst);
                    Ok((1, Duration::from_secs(60)))
                },
                |_| async {
                    // Represents revocation between curriculum completion and exams.
                    cache.clear();
                    Err(ServiceError::expired())
                },
            )
            .await;
        assert!(result.is_err());
        assert_eq!(logins.load(Ordering::SeqCst), 1);
        assert!(cache.entry.lock().unwrap().is_none());
    }
}
