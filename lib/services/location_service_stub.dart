import 'package:flutter/foundation.dart';

/// Stub location service for unsupported platforms.
class LocationServiceStub extends ChangeNotifier {
  bool get isInitialized => false;

  Future<void> init() async {
    debugPrint('📍 Location not supported on this platform');
  }

  Future<Map<String, dynamic>> handleLocationGet(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    throw UnsupportedError('Location not available on this platform');
  }
}
