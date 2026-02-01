import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../crypto/ed25519.dart';

/// Manages Ed25519 keys with persistent storage.
class CryptoService extends ChangeNotifier {
  final Ed25519KeyManager _keyManager = Ed25519KeyManager();
  static const _seedKey = 'ed25519_seed';

  bool get hasKeys => _keyManager.hasKeyPair;

  /// Initialize — load existing keys or generate new ones.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final seedStr = prefs.getString(_seedKey);

    if (seedStr != null) {
      final seed = base64Decode(seedStr);
      await _keyManager.loadFromSeed(seed);
      debugPrint('🔑 Loaded existing Ed25519 key pair');
    } else {
      await _keyManager.generateKeyPair();
      final seed = await _keyManager.getSeed();
      await prefs.setString(_seedKey, base64Encode(seed));
      debugPrint('🔑 Generated new Ed25519 key pair');
    }
    notifyListeners();
  }

  /// Get public key as base64url (no padding) for gateway auth.
  Future<String> getPublicKeyBase64Url() => _keyManager.getPublicKeyBase64Url();

  /// Get raw public key bytes (for hashing).
  Future<List<int>> getPublicKeyRaw() => _keyManager.getPublicKeyRaw();

  /// Get public key hex (for display).
  Future<String> getPublicKeyHex() => _keyManager.getPublicKeyHex();

  /// Sign a string payload (UTF-8) and return base64url signature.
  Future<String> signString(String payload) => _keyManager.sign(payload);

  /// Sign a nonce for challenge-response auth.
  Future<String> sign(String nonce) => _keyManager.sign(nonce);

  /// Sign raw bytes.
  Future<String> signBytes(List<int> bytes) => _keyManager.signBytes(bytes);

  /// Reset keys (generates new identity).
  Future<void> resetKeys() async {
    await _keyManager.generateKeyPair();
    final prefs = await SharedPreferences.getInstance();
    final seed = await _keyManager.getSeed();
    await prefs.setString(_seedKey, base64Encode(seed));
    debugPrint('🔑 Reset Ed25519 key pair');
    notifyListeners();
  }
}
