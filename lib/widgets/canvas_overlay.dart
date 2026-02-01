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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          debugPrint('🖼️ Canvas page loaded: $url');
        },
        onWebResourceError: (error) {
          debugPrint('❌ Canvas WebView error: ${error.description}');
        },
      ));

    // Register with CanvasService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final canvas = context.read<CanvasService>();
        canvas.setWebViewController(_controller);
        _loadUrl(canvas.currentUrl);
      }
    });
  }

  void _loadUrl(String? url) {
    if (url != null && url != _loadedUrl) {
      _loadedUrl = url;
      _controller.loadRequest(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canvas = context.watch<CanvasService>();

    // Load new URL if it changed
    if (canvas.currentUrl != _loadedUrl) {
      _loadUrl(canvas.currentUrl);
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
