// Stub for non-web platforms
// These are never actually used since all code using them is wrapped in kIsWeb checks
class _WindowStub {
  void postMessage(dynamic message, String targetOrigin) {}
}

class _MessageEventStub {}

final window = _WindowStub();
typedef MessageEvent = _MessageEventStub;
