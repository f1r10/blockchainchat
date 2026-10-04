use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(Error, Debug, PartialEq, Eq)]
pub enum SurbError {
    #[error("Empty SURB bundle")]
    EmptyBundle,
    #[error("Exhausted SURB pool")]
    ExhaustedPool,
    #[error("Invalid SURB header or payload")]
    InvalidSurb,
    #[error("Serialization error: {0}")]
    SerializationError(String),
}

/// Raw Anonymous Single Use Reply Block (SURB) payload structure
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq, Zeroize, ZeroizeOnDrop)]
pub struct SingleUseReplyBlock {
    pub surb_id: [u8; 16],
    pub raw_surb_bytes: Vec<u8>,
}

/// Bundle of SURBs published by Bob to the DHT for anonymous message routing
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct SurbBundle {
    pub recipient_commitment: [u8; 32],
    pub surbs: Vec<SingleUseReplyBlock>,
    pub created_at_epoch_sec: u64,
}

impl SurbBundle {
    pub fn new(recipient_commitment: [u8; 32], surbs: Vec<SingleUseReplyBlock>) -> Self {
        let created_at_epoch_sec = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        Self {
            recipient_commitment,
            surbs,
            created_at_epoch_sec,
        }
    }

    /// Pop a SURB from the bundle to wrap an outgoing message chunk
    pub fn pop_surb(&mut self) -> Result<SingleUseReplyBlock, SurbError> {
        self.surbs.pop().ok_or(SurbError::ExhaustedPool)
    }

    /// Number of remaining SURBs in the bundle
    pub fn remaining(&self) -> usize {
        self.surbs.len()
    }

    /// Serialize bundle for storage / DHT transport
    pub fn to_bytes(&self) -> Result<Vec<u8>, SurbError> {
        bincode::serialize(self).map_err(|e| SurbError::SerializationError(e.to_string()))
    }

    /// Deserialize bundle from storage / DHT transport
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, SurbError> {
        bincode::deserialize(bytes).map_err(|e| SurbError::SerializationError(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_surb_bundle_lifecycle() {
        let recipient = [0x55; 32];
        let surbs = vec![
            SingleUseReplyBlock { surb_id: [1u8; 16], raw_surb_bytes: vec![0xAA; 196] },
            SingleUseReplyBlock { surb_id: [2u8; 16], raw_surb_bytes: vec![0xBB; 196] },
        ];

        let mut bundle = SurbBundle::new(recipient, surbs);
        assert_eq!(bundle.remaining(), 2);

        let surb1 = bundle.pop_surb().unwrap();
        assert_eq!(surb1.surb_id, [2u8; 16]); // LIFO pop

        let bytes = bundle.to_bytes().unwrap();
        let restored = SurbBundle::from_bytes(&bytes).unwrap();
        assert_eq!(restored.remaining(), 1);
    }
}
