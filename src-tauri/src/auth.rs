use crate::error::{ServiceError, ServiceResult};

pub fn resolve_credentials(
    account: &Option<String>,
    password: &Option<String>,
) -> ServiceResult<(String, String)> {
    let user = account.as_deref().unwrap_or_default().trim().to_string();
    let user = if user.is_empty() {
        std::env::var("BUPT_USERNAME").unwrap_or_default()
    } else {
        user
    };
    let secret = password
        .as_deref()
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
        .or_else(|| std::env::var("BUPT_PASSWORD").ok())
        .unwrap_or_default();

    if user.trim().is_empty() || secret.is_empty() {
        return Err(ServiceError::with_status(
            "请填写学号和教务密码，或在环境变量中配置 BUPT_USERNAME/BUPT_PASSWORD。",
            400,
        ));
    }
    Ok((user.trim().to_string(), secret))
}
