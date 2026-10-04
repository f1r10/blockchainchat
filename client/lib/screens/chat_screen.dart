/// ChatScreen — Messaging UI.
///
/// Send flow:  RustBridge.sendMessage() → sqflite insert → local UI update.
/// Receive flow: RustBridge.syncMessages() → sqflite insert → Riverpod rebuild.
///
/// Strictly zero background polling. The conversationProvider is a FutureProvider
/// that re-fetches from sqflite whenever the global syncProvider state changes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/rust_bridge.dart';
import '../core/message_db.dart';
import '../providers/sync_provider.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String myUsername;
  final String peerUsername;

  const ChatScreen({
    super.key,
    required this.myUsername,
    required this.peerUsername,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _textCtrl.clear();

    try {
      // 1. Call Rust: PQXDH → Ratchet → 2KB frame → RS chunks → Nym mixnet
      final result = await RustBridge.sendMessage(
        recipientUsername: widget.peerUsername,
        plaintext: text,
      );

      // 2. Persist to local sqflite for history
      await MessageDb.instance.insertSent(
        messageId: result.messageIdHex,
        peerUsername: widget.peerUsername,
        text: text,
      );

      // 3. Invalidate conversation so the UI rebuilds from DB
      ref.invalidate(conversationProvider(widget.peerUsername));

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Göndərmə xətası: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Manual pull ───────────────────────────────────────────────────────────

  Future<void> _manualSync() async {
    await ref
        .read(syncProvider.notifier)
        .sync(currentPeer: widget.peerUsername);
    // conversationProvider rebuilds automatically because it watches syncProvider
    _scrollToBottom();
  }

  // ── Scroll ────────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    final msgsAsync = ref.watch(conversationProvider(widget.peerUsername));

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13132B),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF6C63FF),
              radius: 18,
              child: Text(
                widget.peerUsername.isNotEmpty
                    ? widget.peerUsername[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${widget.peerUsername}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const Text(
                  'Blind Token · 3-of-5 Mix · Nym Mixnet',
                  style: TextStyle(color: Color(0xFF3ECFCF), fontSize: 10),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Manual pull button
          IconButton(
            icon: syncState.status == SyncStatus.syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF3ECFCF),
                    ),
                  )
                : const Icon(Icons.download_outlined, color: Color(0xFF3ECFCF)),
            tooltip: 'Mesajları çək',
            onPressed:
                syncState.status == SyncStatus.syncing ? null : _manualSync,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── E2E security banner ─────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            color: const Color(0xFF0C241B),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock, color: Colors.greenAccent, size: 13),
                SizedBox(width: 6),
                Text(
                  'E2E Ratchet + PQXDH + 3-of-5 Mailbox aktiv',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                ),
              ],
            ),
          ),

          // ── Message list ────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: const Color(0xFF6C63FF),
              backgroundColor: const Color(0xFF13132B),
              onRefresh: _manualSync,
              child: msgsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                ),
                error: (e, _) => Center(
                  child: Text(
                    'Xəta: $e',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
                data: (msgs) {
                  if (msgs.isEmpty) {
                    return ListView(
                      // Needed for RefreshIndicator to work on empty list
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.4,
                          child: Center(
                            child: Text(
                              'Hələ heç bir mesaj yoxdur.\n'
                              'İlk şifrəli paketi göndərin!',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _scrollToBottom());
                  return ListView.builder(
                    controller: _scrollCtrl,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) => _ChatBubble(message: msgs[i]),
                  );
                },
              ),
            ),
          ),

          // ── Input bar ───────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            color: const Color(0xFF13132B),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textCtrl,
                      style: const TextStyle(color: Colors.white),
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: 'Anonim mesaj yazın...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.3),
                        ),
                        filled: true,
                        fillColor: const Color(0xFF1A1A35),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _sending
                            ? null
                            : const LinearGradient(
                                colors: [
                                  Color(0xFF6C63FF),
                                  Color(0xFF3ECFCF),
                                ],
                              ),
                        color: _sending ? const Color(0xFF2A2A4A) : null,
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat Bubble ──────────────────────────────────────────────────────────────

class _ChatBubble extends StatelessWidget {
  final MessageRecord message;
  const _ChatBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final time = DateTime.fromMillisecondsSinceEpoch(message.timestampMs);

    return Align(
      alignment:
          message.isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: message.isMine
              ? const Color(0xFF6C63FF)
              : const Color(0xFF1E1E3A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(message.isMine ? 14 : 4),
            bottomRight: Radius.circular(message.isMine ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${time.hour.toString().padLeft(2, '0')}:'
                  '${time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 10,
                  ),
                ),
                if (message.isMine) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.done_all,
                    size: 12,
                    color: Colors.white.withOpacity(0.5),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
