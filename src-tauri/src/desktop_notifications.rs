//! Platform delivery without a detached, unrevocable task inside a plugin.
//!
//! Call `show` while holding the account and reminder gates. It returns only
//! after the native delivery operation completes (or fails); `clear` closes
//! this feature's own notification, never another app's notifications.

#[cfg(any(target_os = "windows", target_os = "linux", test))]
fn escaped_notification_text(value: &str) -> String {
    value
        .chars()
        .filter(|c| !c.is_control() || matches!(c, '\n' | '\r' | '\t'))
        .fold(String::new(), |mut out, c| {
            match c {
                '&' => out.push_str("&amp;"),
                '<' => out.push_str("&lt;"),
                '>' => out.push_str("&gt;"),
                '"' => out.push_str("&quot;"),
                '\'' => out.push_str("&apos;"),
                _ => out.push(c),
            }
            out
        })
}

#[cfg(any(target_os = "windows", test))]
fn toast_xml(title: &str, body: &str) -> String {
    format!("<toast><visual><binding template=\"ToastGeneric\"><text>{}</text><text>{}</text></binding></visual></toast>", escaped_notification_text(title), escaped_notification_text(body))
}

#[cfg(target_os = "windows")]
mod platform {
    use std::sync::{Mutex, OnceLock};
    use windows::{
        core::HSTRING,
        Data::Xml::Dom::XmlDocument,
        Win32::System::WinRT::{
            RoInitialize, RoUninitialize, RO_INIT_MULTITHREADED, RO_INIT_SINGLETHREADED,
        },
        UI::Notifications::{NotificationSetting, ToastNotification, ToastNotificationManager},
    };

    const TAG: &str = "daily-courses";
    const GROUP: &str = "wts-course";
    static LAST: OnceLock<Mutex<Option<ToastNotification>>> = OnceLock::new();

    struct Apartment;
    impl Apartment {
        fn enter() -> Result<Self, String> {
            // Each caller may be a scheduler worker or an already-initialized UI thread.
            unsafe {
                if let Err(error) = RoInitialize(RO_INIT_MULTITHREADED) {
                    if error.code().0 == 0x80010106u32 as i32 {
                        // RPC_E_CHANGED_MODE
                        RoInitialize(RO_INIT_SINGLETHREADED).map_err(|e| e.to_string())?;
                    } else {
                        return Err(error.to_string());
                    }
                }
            }
            Ok(Self)
        }
    }
    impl Drop for Apartment {
        fn drop(&mut self) {
            unsafe {
                RoUninitialize();
            }
        }
    }

    pub fn show(app_id: &str, title: &str, body: &str) -> Result<(), String> {
        let _apartment = Apartment::enter()?;
        let notifier = ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(app_id))
            .map_err(|e| e.to_string())?;
        if notifier.Setting().map_err(|e| e.to_string())? != NotificationSetting::Enabled {
            return Err("系统通知已关闭，请在 Windows 设置中允许本应用通知。".into());
        }
        let document = XmlDocument::new().map_err(|e| e.to_string())?;
        document
            .LoadXml(&HSTRING::from(super::toast_xml(title, body)))
            .map_err(|e| e.to_string())?;
        let toast =
            ToastNotification::CreateToastNotification(&document).map_err(|e| e.to_string())?;
        toast
            .SetTag(&HSTRING::from(TAG))
            .map_err(|e| e.to_string())?;
        toast
            .SetGroup(&HSTRING::from(GROUP))
            .map_err(|e| e.to_string())?;
        let mut last = LAST
            .get_or_init(|| Mutex::new(None))
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(previous) = last.as_ref() {
            notifier.Hide(previous).map_err(|e| e.to_string())?;
        }
        // Unlike tauri-plugin-notification 2.3.3, this does not spawn a task.
        notifier.Show(&toast).map_err(|e| e.to_string())?;
        *last = Some(toast);
        Ok(())
    }

    pub fn clear(app_id: &str) -> Result<(), String> {
        let _apartment = Apartment::enter()?;
        let mut last = LAST
            .get_or_init(|| Mutex::new(None))
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut error = None;
        if let Some(previous) = last.as_ref() {
            let result =
                ToastNotificationManager::CreateToastNotifierWithId(&HSTRING::from(app_id))
                    .and_then(|notifier| notifier.Hide(previous));
            if let Err(e) = result {
                error = Some(e.to_string());
            }
        }
        // Stable tag/group also removes this feature's history after restart.
        let history_result = ToastNotificationManager::History().and_then(|history| {
            history.RemoveGroupedTagWithId(
                &HSTRING::from(TAG),
                &HSTRING::from(GROUP),
                &HSTRING::from(app_id),
            )
        });
        if let Err(e) = history_result {
            error = Some(e.to_string());
        }
        if let Some(error) = error {
            return Err(error);
        }
        *last = None;
        Ok(())
    }

    pub fn request_permission() {}
}

#[cfg(target_os = "linux")]
#[path = "desktop_notifications/linux.rs"]
mod platform;

#[cfg(target_os = "macos")]
#[path = "desktop_notifications/macos.rs"]
mod platform;

pub use platform::{clear, request_permission, show};

#[cfg(test)]
mod tests {
    #[test]
    fn toast_text_is_escaped_and_does_not_inject_actions_or_invalid_controls() {
        let xml = super::toast_xml("Math < & >", "\"\u{1}'</text><actions/>\nRoom 101");
        assert!(xml.contains("Math &lt; &amp; &gt;"));
        assert!(xml.contains("&quot;&apos;&lt;/text&gt;&lt;actions/&gt;\nRoom 101"));
        assert!(!xml.contains("\u{1}"));
        assert_eq!(xml.matches("<text>").count(), 2);
    }
}
