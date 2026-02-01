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
    return '$baseUrl/__openclaw__/a2ui/?platform=android';
  }

  Future<Map<String, dynamic>> _handlePresent(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final url = params['url'] as String?;
    _currentUrl = url ?? _buildA2uiUrl();
    _visible = true;
    debugPrint('🖼️ Canvas present: $_currentUrl');
    notifyListeners();

    // Wait for the WebView widget to mount and register its controller
    for (int i = 0; i < 30; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_webViewController != null) break;
    }

    // Navigate WebView
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

      // Wait for WebView widget to mount
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (_webViewController != null) break;
      }

      // Load the A2UI page
      if (_webViewController != null && _currentUrl != null) {
        await _webViewController!.loadRequest(Uri.parse(_currentUrl!));
      }
    }

    if (_webViewController != null) {
      // Wait for A2UI host to be ready (up to 8 seconds)
      bool ready = false;
      for (int i = 0; i < 80; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        try {
          final result = await _webViewController!.runJavaScriptReturningResult('''
            (() => {
              try {
                const h = globalThis.openclawA2UI;
                return h && typeof h.applyMessages === 'function' ? 'ready' : 'not_ready';
              } catch (_) { return 'error'; }
            })()
          ''');
          final str = result.toString().replaceAll('"', '');
          if (str == 'ready') {
            debugPrint('🖼️ A2UI host ready after ${(i+1)*100}ms');
            ready = true;
            break;
          }
        } catch (_) {}
      }
      if (!ready) {
        debugPrint('⚠️ A2UI host not ready after 8s, pushing anyway');
      }
      await _pushJsonlToWebView(jsonl);
    } else {
      _pendingJsonl += '$jsonl\n';
    }

    return {'ok': true};
  }

  Future<void> _pushJsonlToWebView(String jsonl) async {
    if (_webViewController == null) return;

    // Parse JSONL into array of messages
    // Each line is a JSON object — combine into a JS array
    final lines = jsonl.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final messagesJson = '[${lines.join(',')}]';

    // Escape backticks and backslashes for JS template
    final escaped = messagesJson
        .replaceAll('\\', '\\\\')
        .replaceAll('`', '\\`')
        .replaceAll('\$', '\\\$');

    // Use globalThis.openclawA2UI.applyMessages() — same as upstream Android app
    final js = '''
      (() => {
        try {
          const host = globalThis.openclawA2UI;
          if (!host) return JSON.stringify({ ok: false, error: "missing openclawA2UI" });
          const messages = $escaped;
          const result = host.applyMessages(messages);
          return JSON.stringify(result);
        } catch (e) {
          return JSON.stringify({ ok: false, error: String(e?.message ?? e) });
        }
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
        (() => {
          try {
            const host = globalThis.openclawA2UI;
            if (host) host.reset();
          } catch (_) {}
        })()
      ''');
    }
    return {'ok': true};
  }
}
