/**
 * Decentralized Anonymous Mailbox Node
 * 
 * - Başladıqda Blockchain-ə qoşulub registerMailbox edir
 * - Bob və ya Alice-in kimliyini bilmir, yalnız deterministik blind token saxlayır
 * - 3-of-5 erasure paylarının 1 hissəsini saxlayır
 * - Yüngül və etibarlı disk saxlancı ilə təmin edilib (heç bir C++ asılılığı yoxdur)
 */

const express = require("express");
const cors = require("cors");
const { ethers } = require("ethers");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

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

const PORT = parseInt(process.env.MAILBOX_PORT || "4000");
const MY_IP = process.env.MY_IP || "127.0.0.1";
const BLOCKCHAIN_RPC = process.env.BLOCKCHAIN_RPC || "http://127.0.0.1:8545";
const CONTRACT_ADDRESS = process.env.CONTRACT_ADDRESS;
const DATA_DIR = process.env.DATA_DIR || path.join(__dirname, "data");

const MY_ENDPOINT = `http://${MY_IP}:${PORT}`;
const NODE_KEYPAIR = crypto.generateKeyPairSync("x25519");
const NODE_PUBKEY_HEX = "0x" + NODE_KEYPAIR.publicKey.export({ type: "spki", format: "der" }).slice(-32).toString("hex");

if (!fs.existsSync(DATA_DIR)) fs.mkdirSync(DATA_DIR, { recursive: true });
const DB_FILE = path.join(DATA_DIR, `shares_${PORT}.json`);

let storage = {};
if (fs.existsSync(DB_FILE)) {
  try {
    storage = JSON.parse(fs.readFileSync(DB_FILE, "utf8"));
  } catch (_) {
    storage = {};
  }
}

function persist() {
  try {
    fs.writeFileSync(DB_FILE, JSON.stringify(storage, null, 2));
  } catch (e) {
    console.error("Storage persist error:", e.message);
  }
}

const TTL_MS = 7 * 24 * 60 * 60 * 1000;

const CONTRACT_ABI = [
  "function registerMailbox(string calldata endpoint, bytes32 pubkey) external"
];

async function registerOnBlockchain() {
  if (!CONTRACT_ADDRESS) {
    console.warn("⚠️ CONTRACT_ADDRESS missing. Standalone mode.");
    return;
  }
  try {
    const provider = new ethers.JsonRpcProvider(BLOCKCHAIN_RPC);
    const signer = await provider.getSigner(0);
    const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

    console.log(`📫 Registering Mailbox [${MY_ENDPOINT}] on Blockchain...`);
    const tx = await contract.registerMailbox(MY_ENDPOINT, NODE_PUBKEY_HEX);
    await tx.wait();
    console.log(`✅ Mailbox registered on-chain: tx ${tx.hash}`);
  } catch (err) {
    console.log(`ℹ️ Mailbox registration notice: ${err.message}`);
  }
}

// ── Store Share ───────────────────────────────────────────────
app.post("/mailbox/store", (req, res) => {
  const { token, shareData, shareIndex } = req.body;
  if (!token || !shareData || shareIndex === undefined) {
    return res.status(400).json({ error: "Missing parameters" });
  }

  const now = Date.now();
  storage[token] = {
    shareData,
    shareIndex,
    createdAt: now,
    expiresAt: now + TTL_MS
  };
  persist();

  console.log(`[Mailbox] Stored share index ${shareIndex} for blind token: ${token.substring(0, 16)}...`);
  res.json({ success: true });
});

// ── Poll Share (Anonymous Bob query) ──────────────────────────
app.get("/mailbox/poll/:token", (req, res) => {
  const { token } = req.params;
  const now = Date.now();
  const item = storage[token];

  if (!item || item.expiresAt < now) {
    return res.status(404).json({ found: false });
  }

  res.json({
    found: true,
    shareData: item.shareData,
    shareIndex: item.shareIndex
  });
});

app.delete("/mailbox/delete/:token", (req, res) => {
  const { token } = req.params;
  if (storage[token]) {
    delete storage[token];
    persist();
  }
  res.json({ success: true });
});

// Client-side liveness check (Variant B)
app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    role: "mailbox",
    endpoint: MY_ENDPOINT,
    activeShares: Object.keys(storage).length,
    uptime: process.uptime()
  });
});

app.listen(PORT, "0.0.0.0", async () => {
  console.log(`📫 Decentralized Mailbox running on port ${PORT}`);
  await registerOnBlockchain();
});
