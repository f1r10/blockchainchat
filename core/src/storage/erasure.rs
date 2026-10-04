use reed_solomon_erasure::galois_8::ReedSolomon;
use serde::{Deserialize, Serialize};
use thiserror::Error;

pub const DATA_SHARDS: usize = 3;
pub const PARITY_SHARDS: usize = 2;
pub const TOTAL_SHARDS: usize = DATA_SHARDS + PARITY_SHARDS;

#[derive(Error, Debug, PartialEq, Eq)]
pub enum ErasureError {
    #[error("Payload is empty")]
    EmptyPayload,
    #[error("Reed-Solomon encoding failed: {0}")]
    EncodingFailed(String),
    #[error("Reed-Solomon decoding failed: {0}")]
    DecodingFailed(String),
    #[error("Insufficient shards for reconstruction: expected at least {required}, got {provided}")]
    InsufficientShards { required: usize, provided: usize },
    #[error("Invalid shard index {0}, must be less than {TOTAL_SHARDS}")]
    InvalidShardIndex(u8),
    #[error("Mismatched header parameters across received chunks")]
    HeaderMismatch,
    #[error("Corrupted shard payload size: expected {expected}, got {got}")]
    InvalidShardSize { expected: usize, got: usize },
    #[error("Serialization error: {0}")]
    SerializationError(String),
}

/// Metadata header attached to every individual erasure chunk.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ChunkHeader {
    /// Unique 256-bit identifier for the message payload
    pub message_id: [u8; 32],
    /// Index of this shard (0..TOTAL_SHARDS-1)
    pub shard_index: u8,
    /// Total number of shards generated (5)
    pub total_shards: u8,
    /// Number of data shards required for reconstruction (3)
    pub data_shards: u8,
    /// Byte length of the unpadded original ciphertext payload
    pub original_len: usize,
    /// Fixed byte length of each individual shard
    pub shard_len: usize,
}

/// Self-contained chunk ready for anonymous SURB wrapper & Mailbox dispatch.
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct ErasureChunk {
    pub header: ChunkHeader,
    pub payload: Vec<u8>,
}

impl ErasureChunk {
    /// Serialize the entire chunk into binary format for transport.
    pub fn to_bytes(&self) -> Result<Vec<u8>, ErasureError> {
        bincode::serialize(self).map_err(|e| ErasureError::SerializationError(e.to_string()))
    }

    /// Deserialize chunk from transport binary format.
    pub fn from_bytes(bytes: &[u8]) -> Result<Self, ErasureError> {
        bincode::deserialize(bytes).map_err(|e| ErasureError::SerializationError(e.to_string()))
    }
}

/// Engine for splitting E2E ciphertext into 5 erasure chunks and reconstructing from any 3.
pub struct ErasureEngine;

impl ErasureEngine {
    /// Splits an E2E ciphertext payload into 5 standalone erasure chunks using 3-of-5 Reed-Solomon scheme.
    pub fn split(message_id: [u8; 32], payload: &[u8]) -> Result<Vec<ErasureChunk>, ErasureError> {
        if payload.is_empty() {
            return Err(ErasureError::EmptyPayload);
        }

        let original_len = payload.len();
        let shard_len = (original_len + DATA_SHARDS - 1) / DATA_SHARDS;

        // Create buffer for 3 data shards + 2 parity shards
        let mut shards: Vec<Vec<u8>> = vec![vec![0u8; shard_len]; TOTAL_SHARDS];

        // Fill data shards with payload bytes, padded with zeros if necessary
        for i in 0..original_len {
            let shard_idx = i / shard_len;
            let byte_idx = i % shard_len;
            shards[shard_idx][byte_idx] = payload[i];
        }

        // Construct Reed-Solomon encoder
        let rs = ReedSolomon::new(DATA_SHARDS, PARITY_SHARDS)
            .map_err(|e| ErasureError::EncodingFailed(e.to_string()))?;

        // Compute parity shards
        rs.encode(&mut shards)
            .map_err(|e| ErasureError::EncodingFailed(e.to_string()))?;

        // Wrap shards into ErasureChunks with explicit metadata headers
        let chunks = shards
            .into_iter()
            .enumerate()
            .map(|(idx, shard_payload)| ErasureChunk {
                header: ChunkHeader {
                    message_id,
                    shard_index: idx as u8,
                    total_shards: TOTAL_SHARDS as u8,
                    data_shards: DATA_SHARDS as u8,
                    original_len,
                    shard_len,
                },
                payload: shard_payload,
            })
            .collect();

        Ok(chunks)
    }

    /// Reconstructs the original E2E ciphertext payload from a collection of chunks (minimum 3 required).
    pub fn reconstruct(chunks: &[ErasureChunk]) -> Result<Vec<u8>, ErasureError> {
        if chunks.len() < DATA_SHARDS {
            return Err(ErasureError::InsufficientShards {
                required: DATA_SHARDS,
                provided: chunks.len(),
            });
        }

        // Validate first header as reference
        let ref_header = &chunks[0].header;
        let message_id = ref_header.message_id;
        let original_len = ref_header.original_len;
        let shard_len = ref_header.shard_len;

        // Prepare sparse shard container for 5 possible slots
        let mut shard_opts: Vec<Option<Vec<u8>>> = vec![None; TOTAL_SHARDS];
        let mut valid_count = 0;

        for chunk in chunks {
            // Check header consistency
            if chunk.header.message_id != message_id
                || chunk.header.original_len != original_len
                || chunk.header.shard_len != shard_len
                || chunk.header.total_shards as usize != TOTAL_SHARDS
                || chunk.header.data_shards as usize != DATA_SHARDS
            {
                return Err(ErasureError::HeaderMismatch);
            }

            let idx = chunk.header.shard_index as usize;
            if idx >= TOTAL_SHARDS {
                return Err(ErasureError::InvalidShardIndex(chunk.header.shard_index));
            }

            if chunk.payload.len() != shard_len {
                return Err(ErasureError::InvalidShardSize {
                    expected: shard_len,
                    got: chunk.payload.len(),
                });
            }

            if shard_opts[idx].is_none() {
                shard_opts[idx] = Some(chunk.payload.clone());
                valid_count += 1;
            }
        }

        if valid_count < DATA_SHARDS {
            return Err(ErasureError::InsufficientShards {
                required: DATA_SHARDS,
                provided: valid_count,
            });
        }

        // Construct Reed-Solomon decoder
        let rs = ReedSolomon::new(DATA_SHARDS, PARITY_SHARDS)
            .map_err(|e| ErasureError::DecodingFailed(e.to_string()))?;

        // Reconstruct missing shards
        rs.reconstruct(&mut shard_opts)
            .map_err(|e| ErasureError::DecodingFailed(e.to_string()))?;

        // Flatten data shards and truncate to original length
        let mut reconstructed = Vec::with_capacity(shard_len * DATA_SHARDS);
        for shard_opt in shard_opts.iter().take(DATA_SHARDS) {
            if let Some(shard) = shard_opt {
                reconstructed.extend_from_slice(shard);
            } else {
                return Err(ErasureError::DecodingFailed(
                    "Data shard missing after reconstruction".into(),
                ));
            }
        }

        reconstructed.truncate(original_len);
        Ok(reconstructed)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_split_and_reconstruct_full() {
        let msg_id = [7u8; 32];
        let original_payload = b"Decentralized zero-metadata post-quantum resilient messaging engine";

        let chunks = ErasureEngine::split(msg_id, original_payload).unwrap();
        assert_eq!(chunks.len(), 5);

        let reconstructed = ErasureEngine::reconstruct(&chunks).unwrap();
        assert_eq!(reconstructed, original_payload);
    }

    #[test]
    fn test_reconstruct_from_any_3_shards() {
        let msg_id = [42u8; 32];
        let original_payload = vec![0xAB; 1000];

        let chunks = ErasureEngine::split(msg_id, &original_payload).unwrap();

        // Try combinations of 3 shards
        let combo_1 = vec![chunks[0].clone(), chunks[2].clone(), chunks[4].clone()];
        assert_eq!(ErasureEngine::reconstruct(&combo_1).unwrap(), original_payload);

        let combo_2 = vec![chunks[1].clone(), chunks[3].clone(), chunks[4].clone()];
        assert_eq!(ErasureEngine::reconstruct(&combo_2).unwrap(), original_payload);

        let combo_3 = vec![chunks[2].clone(), chunks[3].clone(), chunks[0].clone()];
        assert_eq!(ErasureEngine::reconstruct(&combo_3).unwrap(), original_payload);
    }

    #[test]
    fn test_insufficient_shards_fails() {
        let msg_id = [9u8; 32];
        let original_payload = b"Short message";

        let chunks = ErasureEngine::split(msg_id, original_payload).unwrap();
        let insufficient = vec![chunks[0].clone(), chunks[1].clone()];

        let res = ErasureEngine::reconstruct(&insufficient);
        assert!(matches!(res, Err(ErasureError::InsufficientShards { .. })));
    }

    #[test]
    fn test_serialization_roundtrip() {
        let msg_id = [1u8; 32];
        let original_payload = b"Opus voice sample test payload bytes...";

        let chunks = ErasureEngine::split(msg_id, original_payload).unwrap();
        let chunk_bytes = chunks[0].to_bytes().unwrap();
        let restored_chunk = ErasureChunk::from_bytes(&chunk_bytes).unwrap();

        assert_eq!(chunks[0], restored_chunk);
    }
}
