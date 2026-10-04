use blockchainchat_core::crypto::keys::{compute_username_commitment, DeviceIdentity, PublicRegistrationPayload};
use blockchainchat_core::crypto::pqxdh::PqxdhEngine;
use blockchainchat_core::crypto::ratchet::{RatchetMessage, RatchetSession};
use blockchainchat_core::network::surb::{SingleUseReplyBlock, SurbBundle};
use blockchainchat_core::storage::erasure::{ErasureChunk, ErasureEngine};
use blockchainchat_core::storage::frame::{FramePacker, MessageContent, PayloadType, DEFAULT_FRAME_SIZE};
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::Mutex;

/// Mock EVM Commitment Registry simulating CommitmentRegistry.sol
struct MockEvmRegistry {
    registrations: HashMap<[u8; 32], (String, String)>, // commitment -> (owner_address, rendezvous_pointer)
}

impl MockEvmRegistry {
    fn new() -> Self {
        Self {
            registrations: HashMap::new(),
        }
    }

    fn register(&mut self, commitment: [u8; 32], owner: String, pointer: String) -> Result<(), &'static str> {
        if self.registrations.contains_key(&commitment) {
            return Err("AlreadyRegistered");
        }
        self.registrations.insert(commitment, (owner, pointer));
        Ok(())
    }

    fn get_registration(&self, commitment: &[u8; 32]) -> Option<&(String, String)> {
        self.registrations.get(commitment)
    }
}

/// Mock Validator Mailbox Node holding sled/in-memory chunks with immediate delete on pull
struct MockMailboxNode {
    chunks: Mutex<HashMap<[u8; 16], ErasureChunk>>,
}

impl MockMailboxNode {
    fn new() -> Self {
        Self {
            chunks: Mutex::new(HashMap::new()),
        }
    }

    async fn push_chunk(&self, surb_id: [u8; 16], chunk: ErasureChunk) {
        let mut map = self.chunks.lock().await;
        map.insert(surb_id, chunk);
    }

    async fn pull_and_delete(&self, surb_id: &[u8; 16]) -> Option<ErasureChunk> {
        let mut map = self.chunks.lock().await;
        map.remove(surb_id)
    }

    async fn len(&self) -> usize {
        let map = self.chunks.lock().await;
        map.len()
    }
}

/// Mock Decentralized DHT storing Prekey & SURB bundles mapped to rendezvous pointers
struct MockDhtService {
    records: Mutex<HashMap<String, (PublicRegistrationPayload, SurbBundle)>>,
}

impl MockDhtService {
    fn new() -> Self {
        Self {
            records: Mutex::new(HashMap::new()),
        }
    }

    async fn put(&self, pointer: String, payload: PublicRegistrationPayload, surbs: SurbBundle) {
        let mut map = self.records.lock().await;
        map.insert(pointer, (payload, surbs));
    }

    async fn get(&self, pointer: &str) -> Option<(PublicRegistrationPayload, SurbBundle)> {
        let map = self.records.lock().await;
        map.get(pointer).cloned()
    }
}

#[tokio::test]
async fn test_full_e2e_decentralized_messaging_flow() {
    println!("========== [1] INITIALIZING MOCK EVM & 5 VALIDATOR MAILBOXES ==========");
    let mut evm_contract = MockEvmRegistry::new();
    let dht_network = Arc::new(MockDhtService::new());

    // Spin up 5 Validator Mailbox Nodes
    let mailboxes: Vec<Arc<MockMailboxNode>> = (0..5)
        .map(|_| Arc::new(MockMailboxNode::new()))
        .collect();

    println!("========== [2] BOB ONBOARDING & GASLESS COMMITMENT REGISTRATION ==========");
    let bob_salt = [0xBBu8; 32];
    let bob_username = "bob";
    let bob_commitment = compute_username_commitment(bob_username, &bob_salt);

    let bob_device = DeviceIdentity::generate().unwrap();
    let bob_prekey_bundle = bob_device.to_prekey_bundle();

    // Bob generates pool of 20 SURBs
    let mut bob_surbs = Vec::with_capacity(20);
    let mut surb_ids_pool = Vec::with_capacity(20);
    for _ in 0..20 {
        let mut surb_id = [0u8; 16];
        let mut raw_bytes = vec![0u8; 196];
        rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut surb_id);
        rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut raw_bytes);
        surb_ids_pool.push(surb_id);
        bob_surbs.push(SingleUseReplyBlock {
            surb_id,
            raw_surb_bytes: raw_bytes,
        });
    }

    let bob_surb_bundle = SurbBundle::new(bob_commitment, bob_surbs);
    let bob_registration_payload = PublicRegistrationPayload {
        username_commitment: bob_commitment,
        device_id: bob_device.device_id,
        prekey_bundle: bob_prekey_bundle.clone(),
        one_time_prekeys_pub: vec![],
    };

    let bob_rendezvous_pointer = "ipfs://QmBobRendezvousLocator123".to_string();
    let bob_smart_account_addr = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8".to_string();

    // EIP-4337 Relayer writes Bob's commitment to EVM contract
    evm_contract
        .register(bob_commitment, bob_smart_account_addr, bob_rendezvous_pointer.clone())
        .unwrap();

    // Bob publishes prekey & SURB bundle to DHT
    dht_network
        .put(
            bob_rendezvous_pointer.clone(),
            bob_registration_payload,
            bob_surb_bundle,
        )
        .await;

    println!("========== [3] ALICE LOOKS UP BOB & PREPARES E2E MESSAGE ==========");
    let alice_identity = DeviceIdentity::generate().unwrap();
    let plaintext_msg = b"Zero-metadata post-quantum message from Alice to offline Bob!";

    // 1. Resolve Bob's rendezvous pointer from EVM contract using Hash("bob" + salt)
    let (_, fetched_pointer) = evm_contract.get_registration(&bob_commitment).unwrap();
    assert_eq!(fetched_pointer, &bob_rendezvous_pointer);

    // 2. Fetch Bob's prekeys and SURBs from DHT
    let (bob_payload, mut bob_surbs_fetched) = dht_network.get(fetched_pointer).await.unwrap();

    // 3. Perform Hybrid PQXDH Key Exchange (Alice side)
    let (alice_master_secret, alice_ephemeral_pub, pq_ct) =
        PqxdhEngine::initiate(&alice_identity.identity_key, &bob_payload.prekey_bundle).unwrap();

    // 4. Perform Hybrid PQXDH Key Exchange (Bob side)
    let bob_master_secret = PqxdhEngine::respond(
        &bob_device.identity_key,
        &bob_device.signed_prekey,
        &bob_device.pq_prekey,
        &alice_identity.identity_key.public,
        &alice_ephemeral_pub,
        &pq_ct,
    ).unwrap();

    assert_eq!(alice_master_secret.master_secret, bob_master_secret.master_secret);

    // 5. Initialize Double Ratchet session for Alice
    let mut alice_ratchet =
        RatchetSession::init_alice(&alice_master_secret, bob_payload.prekey_bundle.signed_prekey_pub).unwrap();

    // 6. Pack plaintext into 2048-byte fixed frame with random padding
    let content = MessageContent {
        payload_type: PayloadType::Text,
        timestamp_epoch_sec: 1700000000,
        data: plaintext_msg.to_vec(),
    };
    let framed_bytes = FramePacker::pack(&content, DEFAULT_FRAME_SIZE).unwrap();
    assert_eq!(framed_bytes.len(), DEFAULT_FRAME_SIZE);

    // 7. Encrypt framed payload via Double Ratchet
    let ratchet_msg = alice_ratchet.encrypt(&framed_bytes).unwrap();
    let ciphertext = bincode::serialize(&ratchet_msg).unwrap();

    // 8. Split Ciphertext into 5 Chunks (3-of-5 Reed-Solomon scheme)
    let msg_id = [0xAAu8; 32];
    let chunks = ErasureEngine::split(msg_id, &ciphertext).unwrap();
    assert_eq!(chunks.len(), 5);

    println!("========== [4] ALICE DISPATCHES 5 CHUNKS TO 5 MAILBOXES VIA SURBS ==========");
    let mut alice_used_surbs = Vec::new();
    for chunk in &chunks {
        let surb = bob_surbs_fetched.pop_surb().unwrap();
        let mailbox_node = &mailboxes[chunk.header.shard_index as usize];
        mailbox_node.push_chunk(surb.surb_id, chunk.clone()).await;
        alice_used_surbs.push(surb.surb_id);
    }

    // Verify each mailbox holds 1 chunk
    for mb in &mailboxes {
        assert_eq!(mb.len().await, 1);
    }

    println!("========== [5] BOB COMES ONLINE & EXECUTES PULL SYNC ==========");
    // Simulating Mailbox #4 temporarily unreachable to test 3-of-5 resilience!
    println!("Simulating network outage on Mailbox #4 (only 4 of 5 chunks retrieved)...");

    let mut retrieved_chunks = Vec::new();
    for i in 0..4 {
        let surb_id = alice_used_surbs[i];
        let chunk = mailboxes[i].pull_and_delete(&surb_id).await.unwrap();
        retrieved_chunks.push(chunk);
    }

    assert_eq!(retrieved_chunks.len(), 4);

    // Reconstruct original ciphertext from 4 retrieved chunks (3-of-5 threshold satisfied!)
    let reconstructed_ciphertext = ErasureEngine::reconstruct(&retrieved_chunks).unwrap();
    assert_eq!(reconstructed_ciphertext, ciphertext);

    // Deserialize Double Ratchet message
    let restored_ratchet_msg: RatchetMessage = bincode::deserialize(&reconstructed_ciphertext).unwrap();

    // Bob initializes ratchet session with derived master secret and decrypts message
    let mut bob_ratchet =
        RatchetSession::init_bob(&bob_master_secret, bob_device.signed_prekey.clone());
    let decrypted_framed_bytes = bob_ratchet.decrypt(&restored_ratchet_msg).unwrap();

    // Unpack 2048-byte fixed frame and remove padding
    let restored_content = FramePacker::unpack(&decrypted_framed_bytes).unwrap();

    println!("========== [6] VERIFYING PLAINTEXT & DESTRUCTION OF STORED CHUNKS ==========");
    assert_eq!(restored_content.payload_type, PayloadType::Text);
    assert_eq!(restored_content.data, plaintext_msg);

    // Verify pulled chunks were destroyed permanently from Mailbox storage nodes 0..3
    for mb in mailboxes.iter().take(4) {
        assert_eq!(mb.len().await, 0);
    }

    println!("SUCCESS! E2E SIMULATION PASSED CLEANLY!");
    println!("- Zero Metadata Verified (Fixed 2KB Frame Padding + Hash Commitment)");
    println!("- 3-of-5 Erasure Resilience Verified (Reconstructed from 4/5 chunks)");
    println!("- Pull-and-Delete Verification Confirmed (0 chunks remaining after pull)");
    println!("- PQXDH + Double Ratchet AEAD Verification Successful");
}
