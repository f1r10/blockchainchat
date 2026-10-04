import 'dart:convert';
import 'package:flutter/services.dart';

/**
 * AppConfig — Yalnız təməl Blockchain RPC və Kontrakt ünvanını saxlayır.
 * Bütün Relay və Mailbox node-ları Blockchain-dən dinamik kəşf olunur!
 */
class AppConfig {
  static late String blockchainRpc;
  static late String contractAddress;
  static late int chainId;
  static late int pollingIntervalMs;
  static late String version;

  static Future<void> load() async {
    final raw = await rootBundle.loadString('assets/config/app_config.json');
    final json = jsonDecode(raw) as Map<String, dynamic>;

    blockchainRpc = json['blockchainRpc'] as String;
    contractAddress = (json['contractAddress'] as String?) ?? "";
    chainId = json['chainId'] as int;
    pollingIntervalMs = json['pollingIntervalMs'] as int;
    version = json['version'] as String;
  }
}
