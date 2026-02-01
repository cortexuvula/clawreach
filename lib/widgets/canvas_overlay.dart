import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/canvas_service.dart';

/// Overlay that shows the Canvas/A2UI WebView when active.
class CanvasOverlay extends StatefulWidget {
  const CanvasOverlay({super.key});

  @override
  State<CanvasOverlay> createState() => _CanvasOverlayState();
}

class _CanvasOverlayState extends State<CanvasOverlay> {
  late final WebViewController _controller;
  String? _loadedUrl;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _setupController();
  }

  void _setupController() {
    final canvas = context.read<CanvasService>();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'openclawCanvasA2UIAction',
        onMessageReceived: (JavaScriptMessage message) {
          canvas.handleUserAction(message.message);
        },
      )
      ..addJavaScriptChannel(
        'FlutterDebug',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('🌐 JS: ${message.message}');
        },
      )
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        debugPrint('🌐 Console [${message.level.name}]: ${message.message}');
      })
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          canvas.onPageFinished(url);
        },
        onWebResourceError: (error) {
          debugPrint('❌ Canvas WebView error: ${error.description}');
        },
      ));

    // Register with CanvasService
    canvas.setWebViewController(_controller);

    // Load initial URL if available
    final url = canvas.currentUrl;
    if (url != null && url.isNotEmpty) {
      _loadedUrl = url;
      _controller.loadRequest(Uri.parse(url));
    }

    _initialized = true;
  }

  @override
  void dispose() {
    // Clear the controller reference from CanvasService
    try {
      final canvas = context.read<CanvasService>();
      canvas.clearWebViewController();
    } catch (_) {
      // Context may not be available during dispose
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvas = context.watch<CanvasService>();

    // Load new URL if it changed after initialization
    if (_initialized && canvas.currentUrl != null && canvas.currentUrl != _loadedUrl) {
      _loadedUrl = canvas.currentUrl;
      _controller.loadRequest(Uri.parse(canvas.currentUrl!));
    }

    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Header bar with close button
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                    onPressed: () => canvas.handleLocalHide(),
                    tooltip: 'Close canvas',
                  ),
                  const Icon(Icons.web, size: 14, color: Colors.white38),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Canvas',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Refresh button
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white38, size: 18),
                    onPressed: () {
                      if (_loadedUrl != null) {
                        _controller.loadRequest(Uri.parse(_loadedUrl!));
                      }
                    },
                    tooltip: 'Reload',
                  ),
                ],
              ),
            ),
            // WebView
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}
