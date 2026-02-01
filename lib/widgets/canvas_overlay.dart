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
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  void _initWebView() {
    final controller = WebViewController()
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

    _controller = controller;

    // Register with CanvasService after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<CanvasService>().setWebViewController(controller);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final canvas = context.watch<CanvasService>();

    if (!canvas.isVisible) return const SizedBox.shrink();

    // Load URL if available
    if (canvas.currentUrl != null && _controller != null) {
      _controller!.loadRequest(Uri.parse(canvas.currentUrl!));
    }

    return Material(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          children: [
            // Header bar with close button
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                border: Border(
                  bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () {
                      // Hide canvas locally (doesn't send to gateway)
                      // The gateway can re-show it
                      canvas.handleLocalHide();
                    },
                    tooltip: 'Close canvas',
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.web, size: 16, color: Colors.white54),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      canvas.currentUrl ?? 'Canvas',
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // WebView
            Expanded(
              child: WebViewWidget(controller: _controller!),
            ),
          ],
        ),
      ),
    );
  }
}
