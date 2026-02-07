import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'node_connection_service.dart';

// Platform-specific imports
import 'package:webview_flutter/webview_flutter.dart'
    if (dart.library.html) 'package:webview_flutter/webview_flutter.dart';
import 'canvas_service_stub.dart'
    if (dart.library.html) 'canvas_service_web.dart';

/// Handles canvas.* commands from the gateway.
/// Manages a WebView that renders the A2UI interface.
class CanvasService extends ChangeNotifier {
  final NodeConnectionService _nodeConnection;

  bool _visible = false;
  bool _minimized = false; // New: minimized state (hidden but not closed)
  String? _currentUrl;
  String _pendingJsonl = '';
  WebViewController? _webViewController;
  bool _a2uiReady = false;
  
  // Web-specific: store reference to canvas widget for postMessage
  dynamic _canvasWebViewState;
  
  static const _prefKeyCanvasUrl = 'canvas_last_url';
  static const _prefKeyCanvasVisible = 'canvas_was_visible';
  static const _prefKeyCanvasMinimized = 'canvas_minimized';

  CanvasService(this._nodeConnection) {
    _nodeConnection.registerHandler('canvas.present', _handlePresent);
    _nodeConnection.registerHandler('canvas.hide', _handleHide);
    _nodeConnection.registerHandler('canvas.navigate', _handleNavigate);
    _nodeConnection.registerHandler('canvas.eval', _handleEval);
    _nodeConnection.registerHandler('canvas.snapshot', _handleSnapshot);
    _nodeConnection.registerHandler('canvas.a2ui.push', _handleA2uiPushJsonl);
    _nodeConnection.registerHandler('canvas.a2ui.pushJSONL', _handleA2uiPushJsonl);
    _nodeConnection.registerHandler('canvas.a2ui.reset', _handleA2uiReset);
    
    // Listen for reconnection events to restore canvas state
    _nodeConnection.addListener(_onNodeConnectionChanged);
    
    // Load persisted canvas state on init
    _loadPersistedState();
  }
  
  bool _wasVisibleBeforeDisconnect = false;
  String? _lastUrlBeforeDisconnect;
  
  /// Load canvas state from SharedPreferences (survives app restart)
  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasVisible = prefs.getBool(_prefKeyCanvasVisible) ?? false;
      final url = prefs.getString(_prefKeyCanvasUrl);
      final wasMinimized = prefs.getBool(_prefKeyCanvasMinimized) ?? false;
      
      if (wasVisible && url != null && url.isNotEmpty) {
        debugPrint('🖼️ Restoring canvas from storage: visible=$wasVisible, minimized=$wasMinimized, url=$url');
        _currentUrl = url;
        _visible = wasVisible;
        _minimized = wasMinimized;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load canvas state: $e');
    }
  }
  
  /// Persist canvas state to SharedPreferences
  Future<void> _persistState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyCanvasVisible, _visible);
      await prefs.setString(_prefKeyCanvasUrl, _currentUrl ?? '');
      await prefs.setBool(_prefKeyCanvasMinimized, _minimized);
      debugPrint('💾 Canvas state persisted: visible=$_visible, minimized=$_minimized, url=$_currentUrl');
    } catch (e) {
      debugPrint('⚠️ Failed to persist canvas state: $e');
    }
  }
  
  void _onNodeConnectionChanged() {
    final isConnected = _nodeConnection.isConnected;
    
    if (!isConnected) {
      // Save state when disconnecting
      _wasVisibleBeforeDisconnect = _visible;
      _lastUrlBeforeDisconnect = _currentUrl;
      debugPrint('🖼️ Canvas state saved: visible=$_wasVisibleBeforeDisconnect, url=$_lastUrlBeforeDisconnect');
    } else if (_wasVisibleBeforeDisconnect && _lastUrlBeforeDisconnect != null) {
      // Restore canvas after reconnection
      debugPrint('🖼️ Restoring canvas: $_lastUrlBeforeDisconnect');
      _currentUrl = _lastUrlBeforeDisconnect;
      _visible = true;
      _a2uiReady = false;
      _wasVisibleBeforeDisconnect = false; // Clear saved state
      _lastUrlBeforeDisconnect = null;
      notifyListeners();
    }
  }
  
  @override
  void dispose() {
    _nodeConnection.removeListener(_onNodeConnectionChanged);
    super.dispose();
  }

  bool get isVisible => _visible && !_minimized;
  bool get isMinimized => _minimized;
  String? get currentUrl => _currentUrl;

  /// Hide canvas locally (user pressed close).
  void handleLocalHide() {
    _visible = false;
    _minimized = false;
    _a2uiReady = false;
    _persistState();
    notifyListeners();
  }
  
  /// Minimize canvas (hide but keep state for quick restore)
  void minimize() {
    if (_visible) {
      _minimized = true;
      debugPrint('🖼️ Canvas minimized');
      _persistState();
      notifyListeners();
    }
  }
  
  /// Restore minimized canvas
  void restore() {
    if (_minimized) {
      _minimized = false;
      debugPrint('🖼️ Canvas restored');
      _persistState();
      notifyListeners();
    }
  }
  
  /// Toggle minimize/restore
  void toggleMinimize() {
    if (_minimized) {
      restore();
    } else {
      minimize();
    }
  }

  /// Set the WebView controller (called when WebView is created in the UI).
  /// Only used on native platforms (not web).
  void setWebViewController(WebViewController controller) {
    if (!kIsWeb) {
      _webViewController = controller;
      _a2uiReady = false;
      // If there's pending JSONL, we'll push it after the page loads
    }
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
    // On web, skip probing - iframe will load independently
    if (kIsWeb) {
      _a2uiReady = true;
      if (_pendingJsonl.isNotEmpty) {
        _pushPendingJsonl();
      }
      return;
    }

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
    // Convert ws:// to http:// and wss:// to https://
    var baseUrl = config.url.replaceFirst(RegExp(r'/+$'), '');
    baseUrl = baseUrl.replaceFirst('ws://', 'http://').replaceFirst('wss://', 'https://');
    return '$baseUrl/__openclaw__/a2ui/?platform=android';
  }

  Future<Map<String, dynamic>> _handlePresent(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    debugPrint('🖼️ Canvas present params: $params');
    final url = params['url'] as String?;
    debugPrint('🖼️ Canvas URL from params: $url');
    _currentUrl = url ?? _buildA2uiUrl();
    debugPrint('🖼️ Canvas final URL: $_currentUrl');
    _visible = true;
    _minimized = false;
    _a2uiReady = false;
    _persistState(); // Persist canvas state
    notifyListeners();

    if (!kIsWeb) {
      // Wait for the WebView widget to mount and register its controller
      await _waitForWebView();

      // Navigate WebView
      if (_webViewController != null && _currentUrl != null) {
        await _webViewController!.loadRequest(Uri.parse(_currentUrl!));
      }
    }
    // On web, the iframe will be created by the widget with the current URL

    return {'ok': true};
  }

  Future<Map<String, dynamic>> _handleHide(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    _visible = false;
    _minimized = false;
    _a2uiReady = false;
    debugPrint('🖼️ Canvas hide');
    _persistState(); // Persist hidden state
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
    
    // Auto-show canvas if not visible
    if (!_visible) {
      _visible = true;
      _minimized = false;
      debugPrint('🖼️ Canvas navigate (auto-showing): $url');
    } else {
      debugPrint('🖼️ Canvas navigate: $url');
    }

    _persistState(); // Persist new URL and state
    
    if (!kIsWeb && _webViewController != null) {
      await _webViewController!.loadRequest(Uri.parse(url));
    }
    // On web, notifyListeners will trigger iframe rebuild with new URL
    notifyListeners();
    return {'ok': true};
  }

  Future<Map<String, dynamic>> _handleEval(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final js = params['javaScript'] as String?;
    if (js == null) throw Exception('javaScript required');
    debugPrint('🖼️ Canvas eval: ${js.substring(0, js.length.clamp(0, 60))}...');

    if (kIsWeb) {
      // On web, use postMessage bridge to eval in iframe
      try {
        final result = await CanvasWebBridge.eval(js);
        return {'result': result};
      } catch (e) {
        throw Exception('Canvas eval failed: $e');
      }
    }

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

    final format = params['format'] as String? ?? 'png';
    final quality = params['quality'] as num? ?? 0.9;

    if (kIsWeb) {
      // On web, use postMessage bridge to snapshot iframe
      try {
        final result = await CanvasWebBridge.snapshot(
          format: format,
          quality: quality.toDouble(),
        );
        return result;
      } catch (e) {
        throw Exception('Canvas snapshot failed: $e');
      }
    }

    if (_webViewController == null) {
      throw Exception('WebView not initialized');
    }

    final mimeType = format == 'jpeg' || format == 'jpg' ? 'image/jpeg' : 'image/png';

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

      if (!kIsWeb) {
        await _waitForWebView();

        // Load the A2UI page
        if (_webViewController != null && _currentUrl != null) {
          await _webViewController!.loadRequest(Uri.parse(_currentUrl!));
        }
      }
    }

    if (kIsWeb || _webViewController != null) {
      // Wait for A2UI host API to be ready
      await _waitForA2uiReady();
      await _pushJsonlToWebView(jsonl);
    } else {
      // Buffer for later (native only)
      _pendingJsonl += '$jsonl\n';
    }

    return {'ok': true};
  }

  Future<Map<String, dynamic>> _handleA2uiReset(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    debugPrint('🖼️ A2UI reset');
    _a2uiReady = false;

    if (kIsWeb) {
      // On web, use postMessage to reset
      window.postMessage({'type': 'openclaw-a2ui-reset'}, '*');
    } else if (_webViewController != null) {
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
    // On web, iframes load independently - no controller to wait for
    if (kIsWeb) return;

    for (int i = 0; i < 30; i++) {
      if (_webViewController != null) return;
      await Future.delayed(const Duration(milliseconds: 100));
    }
    debugPrint('⚠️ WebView controller not available after 3s');
  }

  /// Wait for globalThis.openclawA2UI to be available (up to 8 seconds).
  Future<void> _waitForA2uiReady() async {
    if (_a2uiReady) return;

    // On web, use a simple delay instead of polling (iframe communication is async)
    if (kIsWeb) {
      await Future.delayed(const Duration(milliseconds: 500));
      _a2uiReady = true;
      return;
    }

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
    // Parse JSONL lines into a JSON array string
    final lines = jsonl.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return;

    final messagesJson = '[${lines.join(',')}]';

    if (kIsWeb) {
      // On web, use postMessage to communicate with iframe
      try {
        // Parse the messages to send as structured data
        final messages = jsonDecode(messagesJson);
        window.postMessage({
          'type': 'openclaw-a2ui-push',
          'messages': messages,
        }, '*');
        debugPrint('🖼️ A2UI push (web): sent ${lines.length} messages via postMessage');
      } catch (e) {
        debugPrint('❌ A2UI push (web) error: $e');
      }
      return;
    }

    // Native platform - use WebViewController
    if (_webViewController == null) return;

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

  /// Register the web canvas view state (web platform only)
  void registerWebViewState(dynamic state) {
    _canvasWebViewState = state;
    debugPrint('🌐 Canvas web view state registered');
  }

  /// Handle incoming messages from canvas (web platform)
  void handleCanvasMessage(Map<String, dynamic> message) {
    final type = message['type'] as String?;
    debugPrint('📨 Canvas message: $type');

    switch (type) {
      case 'ready':
        // Canvas page loaded and ready
        _a2uiReady = true;
        debugPrint('🖼️ Canvas ready');
        break;

      case 'response':
        // Response to a command (eval/snapshot)
        final requestId = message['requestId'] as String?;
        if (requestId != null) {
          CanvasWebBridge.handleResponse(
            requestId,
            message['result'],
            message['error'] as String?,
          );
        }
        break;

      case 'action':
        // User action (button click, form submit, etc.)
        _handleCanvasAction(message['data'] as Map<String, dynamic>?);
        break;

      case 'event':
        // Canvas event (completion, error, etc.)
        _handleCanvasEvent(message);
        break;

      case 'navigation':
        // Canvas wants to navigate
        final url = message['url'] as String?;
        if (url != null) {
          _currentUrl = url;
          notifyListeners();
        }
        break;

      default:
        debugPrint('⚠️ Unknown canvas message type: $type');
    }
  }

  void _handleCanvasAction(Map<String, dynamic>? data) {
    if (data == null) return;
    
    // Send action back to gateway
    _nodeConnection.sendNodeEvent('canvas.action', data);
    debugPrint('📤 Canvas action forwarded to gateway: ${data['action']}');
  }

  void _handleCanvasEvent(Map<String, dynamic> message) {
    final event = message['event'] as String?;
    final data = message['data'] as Map<String, dynamic>?;
    
    // Send event to gateway
    _nodeConnection.sendNodeEvent('canvas.event', {
      'event': event,
      'data': data,
    });
    debugPrint('📤 Canvas event forwarded to gateway: $event');
  }

  /// Send a message to the canvas (web platform)
  void sendMessageToCanvas(Map<String, dynamic> message) {
    if (kIsWeb && _canvasWebViewState != null) {
      try {
        // Call sendMessage on the web view state
        (_canvasWebViewState as dynamic).sendMessage(message);
      } catch (e) {
        debugPrint('❌ Failed to send message to canvas: $e');
      }
    }
  }
}
