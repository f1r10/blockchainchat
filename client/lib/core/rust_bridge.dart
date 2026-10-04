/// RustBridge — thin Dart wrapper over flutter_rust_bridge generated bindings.
///
/// Architecture note: All cryptographic state lives in the Rust `core` crate.
/// This file is the ONLY entry point through which Flutter code may call Rust.
/// If the generated `src/rust/` bindings are not yet available (pre-codegen),
/// the stub implementations below return realistic fake data so UI development
/// can proceed in parallel.
///
/// After running codegen, replace stub calls with the real FRB calls:
///   import 'src/rust/api/identity.dart';
///   import 'src/rust/api/messaging.dart';
///   import 'src/rust/api/sync.dart';

library rust_bridge;

import 'dart:async';

// ─── Data Transfer Objects ────────────────────────────────────────────────────

/// Mirror of Rust `IdentityRegistrationResult`
class IdentityResult {
  final String username;
  final String usernameCommitmentHex;
  final String deviceIdHex;

  const IdentityResult({
    required this.username,
    required this.usernameCommitmentHex,
    required this.deviceIdHex,
  });
}

/// Mirror of Rust `SendMessageResult`
class SendResult {
  final String messageIdHex;
  final int dispatchedChunks;

  const SendResult({required this.messageIdHex, required this.dispatchedChunks});
}

/// Mirror of Rust `DecryptedMessage`
class DecryptedMessage {
  final String messageIdHex;
  final int timestampEpochSec;
  final List<int> payloadBytes;
  final bool isVoice;

  const DecryptedMessage({
    required this.messageIdHex,
    required this.timestampEpochSec,
    required this.payloadBytes,
    required this.isVoice,
  });

  String get text => String.fromCharCodes(payloadBytes);
  DateTime get timestamp =>
      DateTime.fromMillisecondsSinceEpoch(timestampEpochSec * 1000);
}

// ─── Bridge ───────────────────────────────────────────────────────────────────

/// Static bridge to Rust core.
///
/// Usage:
/// ```dart
/// final result = await RustBridge.registerIdentity('alice');
/// final msgs   = await RustBridge.syncMessages();
/// ```
class RustBridge {
  RustBridge._();

  // ── Identity ────────────────────────────────────────────────────────────────

  /// Calls `core::api::identity::register_identity(username)`.
  ///
  /// Generates X25519/PQ keypairs, computes username commitment, generates 20
  /// SURBs, and returns serialised prekey + SURB bundles ready for DHT upload.
  static Future<IdentityResult> registerIdentity(String username) async {
    // ┌─ CODEGEN STUB ──────────────────────────────────────────────────────────
    // │ Replace with generated call once `flutter_rust_bridge_codegen generate`
    // │ has been run:
    // │
    // │   import 'src/rust/api/identity.dart' as rust_identity;
    // │   final r = await rust_identity.registerIdentity(username: username);
    // │   return IdentityResult(
    // │     username: r.username,
    // │     usernameCommitmentHex: r.usernameCommitmentHex,
    // │     deviceIdHex: r.deviceIdHex,
    // │   );
    // └────────────────────────────────────────────────────────────────────────
    await Future.delayed(const Duration(milliseconds: 800)); // simulate crypto
    final commitment = _fakeHex(32);
    final deviceId   = _fakeHex(16);
    return IdentityResult(
      username: username,
      usernameCommitmentHex: commitment,
      deviceIdHex: deviceId,
    );
  }

  // ── Messaging ───────────────────────────────────────────────────────────────

  /// Calls `core::api::messaging::send_message(recipient, payload, is_voice)`.
  ///
  /// Executes the full pipeline: PQXDH → Double Ratchet → 2 KB frame → 3-of-5
  /// Reed-Solomon chunks → SURB-wrapped Sphinx packets → Nym mixnet injection.
  static Future<SendResult> sendMessage({
    required String recipientUsername,
    required String plaintext,
  }) async {
    // ┌─ CODEGEN STUB ──────────────────────────────────────────────────────────
    // │   import 'src/rust/api/messaging.dart' as rust_msg;
    // │   final r = await rust_msg.sendMessage(
    // │     recipientUsername: recipientUsername,
    // │     payloadBytes: plaintext.codeUnits,
    // │     isVoice: false,
    // │   );
    // │   return SendResult(
    // │     messageIdHex: r.messageIdHex,
    // │     dispatchedChunks: r.dispatchedChunks,
    // │   );
    // └────────────────────────────────────────────────────────────────────────
    await Future.delayed(const Duration(milliseconds: 400));
    return SendResult(messageIdHex: _fakeHex(32), dispatchedChunks: 5);
  }

  // ── Sync ────────────────────────────────────────────────────────────────────

  /// Calls `core::api::sync::sync_messages()`.
  ///
  /// One-shot pull: queries registered Mailboxes via SURB, reconstructs 3-of-5
  /// Reed-Solomon chunks, decrypts Double Ratchet, unpacks fixed-size frame.
  /// Returns immediately — zero background loops or sockets remain open.
  static Future<List<DecryptedMessage>> syncMessages() async {
    // ┌─ CODEGEN STUB ──────────────────────────────────────────────────────────
    // │   import 'src/rust/api/sync.dart' as rust_sync;
    // │   final msgs = await rust_sync.syncMessages();
    // │   return msgs.map((m) => DecryptedMessage(
    // │     messageIdHex: m.messageIdHex,
    // │     timestampEpochSec: m.timestampEpochSec,
    // │     payloadBytes: m.payloadBytes,
    // │     isVoice: m.isVoice,
    // │   )).toList();
    // └────────────────────────────────────────────────────────────────────────
    await Future.delayed(const Duration(milliseconds: 600));
    return []; // Mailboxes empty in stub — real Rust will fill these
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static String _fakeHex(int byteLen) {
    final buf = StringBuffer();
    for (int i = 0; i < byteLen; i++) {
      buf.write(((i * 37 + 13) % 256).toRadixString(16).padLeft(2, '0'));
    }
    return buf.toString();
  }
}
