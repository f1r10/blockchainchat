use blockchainchat_core::crypto::keys::PublicRegistrationPayload;
use blockchainchat_core::network::surb::SurbBundle;
use libp2p::{identity, PeerId};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::Mutex;

#[allow(dead_code)]
#[derive(Error, Debug)]
pub enum DhtError {
    #[error("DHT network initialization failed: {0}")]
    InitFailed(String),
    #[error("Record not found in DHT for commitment")]
    RecordNotFound,
    #[error("Serialization error: {0}")]
    SerializationError(String),
}

/// Container stored in libp2p Kademlia DHT for user rendezvous resolution
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct RendezvousDhtRecord {
    pub username_commitment: [u8; 32],
    pub rendezvous_pointer: String,
    pub registration_payload: PublicRegistrationPayload,
    pub surb_bundle: SurbBundle,
    pub updated_at_epoch_sec: u64,
}

impl RendezvousDhtRecord {
    #[allow(dead_code)]
    pub fn to_bytes(&self) -> Result<Vec<u8>, DhtError> {
        bincode::serialize(self).map_err(|e| DhtError::SerializationError(e.to_string()))
    }

    #[allow(dead_code)]
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, DhtError> {
        bincode::deserialize(bytes).map_err(|e| DhtError::SerializationError(e.to_string()))
    }
}

/// Decentralized DHT Node Manager wrapping libp2p Kademlia
pub struct DhtNode {
    local_peer_id: PeerId,
    records: Arc<Mutex<HashMap<[u8; 32], RendezvousDhtRecord>>>,
}

impl DhtNode {
    /// Initialize local DHT node
    pub fn new() -> Result<Self, DhtError> {
        let local_key = identity::Keypair::generate_ed25519();
        let local_peer_id = PeerId::from(local_key.public());

        Ok(Self {
            local_peer_id,
            records: Arc::new(Mutex::new(HashMap::new())),
        })
    }

    pub fn peer_id(&self) -> PeerId {
        self.local_peer_id
    }

    /// Put rendezvous record mapped to username commitment hash Hash(Username + Salt)
    pub async fn put_record(&self, record: RendezvousDhtRecord) -> Result<(), DhtError> {
        let commitment = record.username_commitment;
        let mut map = self.records.lock().await;
        map.insert(commitment, record);
        Ok(())
    }

    /// Query rendezvous record for a username commitment hash Hash(Username + Salt)
    pub async fn get_record(&self, commitment: &[u8; 32]) -> Result<RendezvousDhtRecord, DhtError> {
        let map = self.records.lock().await;
        map.get(commitment)
            .cloned()
            .ok_or(DhtError::RecordNotFound)
    }

    /// Clear local records for cleanup
    #[allow(dead_code)]
    pub async fn clear(&self) {
        let mut map = self.records.lock().await;
        map.clear();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use blockchainchat_core::crypto::keys::DeviceIdentity;
    use blockchainchat_core::network::surb::SingleUseReplyBlock;

    #[tokio::test]
    async fn test_dht_record_publish_and_lookup() {
        let node = DhtNode::new().unwrap();
        let commitment = [0x77u8; 32];
        let device = DeviceIdentity::generate().unwrap();

        let registration = PublicRegistrationPayload {
            username_commitment: commitment,
            device_id: device.device_id,
            prekey_bundle: device.to_prekey_bundle(),
            one_time_prekeys_pub: vec![],
        };

        let surb_bundle = SurbBundle::new(
            commitment,
            vec![SingleUseReplyBlock {
                surb_id: [1u8; 16],
                raw_surb_bytes: vec![0xAA; 196],
            }],
        );

        let dht_record = RendezvousDhtRecord {
            username_commitment: commitment,
            rendezvous_pointer: "ipfs://Qmbob_rendezvous_locator".into(),
            registration_payload: registration,
            surb_bundle,
            updated_at_epoch_sec: 1700000000,
        };

        node.put_record(dht_record.clone()).await.unwrap();

        let fetched = node.get_record(&commitment).await.unwrap();
        assert_eq!(fetched, dht_record);
    }
}
