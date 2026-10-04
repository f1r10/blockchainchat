use rand::RngCore;
use serde::{Deserialize, Serialize};
use thiserror::Error;

pub const DEFAULT_FRAME_SIZE: usize = 2048; // 2 KB standard Nym mixnet payload block

#[derive(Error, Debug, PartialEq, Eq)]
pub enum FrameError {
    #[error("Payload exceeds maximum target frame size {target_size} bytes (got {payload_size} bytes)")]
    PayloadExceedsFrameSize { payload_size: usize, target_size: usize },
    #[error("Invalid frame structure: frame smaller than 4-byte header")]
    InvalidFrameSize,
    #[error("Corrupted frame padding or length header")]
    CorruptedFrameHeader,
    #[error("Serialization error: {0}")]
    SerializationError(String),
}

#[repr(u8)]
#[derive(Serialize, Deserialize, Debug, Clone, Copy, PartialEq, Eq)]
pub enum PayloadType {
    Text = 0,
    OpusAudio = 1,
    ControlAck = 2,
}

#[derive(Serialize, Deserialize, Debug, Clone, PartialEq, Eq)]
pub struct MessageContent {
    pub payload_type: PayloadType,
    pub timestamp_epoch_sec: u64,
    pub data: Vec<u8>,
}

pub struct FramePacker;

impl FramePacker {
    /// Packs message content and adds cryptographic random padding up to exact `target_frame_size`.
    pub fn pack(content: &MessageContent, target_frame_size: usize) -> Result<Vec<u8>, FrameError> {
        let serialized = bincode::serialize(content)
            .map_err(|e| FrameError::SerializationError(e.to_string()))?;

        let payload_len = serialized.len();
        // 4 bytes for length prefix + payload_len
        let required_size = 4 + payload_len;

        if required_size > target_frame_size {
            return Err(FrameError::PayloadExceedsFrameSize {
                payload_size: required_size,
                target_size: target_frame_size,
            });
        }

        let mut frame = vec![0u8; target_frame_size];
        // 1. Store payload length prefix in first 4 bytes (Big Endian)
        let len_bytes = (payload_len as u32).to_be_bytes();
        frame[0..4].copy_from_slice(&len_bytes);

        // 2. Copy serialized payload content
        frame[4..4 + payload_len].copy_from_slice(&serialized);

        // 3. Fill remaining trailing bytes with cryptographically secure random padding
        if target_frame_size > required_size {
            rand::thread_rng().fill_bytes(&mut frame[required_size..target_frame_size]);
        }

        Ok(frame)
    }

    /// Unpacks padded fixed-size frame back into structured MessageContent.
    pub fn unpack(frame: &[u8]) -> Result<MessageContent, FrameError> {
        if frame.len() < 4 {
            return Err(FrameError::InvalidFrameSize);
        }

        let mut len_bytes = [0u8; 4];
        len_bytes.copy_from_slice(&frame[0..4]);
        let payload_len = u32::from_be_bytes(len_bytes) as usize;

        if 4 + payload_len > frame.len() {
            return Err(FrameError::CorruptedFrameHeader);
        }

        let payload_bytes = &frame[4..4 + payload_len];
        let content: MessageContent = bincode::deserialize(payload_bytes)
            .map_err(|e| FrameError::SerializationError(e.to_string()))?;

        Ok(content)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_frame_padding_fixed_length() {
        let msg = MessageContent {
            payload_type: PayloadType::Text,
            timestamp_epoch_sec: 1700000000,
            data: b"Zero metadata, zero tracking.".to_vec(),
        };

        let target_size = DEFAULT_FRAME_SIZE;
        let frame = FramePacker::pack(&msg, target_size).unwrap();

        // Exact size match guaranteeing no side-channel leakage
        assert_eq!(frame.len(), target_size);

        let restored = FramePacker::unpack(&frame).unwrap();
        assert_eq!(restored, msg);
    }

    #[test]
    fn test_frame_exceeds_size_returns_error() {
        let msg = MessageContent {
            payload_type: PayloadType::OpusAudio,
            timestamp_epoch_sec: 1700000000,
            data: vec![0xFF; 3000],
        };

        let res = FramePacker::pack(&msg, 1024);
        assert!(matches!(res, Err(FrameError::PayloadExceedsFrameSize { .. })));
    }
}
