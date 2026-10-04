import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/blockchain_discovery.dart';
import 'onboarding_screen.dart';
import 'chat_list_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('username');

    // Blockchain ilə ilk əlaqə və şəbəkə kəşfi
    try {
      await DecentralizedBlockchainService().refreshNetworkTopology();
    } catch (_) {
      // Non-fatal: validator nodes may not be running during development
    }

    if (!mounted) return;

    if (username != null && username.isNotEmpty) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatListScreen(username: username)),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const OnboardingScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF3ECFCF)],
                ),
              ),
              child: const Icon(Icons.shield_outlined, color: Colors.white, size: 44),
            ),
            const SizedBox(height: 24),
            const Text(
              'BlockchainChat',
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Zero-Metadata · 3-of-5 Mailbox · Mixnet',
              style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(color: Color(0xFF6C63FF)),
          ],
        ),
      ),
    );
  }
}

