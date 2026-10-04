import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/splash_screen.dart';
import 'core/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.load();
  runApp(
    // ProviderScope is required for flutter_riverpod.
    // Wrap the entire app so all providers (syncProvider, conversationProvider,
    // conversationPeersProvider) share the same container.
    const ProviderScope(
      child: BlockchainChatApp(),
    ),
  );
}

class BlockchainChatApp extends StatelessWidget {
  const BlockchainChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlockchainChat',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A1A2E),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        fontFamily: 'monospace',
      ),
      home: const SplashScreen(),
    );
  }
}
