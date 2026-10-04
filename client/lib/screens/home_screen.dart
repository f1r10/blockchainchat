import 'dart:async';
import 'package:flutter/material.dart';
import '../services/blockchain_discovery.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  final String username;
  const HomeScreen({super.key, required this.username});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchCtrl = TextEditingController();
  final _blockchainService = DecentralizedBlockchainService();
  Timer? _refreshTimer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _refreshTopology();
    _refreshTimer = Timer.periodic(const Duration(seconds: 8), (_) => _refreshTopology());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshTopology() async {
    if (_refreshing) return;
    _refreshing = true;
    await _blockchainService.refreshNetworkTopology();
    if (mounted) setState(() => _refreshing = false);
  }

  void _startChat(String peer) {
    final target = peer.trim();
    if (target.isEmpty || target == widget.username) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          myUsername: widget.username,
          peerUsername: target,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aliveRelays = _blockchainService.discoveredRelays.where((r) => r.isAlive).length;
    final totalRelays = _blockchainService.discoveredRelays.length;
    final aliveMailboxes = _blockchainService.discoveredMailboxes.where((m) => m.isAlive).length;
    final totalMailboxes = _blockchainService.discoveredMailboxes.length;

    final isNetworkReady = aliveMailboxes >= 3;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13132B),
        title: Row(
          children: [
            const Icon(Icons.security, color: Color(0xFF6C63FF), size: 20),
            const SizedBox(width: 8),
            Text('@${widget.username}', style: const TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF3ECFCF)),
            onPressed: _refreshTopology,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Topologiya Status Kartı
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF13132B),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isNetworkReady ? const Color(0xFF1E824C) : Colors.redAccent.withOpacity(0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isNetworkReady ? Colors.greenAccent : Colors.redAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isNetworkReady ? "P2P Overlay Hazırdır" : "Gözlənilir (3+ Mailbox lazımdır)",
                            style: TextStyle(
                              color: isNetworkReady ? Colors.greenAccent : Colors.redAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        "Variant B",
                        style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _StatColumn(label: "Mix Relays", value: "$aliveRelays / $totalRelays"),
                      _StatColumn(label: "3-of-5 Mailboxes", value: "$aliveMailboxes / $totalMailboxes"),
                      _StatColumn(label: "Topology", value: "Decentralized"),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Söhbət Başlatma
            const Text(
              "Yeni Söhbət Başlat",
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "İstifadəçi adı (məs: bob)",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                      prefixIcon: const Icon(Icons.alternate_email, color: Color(0xFF6C63FF)),
                      filled: true,
                      fillColor: const Color(0xFF13132B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: _startChat,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => _startChat(_searchCtrl.text),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    padding: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Icon(Icons.arrow_forward, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // Aktiv Maşınlar / Node Siyahısı
            const Text(
              "Aşkar Edilmiş Node-lar (Blockchain)",
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            if (_blockchainService.discoveredRelays.isEmpty && _blockchainService.discoveredMailboxes.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF13132B),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Hələ heç bir node qeydiyyatdan keçməyib. Relay və Mailbox skriptlərini işə salın.",
                  style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
                ),
              ),

            ..._blockchainService.discoveredRelays.map((r) => _NodeTile(node: r)),
            ..._blockchainService.discoveredMailboxes.map((m) => _NodeTile(node: m)),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
      ],
    );
  }
}

class _NodeTile extends StatelessWidget {
  final ActiveNode node;
  const _NodeTile({required this.node});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF13132B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                node.role == 'relay' ? Icons.shuffle : Icons.markunread_mailbox_outlined,
                color: const Color(0xFF6C63FF),
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                node.endpoint,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFamily: 'monospace'),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: node.isAlive ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              node.isAlive ? "ONLINE" : "OFFLINE",
              style: TextStyle(
                color: node.isAlive ? Colors.greenAccent : Colors.redAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        ],
      ),
    );
  }
}
