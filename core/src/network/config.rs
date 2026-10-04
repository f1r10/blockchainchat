use serde::{Deserialize, Serialize};

/// Global Network Configuration for Core Rust Library
#[derive(Serialize, Deserialize, Debug, Clone, PartialEq)]
pub struct NetworkConfig {
    /// EVM Blockchain RPC Endpoint (e.g. Arbitrum Sepolia RPC)
    pub evm_rpc_url: String,
    /// Address of deployed CommitmentRegistry contract on EVM
    pub commitment_registry_address: String,
    /// EVM Chain ID (e.g. 421614 for Arbitrum Sepolia, 11155111 for Sepolia)
    pub chain_id: u64,
    /// Public Bootstrap libp2p DHT Multiaddresses for peer lookup
    pub dht_bootstrap_nodes: Vec<String>,
    /// Public Nym Mixnet Gateway Endpoints for Sphinx packet routing
    pub nym_gateway_nodes: Vec<String>,
}

impl Default for NetworkConfig {
    fn default() -> Self {
        Self::arbitrum_sepolia()
    }
}

impl NetworkConfig {
    /// Pre-configured defaults for Arbitrum Sepolia Public Testnet
    pub fn arbitrum_sepolia() -> Self {
        Self {
            evm_rpc_url: "https://sepolia-rollup.arbitrum.io/rpc".into(),
            commitment_registry_address: "0x0000000000000000000000000000000000000000".into(),
            chain_id: 421614,
            dht_bootstrap_nodes: vec![
                "/ip4/198.51.100.10/tcp/4001/p2p/12D3KooWSmX...".into(),
                "/ip4/203.0.113.25/tcp/4001/p2p/12D3KooWAbc...".into(),
            ],
            nym_gateway_nodes: vec![
                "mixnet-gateway-1.testnet.nymtech.net:9001".into(),
                "mixnet-gateway-2.testnet.nymtech.net:9001".into(),
            ],
        }
    }

    /// Pre-configured defaults for Ethereum Sepolia Testnet
    pub fn ethereum_sepolia() -> Self {
        Self {
            evm_rpc_url: "https://rpc.sepolia.org".into(),
            commitment_registry_address: "0x0000000000000000000000000000000000000000".into(),
            chain_id: 11155111,
            dht_bootstrap_nodes: vec![
                "/ip4/198.51.100.10/tcp/4001/p2p/12D3KooWSmX...".into(),
            ],
            nym_gateway_nodes: vec![
                "mixnet-gateway-1.testnet.nymtech.net:9001".into(),
            ],
        }
    }

    /// Localhost configuration for offline development & simulation
    pub fn localhost() -> Self {
        Self {
            evm_rpc_url: "http://127.0.0.1:8545".into(),
            commitment_registry_address: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9".into(),
            chain_id: 31337,
            dht_bootstrap_nodes: vec![
                "/ip4/127.0.0.1/tcp/4001".into(),
            ],
            nym_gateway_nodes: vec![
                "127.0.0.1:9000".into(),
            ],
        }
    }
}
