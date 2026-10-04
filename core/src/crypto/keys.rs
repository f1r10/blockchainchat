use sha2::{Digest, Sha256};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::crypto::pqxdh::{PqKemKeyPair, PrekeyBundle, X25519KeyPair};

#[derive(Error, Debug, PartialEq, Eq)]
pub enum KeyError {
    #[error("Invalid username commitment calculation")]
    CommitmentError,
    #[error("Serialization error: {0}")]
    SerializationError(String),
}

/// Computes the EVM commitment Hash(Username + Salt)
pub fn compute_username_commitment(username: &str, salt: &[u8; 32]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(username.as_bytes());
    hasher.update(salt);
    let result = hasher.finalize();
    let mut hash = [0u8; 32];
    hash.copy_from_slice(&result);
    hash
}

/// Isolated Local Device Identity Keys
#[derive(Serialize, Deserialize, Clone, Zeroize, ZeroizeOnDrop)]
pub struct DeviceIdentity {
    pub device_id: [u8; 32],
    pub identity_key: X25519KeyPair,
    pub signed_prekey: X25519KeyPair,
    pub signed_prekey_signature: Vec<u8>,
    pub pq_prekey: PqKemKeyPair,
}

impl DeviceIdentity {
    pub fn generate() -> Result<Self, KeyError> {
        use rand::RngCore;
        let mut device_id = [0u8; 32];
        rand::thread_rng().fill_bytes(&mut device_id);

        let identity_key = X25519KeyPair::generate();
        let signed_prekey = X25519KeyPair::generate();
        let pq_prekey = PqKemKeyPair::generate()
            .map_err(|e| KeyError::SerializationError(e.to_string()))?;

        // Compute prekey signature over signed_prekey.public
        let mut sig_hasher = Sha256::new();
        sig_hasher.update(&identity_key.secret);
        sig_hasher.update(&signed_prekey.public);
        let signature = sig_hasher.finalize().to_vec();

        Ok(Self {
            device_id,
            identity_key,
            signed_prekey,
            signed_prekey_signature: signature,
            pq_prekey,
        })
    }

    /// Convert local device keys to a public PrekeyBundle ready for DHT registration
    pub fn to_prekey_bundle(&self) -> PrekeyBundle {
        PrekeyBundle {
            identity_key_pub: self.identity_key.public,
            signed_prekey_pub: self.signed_prekey.public,
            pq_prekey_pub: self.pq_prekey.public_key.clone(),
            signature: self.signed_prekey_signature.clone(),
        }
    }
}

/// Full Public Registration Payload published to DHT/Contract Mempool
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct PublicRegistrationPayload {
    pub username_commitment: [u8; 32],
    pub device_id: [u8; 32],
    pub prekey_bundle: PrekeyBundle,
    pub one_time_prekeys_pub: Vec<[u8; 32]>,
}

impl PublicRegistrationPayload {
    pub fn to_bytes(&self) -> Result<Vec<u8>, KeyError> {
        bincode::serialize(self).map_err(|e| KeyError::SerializationError(e.to_string()))
    }

    pub fn from_bytes(bytes: &[u8]) -> Result<Self, KeyError> {
        bincode::deserialize(bytes).map_err(|e| KeyError::SerializationError(e.to_string()))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_username_commitment_deterministic() {
        let salt = [7u8; 32];
        let commitment1 = compute_username_commitment("bob", &salt);
        let commitment2 = compute_username_commitment("bob", &salt);
        assert_eq!(commitment1, commitment2);

        let commitment_alice = compute_username_commitment("alice", &salt);
        assert_ne!(commitment1, commitment_alice);
    }

    #[test]
    fn test_device_identity_serialization() {
        let device = DeviceIdentity::generate().unwrap();
        let bundle = device.to_prekey_bundle();

        let payload = PublicRegistrationPayload {
            username_commitment: [1u8; 32],
            device_id: device.device_id,
            prekey_bundle: bundle,
            one_time_prekeys_pub: vec![[2u8; 32], [3u8; 32]],
        };

        let bytes = payload.to_bytes().unwrap();
        let restored = PublicRegistrationPayload::from_bytes(&bytes).unwrap();
        assert_eq!(payload, restored);
    }
}
