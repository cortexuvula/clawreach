import 'package:flutter/foundation.dart';

/// Stub camera service for unsupported platforms.
class CameraServiceStub extends ChangeNotifier {
  bool get isInitialized => false;
  List<Map<String, dynamic>> get cameras => [];

  Future<void> init() async {
    debugPrint('📷 Camera not supported on this platform');
  }

  Future<Map<String, dynamic>> handleList(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    throw UnsupportedError('Camera not available on this platform');
  }

  Future<Map<String, dynamic>> handleSnap(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    throw UnsupportedError('Camera not available on this platform');
  }
}
