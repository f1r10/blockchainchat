/// SyncProvider — Riverpod state management for the pull-based sync engine.
///
/// Design constraints (strictly enforced):
///  • Zero background loops — sync is triggered ONLY on foreground resume or
///    explicit "pull to refresh" gesture. Never scheduled with timers.
///  • No FCM / WorkManager / APNs — pull only.
///  • AppLifecycleState.resumed is the single automatic trigger.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/rust_bridge.dart';
import '../core/message_db.dart';

// ─── Sync Status ─────────────────────────────────────────────────────────────

enum SyncStatus { idle, syncing, done, error }

class SyncState {
  final SyncStatus status;
  final int newMessageCount;
  final String? errorMessage;
  final DateTime? lastSync;

  const SyncState({
    this.status = SyncStatus.idle,
    this.newMessageCount = 0,
    this.errorMessage,
    this.lastSync,
  });

  SyncState copyWith({
    SyncStatus? status,
    int? newMessageCount,
    String? errorMessage,
    DateTime? lastSync,
  }) =>
      SyncState(
        status: status ?? this.status,
        newMessageCount: newMessageCount ?? this.newMessageCount,
        errorMessage: errorMessage ?? this.errorMessage,
        lastSync: lastSync ?? this.lastSync,
      );
}

// ─── Sync Notifier ────────────────────────────────────────────────────────────

class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier() : super(const SyncState());

  bool _running = false;

  /// Execute one-shot sync cycle:
  ///   1. Call Rust `sync_messages()` — pulls Mailboxes via SURB, decrypts.
  ///   2. Persist each DecryptedMessage into local sqflite MessageDb.
  ///   3. Update UI state.
  ///
  /// Re-entrant safe: ignores concurrent calls while already running.
  Future<void> sync({String? currentPeer}) async {
    if (_running) return;
    _running = true;
    state = state.copyWith(status: SyncStatus.syncing, newMessageCount: 0);

    try {
      final messages = await RustBridge.syncMessages();
      int inserted = 0;

      for (final msg in messages) {
        if (msg.isVoice) continue; // voice handling future work

        // Derive sender from context (Rust will embed this in the frame header
        // once the full DHT lookup is wired in — stub uses "unknown" for now).
        const sender = 'unknown';

        await MessageDb.instance.insertReceived(
          messageId: msg.messageIdHex,
          peerUsername: currentPeer ?? sender,
          text: msg.text,
          timestampMs: msg.timestamp.millisecondsSinceEpoch,
          isVoice: false,
        );
        inserted++;
      }

      state = state.copyWith(
        status: SyncStatus.done,
        newMessageCount: inserted,
        lastSync: DateTime.now(),
        errorMessage: null,
      );
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        errorMessage: e.toString(),
      );
    } finally {
      _running = false;
    }
  }

  void reset() => state = const SyncState();
}

final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>(
  (_) => SyncNotifier(),
);

// ─── Lifecycle Observer ───────────────────────────────────────────────────────

/// Attach to the widget tree via `WidgetsBindingObserver`.
///
/// ```dart
/// // In your root widget's State:
/// late final _lifecycleObserver = AppLifecycleObserver(ref);
///
/// @override
/// void initState() {
///   super.initState();
///   WidgetsBinding.instance.addObserver(_lifecycleObserver);
/// }
///
/// @override
/// void dispose() {
///   WidgetsBinding.instance.removeObserver(_lifecycleObserver);
///   super.dispose();
/// }
/// ```
class AppLifecycleObserver extends WidgetsBindingObserver {
  final WidgetRef ref;
  AppLifecycleObserver(this.ref);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Trigger sync ONLY when the app comes back to foreground — zero background.
    if (state == AppLifecycleState.resumed) {
      ref.read(syncProvider.notifier).sync();
    }
  }
}

// ─── Conversation Messages Provider ──────────────────────────────────────────

/// Watches sqflite for a given peer's messages. Re-fetches after every sync.
final conversationProvider =
    FutureProvider.family<List<MessageRecord>, String>((ref, peerUsername) async {
  // Rebuild whenever sync completes
  ref.watch(syncProvider);
  return MessageDb.instance.getMessages(peerUsername);
});

/// List of peers who have sent or received messages — for the chat list screen.
final conversationPeersProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(syncProvider);
  return MessageDb.instance.getConversationPeers();
});
