import 'dart:async';
import 'dart:convert';
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
  bool _a2uiReady = false;

  CanvasService(this._nodeConnection) {
    _nodeConnection.registerHandler('canvas.present', _handlePresent);
    _nodeConnection.registerHandler('canvas.hide', _handleHide);
    _nodeConnection.registerHandler('canvas.navigate', _handleNavigate);
    _nodeConnection.registerHandler('canvas.eval', _handleEval);
    _nodeConnection.registerHandler('canvas.snapshot', _handleSnapshot);
    _nodeConnection.registerHandler('canvas.a2ui.push', _handleA2uiPushJsonl);
    _nodeConnection.registerHandler('canvas.a2ui.pushJSONL', _handleA2uiPushJsonl);
    _nodeConnection.registerHandler('canvas.a2ui.reset', _handleA2uiReset);
  }

  bool get isVisible => _visible;
  String? get currentUrl => _currentUrl;

  /// Hide canvas locally (user pressed close).
  void handleLocalHide() {
    _visible = false;
    _a2uiReady = false;
    notifyListeners();
  }

  /// Set the WebView controller (called when WebView is created in the UI).
  void setWebViewController(WebViewController controller) {
    _webViewController = controller;
    _a2uiReady = false;
    // If there's pending JSONL, we'll push it after the page loads
  }

  /// Clear the WebView controller (called when CanvasOverlay is disposed).
  void clearWebViewController() {
    _webViewController = null;
    _a2uiReady = false;
  }

  /// Called when the A2UI page finishes loading in the WebView.
  void onPageFinished(String url) {
    debugPrint('🖼️ Canvas page loaded: $url');
    // Proactively check if A2UI is ready after page load
    _probeA2uiReady();
  }

  /// Proactively probe for A2UI readiness after page load.
  Future<void> _probeA2uiReady() async {
    if (_webViewController == null) return;
    // Poll every 300ms up to 5s for the custom element + JS bundle to initialize
    for (int i = 0; i < 17; i++) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (_webViewController == null) return;
      try {
        final result = await _webViewController!.runJavaScriptReturningResult('''
          (() => {
            try {
              const h = globalThis.openclawA2UI;
              return (h && typeof h.applyMessages === 'function') ? 'ready' : 'not_ready';
            } catch (e) { return 'error:' + e.message; }
          })()
        ''');
        final str = result.toString().replaceAll('"', '').replaceAll("'", '');
        if (str == 'ready') {
          debugPrint('🖼️ A2UI probe ready after ${(i + 1) * 300}ms');
          _a2uiReady = true;
          break;
        }
        if (i % 3 == 0) {
          debugPrint('🖼️ A2UI probe #$i: $str');
        }
      } catch (e) {
        debugPrint('⚠️ A2UI probe error: $e');
      }
    }
    if (!_a2uiReady) {
      debugPrint('⚠️ A2UI never became ready after probe');
    }
    // Push any pending JSONL
    if (_pendingJsonl.isNotEmpty) {
      _pushPendingJsonl();
    }
  }

  /// Handle user action from the A2UI JS bridge.
  void handleUserAction(String jsonPayload) {
    debugPrint('🖼️ A2UI user action: ${jsonPayload.substring(0, jsonPayload.length.clamp(0, 200))}');
    try {
      final data = jsonDecode(jsonPayload) as Map<String, dynamic>;
      final userAction = data['userAction'] as Map<String, dynamic>?;
      if (userAction == null) return;

      // Send the action back to the gateway via node connection
      _nodeConnection.sendNodeEvent('canvas.a2ui.action', {
        'userAction': userAction,
      });
    } catch (e) {
      debugPrint('❌ A2UI action parse error: $e');
    }
  }

  /// Build the gateway A2UI URL.
  /// IMPORTANT: Must use trailing slash so relative resources (a2ui.bundle.js)
  /// resolve correctly in the WebView.
  String _buildA2uiUrl() {
    final config = _nodeConnection.activeConfig;
    if (config == null) return '';
    // A2UI is served at /__openclaw__/a2ui/ on the gateway HTTP server
    final baseUrl = config.url.replaceFirst(RegExp(r'/+$'), '');
    return '$baseUrl/__openclaw__/a2ui/?platform=android';
  }

  Future<Map<String, dynamic>> _handlePresent(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final url = params['url'] as String?;
    _currentUrl = url ?? _buildA2uiUrl();
    _visible = true;
    _a2uiReady = false;
    debugPrint('🖼️ Canvas present: $_currentUrl');
    notifyListeners();

    // Wait for the WebView widget to mount and register its controller
    await _waitForWebView();

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
    _a2uiReady = false;
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
    _a2uiReady = false;
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

    final format = params['format'] as String? ?? 'png';
    final mimeType = format == 'jpeg' || format == 'jpg' ? 'image/jpeg' : 'image/png';
    final quality = params['quality'] as num? ?? 0.9;

    final js = '''
      (function() {
        var canvas = document.getElementById('openclaw-canvas');
        if (canvas && canvas.toDataURL) {
          return canvas.toDataURL('$mimeType', $quality).split(',')[1];
        }
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

  Future<Map<String, dynamic>> _handleA2uiPushJsonl(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final jsonl = params['jsonl'] as String? ?? '';
    if (jsonl.isEmpty) throw Exception('jsonl required');
    debugPrint('🖼️ A2UI push: ${jsonl.length} chars');

    // Auto-show canvas if not visible
    if (!_visible) {
      _currentUrl = _buildA2uiUrl();
      _visible = true;
      _a2uiReady = false;
      notifyListeners();

      await _waitForWebView();

      // Load the A2UI page
      if (_webViewController != null && _currentUrl != null) {
        await _webViewController!.loadRequest(Uri.parse(_currentUrl!));
      }
    }

    if (_webViewController != null) {
      // Wait for A2UI host API to be ready
      await _waitForA2uiReady();
      await _pushJsonlToWebView(jsonl);
    } else {
      // Buffer for later
      _pendingJsonl += '$jsonl\n';
    }

    return {'ok': true};
  }

  Future<Map<String, dynamic>> _handleA2uiReset(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    debugPrint('🖼️ A2UI reset');
    _a2uiReady = false;

    if (_webViewController != null) {
      await _webViewController!.runJavaScript('''
        (() => {
          try {
            const host = globalThis.openclawA2UI;
            if (host && typeof host.reset === 'function') host.reset();
          } catch (_) {}
        })()
      ''');
    }
    return {'ok': true};
  }

  /// Wait for the WebView widget to mount (up to 3 seconds).
  Future<void> _waitForWebView() async {
    for (int i = 0; i < 30; i++) {
      if (_webViewController != null) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('⚠️ WebView controller not available after 3s');
  }

  /// Wait for globalThis.openclawA2UI to be available (up to 8 seconds).
  Future<void> _waitForA2uiReady() async {
    if (_a2uiReady) return;
    if (_webViewController == null) {
      debugPrint('⚠️ A2UI wait: no WebView controller');
      return;
    }

    for (int i = 0; i < 80; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        final result = await _webViewController!.runJavaScriptReturningResult('''
          (() => {
            try {
              const h = globalThis.openclawA2UI;
              return (h && typeof h.applyMessages === 'function') ? 'ready' : 'not_ready';
            } catch (e) { return 'error:' + e.message; }
          })()
        ''');
        final str = result.toString().replaceAll('"', '').replaceAll("'", '');
        if (i % 10 == 0) {
          debugPrint('🖼️ A2UI ready check #$i: raw=$result parsed=$str');
        }
        if (str == 'ready') {
          debugPrint('🖼️ A2UI host ready after ${(i + 1) * 100}ms');
          _a2uiReady = true;
          return;
        }
      } catch (e) {
        if (i % 10 == 0) {
          debugPrint('⚠️ A2UI ready check #$i exception: $e');
        }
      }
    }
    debugPrint('⚠️ A2UI host not ready after 8s, pushing anyway');
    _a2uiReady = true; // Mark as ready anyway so we don't block again
  }

  /// Push buffered JSONL after page load.
  Future<void> _pushPendingJsonl() async {
    if (_pendingJsonl.isEmpty || _webViewController == null) return;
    await _waitForA2uiReady();
    final jsonl = _pendingJsonl;
    _pendingJsonl = '';
    await _pushJsonlToWebView(jsonl);
  }

  /// Push JSONL content to the A2UI WebView via JavaScript.
  Future<void> _pushJsonlToWebView(String jsonl) async {
    if (_webViewController == null) return;

    // Parse JSONL lines into a JSON array string
    final lines = jsonl.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;

    final messagesJson = '[${lines.join(',')}]';

    // Use JSON.stringify for safe escaping, pass via base64 to avoid any
    // template literal / quote escaping issues
    final base64Encoded = base64Encode(utf8.encode(messagesJson));

    final js = '''
      (() => {
        try {
          const host = globalThis.openclawA2UI;
          if (!host || typeof host.applyMessages !== 'function') {
            return JSON.stringify({ ok: false, error: 'missing openclawA2UI' });
          }
          const raw = atob('$base64Encoded');
          const messages = JSON.parse(raw);
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
}
