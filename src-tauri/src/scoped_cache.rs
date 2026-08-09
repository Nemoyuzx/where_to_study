use std::fmt::Write as _;

use serde::de::DeserializeOwned;
use serde::{Deserialize, Serialize};

use crate::error::{ServiceError, ServiceResult};

const SCHEMA_VERSION: u32 = 1;
const SCOPE_PREFIX: &str = "opaque-v1:";
const SCOPE_BYTES: usize = 32;

#[derive(Serialize)]
struct ScopedCacheRef<'a, T> {
    schema_version: u32,
    account_scope: &'a str,
    payload: &'a T,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ScopedCache<T> {
    schema_version: u32,
    account_scope: String,
    payload: T,
}

pub fn new_account_scope() -> ServiceResult<String> {
    let mut entropy = [0_u8; SCOPE_BYTES];
    getrandom::fill(&mut entropy)
        .map_err(|error| ServiceError::new(format!("无法生成本地账号作用域：{error}")))?;

    let mut scope = String::with_capacity(SCOPE_PREFIX.len() + SCOPE_BYTES * 2);
    scope.push_str(SCOPE_PREFIX);
    for byte in entropy {
        write!(&mut scope, "{byte:02x}").expect("writing to String cannot fail");
    }
    Ok(scope)
}

pub fn is_valid_account_scope(scope: &str) -> bool {
    validate_scope(scope).is_ok()
}

pub fn encode<T: Serialize>(scope: &str, payload: &T, description: &str) -> ServiceResult<Vec<u8>> {
    validate_scope(scope)
        .map_err(|message| ServiceError::new(format!("无法保存{description}：{message}")))?;
    serde_json::to_vec_pretty(&ScopedCacheRef {
        schema_version: SCHEMA_VERSION,
        account_scope: scope,
        payload,
    })
    .map_err(|error| ServiceError::new(format!("无法序列化{description}：{error}")))
}

pub fn decode<T: DeserializeOwned>(
    bytes: &[u8],
    expected_scope: &str,
    description: &str,
) -> ServiceResult<Option<T>> {
    validate_scope(expected_scope)
        .map_err(|message| ServiceError::new(format!("无法读取{description}：{message}")))?;
    let value: serde_json::Value = serde_json::from_slice(bytes)
        .map_err(|error| ServiceError::new(format!("{description}格式不正确：{error}")))?;
    let Some(object) = value.as_object() else {
        return Err(ServiceError::new(format!("{description}格式不正确。")));
    };

    if !object.contains_key("schema_version") && !object.contains_key("account_scope") {
        return Ok(None);
    }

    let cache: ScopedCache<T> = serde_json::from_value(value)
        .map_err(|error| ServiceError::new(format!("{description}格式不正确：{error}")))?;
    validate_scope(&cache.account_scope)
        .map_err(|message| ServiceError::new(format!("{description}格式不正确：{message}")))?;
    if cache.schema_version != SCHEMA_VERSION || cache.account_scope != expected_scope {
        return Ok(None);
    }
    Ok(Some(cache.payload))
}

fn validate_scope(scope: &str) -> Result<(), &'static str> {
    let Some(digest) = scope.strip_prefix(SCOPE_PREFIX) else {
        return Err("账号作用域格式无效");
    };
    if digest.len() != 64 || !digest.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return Err("账号作用域格式无效");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, PartialEq, Eq, Serialize, Deserialize)]
    struct Fixture {
        value: String,
    }

    #[test]
    fn generated_scopes_are_opaque_and_unique() {
        let first = new_account_scope().expect("first account scope");
        let second = new_account_scope().expect("second account scope");
        assert!(is_valid_account_scope(&first));
        assert!(is_valid_account_scope(&second));
        assert_ne!(first, second);
        assert!(!first.contains("test-account"));
    }

    #[test]
    fn matching_scope_round_trips_and_mismatch_is_rejected() {
        let first = new_account_scope().expect("first scope");
        let second = new_account_scope().expect("second scope");
        let bytes = encode(
            &first,
            &Fixture {
                value: "account-a data".to_string(),
            },
            "测试缓存",
        )
        .expect("encode scoped cache");

        assert_eq!(
            decode::<Fixture>(&bytes, &first, "测试缓存").expect("decode matching cache"),
            Some(Fixture {
                value: "account-a data".to_string(),
            })
        );
        assert_eq!(
            decode::<Fixture>(&bytes, &second, "测试缓存").expect("reject mismatched cache"),
            None
        );
    }

    #[test]
    fn legacy_unscoped_cache_is_not_loaded() {
        let scope = new_account_scope().expect("account scope");
        let bytes = br#"{"value":"legacy data"}"#;
        assert_eq!(
            decode::<Fixture>(bytes, &scope, "测试缓存").expect("ignore legacy cache"),
            None
        );
    }
}
