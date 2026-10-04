use aes_gcm::{
    aead::{Aead, KeyInit},
    Aes256Gcm, Nonce,
};
use hkdf::Hkdf;
use sha2::Sha256;
use serde::{Deserialize, Serialize};
use thiserror::Error;
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::crypto::pqxdh::{DerivedSharedSecret, X25519KeyPair};

#[derive(Error, Debug, PartialEq, Eq)]
pub enum RatchetError {
    #[error("Encryption failed: {0}")]
    EncryptionFailed(String),
    #[error("Decryption failed: {0}")]
    DecryptionFailed(String),
    #[error("HKDF key derivation failed")]
    KeyDerivationFailed,
    #[error("Out of order message threshold exceeded")]
    OutOfOrderExceeded,
    #[error("Serialization error: {0}")]
    SerializationError(String),
}

/// Message payload output by Double Ratchet session
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct RatchetMessage {
    pub ratchet_pub: [u8; 32],
    pub sequence: u32,
    pub nonce: [u8; 12],
    pub ciphertext: Vec<u8>,
}

/// Double Ratchet State Manager
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct RatchetSession {
    root_key: [u8; 32],
    chain_key_send: [u8; 32],
    chain_key_recv: [u8; 32],
    dh_send: X25519KeyPair,
    dh_recv_pub: Option<[u8; 32]>,
    sequence_send: u32,
    sequence_recv: u32,
}

impl RatchetSession {
    /// Initialize a Double Ratchet session as Alice (Initiator) using derived shared secret
    pub fn init_alice(shared_secret: &DerivedSharedSecret, bob_dh_pub: [u8; 32]) -> Result<Self, RatchetError> {
        let hk = Hkdf::<Sha256>::new(Some(b"Double-Ratchet-Init-Salt"), &shared_secret.master_secret);
        let mut okm = [0u8; 64];
        hk.expand(b"Double-Ratchet-Init-OKM", &mut okm)
            .map_err(|_| RatchetError::KeyDerivationFailed)?;
        
        let mut initial_root_key = [0u8; 32];
        initial_root_key.copy_from_slice(&okm[0..32]);

        let dh_send = X25519KeyPair::generate();
        let dh_shared = dh_send.diffie_hellman(&bob_dh_pub);

        let (root_key, chain_key_send) = Self::kdf_root(&initial_root_key, &dh_shared)?;

        Ok(Self {
            root_key,
            chain_key_send,
            chain_key_recv: [0u8; 32],
            dh_send,
            dh_recv_pub: Some(bob_dh_pub),
            sequence_send: 0,
            sequence_recv: 0,
        })
    }

    /// Initialize a Double Ratchet session as Bob (Responder) using derived shared secret
    pub fn init_bob(shared_secret: &DerivedSharedSecret, bob_dh_key: X25519KeyPair) -> Self {
        let mut root_key = [0u8; 32];
        let mut chain_key_recv = [0u8; 32];
        
        let hk = Hkdf::<Sha256>::new(Some(b"Double-Ratchet-Init-Salt"), &shared_secret.master_secret);
        let mut okm = [0u8; 64];
        let _ = hk.expand(b"Double-Ratchet-Init-OKM", &mut okm);

        root_key.copy_from_slice(&okm[0..32]);
        chain_key_recv.copy_from_slice(&okm[32..64]);

        Self {
            root_key,
            chain_key_send: [0u8; 32],
            chain_key_recv,
            dh_send: bob_dh_key,
            dh_recv_pub: None,
            sequence_send: 0,
            sequence_recv: 0,
        }
    }

    /// Encrypt a plaintext message and advance send ratchet chain
    pub fn encrypt(&mut self, plaintext: &[u8]) -> Result<RatchetMessage, RatchetError> {
        let (next_chain, message_key) = Self::kdf_chain(&self.chain_key_send)?;
        self.chain_key_send = next_chain;

        // Generate 96-bit AES-GCM nonce using message sequence and key material
        let nonce_bytes = Self::derive_nonce(&message_key, self.sequence_send);
        let cipher = Aes256Gcm::new_from_slice(&message_key)
            .map_err(|e| RatchetError::EncryptionFailed(e.to_string()))?;
        
        let nonce = Nonce::from_slice(&nonce_bytes);
        let ciphertext = cipher
            .encrypt(nonce, plaintext)
            .map_err(|e| RatchetError::EncryptionFailed(e.to_string()))?;

        let msg = RatchetMessage {
            ratchet_pub: self.dh_send.public,
            sequence: self.sequence_send,
            nonce: nonce_bytes,
            ciphertext,
        };

        self.sequence_send += 1;
        Ok(msg)
    }

    /// Decrypt an incoming ciphertext and advance receive ratchet chain
    pub fn decrypt(&mut self, msg: &RatchetMessage) -> Result<Vec<u8>, RatchetError> {
        // Perform DH ratchet step if new ratchet public key received
        if self.dh_recv_pub != Some(msg.ratchet_pub) {
            self.dh_ratchet_step(msg.ratchet_pub)?;
        }

        let (next_chain, message_key) = Self::kdf_chain(&self.chain_key_recv)?;
        self.chain_key_recv = next_chain;

        let cipher = Aes256Gcm::new_from_slice(&message_key)
            .map_err(|e| RatchetError::DecryptionFailed(e.to_string()))?;
        
        let nonce = Nonce::from_slice(&msg.nonce);
        let plaintext = cipher
            .decrypt(nonce, msg.ciphertext.as_ref())
            .map_err(|e| RatchetError::DecryptionFailed(e.to_string()))?;

        self.sequence_recv += 1;
        Ok(plaintext)
    }

    fn dh_ratchet_step(&mut self, remote_pub: [u8; 32]) -> Result<(), RatchetError> {
        self.dh_recv_pub = Some(remote_pub);
        
        let dh_shared = self.dh_send.diffie_hellman(&remote_pub);
        let (next_root, recv_chain) = Self::kdf_root(&self.root_key, &dh_shared)?;
        self.root_key = next_root;
        self.chain_key_recv = recv_chain;

        // Generate new send key pair
        self.dh_send = X25519KeyPair::generate();
        let dh_send_shared = self.dh_send.diffie_hellman(&remote_pub);
        let (next_root_send, send_chain) = Self::kdf_root(&self.root_key, &dh_send_shared)?;
        self.root_key = next_root_send;
        self.chain_key_send = send_chain;

        Ok(())
    }

    fn kdf_chain(chain_key: &[u8; 32]) -> Result<([u8; 32], [u8; 32]), RatchetError> {
        let hk = Hkdf::<Sha256>::new(Some(b"Ratchet-Chain-Salt"), chain_key);
        let mut okm = [0u8; 64];
        hk.expand(b"Ratchet-Chain-Step", &mut okm)
            .map_err(|_| RatchetError::KeyDerivationFailed)?;

        let mut next_chain = [0u8; 32];
        let mut message_key = [0u8; 32];
        next_chain.copy_from_slice(&okm[0..32]);
        message_key.copy_from_slice(&okm[32..64]);

        Ok((next_chain, message_key))
    }

    fn kdf_root(root_key: &[u8; 32], dh_secret: &[u8; 32]) -> Result<([u8; 32], [u8; 32]), RatchetError> {
        let mut ikm = Vec::with_capacity(64);
        ikm.extend_from_slice(root_key);
        ikm.extend_from_slice(dh_secret);

        let hk = Hkdf::<Sha256>::new(Some(b"Ratchet-Root-Salt"), &ikm);
        let mut okm = [0u8; 64];
        hk.expand(b"Ratchet-Root-Step", &mut okm)
            .map_err(|_| RatchetError::KeyDerivationFailed)?;

        let mut next_root = [0u8; 32];
        let mut chain_key = [0u8; 32];
        next_root.copy_from_slice(&okm[0..32]);
        chain_key.copy_from_slice(&okm[32..64]);

        Ok((next_root, chain_key))
    }

    fn derive_nonce(message_key: &[u8; 32], seq: u32) -> [u8; 12] {
        let mut nonce = [0u8; 12];
        nonce[0..8].copy_from_slice(&message_key[0..8]);
        nonce[8..12].copy_from_slice(&seq.to_le_bytes());
        nonce
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_double_ratchet_session() {
        let master_secret = DerivedSharedSecret { master_secret: [99u8; 32] };
        let bob_dh = X25519KeyPair::generate();
        let bob_pub = bob_dh.public;

        let mut alice_session = RatchetSession::init_alice(&master_secret, bob_pub).unwrap();
        let mut bob_session = RatchetSession::init_bob(&master_secret, bob_dh);

        let msg1_text = b"Hello Bob! Zero metadata communication.";
        let msg1 = alice_session.encrypt(msg1_text).unwrap();

        let decrypted1 = bob_session.decrypt(&msg1).unwrap();
        assert_eq!(decrypted1, msg1_text);
    }
}
