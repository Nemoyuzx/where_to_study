use block2::RcBlock;
use objc2_foundation::{NSArray, NSError, NSString, NSUUID};
use objc2_user_notifications::{
    UNAuthorizationOptions, UNAuthorizationStatus, UNMutableNotificationContent, UNNotification,
    UNNotificationRequest, UNNotificationSettings, UNUserNotificationCenter,
};
use std::{
    ptr::NonNull,
    sync::{
        atomic::{AtomicBool, Ordering},
        mpsc, Arc, Mutex,
    },
    time::{Duration, Instant},
};

const PREFIX: &str = "wts.daily-course.";
const CALLBACK_TIMEOUT: Duration = Duration::from_secs(8);
const CLEAR_RECHECK_DELAY: Duration = Duration::from_millis(50);
// This gate covers the native calls and their callbacks, not just bookkeeping.
static LAST: Mutex<Option<String>> = Mutex::new(None);

fn remove(identifiers: &[String]) {
    if identifiers.is_empty() {
        return;
    }
    let strings: Vec<_> = identifiers
        .iter()
        .map(|id| NSString::from_str(id))
        .collect();
    let references: Vec<_> = strings.iter().map(|id| id.as_ref()).collect();
    let identifiers = NSArray::from_slice(&references);
    let center = UNUserNotificationCenter::currentNotificationCenter();
    center.removePendingNotificationRequestsWithIdentifiers(&identifiers);
    center.removeDeliveredNotificationsWithIdentifiers(&identifiers);
}

fn owned_identifiers(identifiers: impl IntoIterator<Item = String>) -> Vec<String> {
    let mut owned: Vec<_> = identifiers
        .into_iter()
        .filter(|id| id.starts_with(PREFIX))
        .collect();
    owned.sort_unstable();
    owned.dedup();
    owned
}

fn remaining(deadline: Instant) -> Result<Duration, String> {
    deadline
        .checked_duration_since(Instant::now())
        .filter(|remaining| !remaining.is_zero())
        .ok_or_else(|| "系统课程通知清理超时，尚未确认全部移除。".to_string())
}

fn receive_snapshot(
    receiver: &mpsc::Receiver<Vec<String>>,
    deadline: Instant,
) -> Result<Vec<String>, String> {
    let mut identifiers = Vec::new();
    for _ in 0..2 {
        identifiers.extend(
            receiver
                .recv_timeout(remaining(deadline)?)
                .map_err(|_| "读取待处理或已送达课程通知超时，清理未完成。".to_string())?,
        );
    }
    Ok(owned_identifiers(identifiers))
}

fn snapshot(timeout: Duration) -> Result<Vec<String>, String> {
    let deadline = Instant::now() + timeout;
    let center = UNUserNotificationCenter::currentNotificationCenter();
    let (sender, receiver) = mpsc::channel();
    let pending_sender = sender.clone();
    let pending = RcBlock::new(move |requests: NonNull<NSArray<UNNotificationRequest>>| {
        // Apple guarantees callback arguments remain valid for the callback.
        let identifiers = unsafe { requests.as_ref() }
            .iter()
            .map(|request| request.identifier().to_string())
            .collect();
        let _ = pending_sender.send(identifiers);
    });
    let delivered = RcBlock::new(move |notifications: NonNull<NSArray<UNNotification>>| {
        let identifiers = unsafe { notifications.as_ref() }
            .iter()
            .map(|notification| notification.request().identifier().to_string())
            .collect();
        let _ = sender.send(identifiers);
    });
    center.getPendingNotificationRequestsWithCompletionHandler(&pending);
    center.getDeliveredNotificationsWithCompletionHandler(&delivered);
    // Late enumeration callbacks only send IDs into this request's channel.
    // They never delete notifications after the gate has been released.
    receive_snapshot(&receiver, deadline)
}

fn clear_until_absent(
    known_identifier: Option<&str>,
    timeout: Duration,
    mut snapshot: impl FnMut(Duration) -> Result<Vec<String>, String>,
    mut remove: impl FnMut(&[String]),
) -> Result<(), String> {
    let deadline = Instant::now() + timeout;
    let mut identifiers = snapshot(remaining(deadline)?)?;
    identifiers.extend(known_identifier.map(str::to_owned));
    let mut identifiers = owned_identifiers(identifiers);
    while !identifiers.is_empty() {
        remove(&identifiers);
        identifiers = owned_identifiers(snapshot(remaining(deadline)?)?);
        if !identifiers.is_empty() {
            // Removal has no completion callback. Verify the system snapshot,
            // with a bounded pause if the removal has not become visible yet.
            std::thread::sleep(CLEAR_RECHECK_DELAY.min(remaining(deadline)?));
        }
    }
    Ok(())
}

struct Submission {
    identifier: String,
    abandoned: AtomicBool,
}

impl Submission {
    fn complete(&self, remove: impl FnOnce(&str)) {
        if self.abandoned.load(Ordering::Acquire) {
            remove(&self.identifier);
        }
    }

    fn abandon(&self, remove: impl FnOnce(&str)) {
        self.abandoned.store(true, Ordering::Release);
        remove(&self.identifier);
    }
}

pub fn show(_: &str, title: &str, body: &str) -> Result<(), String> {
    let mut last = LAST
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let center = UNUserNotificationCenter::currentNotificationCenter();
    let (sender, receiver) = mpsc::channel();
    let settings = RcBlock::new(move |settings: NonNull<UNNotificationSettings>| {
        let status = unsafe { settings.as_ref() }.authorizationStatus();
        let _ = sender.send(
            status == UNAuthorizationStatus::Authorized
                || status == UNAuthorizationStatus::Provisional,
        );
    });
    center.getNotificationSettingsWithCompletionHandler(&settings);
    if !receiver
        .recv_timeout(CALLBACK_TIMEOUT)
        .map_err(|_| "读取系统通知权限超时。")?
    {
        return Err("系统通知未开启，请在设置中重新开启课程提醒并允许通知。".into());
    }
    // A UUID remains unique across relaunches and process-ID reuse. A late
    // callback can only remove its own request, never a newer daily summary.
    let identifier = format!("{PREFIX}{}", NSUUID::UUID().UUIDString());
    let content = UNMutableNotificationContent::new();
    content.setTitle(&NSString::from_str(title));
    content.setBody(&NSString::from_str(body));
    content.setThreadIdentifier(&NSString::from_str("daily-courses"));
    let request = UNNotificationRequest::requestWithIdentifier_content_trigger(
        &NSString::from_str(&identifier),
        &content,
        None,
    );
    let (sender, receiver) = mpsc::channel();
    let submission = Arc::new(Submission {
        identifier: identifier.clone(),
        abandoned: AtomicBool::new(false),
    });
    let callback_submission = submission.clone();
    let block = RcBlock::new(move |error: *mut NSError| {
        let result = if error.is_null() {
            Ok(())
        } else {
            Err(unsafe { &*error }.localizedDescription().to_string())
        };
        callback_submission.complete(|id| remove(&[id.to_owned()]));
        let _ = sender.send(result);
    });
    center.addNotificationRequest_withCompletionHandler(&request, Some(&block));
    match receiver.recv_timeout(CALLBACK_TIMEOUT) {
        Ok(result) => result?,
        Err(_) => {
            submission.abandon(|id| remove(&[id.to_owned()]));
            return Err("发送系统通知超时，已请求撤销该通知。".into());
        }
    }
    if let Some(previous) = last.replace(identifier) {
        remove(&[previous]);
    }
    Ok(())
}

pub fn clear(_: &str) -> Result<(), String> {
    let mut last = LAST
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    clear_until_absent(last.as_deref(), CALLBACK_TIMEOUT, snapshot, remove)?;
    // Keep the known identifier when enumeration or confirmation fails.
    *last = None;
    Ok(())
}

// Only called after the user explicitly enables and saves notifications.
pub fn request_permission() {
    let block = RcBlock::new(|_: objc2::runtime::Bool, _: *mut NSError| {});
    UNUserNotificationCenter::currentNotificationCenter()
        .requestAuthorizationWithOptions_completionHandler(
            UNAuthorizationOptions::Alert | UNAuthorizationOptions::Sound,
            &block,
        );
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;

    #[test]
    fn clear_finds_previous_process_notifications_without_touching_other_features() {
        let current = RefCell::new(vec![
            "wts.daily-course.123.4".to_owned(),
            "wts.daily-course.old-uuid".to_owned(),
            "different-feature".to_owned(),
            "wts.daily-course-without-prefix-dot".to_owned(),
        ]);
        let removed = RefCell::new(Vec::new());
        clear_until_absent(
            None,
            Duration::from_secs(1),
            |_| Ok(current.borrow().clone()),
            |ids| {
                removed.borrow_mut().extend_from_slice(ids);
                current.borrow_mut().retain(|id| !ids.contains(id));
            },
        )
        .unwrap();
        assert_eq!(
            removed.into_inner(),
            ["wts.daily-course.123.4", "wts.daily-course.old-uuid"]
        );
        assert_eq!(current.into_inner().len(), 2);
    }

    #[test]
    fn clear_does_not_report_success_if_the_system_keeps_the_notification() {
        let calls = RefCell::new(0);
        let result = clear_until_absent(
            Some("wts.daily-course.known"),
            Duration::from_millis(5),
            |_| Ok(vec!["wts.daily-course.known".into()]),
            |_| *calls.borrow_mut() += 1,
        );
        assert!(result.is_err());
        assert!(
            calls.into_inner() <= 2,
            "cleanup must pause between retries"
        );
    }

    #[test]
    fn clear_propagates_snapshot_failure_before_removing_any_notifications() {
        let result = clear_until_absent(
            Some("wts.daily-course.known"),
            Duration::from_secs(1),
            |_| Err("enumeration failed".into()),
            |_| panic!("failed snapshot must not claim removal"),
        );
        assert_eq!(result, Err("enumeration failed".into()));
    }

    #[test]
    fn snapshot_requires_both_pending_and_delivered_callbacks() {
        let (sender, receiver) = mpsc::channel();
        sender
            .send(vec!["wts.daily-course.pending".into()])
            .unwrap();
        assert!(receive_snapshot(&receiver, Instant::now() + Duration::from_millis(2)).is_err());
        drop(receiver);
        assert!(sender.send(vec!["wts.daily-course.later".into()]).is_err());
    }

    #[test]
    fn late_submission_cleanup_never_targets_a_newer_notification() {
        let old = Submission {
            identifier: "wts.daily-course.old".into(),
            abandoned: AtomicBool::new(false),
        };
        let removed = RefCell::new(Vec::new());
        old.abandon(|id| removed.borrow_mut().push(id.to_owned()));
        old.complete(|id| removed.borrow_mut().push(id.to_owned()));
        assert_eq!(
            removed.into_inner(),
            ["wts.daily-course.old", "wts.daily-course.old"]
        );
        let completed = Submission {
            identifier: "wts.daily-course.new".into(),
            abandoned: AtomicBool::new(false),
        };
        completed.complete(|_| panic!("active submission must not be cancelled"));
    }
}
