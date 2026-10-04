/// NewChatScreen — username input for starting a new conversation.
///
/// Separated from HomeScreen so ChatListScreen doesn't carry its own search logic.
library;

import 'package:flutter/material.dart';

class NewChatScreen extends StatefulWidget {
  final String myUsername;
  final void Function(String peer) onStartChat;

  const NewChatScreen({
    super.key,
    required this.myUsername,
    required this.onStartChat,
  });

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _start() {
    final peer = _ctrl.text.trim();
    if (peer.isEmpty || peer == widget.myUsername) return;
    Navigator.of(context).pop();
    widget.onStartChat(peer);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13132B),
        title: const Text('Yeni Söhbət', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'İstifadəçi adı (məs: bob)',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                prefixIcon: const Icon(
                  Icons.alternate_email,
                  color: Color(0xFF6C63FF),
                ),
                filled: true,
                fillColor: const Color(0xFF13132B),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _start(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.arrow_forward, color: Colors.white),
                label: const Text(
                  'Söhbəti Başlat',
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _start,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
