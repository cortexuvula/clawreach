import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'node_connection_service.dart';

/// Handles canvas.* commands from the gateway.
/// Manages a WebView that renders the A2UI interface.
class CanvasService extends ChangeNotifier {
  final NodeConnectionService _nodeConnection;

  bool _visible = false;
  String? _currentUrl;
  String _pendingJsonl = '';
  WebViewController? _webViewController;

  // Snapshot completer for async screenshot capture
  Completer<Map<String, dynamic>>? _snapshotCompleter;

  CanvasService(this._nodeConnection) {
    _nodeConnection.registerHandler('canvas.present', _handlePresent);
    _nodeConnection.registerHandler('canvas.hide', _handleHide);
    _nodeConnection.registerHandler('canvas.navigate', _handleNavigate);
    _nodeConnection.registerHandler('canvas.eval', _handleEval);
    _nodeConnection.registerHandler('canvas.snapshot', _handleSnapshot);
    _nodeConnection.registerHandler('canvas.a2ui.push', _handleA2uiPush);
    _nodeConnection.registerHandler('canvas.a2ui.pushJSONL', _handleA2uiPushJsonl);
    _nodeConnection.registerHandler('canvas.a2ui.reset', _handleA2uiReset);
  }

  bool get isVisible => _visible;
  String? get currentUrl => _currentUrl;

  /// Hide canvas locally (user pressed close).
  void handleLocalHide() {
    _visible = false;
    notifyListeners();
  }

  /// Set the WebView controller (called when WebView is created in the UI).
  void setWebViewController(WebViewController controller) {
    _webViewController = controller;
    // If there's pending JSONL, push it now
    if (_pendingJsonl.isNotEmpty) {
      _pushJsonlToWebView(_pendingJsonl);
      _pendingJsonl = '';
    }
  }

  /// Build the gateway A2UI URL.
  String _buildA2uiUrl() {
    // The A2UI page is served by the gateway at /__openclaw__/a2ui
    final config = _nodeConnection.activeConfig;
    if (config == null) return '';
    final baseUrl = config.url.replaceFirst(RegExp(r'/+$'), '');
    return '$baseUrl/__openclaw__/a2ui?platform=android';
  }

  Future<Map<String, dynamic>> _handlePresent(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final url = params['url'] as String?;
    _currentUrl = url ?? _buildA2uiUrl();
    _visible = true;
    debugPrint('🖼️ Canvas present: $_currentUrl');
    notifyListeners();

    // Navigate WebView if available
    if (_webViewController != null && _currentUrl != null) {
      await _webViewController!.loadRequest(Uri.parse(_currentUrl!));
    }

    return {'ok': true};
  }

  Future<Map<String, dynamic>> _handleHide(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    _visible = false;
    debugPrint('🖼️ Canvas hide');
    notifyListeners();
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _handleNavigate(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final url = params['url'] as String?;
    if (url == null) throw Exception('url required');
    _currentUrl = url;
    debugPrint('🖼️ Canvas navigate: $url');

    if (_webViewController != null) {
      await _webViewController!.loadRequest(Uri.parse(url));
    }
    notifyListeners();
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _handleEval(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final js = params['javaScript'] as String?;
    if (js == null) throw Exception('javaScript required');
    debugPrint('🖼️ Canvas eval: ${js.substring(0, js.length.clamp(0, 60))}...');

    if (_webViewController == null) {
      throw Exception('WebView not initialized');
    }

    final result = await _webViewController!.runJavaScriptReturningResult(js);
    return {'result': result.toString()};
  }

  Future<Map<String, dynamic>> _handleSnapshot(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    debugPrint('🖼️ Canvas snapshot requested');

    if (_webViewController == null) {
      throw Exception('WebView not initialized');
    }

    // Use JavaScript to capture canvas content as base64
    final format = params['format'] as String? ?? 'png';
    final mimeType = format == 'jpeg' || format == 'jpg' ? 'image/jpeg' : 'image/png';
    final quality = params['quality'] as num? ?? 0.9;

    // Try to get the canvas element and convert to base64
    final js = '''
      (function() {
        var canvas = document.getElementById('openclaw-canvas');
        if (canvas) {
          return canvas.toDataURL('$mimeType', $quality).split(',')[1];
        }
        // Fallback: try html2canvas-like approach via document
        return '';
      })()
    ''';

    final result = await _webViewController!.runJavaScriptReturningResult(js);
    final base64 = result.toString().replaceAll('"', '');

    if (base64.isEmpty) {
      throw Exception('Failed to capture canvas snapshot');
    }

    return {
      'format': format == 'jpg' ? 'jpeg' : format,
      'base64': base64,
    };
  }

  Future<Map<String, dynamic>> _handleA2uiPush(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final jsonl = params['jsonl'] as String? ?? '';
    return _pushA2ui(jsonl);
  }

  Future<Map<String, dynamic>> _handleA2uiPushJsonl(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final jsonl = params['jsonl'] as String? ?? '';
    return _pushA2ui(jsonl);
  }

  Future<Map<String, dynamic>> _pushA2ui(String jsonl) async {
    if (jsonl.isEmpty) throw Exception('jsonl required');
    debugPrint('🖼️ A2UI push: ${jsonl.length} chars');

    // Auto-show canvas if not visible
    if (!_visible) {
      _currentUrl = _buildA2uiUrl();
      _visible = true;
      notifyListeners();
      // Wait a bit for WebView to load
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (_webViewController != null) {
      await _pushJsonlToWebView(jsonl);
    } else {
      _pendingJsonl += jsonl;
    }

    return {'ok': true};
  }

  Future<void> _pushJsonlToWebView(String jsonl) async {
    if (_webViewController == null) return;

    // Escape for JS string
    final escaped = jsonl
        .replaceAll('\\', '\\\\')
        .replaceAll("'", "\\'")
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r');

    // Push to the A2UI host element
    final js = '''
      (function() {
        var host = document.querySelector('openclaw-a2ui-host');
        if (host && host.pushJSONL) {
          host.pushJSONL('$escaped');
          return 'ok';
        }
        // Try direct window function
        if (window.__openclaw_a2ui_push) {
          window.__openclaw_a2ui_push('$escaped');
          return 'ok';
        }
        return 'no_host';
      })()
    ''';

    try {
      final result = await _webViewController!.runJavaScriptReturningResult(js);
      debugPrint('🖼️ A2UI push result: $result');
    } catch (e) {
      debugPrint('❌ A2UI push error: $e');
    }
  }

  Future<Map<String, dynamic>> _handleA2uiReset(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    debugPrint('🖼️ A2UI reset');

    if (_webViewController != null) {
      await _webViewController!.runJavaScript('''
        var host = document.querySelector('openclaw-a2ui-host');
        if (host && host.reset) host.reset();
      ''');
    }
    return {'ok': true};
  }
}
