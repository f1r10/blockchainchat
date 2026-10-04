import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import '../core/app_config.dart';
import '../core/crypto_core.dart';

/**
 * NodeInfo modeli — hər maşındakı Relay və ya Mailbox
 */
class ActiveNode {
  final String endpoint;
  final String pubkey;
  final bool isAlive;
  final String role;

  ActiveNode({
    required this.endpoint,
    required this.pubkey,
    required this.isAlive,
    required this.role,
  });
}

/**
 * DecentralizedBlockchainService
 * 
 * Heç bir mərkəzi server yoxdur!
 * Yalnız Blockchain RPC və fərdi maşınların /health endpoint-ləri ilə işləyir.
 */
class DecentralizedBlockchainService {
  static final DecentralizedBlockchainService _instance = DecentralizedBlockchainService._internal();
  factory DecentralizedBlockchainService() => _instance;
  DecentralizedBlockchainService._internal();

  List<ActiveNode> discoveredRelays = [];
  List<ActiveNode> discoveredMailboxes = [];
  String? lastError;

  late Web3Client _web3Client;
  DeployedContract? _contract;

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _web3Client = Web3Client(AppConfig.blockchainRpc, http.Client());

    final abiJson = '''[
      {"inputs":[{"internalType":"string","name":"endpoint","type":"string"},{"internalType":"bytes32","name":"pubkey","type":"bytes32"}],"name":"registerRelay","outputs":[],"stateMutability":"nonpayable","type":"function"},
      {"inputs":[{"internalType":"string","name":"endpoint","type":"string"},{"internalType":"bytes32","name":"pubkey","type":"bytes32"}],"name":"registerMailbox","outputs":[],"stateMutability":"nonpayable","type":"function"},
      {"inputs":[],"name":"getRelays","outputs":[{"components":[{"internalType":"string","name":"endpoint","type":"string"},{"internalType":"bytes32","name":"pubkey","type":"bytes32"},{"internalType":"uint256","name":"registeredAt","type":"uint256"},{"internalType":"bool","name":"exists","type":"bool"}],"internalType":"struct NodeAndUserRegistry.NodeInfo[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
      {"inputs":[],"name":"getMailboxes","outputs":[{"components":[{"internalType":"string","name":"endpoint","type":"string"},{"internalType":"bytes32","name":"pubkey","type":"bytes32"},{"internalType":"uint256","name":"registeredAt","type":"uint256"},{"internalType":"bool","name":"exists","type":"bool"}],"internalType":"struct NodeAndUserRegistry.NodeInfo[]","name":"","type":"tuple[]"}],"stateMutability":"view","type":"function"},
      {"inputs":[{"internalType":"bytes32","name":"usernameHash","type":"bytes32"},{"internalType":"bytes32","name":"commitment","type":"bytes32"},{"internalType":"bytes32","name":"prekeyBundle","type":"bytes32"}],"name":"registerUser","outputs":[],"stateMutability":"nonpayable","type":"function"},
      {"inputs":[{"internalType":"bytes32","name":"usernameHash","type":"bytes32"}],"name":"getUser","outputs":[{"internalType":"bytes32","name":"commitment","type":"bytes32"},{"internalType":"bytes32","name":"prekeyBundle","type":"bytes32"},{"internalType":"uint256","name":"registeredAt","type":"uint256"}],"stateMutability":"view","type":"function"},
      {"inputs":[{"internalType":"bytes32","name":"usernameHash","type":"bytes32"}],"name":"isUserRegistered","outputs":[{"internalType":"bool","name":"","type":"bool"}],"stateMutability":"view","type":"function"}
    ]''';

    if (AppConfig.contractAddress.isNotEmpty) {
      _contract = DeployedContract(
        ContractAbi.fromJson(abiJson, 'NodeAndUserRegistry'),
        EthereumAddress.fromHex(AppConfig.contractAddress),
      );
    }
    _initialized = true;
  }

  /// Blockchain-dən Relay və Mailbox-ları çək və Variant B (Client-side /health ping) ilə aktiv olanları tap
  Future<void> refreshNetworkTopology() async {
    await initialize();
    if (_contract == null) return;

    try {
      final getRelaysFunc = _contract!.function('getRelays');
      final getMailboxesFunc = _contract!.function('getMailboxes');

      final relayResults = await _web3Client.call(contract: _contract!, function: getRelaysFunc, params: []);
      final mailboxResults = await _web3Client.call(contract: _contract!, function: getMailboxesFunc, params: []);

      final rawRelays = relayResults.first as List;
      final rawMailboxes = mailboxResults.first as List;

      // VARIANT B: Hər bir maşının /health endpoint-inə asinxron ping at
      final aliveRelays = <ActiveNode>[];
      for (final r in rawRelays) {
        final ep = r[0] as String;
        final pk = (r[1] as List<int>).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final isAlive = await _pingNode(ep);
        aliveRelays.add(ActiveNode(endpoint: ep, pubkey: pk, isAlive: isAlive, role: 'relay'));
      }

      final aliveMailboxes = <ActiveNode>[];
      for (final m in rawMailboxes) {
        final ep = m[0] as String;
        final pk = (m[1] as List<int>).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final isAlive = await _pingNode(ep);
        aliveMailboxes.add(ActiveNode(endpoint: ep, pubkey: pk, isAlive: isAlive, role: 'mailbox'));
      }

      discoveredRelays = aliveRelays;
      discoveredMailboxes = aliveMailboxes;
      print("🌐 Şəbəkə kəşfi: ${discoveredRelays.where((r) => r.isAlive).length} aktiv Relay, ${discoveredMailboxes.where((m) => m.isAlive).length} aktiv Mailbox.");
    } catch (e) {
      print("Network discovery xətası: $e");
    }
  }

  Future<bool> _pingNode(String endpoint) async {
    try {
      final res = await http.get(Uri.parse('$endpoint/health')).timeout(const Duration(milliseconds: 1500));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// İstifadəçi Qeydiyyatı (Blockchain-ə commitment yazır)
  Future<bool> registerUser({
    required String username,
    required String publicKeyHex,
  }) async {
    await initialize();
    if (_contract == null) return false;

    try {
      final usernameHash = _hexToBytes32(CryptoCore.sha256Hex(username));
      final salt = CryptoCore.randomBytes(16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final commitmentHex = CryptoCore.createCommitment(username, salt, publicKeyHex);
      final commitment = _hexToBytes32(commitmentHex);
      final prekeyBundle = _hexToBytes32(publicKeyHex);

      // Demo üçün 0-cı hesab ilə tx göndəririk (Hardhat dev key)
      // Əvvəlcə web3dart ilə cəhd edirik
      try {
        final registerFunc = _contract!.function('registerUser');
        final credentials = EthPrivateKey.fromHex("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
        final txHash = await _web3Client.sendTransaction(
          credentials,
          Transaction.callContract(
            contract: _contract!,
            function: registerFunc,
            parameters: [usernameHash, commitment, prekeyBundle],
            maxGas: 500000,
          ),
          chainId: AppConfig.chainId,
        );
        print("✅ İstifadəçi qeydiyyatı on-chain uğurlu oldu: $txHash");
        return true;
      } catch (innerErr) {
        print("web3dart sendTransaction xətası, birbaşa RPC fallback sınanır: $innerErr");
        
        // Fallback: Birbaşa eth_sendTransaction (Hardhat node-da 0-cı hesab unlock vəziyyətindədir)
        final registerFunc = _contract!.function('registerUser');
        final encodedData = registerFunc.encodeCall([usernameHash, commitment, prekeyBundle]);
        final hexData = "0x" + encodedData.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

        final rpcRes = await http.post(
          Uri.parse(AppConfig.blockchainRpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            "jsonrpc": "2.0",
            "method": "eth_sendTransaction",
            "params": [{
              "from": "0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266",
              "to": AppConfig.contractAddress,
              "data": hexData,
              "gas": "0x7a120"
            }],
            "id": DateTime.now().millisecondsSinceEpoch
          }),
        ).timeout(const Duration(seconds: 4));

        if (rpcRes.statusCode == 200) {
          final json = jsonDecode(rpcRes.body) as Map<String, dynamic>;
          if (json.containsKey('result')) {
            print("✅ Birbaşa RPC ilə qeydiyyat uğurlu oldu: ${json['result']}");
            return true;
          } else if (json.containsKey('error')) {
            lastError = json['error']['message']?.toString();
          }
        }
        throw innerErr;
      }
    } catch (e, stack) {
      print("Blockchain qeydiyyat xetasi: $e\n$stack");
      lastError = e.toString();
      return false;
    }
  }

  /// Username Lookup (Blockchain-dən public prekey əldə etmə)
  Future<Map<String, dynamic>?> lookupUser(String username) async {
    await initialize();
    if (_contract == null) return null;

    try {
      final usernameHash = _hexToBytes32(CryptoCore.sha256Hex(username));
      final getUserFunc = _contract!.function('getUser');

      final result = await _web3Client.call(
        contract: _contract!,
        function: getUserFunc,
        params: [usernameHash],
      );

      final commitmentBytes = result[0] as List<int>;
      final prekeyBytes = result[1] as List<int>;

      final prekeyHex = prekeyBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final commitmentHex = commitmentBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      return {
        'prekeyHex': prekeyHex,
        'commitmentHex': commitmentHex,
        'prekeyBase64': base64Encode(prekeyBytes),
      };
    } catch (e) {
      print("Lookup xətası: $e");
      return null;
    }
  }

  Uint8List _hexToBytes32(String hex) {
    hex = hex.replaceAll("0x", "");
    if (hex.length > 64) hex = hex.substring(0, 64);
    if (hex.length < 64) hex = hex.padLeft(64, '0');
    final bytes = Uint8List(32);
    for (int i = 0; i < 32; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }
}
