use std::{
    collections::HashMap,
    sync::{Mutex, OnceLock},
    time::Duration,
};
use zbus::{
    blocking::{connection::Builder, Connection, Proxy},
    zvariant::Value,
};

const SERVICE: &str = "org.freedesktop.Notifications";
const PATH: &str = "/org/freedesktop/Notifications";

struct Delivered {
    connection: Connection,
    owner: String,
    id: u32,
}

static LAST: OnceLock<Mutex<Option<Delivered>>> = OnceLock::new();

pub fn show(_: &str, title: &str, body: &str) -> Result<(), String> {
    let mut last = LAST
        .get_or_init(|| Mutex::new(None))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let connection = Builder::session()
        .map_err(|e| e.to_string())?
        .method_timeout(Duration::from_secs(5))
        .build()
        .map_err(|e| e.to_string())?;
    let bus = Proxy::new(
        &connection,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    )
    .map_err(|e| e.to_string())?;
    let owner: String = bus
        .call("GetNameOwner", &(SERVICE,))
        .or_else(|_| {
            // Some desktops activate their notification service on the first call.
            let _: u32 = bus.call("StartServiceByName", &(SERVICE, 0u32))?;
            bus.call("GetNameOwner", &(SERVICE,))
        })
        .map_err(|e| e.to_string())?;
    // Address the unique owner, so service replacement cannot receive an old ID.
    let proxy =
        Proxy::new(&connection, owner.as_str(), PATH, SERVICE).map_err(|e| e.to_string())?;
    if let Some(previous) = last.as_ref() {
        close(previous)?;
    }
    let hints = HashMap::from([
        ("transient", Value::from(true)),
        ("urgency", Value::from(1u8)),
    ]);
    let id: u32 = proxy
        .call(
            "Notify",
            &(
                "Where To Study",
                0u32,
                "where_to_study",
                title,
                super::escaped_notification_text(body),
                Vec::<String>::new(),
                hints,
                -1i32,
            ),
        )
        .map_err(|e| e.to_string())?;
    drop(proxy);
    drop(bus);
    *last = Some(Delivered {
        connection,
        owner,
        id,
    });
    Ok(())
}

fn close(notification: &Delivered) -> Result<(), String> {
    if notification.connection.is_closed() {
        return Ok(());
    }
    let bus = Proxy::new(
        &notification.connection,
        "org.freedesktop.DBus",
        "/org/freedesktop/DBus",
        "org.freedesktop.DBus",
    )
    .map_err(|e| e.to_string())?;
    let alive: bool = bus
        .call("NameHasOwner", &(notification.owner.as_str(),))
        .map_err(|e| e.to_string())?;
    if !alive {
        return Ok(());
    }
    Proxy::new(
        &notification.connection,
        notification.owner.as_str(),
        PATH,
        SERVICE,
    )
    .and_then(|proxy| proxy.call::<_, _, ()>("CloseNotification", &(notification.id,)))
    .map_err(|e| e.to_string())
}

pub fn clear(_: &str) -> Result<(), String> {
    let mut last = LAST
        .get_or_init(|| Mutex::new(None))
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if let Some(previous) = last.as_ref() {
        // Do not take/drop the handle before a successful CloseNotification reply.
        // A failure is reported and the ID remains available for another attempt.
        close(previous)?;
        *last = None;
    }
    Ok(())
}

pub fn request_permission() {}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{
        atomic::{AtomicBool, AtomicU32, Ordering},
        Arc,
    };

    struct TestServer {
        seen: Arc<Mutex<Vec<String>>>,
        next: AtomicU32,
        fail_close: Arc<AtomicBool>,
    }

    #[zbus::interface(name = "org.freedesktop.Notifications")]
    impl TestServer {
        #[allow(clippy::too_many_arguments)]
        fn notify(
            &self,
            app: &str,
            replaces: u32,
            _icon: &str,
            title: &str,
            body: &str,
            _actions: Vec<String>,
            hints: HashMap<String, zbus::zvariant::OwnedValue>,
            _timeout: i32,
        ) -> u32 {
            assert_eq!(app, "Where To Study");
            assert_eq!(replaces, 0);
            assert!(hints.contains_key("transient"));
            let id = self.next.fetch_add(1, Ordering::SeqCst);
            self.seen
                .lock()
                .unwrap()
                .push(format!("show {id}: {title} | {body}"));
            id
        }

        fn close_notification(&self, id: u32) -> zbus::fdo::Result<()> {
            if self.fail_close.load(Ordering::SeqCst) {
                return Err(zbus::fdo::Error::Failed("simulated close failure".into()));
            }
            self.seen.lock().unwrap().push(format!("close {id}"));
            Ok(())
        }
    }

    #[test]
    #[ignore = "Run only with WTS_PRIVATE_NOTIFICATION_BUS=1 under dbus-run-session"]
    fn private_dbus_notification_delivery_and_failed_close_round_trip() {
        assert_eq!(
            std::env::var("WTS_PRIVATE_NOTIFICATION_BUS").as_deref(),
            Ok("1")
        );
        let seen = Arc::new(Mutex::new(Vec::new()));
        let fail_close = Arc::new(AtomicBool::new(false));
        let server = TestServer {
            seen: seen.clone(),
            next: AtomicU32::new(71),
            fail_close: fail_close.clone(),
        };
        let _connection = Builder::session()
            .unwrap()
            .name(SERVICE)
            .unwrap()
            .serve_at(PATH, server)
            .unwrap()
            .build()
            .unwrap();
        show(
            "com.nemoyu.wheretostudy",
            "Today's courses",
            "Room <101> & lab",
        )
        .unwrap();
        assert_eq!(
            seen.lock().unwrap().as_slice(),
            ["show 71: Today's courses | Room &lt;101&gt; &amp; lab"]
        );
        fail_close.store(true, Ordering::SeqCst);
        assert!(clear("com.nemoyu.wheretostudy").is_err());
        assert!(LAST.get().unwrap().lock().unwrap().is_some());
        fail_close.store(false, Ordering::SeqCst);
        clear("com.nemoyu.wheretostudy").unwrap();
        assert!(LAST.get().unwrap().lock().unwrap().is_none());
        assert_eq!(seen.lock().unwrap().last().unwrap(), "close 71");
        show("com.nemoyu.wheretostudy", "replacement", "safe text").unwrap();
        drop(_connection);
        // A dead owner must not leave the feature permanently unable to clear.
        clear("com.nemoyu.wheretostudy").unwrap();
        assert!(LAST.get().unwrap().lock().unwrap().is_none());
    }
}
