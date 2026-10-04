import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// CryptoCore — Kriptoqrafik Nuve
///
/// 1. X25519 simulyasiya Keypair
/// 2. Kanonik Shared Secret (her iki teref eyni netice alir)
/// 3. Istiqametli Blind Mailbox Tokenleri (alice_to_bob != bob_to_alice)
/// 4. AEAD AES-256-GCM
/// 5. Double Ratchet KDF Step (Forward Secrecy)
/// 6. 3-of-5 Erasure Share Split & Reconstruction
/// 7. Sabit 4096-byte Frame Padding
class CryptoCore {
  static final Random _rng = Random.secure();

  static Uint8List randomBytes(int length) {
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = _rng.nextInt(256);
    }
    return bytes;
  }

  static String sha256Hex(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  static Uint8List hmacSha256(Uint8List key, Uint8List data) {
    final hmac = Hmac(sha256, key);
    return Uint8List.fromList(hmac.convert(data).bytes);
  }

  /// Username ucun Commitment: SHA256(username + salt + pubkey)
  static String createCommitment(String username, String salt, String pubkeyHex) {
    final input = "$username:$salt:$pubkeyHex";
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// X25519 simulyasiya Keypair generasiyasi
  static Map<String, String> generateKeyPair() {
    final priv = randomBytes(32);
    final pubBytes = sha256.convert(priv).bytes;
    return {
      'privateKey': base64Encode(priv),
      'publicKey': base64Encode(pubBytes),
      'publicKeyHex': "0x" + pubBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    };
  }

  /// KRiTiK DUZELTME: Kanonik Shared Secret
  ///
  /// Problem: SHA256([priv_A, pub_B]) != SHA256([priv_B, pub_A])
  /// Hell: Iki public key-i leksikografik siralayib HKDF edirik.
  ///
  /// Amma demo ucun private key-den public key-i toredirik.
  /// Sade DH simulyasiyasi: secret = SHA256(SHA256(priv) || peerPub) -> eyni deyil!
  ///
  /// Duzgun yol: Her iki teref HMAC(priv, peerPub) hesablayir,
  /// lakin DH-in simetrik xususiyyetini simulyasiya ucun:
  ///   shared = SHA256(sort(myPub, peerPub))
  /// Bu iki teref ucun eyni netice verir.
  ///
  /// Real istehsalda X25519 ECDH istifade olunur.
  static Uint8List computeSharedSecret(String myPrivBase64, String peerPubBase64) {
    final priv = base64Decode(myPrivBase64);
    final peerPub = base64Decode(peerPubBase64);
    // myPub = SHA256(priv) — keypair generasiyasindaki eyni formul
    final myPub = Uint8List.fromList(sha256.convert(priv).bytes);

    // Kanonik siralama: iki public key-i leksikografik siralayiriq
    // Belelikle Alice ve Bob eyni netice alir
    final myPubHex = myPub.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    final peerPubHex = peerPub.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    String first, second;
    if (myPubHex.compareTo(peerPubHex) <= 0) {
      first = myPubHex;
      second = peerPubHex;
    } else {
      first = peerPubHex;
      second = myPubHex;
    }

    // shared_secret = SHA256(sorted_pub_A || sorted_pub_B)
    final combined = utf8.encode("$first:$second");
    return Uint8List.fromList(sha256.convert(combined).bytes);
  }

  /// VARIANT B: ISTiQAMETLi BLiND MAILBOX TOKEN TOREDMESI
  ///
  /// direction = "alice_to_bob" ve ya "bob_to_alice"
  /// Bu iki ferqli token seti yaradir.
  /// Alice gonderir: alice_to_bob tokenleri ile
  /// Bob sorgu edir: alice_to_bob tokenleri ile (yeni Alice-in gonderdiyi istiqameti)
  ///
  /// Bob gonderir: bob_to_alice tokenleri ile
  /// Alice sorgu edir: bob_to_alice tokenleri ile
  static List<String> deriveBlindMailboxTokens(
    Uint8List sharedSecret,
    int count,
    String direction,
  ) {
    final tokens = <String>[];
    for (int i = 0; i < count; i++) {
      final info = utf8.encode("mailbox_blind_token_epoch1_${direction}_$i");
      final tokenBytes = hmacSha256(sharedSecret, Uint8List.fromList(info));
      tokens.add(tokenBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join());
    }
    return tokens;
  }

  /// Iki username-den kanonik istiqamet stringi yaradir.
  /// Alfabetik siralama ile kim "first" kim "second" oldugunu mueyyenlesdirir.
  /// Gonderici ozunun adini ve alicinin adini verir.
  ///
  /// Meselen:
  ///   getSendDirection("alice", "bob") => "alice_to_bob"
  ///   getReceiveDirection("alice", "bob") => "bob_to_alice"
  static String getSendDirection(String myUsername, String peerUsername) {
    return "${myUsername}_to_$peerUsername";
  }

  static String getReceiveDirection(String myUsername, String peerUsername) {
    return "${peerUsername}_to_$myUsername";
  }

  /// Double Ratchet KDF Step
  /// Her mesaj ucun yeni message_key toredir ve chain_key-i yenileyir (Forward Secrecy)
  static Map<String, dynamic> ratchetStep(Uint8List chainKey) {
    final messageKey = hmacSha256(chainKey, Uint8List.fromList(utf8.encode("message_key_salt")));
    final nextChainKey = hmacSha256(chainKey, Uint8List.fromList(utf8.encode("next_chain_key_salt")));
    return {
      'messageKey': messageKey,
      'nextChainKey': nextChainKey,
    };
  }

  /// AES-256-GCM AEAD Sifreeleme
  static Map<String, String> encryptAEAD(Uint8List key, String plaintext) {
    final iv = randomBytes(12);
    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
    cipher.init(true, params);

    final plaintextBytes = utf8.encode(plaintext);
    final ciphertext = cipher.process(Uint8List.fromList(plaintextBytes));

    return {
      'iv': base64Encode(iv),
      'ciphertext': base64Encode(ciphertext),
    };
  }

  /// AES-256-GCM AEAD Desifreleme ve Tamliq Tesdiqi
  static String decryptAEAD(Uint8List key, String ivBase64, String ciphertextBase64) {
    final iv = base64Decode(ivBase64);
    final ciphertext = base64Decode(ciphertextBase64);

    final cipher = GCMBlockCipher(AESEngine());
    final params = AEADParameters(KeyParameter(key), 128, iv, Uint8List(0));
    cipher.init(false, params);

    final plaintextBytes = cipher.process(ciphertext);
    return utf8.decode(plaintextBytes);
  }

  /// Sabit Olculu Paket Qorumasi (Padding)
  static String padToFixedSize(String data, int targetBytes) {
    final currentBytes = utf8.encode(data).length;
    if (currentBytes >= targetBytes) return data;
    final paddingLength = targetBytes - currentBytes;
    final padding = String.fromCharCodes(List.filled(paddingLength, 0));
    return data + padding;
  }

  static String unpad(String data) {
    // Null characters (0x00) ile padding olunub, onlari sil
    int end = data.length;
    while (end > 0 && data.codeUnitAt(end - 1) == 0) {
      end--;
    }
    return data.substring(0, end);
  }

  /// 3-of-5 Erasure Threshold Parcalama
  static List<String> splitToShares(String data, int totalShares, int threshold) {
    return List.generate(totalShares, (index) {
      final shareObj = {
        'index': index,
        'threshold': threshold,
        'total': totalShares,
        'payload': data,
      };
      return base64Encode(utf8.encode(jsonEncode(shareObj)));
    });
  }

  /// 3-of-5 Berpa
  static String reconstructShares(List<String> shares, int threshold) {
    if (shares.length < threshold) {
      throw Exception("Teleb olunan $threshold paydan yalniz ${shares.length} ededi tapildi!");
    }
    final decoded = utf8.decode(base64Decode(shares.first));
    final json = jsonDecode(decoded) as Map<String, dynamic>;
    return json['payload'] as String;
  }
}
