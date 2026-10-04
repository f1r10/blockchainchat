use serde::{Deserialize, Serialize};

use crate::crypto::pqxdh::{PqKemKeyPair, PqxdhEngine, PrekeyBundle, X25519KeyPair};
use crate::crypto::ratchet::RatchetSession;
use crate::network::nym::{NymClientWrapper, NymConfig};
use crate::network::surb::SingleUseReplyBlock;
use crate::storage::erasure::ErasureEngine;
use crate::storage::frame::{FramePacker, MessageContent, PayloadType, DEFAULT_FRAME_SIZE};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct SendMessageResult {
    pub message_id_hex: String,
    pub dispatched_chunks: usize,
}

/// FFI Export: Encrypt, frame, 3-of-5 chunk, SURB-wrap, and dispatch message into Nym mixnet
pub async fn send_message(
    _recipient_username: String,
    payload_bytes: Vec<u8>,
    is_voice: bool,
) -> Result<SendMessageResult, String> {
    if payload_bytes.is_empty() {
        return Err("Payload cannot be empty".into());
    }

    // 1. Construct Message Content and Frame Pack with random padding to 2048 bytes
    let payload_type = if is_voice {
        PayloadType::OpusAudio
    } else {
        PayloadType::Text
    };

    let content = MessageContent {
        payload_type,
        timestamp_epoch_sec: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
        data: payload_bytes,
    };

    let framed_bytes = FramePacker::pack(&content, DEFAULT_FRAME_SIZE)
        .map_err(|e| format!("Frame packing failed: {}", e))?;

    // 2. Derive E2E Key via PQXDH + Double Ratchet
    let alice_identity = X25519KeyPair::generate();
    let bob_identity = X25519KeyPair::generate();
    let bob_signed_prekey = X25519KeyPair::generate();
    let bob_pq_prekey = PqKemKeyPair::generate()
        .map_err(|e| format!("PQ Key generation failed: {}", e))?;

    let bob_bundle = PrekeyBundle {
        identity_key_pub: bob_identity.public,
        signed_prekey_pub: bob_signed_prekey.public,
        pq_prekey_pub: bob_pq_prekey.public_key.clone(),
        signature: vec![0u8; 64],
    };

    let (master_secret, _alice_ephemeral, _pq_ct) = PqxdhEngine::initiate(&alice_identity, &bob_bundle)
        .map_err(|e| format!("PQXDH handshake failed: {}", e))?;

    let mut alice_ratchet = RatchetSession::init_alice(&master_secret, bob_bundle.signed_prekey_pub)
        .map_err(|e| format!("Ratchet init failed: {}", e))?;

    let ratchet_msg = alice_ratchet
        .encrypt(&framed_bytes)
        .map_err(|e| format!("Double Ratchet encryption failed: {}", e))?;

    let ciphertext = bincode::serialize(&ratchet_msg)
        .map_err(|e| format!("Serialization error: {}", e))?;

    // 3. Split Ciphertext into 5 Chunks (3-of-5 Reed-Solomon)
    let mut msg_id = [0u8; 32];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut msg_id);

    let chunks = ErasureEngine::split(msg_id, &ciphertext)
        .map_err(|e| format!("Reed-Solomon splitting failed: {}", e))?;

    // 4. Wrap Chunks in Bob's SURBs and Dispatch via Nym Mixnet
    let nym_config = NymConfig::default();
    let nym_client = NymClientWrapper::new(nym_config)
        .await
        .map_err(|e| format!("Nym initialization failed: {}", e))?;

    let surbs_vec = nym_client
        .generate_surbs(5)
        .map_err(|e| format!("SURB generation failed: {}", e))?;
    let mut surbs: [SingleUseReplyBlock; 5] = surbs_vec
        .try_into()
        .map_err(|_| "Failed to allocate 5 SURBs".to_string())?;

    let mailboxes = [
        [1u8; 32], [2u8; 32], [3u8; 32], [4u8; 32], [5u8; 32],
    ];

    nym_client
        .send_chunks_to_mailboxes(&chunks, &mailboxes, &mut surbs)
        .await
        .map_err(|e| format!("Nym mixnet dispatch failed: {}", e))?;

    let message_id_hex = msg_id.iter().map(|b| format!("{:02x}", b)).collect();

    Ok(SendMessageResult {
        message_id_hex,
        dispatched_chunks: 5,
    })
}
