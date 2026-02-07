// Stub for non-web platforms
// These are never actually used since all code using them is wrapped in kIsWeb checks
class _WindowStub {
  void postMessage(dynamic message, String targetOrigin) {}
}

class _MessageEventStub {}

final window = _WindowStub();
typedef MessageEvent = _MessageEventStub;

/// Stub for CanvasWebBridge (only used on web)
class CanvasWebBridge {
  static Future<dynamic> eval(String js) async {
    throw UnimplementedError('CanvasWebBridge.eval only available on web');
  }

  static Future<Map<String, dynamic>> snapshot({
    required String format,
    required double quality,
  }) async {
    throw UnimplementedError('CanvasWebBridge.snapshot only available on web');
  }

  static void handleResponse(String requestId, dynamic result, String? error) {
    throw UnimplementedError('CanvasWebBridge.handleResponse only available on web');
  }
}
