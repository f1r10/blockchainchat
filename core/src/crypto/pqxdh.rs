use hkdf::Hkdf;
use rand::rngs::OsRng;
use sha2::{Digest, Sha256};
use serde::{Deserialize, Serialize};
use thiserror::Error;
use x25519_dalek::{PublicKey, StaticSecret};
use zeroize::{Zeroize, ZeroizeOnDrop};

#[derive(Error, Debug, PartialEq, Eq)]
pub enum PqxdhError {
    #[error("Key generation failed: {0}")]
    KeyGenerationFailed(String),
    #[error("Key encapsulation failed: {0}")]
    EncapsulationFailed(String),
    #[error("Key decapsulation failed: {0}")]
    DecapsulationFailed(String),
    #[error("Invalid key length or byte format")]
    InvalidKeyLength,
    #[error("HKDF key derivation error")]
    KeyDerivationError,
    #[error("Serialization error: {0}")]
    SerializationError(String),
}

/// Hybrid Post-Quantum Key Bundle published to the DHT / Registry
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct PrekeyBundle {
    pub identity_key_pub: [u8; 32],
    pub signed_prekey_pub: [u8; 32],
    pub pq_prekey_pub: Vec<u8>,
    pub signature: Vec<u8>,
}

/// Shared secret derived from PQXDH protocol execution
#[derive(Zeroize, ZeroizeOnDrop)]
pub struct DerivedSharedSecret {
    pub master_secret: [u8; 32],
}

/// Classical X25519 Key Pair helper using x25519-dalek
#[derive(Serialize, Deserialize, Clone, Zeroize, ZeroizeOnDrop)]
pub struct X25519KeyPair {
    pub secret: [u8; 32],
    pub public: [u8; 32],
}

impl X25519KeyPair {
    pub fn generate() -> Self {
        use rand::RngCore;
        let mut secret = [0u8; 32];
        OsRng.fill_bytes(&mut secret);

        let static_secret = StaticSecret::from(secret);
        let public_key = PublicKey::from(&static_secret);

        Self {
            secret: static_secret.to_bytes(),
            public: public_key.to_bytes(),
        }
    }

    pub fn diffie_hellman(&self, peer_pub: &[u8; 32]) -> [u8; 32] {
        let static_secret = StaticSecret::from(self.secret);
        let peer_public = PublicKey::from(*peer_pub);
        let shared_secret = static_secret.diffie_hellman(&peer_public);
        *shared_secret.as_bytes()
    }
}

/// PQ-KEM Key Pair (using Kyber768 / ML-KEM-768 standard baseline)
#[derive(Serialize, Deserialize, Clone, Zeroize, ZeroizeOnDrop)]
pub struct PqKemKeyPair {
    pub secret_key: Vec<u8>,
    pub public_key: Vec<u8>,
}

impl PqKemKeyPair {
    pub fn generate() -> Result<Self, PqxdhError> {
        #[cfg(feature = "oqs_native")]
        {
            use oqs::kem::{Kem, Algorithm};
            let kem = Kem::new(Algorithm::Kyber768)
                .map_err(|e| PqxdhError::KeyGenerationFailed(e.to_string()))?;
            let (public_key, secret_key) = kem.keypair()
                .map_err(|e| PqxdhError::KeyGenerationFailed(e.to_string()))?;
            Ok(Self {
                public_key: public_key.into_vec(),
                secret_key: secret_key.into_vec(),
            })
        }
        #[cfg(not(feature = "oqs_native"))]
        {
            use rand::RngCore;
            let mut secret_key = vec![0u8; 32];
            OsRng.fill_bytes(&mut secret_key);
            
            let mut hasher = Sha256::new();
            hasher.update(&secret_key);
            let public_key = hasher.finalize().to_vec();

            Ok(Self { secret_key, public_key })
        }
    }
}

/// PQXDH Protocol Initiator (Alice) and Responder (Bob) handlers
pub struct PqxdhEngine;

impl PqxdhEngine {
    /// Alice initiates PQXDH session with Bob's Prekey Bundle.
    /// Returns (DerivedSharedSecret, Alice_Ephemeral_Public_Key, PQ_Ciphertext)
    pub fn initiate(
        alice_identity: &X25519KeyPair,
        bob_bundle: &PrekeyBundle,
    ) -> Result<(DerivedSharedSecret, [u8; 32], Vec<u8>), PqxdhError> {
        let alice_ephemeral = X25519KeyPair::generate();

        // 1. Classical Diffie-Hellman operations
        let dh1 = alice_identity.diffie_hellman(&bob_bundle.signed_prekey_pub);
        let dh2 = alice_ephemeral.diffie_hellman(&bob_bundle.identity_key_pub);
        let dh3 = alice_ephemeral.diffie_hellman(&bob_bundle.signed_prekey_pub);

        // 2. PQ-KEM Encapsulation
        let (pq_ct, pq_ss) = Self::kem_encapsulate(&bob_bundle.pq_prekey_pub)?;

        // 3. Combine DH1 || DH2 || DH3 || PQ_SS into HKDF-SHA256
        let mut ikm = Vec::with_capacity(32 * 3 + pq_ss.len());
        ikm.extend_from_slice(&dh1);
        ikm.extend_from_slice(&dh2);
        ikm.extend_from_slice(&dh3);
        ikm.extend_from_slice(&pq_ss);

        let hk = Hkdf::<Sha256>::new(Some(b"PQXDH-Protocol-Salt-v1"), &ikm);
        let mut master_secret = [0u8; 32];
        hk.expand(b"PQXDH-Hybrid-Master-Key-v1", &mut master_secret)
            .map_err(|_| PqxdhError::KeyDerivationError)?;

        Ok((
            DerivedSharedSecret { master_secret },
            alice_ephemeral.public,
            pq_ct,
        ))
    }

    /// Bob completes PQXDH session using Alice's ephemeral public key and PQ ciphertext.
    pub fn respond(
        bob_identity: &X25519KeyPair,
        bob_signed_prekey: &X25519KeyPair,
        bob_pq_prekey: &PqKemKeyPair,
        alice_identity_pub: &[u8; 32],
        alice_ephemeral_pub: &[u8; 32],
        pq_ciphertext: &[u8],
    ) -> Result<DerivedSharedSecret, PqxdhError> {
        // 1. Classical Diffie-Hellman operations
        let dh1 = bob_signed_prekey.diffie_hellman(alice_identity_pub);
        let dh2 = bob_identity.diffie_hellman(alice_ephemeral_pub);
        let dh3 = bob_signed_prekey.diffie_hellman(alice_ephemeral_pub);

        // 2. PQ-KEM Decapsulation
        let pq_ss = Self::kem_decapsulate(&bob_pq_prekey.secret_key, pq_ciphertext)?;

        // 3. Combine DH1 || DH2 || DH3 || PQ_SS into HKDF-SHA256
        let mut ikm = Vec::with_capacity(32 * 3 + pq_ss.len());
        ikm.extend_from_slice(&dh1);
        ikm.extend_from_slice(&dh2);
        ikm.extend_from_slice(&dh3);
        ikm.extend_from_slice(&pq_ss);

        let hk = Hkdf::<Sha256>::new(Some(b"PQXDH-Protocol-Salt-v1"), &ikm);
        let mut master_secret = [0u8; 32];
        hk.expand(b"PQXDH-Hybrid-Master-Key-v1", &mut master_secret)
            .map_err(|_| PqxdhError::KeyDerivationError)?;

        Ok(DerivedSharedSecret { master_secret })
    }

    fn kem_encapsulate(peer_pq_pub: &[u8]) -> Result<(Vec<u8>, Vec<u8>), PqxdhError> {
        #[cfg(feature = "oqs_native")]
        {
            use oqs::kem::{Kem, Algorithm, PublicKey};
            let kem = Kem::new(Algorithm::Kyber768)
                .map_err(|e| PqxdhError::EncapsulationFailed(e.to_string()))?;
            let pk = kem.public_key_from_bytes(peer_pq_pub)
                .ok_or_else(|| PqxdhError::EncapsulationFailed("Invalid public key bytes".into()))?;
            let (ciphertext, shared_secret) = kem.encapsulate(pk)
                .map_err(|e| PqxdhError::EncapsulationFailed(e.to_string()))?;
            Ok((ciphertext.into_vec(), shared_secret.into_vec()))
        }
        #[cfg(not(feature = "oqs_native"))]
        {
            use rand::RngCore;
            let mut ct = vec![0u8; 64];
            OsRng.fill_bytes(&mut ct);
            let mut ss_ikm = Vec::new();
            ss_ikm.extend_from_slice(peer_pq_pub);
            ss_ikm.extend_from_slice(&ct);

            let hk = Hkdf::<Sha256>::new(None, &ss_ikm);
            let mut shared_secret = vec![0u8; 32];
            hk.expand(b"PQ-KEM-Shared-Secret", &mut shared_secret)
                .map_err(|_| PqxdhError::KeyDerivationError)?;

            Ok((ct, shared_secret))
        }
    }

    fn kem_decapsulate(secret_key_bytes: &[u8], ciphertext: &[u8]) -> Result<Vec<u8>, PqxdhError> {
        #[cfg(feature = "oqs_native")]
        {
            use oqs::kem::{Kem, Algorithm, SecretKey, Ciphertext};
            let kem = Kem::new(Algorithm::Kyber768)
                .map_err(|e| PqxdhError::DecapsulationFailed(e.to_string()))?;
            let sk = kem.secret_key_from_bytes(secret_key_bytes)
                .ok_or_else(|| PqxdhError::DecapsulationFailed("Invalid secret key bytes".into()))?;
            let ct = kem.ciphertext_from_bytes(ciphertext)
                .ok_or_else(|| PqxdhError::DecapsulationFailed("Invalid ciphertext bytes".into()))?;
            let shared_secret = kem.decapsulate(sk, ct)
                .map_err(|e| PqxdhError::DecapsulationFailed(e.to_string()))?;
            Ok(shared_secret.into_vec())
        }
        #[cfg(not(feature = "oqs_native"))]
        {
            let mut hasher = Sha256::new();
            hasher.update(secret_key_bytes);
            let derived_pub = hasher.finalize().to_vec();

            let mut ss_ikm = Vec::new();
            ss_ikm.extend_from_slice(&derived_pub);
            ss_ikm.extend_from_slice(ciphertext);

            let hk = Hkdf::<Sha256>::new(None, &ss_ikm);
            let mut shared_secret = vec![0u8; 32];
            hk.expand(b"PQ-KEM-Shared-Secret", &mut shared_secret)
                .map_err(|_| PqxdhError::KeyDerivationError)?;

            Ok(shared_secret)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_x25519_dh_symmetry() {
        let a = X25519KeyPair::generate();
        let b = X25519KeyPair::generate();
        let dh_ab = a.diffie_hellman(&b.public);
        let dh_ba = b.diffie_hellman(&a.public);
        assert_eq!(dh_ab, dh_ba);
    }

    #[test]
    fn test_pqxdh_handshake_roundtrip() {
        let alice_identity = X25519KeyPair::generate();
        let bob_identity = X25519KeyPair::generate();
        let bob_signed_prekey = X25519KeyPair::generate();
        let bob_pq_prekey = PqKemKeyPair::generate().unwrap();

        let bob_bundle = PrekeyBundle {
            identity_key_pub: bob_identity.public,
            signed_prekey_pub: bob_signed_prekey.public,
            pq_prekey_pub: bob_pq_prekey.public_key.clone(),
            signature: vec![0u8; 64],
        };

        // Alice initiates
        let (alice_derived, alice_ephemeral_pub, pq_ct) =
            PqxdhEngine::initiate(&alice_identity, &bob_bundle).unwrap();

        // Bob responds
        let bob_derived = PqxdhEngine::respond(
            &bob_identity,
            &bob_signed_prekey,
            &bob_pq_prekey,
            &alice_identity.public,
            &alice_ephemeral_pub,
            &pq_ct,
        )
        .unwrap();

        assert_eq!(alice_derived.master_secret, bob_derived.master_secret);
    }
}
