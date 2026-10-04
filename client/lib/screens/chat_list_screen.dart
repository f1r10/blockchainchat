/// ChatListScreen — Conversation list with global pull-to-refresh sync trigger.
///
/// Sync policy (strictly enforced):
///  • Pull-to-refresh: user swipes down → calls `sync_messages()` once → done.
///  • AppLifecycle.resumed: handled globally by AppLifecycleObserver.
///  • No timers, no periodic polling in this widget.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/sync_provider.dart';
import 'new_chat_screen.dart';
import 'chat_screen.dart';
import 'onboarding_screen.dart';

class ChatListScreen extends ConsumerStatefulWidget {
  final String username;
  const ChatListScreen({super.key, required this.username});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen>
    with WidgetsBindingObserver {

  late final AppLifecycleObserver _lifecycleObserver;

  @override
  void initState() {
    super.initState();
    // Register foreground-resume sync hook
    _lifecycleObserver = AppLifecycleObserver(ref);
    WidgetsBinding.instance.addObserver(_lifecycleObserver);

    // One initial sync on first load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncProvider.notifier).sync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleObserver);
    super.dispose();
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const OnboardingScreen()),
    );
  }

  void _openChat(String peer) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          myUsername: widget.username,
          peerUsername: peer,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final syncState = ref.watch(syncProvider);
    final peersAsync = ref.watch(conversationPeersProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13132B),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                ),
              ),
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 10),
            Text(
              '@${widget.username}',
              style: const TextStyle(color: Colors.white, fontSize: 17),
            ),
          ],
        ),
        actions: [
          // Sync status indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _SyncBadge(syncState: syncState),
          ),
          // New chat
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF6C63FF)),
            tooltip: 'Yeni söhbət',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => NewChatScreen(
                  myUsername: widget.username,
                  onStartChat: _openChat,
                ),
              ),
            ),
          ),
          // Logout
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white.withOpacity(0.4)),
            tooltip: 'Çıxış',
            onPressed: _logout,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF6C63FF),
        backgroundColor: const Color(0xFF13132B),
        // Pull-to-refresh is the manual sync trigger
        onRefresh: () => ref.read(syncProvider.notifier).sync(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Security info banner ────────────────────────────────────────
            SliverToBoxAdapter(
              child: _SecurityBanner(lastSync: syncState.lastSync),
            ),

            // ── Conversation list ────────────────────────────────────────────
            peersAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
                ),
              ),
              error: (e, _) => SliverFillRemaining(
                child: _EmptyState(error: e.toString()),
              ),
              data: (peers) {
                if (peers.isEmpty) {
                  return SliverFillRemaining(
                    child: _EmptyState(
                      hint: 'Hələ heç bir söhbət yoxdur.\n'
                          'Sağ yuxarıdakı + düyməsini basın.',
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _ConversationTile(
                      peer: peers[i],
                      onTap: () => _openChat(peers[i]),
                    ),
                    childCount: peers.length,
                  ),
                );
              },
            ),
          ],
        ),
      ),

      // Floating action button — same as the + in the AppBar but more visible
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF6C63FF),
        child: const Icon(Icons.add, color: Colors.white),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => NewChatScreen(
              myUsername: widget.username,
              onStartChat: _openChat,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SecurityBanner extends StatelessWidget {
  final DateTime? lastSync;
  const _SecurityBanner({this.lastSync});

  @override
  Widget build(BuildContext context) {
    final syncText = lastSync == null
        ? 'Hələ sinxronizasiya edilməyib'
        : 'Son pull: ${_fmt(lastSync!)}';

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0C1F0F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E824C).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock, color: Colors.greenAccent, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PQXDH · Double Ratchet · 3-of-5 Mixnet · Sıfır metadata',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  syncText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.4),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmt(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'indi';
    if (diff.inMinutes < 60) return '${diff.inMinutes}d əvvəl';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SyncBadge extends StatelessWidget {
  final SyncState syncState;
  const _SyncBadge({required this.syncState});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: switch (syncState.status) {
        SyncStatus.syncing => const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Color(0xFF3ECFCF),
            ),
          ),
        SyncStatus.done => syncState.newMessageCount > 0
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C63FF),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '+${syncState.newMessageCount}',
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              )
            : const Icon(Icons.check_circle_outline,
                color: Colors.greenAccent, size: 18),
        SyncStatus.error => const Icon(Icons.error_outline,
            color: Colors.redAccent, size: 18),
        SyncStatus.idle => const SizedBox.shrink(),
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final String peer;
  final VoidCallback onTap;
  const _ConversationTile({required this.peer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF13132B),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFF6C63FF).withOpacity(0.2),
              child: Text(
                peer.isNotEmpty ? peer[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Color(0xFF6C63FF),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@$peer',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 3),
                  const Text(
                    'Blind Token · 3-of-5 Mix',
                    style: TextStyle(color: Color(0xFF3ECFCF), fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF6C63FF),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String? hint;
  final String? error;
  const _EmptyState({this.hint, this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              error != null ? Icons.error_outline : Icons.chat_bubble_outline,
              color: Colors.white.withOpacity(0.2),
              size: 52,
            ),
            const SizedBox(height: 16),
            Text(
              error ?? hint ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
