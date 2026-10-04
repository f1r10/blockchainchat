use serde::{Deserialize, Serialize};

use crate::crypto::keys::{compute_username_commitment, DeviceIdentity, PublicRegistrationPayload};
use crate::network::surb::{SingleUseReplyBlock, SurbBundle};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct IdentityRegistrationResult {
    pub username: String,
    pub username_commitment_hex: String,
    pub device_id_hex: String,
    pub prekey_bundle_bytes: Vec<u8>,
    pub surb_bundle_bytes: Vec<u8>,
}

/// FFI Export: Register user identity off-chain & generate prekey + SURB bundles
pub fn register_identity(username: String) -> Result<IdentityRegistrationResult, String> {
    if username.trim().is_empty() {
        return Err("Username cannot be empty".into());
    }

    let mut salt = [0u8; 32];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut salt);

    let commitment = compute_username_commitment(&username, &salt);
    let device = DeviceIdentity::generate()
        .map_err(|e| format!("Failed to generate device identity: {}", e))?;

    let prekey_bundle = device.to_prekey_bundle();

    // Generate initial pool of 20 SURBs for offline message receipt
    let mut surbs = Vec::with_capacity(20);
    for _ in 0..20 {
        let mut surb_id = [0u8; 16];
        let mut raw_bytes = vec![0u8; 196];
        rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut surb_id);
        rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut raw_bytes);
        surbs.push(SingleUseReplyBlock {
            surb_id,
            raw_surb_bytes: raw_bytes,
        });
    }

    let surb_bundle = SurbBundle::new(commitment, surbs);

    let payload = PublicRegistrationPayload {
        username_commitment: commitment,
        device_id: device.device_id,
        prekey_bundle,
        one_time_prekeys_pub: vec![],
    };

    let payload_bytes = payload
        .to_bytes()
        .map_err(|e| format!("Serialization error: {}", e))?;

    let surb_bytes = surb_bundle
        .to_bytes()
        .map_err(|e| format!("Serialization error: {}", e))?;

    Ok(IdentityRegistrationResult {
        username,
        username_commitment_hex: hex_encode(&commitment),
        device_id_hex: hex_encode(&device.device_id),
        prekey_bundle_bytes: payload_bytes,
        surb_bundle_bytes: surb_bytes,
    })
}

fn hex_encode(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}
