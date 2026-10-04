mod dht;
mod mailbox;

use dht::{DhtNode, RendezvousDhtRecord};
use mailbox::MailboxEngine;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;
use tracing::{info, warn};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    info!("Starting Decentralized Validator Mailbox & DHT Node...");

    let db_path = PathBuf::from("./validator_mailbox_db");
    let mailbox = Arc::new(MailboxEngine::new(db_path, None)?);
    info!("Mailbox sled engine initialized (14-day auto-purge TTL enabled).");

    let dht_node = Arc::new(DhtNode::new()?);
    info!("libp2p Kademlia DHT Node initialized. PeerId: {}", dht_node.peer_id());

    // Task 1: Background Purge Task (Purges stale chunks older than 14 days every 1 hour)
    let mailbox_purge_handle = Arc::clone(&mailbox);
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(Duration::from_secs(3600));
        loop {
            interval.tick().await;
            match mailbox_purge_handle.purge_expired() {
                Ok(count) if count > 0 => info!("Purged {} expired chunks from Mailbox storage.", count),
                Ok(_) => {},
                Err(e) => warn!("Mailbox TTL purge background task error: {}", e),
            }
        }
    });

    // Task 2: libp2p Kademlia DHT Event & Query Loop
    let dht_handle = Arc::clone(&dht_node);
    tokio::spawn(async move {
        let mut dht_channel_rx = tokio::sync::mpsc::channel::<(bool, [u8; 32], Option<RendezvousDhtRecord>)>(100).1;
        while let Some((is_put, commitment, record_opt)) = dht_channel_rx.recv().await {
            if is_put {
                if let Some(rec) = record_opt {
                    let _ = dht_handle.put_record(rec).await;
                }
            } else {
                let _ = dht_handle.get_record(&commitment).await;
            }
        }
    });

    // Task 3: Nym Mixnet Receiver Loop (Sphinx packet handling)
    let mailbox_mixnet_handle = Arc::clone(&mailbox);
    tokio::spawn(async move {
        let mut mixnet_rx = tokio::sync::mpsc::channel::<(bool, [u8; 16], Option<blockchainchat_core::storage::erasure::ErasureChunk>)>(100).1;
        while let Some((is_push, surb_id, chunk_opt)) = mixnet_rx.recv().await {
            if is_push {
                if let Some(chunk) = chunk_opt {
                    if let Err(e) = mailbox_mixnet_handle.push_chunk(surb_id, chunk) {
                        warn!("Anonymous push chunk error: {}", e);
                    }
                }
            } else {
                // Anonymous pull request from Bob via SURB
                match mailbox_mixnet_handle.pull_and_delete(&surb_id) {
                    Ok(_chunk) => {
                        info!("Pulled chunk for SURB {:?}, deleted from storage.", surb_id);
                    }
                    Err(e) => warn!("Anonymous pull chunk error: {}", e),
                }
            }
        }
    });

    info!("Validator running with active async event loops and zero IP logging.");

    // Keep node running until CTRL+C signal
    tokio::signal::ctrl_c().await?;
    info!("Shutting down validator node cleanly...");

    Ok(())
}
