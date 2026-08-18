use std::io::{self, Write};

use where_to_study_lib::error::ServiceResult;

/// Interactive password prompt that does not echo input.
pub fn prompt_password(prompt: &str) -> ServiceResult<String> {
    print!("{prompt}");
    io::stdout().flush().map_err(|error| {
        where_to_study_lib::error::ServiceError::new(format!("无法刷新终端输出：{error}"))
    })?;
    let password = rpassword::read_password().map_err(|error| {
        where_to_study_lib::error::ServiceError::new(format!("无法读取密码输入：{error}"))
    })?;
    Ok(password.trim_end_matches(['\r', '\n']).to_string())
}

/// Save credentials to the system credential store.
pub fn save(account: &str, password: &str) -> ServiceResult<()> {
    let credentials = where_to_study_lib::credential_store::Credentials {
        account: account.trim().to_string(),
        password: password.to_string(),
        account_scope: String::new(),
    };
    where_to_study_lib::credential_store::save(&credentials)
}

/// Load credentials from the system credential store.
pub fn load() -> ServiceResult<Option<(String, String)>> {
    let credentials = where_to_study_lib::credential_store::load()?;
    let Some(credentials) = credentials else {
        return Ok(None);
    };
    let account = credentials.account.clone();
    let password = credentials.password.clone();
    Ok(Some((account, password)))
}

/// Clear credentials from the system credential store.
pub fn clear() -> ServiceResult<()> {
    where_to_study_lib::credential_store::save(
        &where_to_study_lib::credential_store::Credentials::default(),
    )
}
