use std::io::{self, Write};

use where_to_study_lib::credential_store::Credentials;
use where_to_study_lib::error::ServiceResult;
use zeroize::Zeroizing;

/// Interactive password prompt that does not echo input.
pub fn prompt_password(prompt: &str) -> ServiceResult<Zeroizing<String>> {
    print!("{prompt}");
    io::stdout().flush().map_err(|error| {
        where_to_study_lib::error::ServiceError::new(format!("无法刷新终端输出：{error}"))
    })?;
    let password = rpassword::read_password().map_err(|error| {
        where_to_study_lib::error::ServiceError::new(format!("无法读取密码输入：{error}"))
    })?;
    Ok(Zeroizing::new(password))
}

/// Save credentials to the system credential store.
pub fn save(account: &str, password: String) -> ServiceResult<()> {
    let account = account.trim();
    let existing = where_to_study_lib::credential_store::load()?;
    let account_scope = account_scope_for(existing.as_ref(), account)?;
    let credentials = Credentials {
        account: account.to_string(),
        password,
        account_scope,
    };
    where_to_study_lib::credential_store::save(&credentials)
}

fn account_scope_for(existing: Option<&Credentials>, account: &str) -> ServiceResult<String> {
    let preserved_scope = existing
        .filter(|credentials| credentials.account.trim() == account)
        .map(|credentials| credentials.account_scope.as_str())
        .filter(|scope| where_to_study_lib::scoped_cache::is_valid_account_scope(scope));
    if let Some(scope) = preserved_scope {
        Ok(scope.to_string())
    } else {
        where_to_study_lib::scoped_cache::new_account_scope()
    }
}

/// Load credentials from the system credential store.
pub fn load() -> ServiceResult<Option<where_to_study_lib::credential_store::Credentials>> {
    where_to_study_lib::credential_store::load()
}

/// Clear credentials from the system credential store.
pub fn clear() -> ServiceResult<()> {
    where_to_study_lib::credential_store::save(
        &where_to_study_lib::credential_store::Credentials::default(),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    const VALID_SCOPE: &str =
        "opaque-v1:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    fn fixture(account: &str, scope: &str) -> Credentials {
        Credentials {
            account: account.to_string(),
            password: "fixture-password".to_string(),
            account_scope: scope.to_string(),
        }
    }

    #[test]
    fn same_account_preserves_valid_desktop_cache_scope() {
        let existing = fixture("2023000000", VALID_SCOPE);
        assert_eq!(
            account_scope_for(Some(&existing), "2023000000").unwrap(),
            VALID_SCOPE
        );
    }

    #[test]
    fn changed_account_or_invalid_scope_gets_new_opaque_scope() {
        let existing = fixture("2023000000", VALID_SCOPE);
        let changed = account_scope_for(Some(&existing), "2023000001").unwrap();
        assert!(where_to_study_lib::scoped_cache::is_valid_account_scope(
            &changed
        ));
        assert_ne!(changed, VALID_SCOPE);

        let invalid = fixture("2023000000", "legacy-scope");
        let repaired = account_scope_for(Some(&invalid), "2023000000").unwrap();
        assert!(where_to_study_lib::scoped_cache::is_valid_account_scope(
            &repaired
        ));
        assert_ne!(repaired, "legacy-scope");
    }
}
