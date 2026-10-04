use blockchainchat_core::network::surb::SingleUseReplyBlock;
use blockchainchat_core::storage::erasure::ErasureChunk;
use sled::Db;
use serde::{Deserialize, Serialize};
use std::path::Path;
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

pub const DEFAULT_TTL_SECONDS: u64 = 14 * 86400; // 14 days strict TTL

#[allow(dead_code)]
#[derive(Error, Debug)]
pub enum MailboxError {
    #[error("Database error: {0}")]
    DatabaseError(#[from] sled::Error),
    #[error("Serialization error: {0}")]
    SerializationError(String),
    #[error("Chunk not found or expired")]
    ChunkNotFound,
    #[error("Dispatch back to mixnet failed: {0}")]
    DispatchFailed(String),
}

/// Record stored in local Mailbox storage with timestamp and TTL
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct StoredMailboxEntry {
    pub surb_id: [u8; 16],
    pub chunk: ErasureChunk,
    pub stored_at_sec: u64,
    pub ttl_sec: u64,
}

/// Anonymous SURB-based pull request payload from Bob
#[allow(dead_code)]
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct PullRequestPayload {
    pub target_surb_id: [u8; 16],
    pub reply_surb: SingleUseReplyBlock,
}

/// Decentralized Mailbox Storage Engine
pub struct MailboxEngine {
    db: Db,
    ttl_duration: u64,
}

impl MailboxEngine {
    /// Initialize Mailbox storage node using sled KV store
    pub fn new<P: AsRef<Path>>(db_path: P, ttl_seconds: Option<u64>) -> Result<Self, MailboxError> {
        let db = sled::open(db_path)?;
        let ttl_duration = ttl_seconds.unwrap_or(DEFAULT_TTL_SECONDS);

        let engine = Self { db, ttl_duration };
        Ok(engine)
    }

    /// Anonymous Push: Store incoming ErasureChunk under its SURB identifier.
    /// Zero metadata: No sender IP, no sender identity, and no metadata logs are retained.
    pub fn push_chunk(&self, surb_id: [u8; 16], chunk: ErasureChunk) -> Result<(), MailboxError> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let entry = StoredMailboxEntry {
            surb_id,
            chunk,
            stored_at_sec: now,
            ttl_sec: self.ttl_duration,
        };

        let encoded = bincode::serialize(&entry)
            .map_err(|e| MailboxError::SerializationError(e.to_string()))?;

        // Write chunk into sled database under SURB ID key
        self.db.insert(&surb_id, encoded)?;
        self.db.flush()?;

        Ok(())
    }

    /// Anonymous Pull: Receive SURB pull request from Bob, retrieve chunk, and IMMEDIATELY delete from storage.
    pub fn pull_and_delete(&self, surb_id: &[u8; 16]) -> Result<ErasureChunk, MailboxError> {
        let raw_bytes = self.db.remove(surb_id)?.ok_or(MailboxError::ChunkNotFound)?;
        self.db.flush()?;

        let entry: StoredMailboxEntry = bincode::deserialize(&raw_bytes)
            .map_err(|e| MailboxError::SerializationError(e.to_string()))?;

        // Check TTL expiration
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        if now > entry.stored_at_sec + entry.ttl_sec {
            return Err(MailboxError::ChunkNotFound);
        }

        Ok(entry.chunk)
    }

    /// Background task: Purge expired chunks that exceed the 14-day TTL limit.
    pub fn purge_expired(&self) -> Result<usize, MailboxError> {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs();

        let mut purged_count = 0;
        let mut keys_to_delete = Vec::new();

        for item in self.db.iter() {
            let (key, value) = item?;
            if let Ok(entry) = bincode::deserialize::<StoredMailboxEntry>(&value) {
                if now > entry.stored_at_sec + entry.ttl_sec {
                    keys_to_delete.push(key);
                }
            }
        }

        for key in keys_to_delete {
            self.db.remove(key)?;
            purged_count += 1;
        }

        if purged_count > 0 {
            self.db.flush()?;
        }

        Ok(purged_count)
    }

    /// Get total stored chunk count in Mailbox storage node
    #[allow(dead_code)]
    pub fn count(&self) -> usize {
        self.db.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use blockchainchat_core::storage::erasure::ErasureEngine;

    #[test]
    fn test_mailbox_push_pull_delete_lifecycle() {
        let temp_dir = tempfile::tempdir().unwrap();
        let mailbox = MailboxEngine::new(temp_dir.path(), Some(3600)).unwrap();

        let msg_id = [99u8; 32];
        let payload = b"E2E Encrypted Opus audio/text payload";
        let chunks = ErasureEngine::split(msg_id, payload).unwrap();

        let surb_id = [77u8; 16];
        mailbox.push_chunk(surb_id, chunks[0].clone()).unwrap();
        assert_eq!(mailbox.count(), 1);

        // Anonymous pull returns chunk and immediately deletes from sled database
        let pulled_chunk = mailbox.pull_and_delete(&surb_id).unwrap();
        assert_eq!(pulled_chunk, chunks[0]);

        // Second pull fails (chunk permanently deleted)
        let second_pull = mailbox.pull_and_delete(&surb_id);
        assert!(matches!(second_pull, Err(MailboxError::ChunkNotFound)));
        assert_eq!(mailbox.count(), 0);
    }

    #[test]
    fn test_mailbox_ttl_purge() {
        let temp_dir = tempfile::tempdir().unwrap();
        // 0 second TTL for instant expiration testing
        let mailbox = MailboxEngine::new(temp_dir.path(), Some(0)).unwrap();

        let msg_id = [12u8; 32];
        let chunks = ErasureEngine::split(msg_id, b"Expiring payload").unwrap();
        let surb_id = [11u8; 16];

        mailbox.push_chunk(surb_id, chunks[0].clone()).unwrap();
        std::thread::sleep(std::time::Duration::from_millis(10));

        let purged = mailbox.purge_expired().unwrap();
        assert_eq!(purged, 1);
        assert_eq!(mailbox.count(), 0);
    }
}
