use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Credential payload shared with file-backed terminal clients.
///
/// Platform-specific storage remains owned by each application target.
#[derive(Clone, Default, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct Credentials {
    pub account: String,
    pub password: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub teaching_cloud_password: Option<String>,
    #[serde(default)]
    pub account_scope: String,
}

impl Credentials {
    pub fn assignment_password(&self) -> &str {
        self.teaching_cloud_password
            .as_deref()
            .filter(|value| !value.is_empty())
            .unwrap_or(&self.password)
    }
}

impl std::fmt::Debug for Credentials {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Credentials")
            .field("has_account", &!self.account.is_empty())
            .field("has_password", &!self.password.is_empty())
            .field(
                "has_teaching_cloud_password",
                &self.teaching_cloud_password.is_some(),
            )
            .finish_non_exhaustive()
    }
}
