use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Credential payload shared with file-backed terminal clients.
///
/// Platform-specific storage remains owned by each application target.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, Zeroize, ZeroizeOnDrop)]
pub struct Credentials {
    pub account: String,
    pub password: String,
    #[serde(default)]
    pub account_scope: String,
}
