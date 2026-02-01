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

  /// Get the public key as base64url (no padding) string.
  Future<String> getPublicKeyBase64Url() async {
    if (_keyPair == null) throw StateError('No key pair generated');
    final publicKey = await _keyPair!.extractPublicKey();
    return _bytesToBase64Url(publicKey.bytes);
  }

  /// Get raw public key bytes.
  Future<List<int>> getPublicKeyRaw() async {
    if (_keyPair == null) throw StateError('No key pair generated');
    final publicKey = await _keyPair!.extractPublicKey();
    return publicKey.bytes;
  }

  /// Get the public key as hex string (for display).
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

  /// Sign a message (nonce) and return the signature as base64url (no padding).
  Future<String> sign(String message) async {
    if (_keyPair == null) throw StateError('No key pair generated');
    final messageBytes = utf8.encode(message);
    final signature = await _algorithm.sign(messageBytes, keyPair: _keyPair!);
    return _bytesToBase64Url(signature.bytes);
  }

  /// Sign raw bytes and return signature as base64url (no padding).
  Future<String> signBytes(List<int> bytes) async {
    if (_keyPair == null) throw StateError('No key pair generated');
    final signature = await _algorithm.sign(bytes, keyPair: _keyPair!);
    return _bytesToBase64Url(signature.bytes);
  }

  bool get hasKeyPair => _keyPair != null;

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _bytesToBase64Url(List<int> bytes) {
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
