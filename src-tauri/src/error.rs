#[derive(Debug, Clone)]
pub struct ServiceError {
    pub message: String,
    pub authentication_expired: bool,
}

impl ServiceError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            authentication_expired: false,
        }
    }

    pub fn with_status(message: impl Into<String>, status_code: u16) -> Self {
        Self {
            message: message.into(),
            authentication_expired: status_code == 401,
        }
    }

    pub fn expired() -> Self {
        Self::with_status("登录状态已失效，请重新获取。", 401)
    }
}

impl std::fmt::Display for ServiceError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for ServiceError {}

pub type ServiceResult<T> = Result<T, ServiceError>;
