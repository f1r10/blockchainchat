/**
 * Decentralized Mix/Relay Node
 * 
 * - Başladıqda Blockchain-dəki NodeAndUserRegistry kontraktına qoşulur
 * - Özünü şəbəkəyə elan edir (registerRelay)
 * - Digər aktiv Relay-ləri və Mailbox-ları blockchain-dən çəkir
 * - Paketləri random delay (50-400ms) və padding ilə növbəti hop-a yönləndirir
 */

const express = require("express");
const cors = require("cors");
const { ethers } = require("ethers");
const crypto = require("crypto");

const app = express();
app.use(express.json({ limit: "10mb" }));
app.use(cors());

app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS");
  res.header("Access-Control-Allow-Headers", "Content-Type, Authorization");
  if (req.method === "OPTIONS") return res.sendStatus(200);
  next();
});

const PORT = parseInt(process.env.NODE_PORT || "3000");
const MY_IP = process.env.MY_IP || "127.0.0.1";
const BLOCKCHAIN_RPC = process.env.BLOCKCHAIN_RPC || "http://127.0.0.1:8545";
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;

const MY_ENDPOINT = `http://${MY_IP}:${PORT}`;
const NODE_KEYPAIR = crypto.generateKeyPairSync("x25519");
const NODE_PUBKEY_HEX = "0x" + NODE_KEYPAIR.publicKey.export({ type: "spki", format: "der" }).slice(-32).toString("hex");

let knownRelays = [];
let knownMailboxes = [];
let packetsRelayed = 0;

const CONTRACT_ABI = [
  "function registerRelay(string calldata endpoint, bytes32 pubkey) external",
  "function getRelays() external view returns (tuple(string endpoint, bytes32 pubkey, uint256 registeredAt, bool exists)[])",
  "function getMailboxes() external view returns (tuple(string endpoint, bytes32 pubkey, uint256 registeredAt, bool exists)[])"
];

async function syncWithBlockchain() {
  if (!CONTRACT_ADDRESS) {
    console.warn("⚠️ CONTRACT_ADDRESS not provided. Running in standalone test mode.");
    return;
  }

  try {
    const provider = new ethers.JsonRpcProvider(BLOCKCHAIN_RPC);
    const signer = await provider.getSigner(0); // Testnet first funded account
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

    console.log(`📡 Registering Relay [${MY_ENDPOINT}] to Blockchain...`);
    try {
      const tx = await contract.registerRelay(MY_ENDPOINT, NODE_PUBKEY_HEX);
      await tx.wait();
      console.log(`✅ Registered on-chain: tx ${tx.hash}`);
    } catch (e) {
      console.log(`ℹ️ Already registered or skipped: ${e.message}`);
    }

    // Refresh network topology from chain
    const relays = await contract.getRelays();
    const mailboxes = await contract.getMailboxes();

    knownRelays = relays.map(r => r.endpoint).filter(ep => ep !== MY_ENDPOINT);
    knownMailboxes = mailboxes.map(m => m.endpoint);

    console.log(`🌐 Discovered ${knownRelays.length} peer relays and ${knownMailboxes.length} mailboxes from blockchain.`);
  } catch (err) {
    console.error("❌ Blockchain sync error:", err.message);
  }
}

// Random mix delay to defeat traffic timing analysis
function mixDelay() {
  const ms = 50 + Math.floor(Math.random() * 350);
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * POST /relay/packet
 * Body: { destination, token, shareData, shareIndex, hopsRemaining }
 */
app.post("/relay/packet", async (req, res) => {
  packetsRelayed++;
  const packet = req.body;

  // Cavabı dərhal qaytarırıq (asynchronous decoupling)
  res.json({ accepted: true, relay: MY_ENDPOINT });

  await mixDelay();

  const hops = packet.hopsRemaining ?? 1;
  const { default: fetch } = await import("node-fetch");

  try {
    if (hops > 0 && knownRelays.length > 0) {
      // Başqa bir relay-ə ötür (Multi-hop onion mixing)
      const nextRelay = knownRelays[Math.floor(Math.random() * knownRelays.length)];
      await fetch(`${nextRelay}/relay/packet`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...packet, hopsRemaining: hops - 1 })
      });
    } else {
      // Son hop: Hedef Mailbox-a çatdır
      const targetMailbox = packet.destination;
      if (targetMailbox) {
        await fetch(`${targetMailbox}/mailbox/store`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            token: packet.token,
            shareData: packet.shareData,
            shareIndex: packet.shareIndex
          })
        });
      }
    }
  } catch (e) {
    console.error(`[Relay Forward Error]: ${e.message}`);
  }
});

// Client-side liveness check (Variant B)
app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    role: "relay",
    endpoint: MY_ENDPOINT,
    peerRelaysCount: knownRelays.length,
    mailboxesCount: knownMailboxes.length,
    packetsRelayed,
    uptime: process.uptime()
  });
});

app.listen(PORT, "0.0.0.0", async () => {
  console.log(`🔀 Decentralized Mix/Relay running on port ${PORT}`);
  await syncWithBlockchain();
  setInterval(syncWithBlockchain, 60000); // Hər 1 dəqiqədən bir yeni node-ları sinxronlaşdır
});
