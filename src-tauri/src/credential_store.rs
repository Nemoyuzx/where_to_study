use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

use crate::error::{ServiceError, ServiceResult};

const SERVICE_NAME: &str = "com.nemoyu.wheretostudy";
const ENTRY_NAME: &str = "default-account";

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct Credentials {
    pub account: String,
    pub password: String,
    #[serde(default)]
    pub account_scope: String,
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn load() -> ServiceResult<Option<Credentials>> {
    use security_framework::passwords::{generic_password, PasswordOptions};
    use security_framework_sys::base::errSecItemNotFound;

    let payload = Zeroizing::new(
        match generic_password(PasswordOptions::new_generic_password(
            SERVICE_NAME,
            ENTRY_NAME,
        )) {
            Ok(payload) => payload,
            Err(error) if error.code() == errSecItemNotFound => return Ok(None),
            Err(error) => return Err(ServiceError::new(format!("无法读取系统凭据存储：{error}"))),
        },
    );
    serde_json::from_slice(&payload)
        .map(Some)
        .map_err(|error| ServiceError::new(format!("系统凭据内容格式不正确：{error}")))
}

#[cfg(any(target_os = "macos", target_os = "ios"))]
pub fn save(credentials: &Credentials) -> ServiceResult<()> {
    use security_framework::passwords::{delete_generic_password, set_generic_password};
    use security_framework_sys::base::errSecItemNotFound;

    if credentials.account.is_empty() && credentials.password.is_empty() {
        return match delete_generic_password(SERVICE_NAME, ENTRY_NAME) {
            Ok(()) => Ok(()),
            Err(error) if error.code() == errSecItemNotFound => Ok(()),
            Err(error) => Err(ServiceError::new(format!("无法清除系统凭据存储：{error}"))),
        };
    }

    let payload = Zeroizing::new(
        serde_json::to_vec(credentials)
            .map_err(|error| ServiceError::new(format!("无法序列化账户凭据：{error}")))?,
    );
    set_generic_password(SERVICE_NAME, ENTRY_NAME, &payload)
        .map_err(|error| ServiceError::new(format!("无法写入系统凭据存储：{error}")))
}

#[cfg(target_os = "android")]
fn android_entry() -> ServiceResult<keyring_core::Entry> {
    use keyring_core::api::CredentialStoreApi;

    let store = android_native_keyring_store::Store::new()
        .map_err(|error| ServiceError::new(format!("无法访问 Android Keystore：{error}")))?;
    store
        .build(SERVICE_NAME, ENTRY_NAME, None)
        .map_err(|error| ServiceError::new(format!("无法创建 Android 凭据记录：{error}")))
}

#[cfg(target_os = "android")]
pub fn load() -> ServiceResult<Option<Credentials>> {
    let payload = Zeroizing::new(match android_entry()?.get_secret() {
        Ok(payload) => payload,
        Err(keyring_core::Error::NoEntry) => return Ok(None),
        Err(error) => return Err(ServiceError::new(format!("无法读取 Android 凭据：{error}"))),
    });
    serde_json::from_slice(&payload)
        .map(Some)
        .map_err(|error| ServiceError::new(format!("系统凭据内容格式不正确：{error}")))
}

#[cfg(target_os = "android")]
pub fn save(credentials: &Credentials) -> ServiceResult<()> {
    let entry = android_entry()?;
    if credentials.account.is_empty() && credentials.password.is_empty() {
        return match entry.delete_credential() {
            Ok(()) | Err(keyring_core::Error::NoEntry) => Ok(()),
            Err(error) => Err(ServiceError::new(format!("无法清除 Android 凭据：{error}"))),
        };
    }

    let payload = Zeroizing::new(
        serde_json::to_vec(credentials)
            .map_err(|error| ServiceError::new(format!("无法序列化账户凭据：{error}")))?,
    );
    entry
        .set_secret(&payload)
        .map_err(|error| ServiceError::new(format!("无法写入 Android 凭据：{error}")))
}

#[cfg(target_os = "windows")]
pub fn load() -> ServiceResult<Option<Credentials>> {
    use std::{ptr, slice};
    use windows_sys::Win32::Foundation::{GetLastError, ERROR_NOT_FOUND};
    use windows_sys::Win32::Security::Credentials::{
        CredFree, CredReadW, CREDENTIALW, CRED_TYPE_GENERIC,
    };

    struct CredentialGuard(*mut CREDENTIALW);

    impl Drop for CredentialGuard {
        fn drop(&mut self) {
            unsafe {
                if !self.0.is_null() {
                    let credential = &mut *self.0;
                    if credential.CredentialBlobSize > 0 && !credential.CredentialBlob.is_null() {
                        std::ptr::write_bytes(
                            credential.CredentialBlob,
                            0,
                            credential.CredentialBlobSize as usize,
                        );
                    }
                    CredFree(self.0.cast());
                }
            }
        }
    }

    let target_name = wide_string(&format!("{SERVICE_NAME}/{ENTRY_NAME}"));
    let mut raw_credential: *mut CREDENTIALW = ptr::null_mut();
    if unsafe {
        CredReadW(
            target_name.as_ptr(),
            CRED_TYPE_GENERIC,
            0,
            &mut raw_credential,
        )
    } == 0
    {
        let error = unsafe { GetLastError() };
        if error == ERROR_NOT_FOUND {
            return Ok(None);
        }
        return Err(ServiceError::new(format!(
            "无法读取 Windows 凭据管理器：错误代码 {error}"
        )));
    }

    if raw_credential.is_null() {
        return Err(ServiceError::new("Windows 凭据管理器返回了空记录"));
    }
    let guard = CredentialGuard(raw_credential);
    let stored = unsafe { &*guard.0 };
    if stored.CredentialBlobSize == 0 || stored.CredentialBlob.is_null() {
        return Err(ServiceError::new("Windows 凭据管理器返回了无效记录"));
    }
    let payload =
        unsafe { slice::from_raw_parts(stored.CredentialBlob, stored.CredentialBlobSize as usize) };
    serde_json::from_slice(payload)
        .map(Some)
        .map_err(|error| ServiceError::new(format!("系统凭据内容格式不正确：{error}")))
}

#[cfg(target_os = "windows")]
pub fn save(credentials: &Credentials) -> ServiceResult<()> {
    use windows_sys::Win32::Foundation::{GetLastError, ERROR_NOT_FOUND};
    use windows_sys::Win32::Security::Credentials::{
        CredDeleteW, CredWriteW, CREDENTIALW, CRED_MAX_CREDENTIAL_BLOB_SIZE,
        CRED_PERSIST_LOCAL_MACHINE, CRED_TYPE_GENERIC,
    };

    let mut target_name = wide_string(&format!("{SERVICE_NAME}/{ENTRY_NAME}"));
    if credentials.account.is_empty() && credentials.password.is_empty() {
        if unsafe { CredDeleteW(target_name.as_ptr(), CRED_TYPE_GENERIC, 0) } != 0 {
            return Ok(());
        }
        let error = unsafe { GetLastError() };
        if error == ERROR_NOT_FOUND {
            return Ok(());
        }
        return Err(ServiceError::new(format!(
            "无法清除 Windows 凭据管理器：错误代码 {error}"
        )));
    }

    let mut payload = Zeroizing::new(
        serde_json::to_vec(credentials)
            .map_err(|error| ServiceError::new(format!("无法序列化账户凭据：{error}")))?,
    );
    let payload_size = u32::try_from(payload.len())
        .map_err(|_| ServiceError::new("账户凭据超过 Windows 凭据管理器容量限制"))?;
    if payload_size > CRED_MAX_CREDENTIAL_BLOB_SIZE {
        return Err(ServiceError::new("账户凭据超过 Windows 凭据管理器容量限制"));
    }
    let mut user_name = wide_string(ENTRY_NAME);
    let credential = CREDENTIALW {
        Type: CRED_TYPE_GENERIC,
        TargetName: target_name.as_mut_ptr(),
        CredentialBlobSize: payload_size,
        CredentialBlob: payload.as_mut_ptr(),
        Persist: CRED_PERSIST_LOCAL_MACHINE,
        UserName: user_name.as_mut_ptr(),
        ..Default::default()
    };
    if unsafe { CredWriteW(&credential, 0) } == 0 {
        let error = unsafe { GetLastError() };
        return Err(ServiceError::new(format!(
            "无法写入 Windows 凭据管理器：错误代码 {error}"
        )));
    }
    Ok(())
}

#[cfg(target_os = "windows")]
fn wide_string(value: &str) -> Vec<u16> {
    value.encode_utf16().chain(std::iter::once(0)).collect()
}

#[cfg(all(
    not(target_os = "macos"),
    not(target_os = "windows"),
    not(target_os = "android"),
    not(target_os = "ios")
))]
pub fn load() -> ServiceResult<Option<Credentials>> {
    Err(ServiceError::new("当前平台尚未提供系统级安全凭据存储"))
}

#[cfg(all(
    not(target_os = "macos"),
    not(target_os = "windows"),
    not(target_os = "android"),
    not(target_os = "ios")
))]
pub fn save(_credentials: &Credentials) -> ServiceResult<()> {
    Err(ServiceError::new("当前平台尚未提供系统级安全凭据存储"))
}

#[cfg(test)]
mod tests {
    use super::Credentials;
    use zeroize::Zeroizing;

    #[test]
    fn credential_payload_round_trips_as_structured_json() {
        let credentials = Credentials {
            account: "fixture-account".to_string(),
            password: "fixture-password".to_string(),
            account_scope:
                "opaque-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
                    .to_string(),
        };
        let payload = Zeroizing::new(
            serde_json::to_string(&credentials).expect("serialize fixture credentials"),
        );
        let decoded: Credentials =
            serde_json::from_str(&payload).expect("deserialize fixture credentials");
        assert_eq!(decoded.account, credentials.account);
        assert_eq!(decoded.password, credentials.password);
    }
}
