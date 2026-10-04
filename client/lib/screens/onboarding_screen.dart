/// OnboardingScreen — Username registration via Rust FFI `register_identity()`.
///
/// Flow:
///   1. User enters username (≥3 chars).
///   2. Calls `RustBridge.registerIdentity(username)` — generates X25519/PQ
///      keypairs, computes username commitment, generates 20 SURBs.
///   3. Saves `username` + opaque `deviceIdHex` to SharedPreferences
///      (no raw private keys stored in Dart).
///   4. Navigates to ChatListScreen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/rust_bridge.dart';
import 'chat_list_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _usernameCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    final username = _usernameCtrl.text.trim();
    if (username.length < 3) {
      setState(() => _error = 'İstifadəçi adı minimum 3 simvol olmalıdır');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _status = 'X25519/Kyber açar cütlükləri generasiya edilir...';
    });

    try {
      setState(() => _status = 'Commitment hesablanır və SURB-lar yaradılır...');

      final result = await RustBridge.registerIdentity(username);

      setState(() => _status = 'Şəxsiyyət yaradıldı. Saxlanılır...');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', result.username);
      // Store only the opaque device ID — private keys never leave Rust.
      await prefs.setString('deviceIdHex', result.deviceIdHex);
      await prefs.setString(
        'usernameCommitmentHex',
        result.usernameCommitmentHex,
      );

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ChatListScreen(username: result.username),
        ),
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Qeydiyyat xətası: $e';
        _status = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                  ),
                ),
                child: const Icon(
                  Icons.fingerprint,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 28),

              // Title
              const Text(
                'Mərkəzsiz Şəxsiyyət Yarat',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'PQXDH · Double Ratchet · 3-of-5 Mailbox\n'
                'IP ünvanın heç bir yerdə saxlanılmır.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 12,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 36),

              // Username field
              TextField(
                controller: _usernameCtrl,
                style: const TextStyle(color: Colors.white),
                enabled: !_loading,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _register(),
                decoration: InputDecoration(
                  hintText: 'məs: alice, bob',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  prefixIcon: const Icon(
                    Icons.alternate_email,
                    color: Color(0xFF6C63FF),
                  ),
                  filled: true,
                  fillColor: const Color(0xFF13132B),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF3ECFCF)),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1A1A35)),
                  ),
                ),
              ),

              // Error banner
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],

              // Status ticker
              if (_status != null) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Color(0xFF3ECFCF),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        _status!,
                        style: const TextStyle(
                          color: Color(0xFF3ECFCF),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // Register button
              ElevatedButton(
                onPressed: _loading ? null : _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  disabledBackgroundColor: const Color(0xFF3A3A6A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child:
                    _loading
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Text(
                          'Qeydiyyatdan Keç',
                          style: TextStyle(color: Colors.white, fontSize: 16),
                        ),
              ),

              const SizedBox(height: 16),

              // Privacy note
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 13,
                    color: Colors.white.withOpacity(0.3),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Açarlar yalnız bu cihazda Rust core-da saxlanılır',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.3),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
