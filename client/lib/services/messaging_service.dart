import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/crypto_core.dart';
import 'blockchain_discovery.dart';

/// Decentralized Messaging Service
///
/// - Variant B Blind Tokenlerle isleyir (Mailbox-lar kimin kime yazdigini bilmir)
/// - Istiqametli tokenler: send != receive (self-echo problemi hell olunur)
/// - Mix/Relay vasitesile anonim gonderir
/// - 3-of-5 paylari 5 ayri masinindaki Mailbox-a paylayir
/// - Bob dovri olaraq (cover traffic xarakterli) polling edir
class MessagingService {
  static final MessagingService _instance = MessagingService._internal();
  factory MessagingService() => _instance;
  MessagingService._internal();

  final _discovery = DecentralizedBlockchainService();

  /// Send chain key-leri her sohbet ucun saxlayir (Forward Secrecy)
  /// Key: "send_chain_{peerUsername}", Value: base64 encoded chain key
  final Map<String, Uint8List> _sendChainKeys = {};

  /// Receive chain key-leri
  final Map<String, Uint8List> _recvChainKeys = {};

  Uint8List _getSendChainKey(String peerUsername, Uint8List sharedSecret) {
    final key = "send_$peerUsername";
    if (!_sendChainKeys.containsKey(key)) {
      // Ilk chain key = HMAC(sharedSecret, "send_chain_init")
      _sendChainKeys[key] = CryptoCore.hmacSha256(
        sharedSecret,
        Uint8List.fromList(utf8.encode("send_chain_init")),
      );
    }
    return _sendChainKeys[key]!;
  }

  Uint8List _getRecvChainKey(String peerUsername, Uint8List sharedSecret) {
    final key = "recv_$peerUsername";
    if (!_recvChainKeys.containsKey(key)) {
      // Ilk chain key = HMAC(sharedSecret, "recv_chain_init")
      _recvChainKeys[key] = CryptoCore.hmacSha256(
        sharedSecret,
        Uint8List.fromList(utf8.encode("recv_chain_init")),
      );
    }
    return _recvChainKeys[key]!;
  }

  void _advanceSendChain(String peerUsername, Uint8List nextChainKey) {
    _sendChainKeys["send_$peerUsername"] = nextChainKey;
  }

  void _advanceRecvChain(String peerUsername, Uint8List nextChainKey) {
    _recvChainKeys["recv_$peerUsername"] = nextChainKey;
  }

  Future<bool> sendMessage({
    required String myUsername,
    required String myPrivateKeyBase64,
    required String recipientUsername,
    required String plaintext,
  }) async {
    try {
      // 1. Sebeke topologiyasini tezelele
      await _discovery.refreshNetworkTopology();
      final activeRelays = _discovery.discoveredRelays.where((r) => r.isAlive).toList();
      final activeMailboxes = _discovery.discoveredMailboxes.where((m) => m.isAlive).toList();

      if (activeMailboxes.length < 3) {
        print("Kifayet qeder aktiv Mailbox yoxdur (minimum 3 teleb olunur, movcud: ${activeMailboxes.length})");
        return false;
      }

      // 2. Bob-un Prekey-ini Blockchain-den elde et
      final recipientData = await _discovery.lookupUser(recipientUsername);
      if (recipientData == null) {
        print("Istifadeci blockchain-de tapilmadi: $recipientUsername");
        return false;
      }

      final peerPrekeyBase64 = recipientData['prekeyBase64'] as String;

      // 3. Kanonik shared secret (her iki teref eyni netice alir)
      final sharedSecret = CryptoCore.computeSharedSecret(myPrivateKeyBase64, peerPrekeyBase64);

      // 4. Forward Secrecy Ratchet Step (send chain)
      final chainKey = _getSendChainKey(recipientUsername, sharedSecret);
      final ratchet = CryptoCore.ratchetStep(chainKey);
      final messageKey = ratchet['messageKey'] as Uint8List;
      _advanceSendChain(recipientUsername, ratchet['nextChainKey'] as Uint8List);

      // 5. AEAD Sifreleme ve Sabit Olculu Padding (4096 bayt)
      final encrypted = CryptoCore.encryptAEAD(messageKey, plaintext);
      final packetJson = jsonEncode(encrypted);
      final padded = CryptoCore.padToFixedSize(packetJson, 4096);

      // 6. 3-of-5 Erasure Share-lere bol
      final shares = CryptoCore.splitToShares(padded, 5, 3);

      // 7. ISTIQAMETLI BLIND TOKENLER
      // Alice gonderir: "alice_to_bob" istiqameti ile
      // Bob alir: CryptoCore.getReceiveDirection("bob", "alice") => "alice_to_bob"
      // Belelikle eyni tokenler ust-uste dusur!
      final sendDirection = CryptoCore.getSendDirection(myUsername, recipientUsername);
      final blindTokens = CryptoCore.deriveBlindMailboxTokens(sharedSecret, 5, sendDirection);

      // 8. Paylari aktiv Mailbox-lara gonder (Relay vasitesile)
      int successCount = 0;
      for (int i = 0; i < 5; i++) {
        final targetMailbox = activeMailboxes[i % activeMailboxes.length].endpoint;
        final token = blindTokens[i];
        final shareData = shares[i];

        bool sent = false;
        if (activeRelays.isNotEmpty) {
          final relay = activeRelays[i % activeRelays.length].endpoint;
          sent = await _sendViaRelay(relay, targetMailbox, token, shareData, i);
        }

        if (!sent) {
          sent = await _sendDirectMailbox(targetMailbox, token, shareData, i);
        }

        if (sent) successCount++;
      }

      print("3-of-5 gonderisi: $successCount/5 pay ugurla catdirildi.");
      return successCount >= 3;
    } catch (e) {
      print("Gonderme xetasi: $e");
      return false;
    }
  }

  Future<bool> _sendViaRelay(String relayUrl, String targetMailbox, String token, String shareData, int index) async {
    try {
      final res = await http.post(
        Uri.parse('$relayUrl/relay/packet'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'destination': targetMailbox,
          'token': token,
          'shareData': shareData,
          'shareIndex': index,
          'hopsRemaining': 1,
        }),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _sendDirectMailbox(String mailboxUrl, String token, String shareData, int index) async {
    try {
      final res = await http.post(
        Uri.parse('$mailboxUrl/mailbox/store'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': token,
          'shareData': shareData,
          'shareIndex': index,
        }),
      ).timeout(const Duration(seconds: 4));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Bob ucun anonim mesaj sorgusu (Polling)
  ///
  /// KRiTiK: pollMessages() EKSINI istifade edir!
  /// Bob "alice_to_bob" tokenleri ile sorgu edir
  /// (yeni Alice-in gonderme istiqameti = Bob-un qebul istiqameti)
  Future<List<Map<String, dynamic>>> pollMessages({
    required String myUsername,
    required String myPrivateKeyBase64,
    required String peerUsername,
  }) async {
    final messages = <Map<String, dynamic>>[];

    try {
      final peerData = await _discovery.lookupUser(peerUsername);
      if (peerData == null) return messages;

      final peerPrekey = peerData['prekeyBase64'] as String;
      final sharedSecret = CryptoCore.computeSharedSecret(myPrivateKeyBase64, peerPrekey);

      // Receive chain key ile decrypt
      final chainKey = _getRecvChainKey(peerUsername, sharedSecret);

      // EKSINI istifade et: men "bob"-am, peer "alice"-dir
      // getReceiveDirection("bob", "alice") => "alice_to_bob"
      // Bu Alice-in gonderdigi tokenlerle eynidir!
      final recvDirection = CryptoCore.getReceiveDirection(myUsername, peerUsername);
      final blindTokens = CryptoCore.deriveBlindMailboxTokens(sharedSecret, 5, recvDirection);

      final activeMailboxes = _discovery.discoveredMailboxes.where((m) => m.isAlive).toList();
      if (activeMailboxes.isEmpty) return messages;

      final collectedShares = <String>[];

      for (int i = 0; i < 5; i++) {
        final token = blindTokens[i];
        for (final mb in activeMailboxes) {
          try {
            final res = await http.get(
              Uri.parse('${mb.endpoint}/mailbox/poll/$token'),
            ).timeout(const Duration(milliseconds: 1500));
            if (res.statusCode == 200) {
              final json = jsonDecode(res.body) as Map<String, dynamic>;
              if (json['found'] == true) {
                collectedShares.add(json['shareData'] as String);
                // Oxunduqdan sonra mailbox-dan sil
                http.delete(Uri.parse('${mb.endpoint}/mailbox/delete/$token')).ignore();
                break;
              }
            }
          } catch (_) {}
        }
      }

      // 3-of-5 Threshold yoxlanisi
      if (collectedShares.length >= 3) {
        // Ratchet step + decrypt
        final ratchet = CryptoCore.ratchetStep(chainKey);
        final messageKey = ratchet['messageKey'] as Uint8List;
        _advanceRecvChain(peerUsername, ratchet['nextChainKey'] as Uint8List);

        final reconstructedPadded = CryptoCore.reconstructShares(collectedShares, 3);
        final unpadded = CryptoCore.unpad(reconstructedPadded);
        final encData = jsonDecode(unpadded) as Map<String, dynamic>;

        final plaintext = CryptoCore.decryptAEAD(
          messageKey,
          encData['iv'] as String,
          encData['ciphertext'] as String,
        );

        messages.add({
          'text': plaintext,
          'receivedAt': DateTime.now().millisecondsSinceEpoch,
          'sharesRecovered': collectedShares.length,
        });
      }
    } catch (e) {
      print("Polling / desifre xetasi: $e");
    }

    return messages;
  }
}
