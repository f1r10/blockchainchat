/// MessageDb — sqflite-backed local storage for decrypted message history.
///
/// Cryptographic state (keys, ratchet state, SURBs) lives exclusively in Rust.
/// This database holds ONLY plaintext messages AFTER successful decryption.
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class MessageRecord {
  final String messageId;
  final String conversationId; // SHA256(myUsername + peerUsername) sorted
  final String peerUsername;
  final String text;
  final bool isMine;
  final int timestampMs;
  final bool isVoice;

  const MessageRecord({
    required this.messageId,
    required this.conversationId,
    required this.peerUsername,
    required this.text,
    required this.isMine,
    required this.timestampMs,
    required this.isVoice,
  });

  Map<String, Object?> toMap() => {
    'message_id': messageId,
    'conversation_id': conversationId,
    'peer_username': peerUsername,
    'text': text,
    'is_mine': isMine ? 1 : 0,
    'timestamp_ms': timestampMs,
    'is_voice': isVoice ? 1 : 0,
  };

  factory MessageRecord.fromMap(Map<String, Object?> m) => MessageRecord(
    messageId: m['message_id'] as String,
    conversationId: m['conversation_id'] as String,
    peerUsername: m['peer_username'] as String,
    text: m['text'] as String,
    isMine: (m['is_mine'] as int) == 1,
    timestampMs: m['timestamp_ms'] as int,
    isVoice: (m['is_voice'] as int) == 1,
  );
}

class MessageDb {
  MessageDb._();
  static MessageDb? _instance;
  static MessageDb get instance => _instance ??= MessageDb._();

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, 'blockchainchat.db');
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE messages (
            message_id    TEXT PRIMARY KEY,
            conversation_id TEXT NOT NULL,
            peer_username TEXT NOT NULL,
            text          TEXT NOT NULL,
            is_mine       INTEGER NOT NULL DEFAULT 0,
            timestamp_ms  INTEGER NOT NULL,
            is_voice      INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_conv ON messages(conversation_id, timestamp_ms)',
        );
      },
    );
    return _db!;
  }

  /// Insert a received (decrypted) message. Idempotent on message_id.
  Future<void> insertReceived({
    required String messageId,
    required String peerUsername,
    required String text,
    required int timestampMs,
    bool isVoice = false,
  }) async {
    final db = await _database;
    await db.insert(
      'messages',
      MessageRecord(
        messageId: messageId,
        conversationId: _convId('me', peerUsername),
        peerUsername: peerUsername,
        text: text,
        isMine: false,
        timestampMs: timestampMs,
        isVoice: isVoice,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Insert a sent message (for local history).
  Future<void> insertSent({
    required String messageId,
    required String peerUsername,
    required String text,
  }) async {
    final db = await _database;
    await db.insert(
      'messages',
      MessageRecord(
        messageId: messageId,
        conversationId: _convId('me', peerUsername),
        peerUsername: peerUsername,
        text: text,
        isMine: true,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        isVoice: false,
      ).toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Retrieve all messages for a conversation, oldest first.
  Future<List<MessageRecord>> getMessages(String peerUsername) async {
    final db = await _database;
    final rows = await db.query(
      'messages',
      where: 'conversation_id = ?',
      whereArgs: [_convId('me', peerUsername)],
      orderBy: 'timestamp_ms ASC',
    );
    return rows.map(MessageRecord.fromMap).toList();
  }

  /// Return list of distinct peer usernames, most recently active first.
  Future<List<String>> getConversationPeers() async {
    final db = await _database;
    final rows = await db.rawQuery(
      'SELECT peer_username, MAX(timestamp_ms) as last '
      'FROM messages GROUP BY peer_username ORDER BY last DESC',
    );
    return rows.map((r) => r['peer_username'] as String).toList();
  }

  /// Stable conversation ID: sorted(a,b) joined with ":".
  static String _convId(String a, String b) {
    final parts = [a, b]..sort();
    return parts.join(':');
  }
}
