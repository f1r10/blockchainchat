pub mod identity;
pub mod messaging;
pub mod sync;

pub use identity::{register_identity, IdentityRegistrationResult};
pub use messaging::{send_message, SendMessageResult};
pub use sync::{sync_messages, DecryptedMessage};
