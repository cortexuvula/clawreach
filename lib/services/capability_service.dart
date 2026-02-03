import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Discovers server capabilities on connect.
/// Allows ClawReach to gracefully degrade on vanilla OpenClaw installs.
class CapabilityService extends ChangeNotifier {
  String? _gatewayHost;
  bool _hasTranscriptionServer = false;
  bool _hasLargePayload = false;
  bool _probed = false;

  /// Whether a faster-whisper transcription server is available on port 8014.
  bool get hasTranscriptionServer => _hasTranscriptionServer;

  /// Whether the gateway supports payloads > 512KB (i.e., PR #6805 merged).
  bool get hasLargePayload => _hasLargePayload;

  /// Whether capability probing has completed.
  bool get probed => _probed;

  /// Max image dimension based on payload support.
  int get maxImageDimension => _hasLargePayload ? 1920 : 800;

  /// JPEG quality based on payload support.
  int get imageQuality => _hasLargePayload ? 80 : 50;

  /// Probe server capabilities. Call after gateway connects.
  /// Skips re-probing if already probed for the same host (saves battery).
  Future<void> probe(String gatewayUrl, {bool force = false}) async {
    try {
      final uri = Uri.parse(gatewayUrl);
      final newHost = uri.host;
      // Skip if already probed for same host (reconnect scenario)
      if (_probed && !force && newHost == _gatewayHost) {
        debugPrint('🔍 Capabilities: cached for $_gatewayHost (skip re-probe)');
        return;
      }
      _gatewayHost = newHost;
    } catch (_) {
      _gatewayHost = null;
    }

    if (_gatewayHost == null) {
      _probed = true;
      notifyListeners();
      return;
    }

    // Probe transcription server (port 8014)
    _hasTranscriptionServer = await _probeTranscription();

    // Probe payload limit by sending a test message
    // For now, assume large payload if transcription server exists
    // (indicates a customized setup). Otherwise assume vanilla 512KB.
    _hasLargePayload = _hasTranscriptionServer;

    _probed = true;
    debugPrint('🔍 Capabilities: transcription=$_hasTranscriptionServer, '
        'largePayload=$_hasLargePayload, '
        'maxDim=$maxImageDimension, quality=$imageQuality');
    notifyListeners();
  }

  /// Reset on disconnect.
  void reset() {
    _hasTranscriptionServer = false;
    _hasLargePayload = false;
    _probed = false;
    notifyListeners();
  }

  Future<bool> _probeTranscription() async {
    if (_gatewayHost == null) return false;
    try {
      final url = 'http://$_gatewayHost:8014/health';
      final response = await http.get(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final ok = data['status'] == 'ok';
        debugPrint('🔍 Transcription server: $ok (${data['model'] ?? 'unknown'})');
        return ok;
      }
    } catch (e) {
      debugPrint('🔍 Transcription server: unavailable ($e)');
    }
    return false;
  }
}
