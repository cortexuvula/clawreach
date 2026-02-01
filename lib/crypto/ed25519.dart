import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Ed25519 key management for OpenClaw node authentication.
class Ed25519KeyManager {
  SimpleKeyPair? _keyPair;
  final Ed25519 _algorithm = Ed25519();

  /// Generate a new Ed25519 key pair.
  Future<void> generateKeyPair() async {
    _keyPair = await _algorithm.newKeyPair();
  }

  /// Load key pair from stored seed bytes.
  Future<void> loadFromSeed(List<int> seed) async {
    _keyPair = await _algorithm.newKeyPairFromSeed(seed);
  }

  /// Get the public key as hex string.
  Future<String> getPublicKeyHex() async {
    if (_keyPair == null) throw StateError('No key pair generated');
    final publicKey = await _keyPair!.extractPublicKey();
    return _bytesToHex(publicKey.bytes);
  }

  /// Get the seed (private key material) for secure storage.
  Future<List<int>> getSeed() async {
    if (_keyPair == null) throw StateError('No key pair generated');
    final extracted = await _keyPair!.extract();
    return extracted.bytes;
  }

  /// Sign a message (nonce) and return the signature as hex.
  Future<String> sign(String message) async {
    if (_keyPair == null) throw StateError('No key pair generated');
    final messageBytes = utf8.encode(message);
    final signature = await _algorithm.sign(messageBytes, keyPair: _keyPair!);
    return _bytesToHex(signature.bytes);
  }

  /// Sign raw bytes and return signature as hex.
  Future<String> signBytes(List<int> bytes) async {
    if (_keyPair == null) throw StateError('No key pair generated');
    final signature = await _algorithm.sign(bytes, keyPair: _keyPair!);
    return _bytesToHex(signature.bytes);
  }

  bool get hasKeyPair => _keyPair != null;

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
