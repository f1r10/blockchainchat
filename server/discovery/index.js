/**
 * Discovery Server
 * 
 * Bu server:
 * - Username → rendezvous token mapping saxlayır (RAM-da, proto üçün)
 * - Relay node-larını qeydiyyatdan keçirir
 * - Mailbox node-larını qeydiyyatdan keçirir
 * - /health endpoint-i təqdim edir
 * 
 * Production-da: OPRF + DHT + anonymous lookup olacaq.
 * Prototip üçün: sadə REST API.
 */

const express = require("express");
const cors = require("cors");
const crypto = require("crypto");

const app = express();
app.use(express.json());
app.use(cors());

const PORT = process.env.PORT || 5000;

// ── In-memory stores (prototip üçün) ──────────────────────────
// Production-da: OPRF-based anonymous lookup
const userDirectory = new Map();   // usernameHash → {prekeys, mailboxes, updatedAt}
const relayNodes = new Map();      // nodeId → {url, lastSeen}
const mailboxNodes = new Map();    // nodeId → {url, lastSeen}

// ── Username Registration ──────────────────────────────────────

/**
 * POST /api/register
 * Body: { usernameHash, prekeys: [...], mailboxes: [...] }
 * 
 * usernameHash = client tərəfdən hash edilmiş username
 * (real username bu server-ə gəlmir — prototip mərhələsi istisna)
 */
app.post("/api/register", (req, res) => {
  const { usernameHash, prekeys, mailboxes } = req.body;

  if (!usernameHash || !prekeys || !mailboxes) {
    return res.status(400).json({ error: "Missing fields" });
  }

  userDirectory.set(usernameHash, {
    prekeys,
    mailboxes,
    updatedAt: Date.now(),
  });

  console.log(`[Discovery] Registered: ${usernameHash.substring(0, 16)}...`);
  res.json({ success: true, epoch: 1 });
});

/**
 * GET /api/lookup/:usernameHash
 * 
 * Cavab: { prekeys, mailboxes }
 * 
 * Production-da bu endpoint OPRF üzərindən işləyəcək:
 * client username-i blind edir, server blinded response verir.
 */
app.get("/api/lookup/:usernameHash", (req, res) => {
  const { usernameHash } = req.params;
  const record = userDirectory.get(usernameHash);

  if (!record) {
    return res.status(404).json({ error: "Username not found" });
  }

  // One-time prekey götür
  const prekey = record.prekeys.shift() || record.prekeys[0];

  res.json({
    prekey,
    mailboxes: record.mailboxes,
    updatedAt: record.updatedAt,
  });
});

// ── Node Registration ──────────────────────────────────────────

app.post("/api/nodes/relay/register", (req, res) => {
  const { nodeId, url } = req.body;
  if (!nodeId || !url) return res.status(400).json({ error: "Missing fields" });

  relayNodes.set(nodeId, { url, lastSeen: Date.now() });
  console.log(`[Discovery] Relay registered: ${nodeId} @ ${url}`);
  res.json({ success: true });
});

app.post("/api/nodes/mailbox/register", (req, res) => {
  const { nodeId, url } = req.body;
  if (!nodeId || !url) return res.status(400).json({ error: "Missing fields" });

  mailboxNodes.set(nodeId, { url, lastSeen: Date.now() });
  console.log(`[Discovery] Mailbox registered: ${nodeId} @ ${url}`);
  res.json({ success: true });
});

// ── Node Discovery ─────────────────────────────────────────────

app.get("/api/nodes/relays", (_req, res) => {
  const now = Date.now();
  const alive = [...relayNodes.values()].filter(
    (n) => now - n.lastSeen < 60_000
  );
  res.json({ relays: alive });
});

app.get("/api/nodes/mailboxes", (_req, res) => {
  const now = Date.now();
  const alive = [...mailboxNodes.values()].filter(
    (n) => now - n.lastSeen < 60_000
  );
  res.json({ mailboxes: alive });
});

// ── Heartbeat ──────────────────────────────────────────────────

app.post("/api/nodes/heartbeat", (req, res) => {
  const { nodeId, type } = req.body;
  const store = type === "relay" ? relayNodes : mailboxNodes;
  const node = store.get(nodeId);
  if (node) {
    node.lastSeen = Date.now();
    store.set(nodeId, node);
  }
  res.json({ success: true, timestamp: Date.now() });
});

// ── Health ─────────────────────────────────────────────────────

app.get("/health", (_req, res) => {
  res.json({
    status: "ok",
    users: userDirectory.size,
    relays: relayNodes.size,
    mailboxes: mailboxNodes.size,
    uptime: process.uptime(),
  });
});

app.get("/api/config", (_req, res) => {
  res.json({
    chainId: 31337,
    blockchainRpc: process.env.BLOCKCHAIN_RPC || "http://localhost:8545",
    version: "0.1.0-proto",
  });
});

// ── Start ──────────────────────────────────────────────────────

app.listen(PORT, "0.0.0.0", () => {
  console.log(`🔍 Discovery server running on port ${PORT}`);
});
