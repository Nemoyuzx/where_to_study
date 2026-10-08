//! Fixed metadata only. This module is compiled solely by Linux Debug QA opt-in.
//! No document, identity, URL, nonce, error text, payload or credential is accepted.
use serde::Serialize;
use std::sync::{
    atomic::{AtomicU32, Ordering},
    Mutex,
};

pub(super) fn enabled() -> bool {
    option_env!("WTS_QA_CREDENTIAL_SERVICE")
        == Some("com.nemoyu.wheretostudy.qa.linux.de5e10b2c4a64155810262d7869ee74a")
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
#[repr(usize)]
pub(super) enum Milestone {
    AttemptStarted,
    BuildRequested,
    BuildReturned,
    NavigateAccepted,
    CommittedCallback,
    FinishedCallback,
    CallbackGuardRejected,
    FinishedUrlUnavailableOrMismatch,
    FinishedWindowMissing,
    LayoutReady,
    PageEvalRequested,
    AuthEvalRequested,
    AuthEvalDispatchError,
    AuthEvalCallbackReceived,
    AuthEvalReturned,
    AuthEvalSyncThrown,
    AuthEvalResultUnavailable,
    AuthObserverTransformUnavailable,
    AuthObserverReadRequested,
    AuthObserverReadCallbackReceived,
    AuthObserverReadDispatchError,
    AuthObserverUnavailable,
    AuthObserverInstallOk,
    AuthObserverInstallConflict,
    AuthObserverPollConflict,
    AuthObserverPollEntered,
    AuthObserverLocationMismatch,
    AuthObserverInspectEntered,
    AuthObserverInspectReturned,
    AuthObserverIpcRequested,
    AuthObserverIpcResolved,
    AuthObserverIpcRejected,
    AuthObserverCancelled,
    AuthReportReceived,
    AuthEnvelopeAccepted,
    PageLoading,
    PassiveTransit,
    SyncBeginReceived,
    SyncStarted,
    SnapshotReceived,
    SnapshotPublished,
    DeadlineArmed,
    DeadlineExpired,
}
const ALL: [Milestone; 43] = [
    Milestone::AttemptStarted,
    Milestone::BuildRequested,
    Milestone::BuildReturned,
    Milestone::NavigateAccepted,
    Milestone::CommittedCallback,
    Milestone::FinishedCallback,
    Milestone::CallbackGuardRejected,
    Milestone::FinishedUrlUnavailableOrMismatch,
    Milestone::FinishedWindowMissing,
    Milestone::LayoutReady,
    Milestone::PageEvalRequested,
    Milestone::AuthEvalRequested,
    Milestone::AuthEvalDispatchError,
    Milestone::AuthEvalCallbackReceived,
    Milestone::AuthEvalReturned,
    Milestone::AuthEvalSyncThrown,
    Milestone::AuthEvalResultUnavailable,
    Milestone::AuthObserverTransformUnavailable,
    Milestone::AuthObserverReadRequested,
    Milestone::AuthObserverReadCallbackReceived,
    Milestone::AuthObserverReadDispatchError,
    Milestone::AuthObserverUnavailable,
    Milestone::AuthObserverInstallOk,
    Milestone::AuthObserverInstallConflict,
    Milestone::AuthObserverPollConflict,
    Milestone::AuthObserverPollEntered,
    Milestone::AuthObserverLocationMismatch,
    Milestone::AuthObserverInspectEntered,
    Milestone::AuthObserverInspectReturned,
    Milestone::AuthObserverIpcRequested,
    Milestone::AuthObserverIpcResolved,
    Milestone::AuthObserverIpcRejected,
    Milestone::AuthObserverCancelled,
    Milestone::AuthReportReceived,
    Milestone::AuthEnvelopeAccepted,
    Milestone::PageLoading,
    Milestone::PassiveTransit,
    Milestone::SyncBeginReceived,
    Milestone::SyncStarted,
    Milestone::SnapshotReceived,
    Milestone::SnapshotPublished,
    Milestone::DeadlineArmed,
    Milestone::DeadlineExpired,
];

#[derive(Clone, Serialize)]
pub(super) struct Counter {
    milestone: Milestone,
    count: u32,
}
#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Snapshot {
    last: Option<Milestone>,
    last_progress: Option<Milestone>,
    counters: Vec<Counter>,
    dropped_marks: u32,
}
struct State {
    last: Option<Milestone>,
    last_progress: Option<Milestone>,
    counts: [u32; ALL.len()],
}
impl Default for State {
    fn default() -> Self {
        Self {
            last: None,
            last_progress: None,
            counts: [0; ALL.len()],
        }
    }
}
#[derive(Default)]
pub(super) struct Recorder {
    state: Mutex<State>,
    dropped: AtomicU32,
}
impl Recorder {
    pub(super) fn mark(&self, milestone: Milestone) {
        if enabled() {
            self.mark_enabled(milestone);
        }
    }
    fn mark_enabled(&self, milestone: Milestone) {
        // Diagnostics never wait on a lock held by the main read-only status query.
        if let Ok(mut state) = self.state.try_lock() {
            let count = &mut state.counts[milestone as usize];
            *count = count.saturating_add(1);
            state.last = Some(milestone);
            if !matches!(
                milestone,
                Milestone::DeadlineArmed | Milestone::DeadlineExpired
            ) {
                state.last_progress = Some(milestone);
            }
        } else {
            let _ = self
                .dropped
                .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |value| {
                    Some(value.saturating_add(1))
                });
        }
    }
    pub(super) fn snapshot(&self) -> Option<Snapshot> {
        enabled().then(|| self.snapshot_enabled()).flatten()
    }
    fn snapshot_enabled(&self) -> Option<Snapshot> {
        let state = self.state.try_lock().ok()?;
        Some(Snapshot {
            last: state.last,
            last_progress: state.last_progress,
            counters: ALL
                .iter()
                .copied()
                .map(|milestone| Counter {
                    milestone,
                    count: state.counts[milestone as usize],
                })
                .collect(),
            dropped_marks: self.dropped.load(Ordering::Relaxed),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fixed_catalog_is_dense_and_deadline_preserves_last_progress() {
        for (index, milestone) in ALL.iter().enumerate() {
            assert_eq!(*milestone as usize, index);
        }
        let recorder = Recorder::default();
        recorder.mark_enabled(Milestone::FinishedCallback);
        recorder.mark_enabled(Milestone::DeadlineArmed);
        recorder.mark_enabled(Milestone::DeadlineExpired);
        let snapshot = recorder.snapshot_enabled().unwrap();
        assert_eq!(snapshot.last, Some(Milestone::DeadlineExpired));
        assert_eq!(snapshot.last_progress, Some(Milestone::FinishedCallback));
        assert_eq!(
            snapshot.counters[Milestone::FinishedCallback as usize].count,
            1
        );
    }
    #[test]
    fn counters_saturate_and_contention_never_waits() {
        let recorder = Recorder::default();
        recorder.state.lock().unwrap().counts[0] = u32::MAX;
        recorder.mark_enabled(Milestone::AttemptStarted);
        assert_eq!(
            recorder.snapshot_enabled().unwrap().counters[0].count,
            u32::MAX
        );
        let guard = recorder.state.lock().unwrap();
        recorder.mark_enabled(Milestone::FinishedCallback);
        assert!(recorder.snapshot_enabled().is_none());
        drop(guard);
        assert_eq!(recorder.snapshot_enabled().unwrap().dropped_marks, 1);
    }
    #[test]
    fn namespace_gate_never_records_or_exposes_when_disabled() {
        let recorder = Recorder::default();
        recorder.mark(Milestone::AttemptStarted);
        assert_eq!(recorder.snapshot().is_some(), enabled());
        assert_eq!(
            recorder.snapshot_enabled().unwrap().counters[0].count,
            u32::from(enabled())
        );
    }
    #[test]
    fn serialized_snapshot_contains_only_fixed_metadata() {
        let recorder = Recorder::default();
        recorder.mark_enabled(Milestone::FinishedCallback);
        let value = serde_json::to_value(recorder.snapshot_enabled().unwrap()).unwrap();
        let keys: std::collections::BTreeSet<_> = value
            .as_object()
            .unwrap()
            .keys()
            .map(String::as_str)
            .collect();
        assert_eq!(
            keys,
            ["counters", "droppedMarks", "last", "lastProgress"]
                .into_iter()
                .collect()
        );
        assert_eq!(value["last"], "FINISHED_CALLBACK");
        for counter in value["counters"].as_array().unwrap() {
            assert_eq!(counter.as_object().unwrap().len(), 2);
            assert!(counter["count"].as_u64().is_some());
            assert!(counter["milestone"]
                .as_str()
                .unwrap()
                .bytes()
                .all(|c| c.is_ascii_uppercase() || c == b'_'));
        }
    }
}
