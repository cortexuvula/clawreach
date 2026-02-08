import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/canvas_service.dart';
import 'canvas_web_view_stub.dart'
    if (dart.library.html) 'canvas_web_view.dart';

/// Overlay that shows the Canvas/A2UI WebView when active.
class CanvasOverlay extends StatefulWidget {
  const CanvasOverlay({super.key});

  @override
  State<CanvasOverlay> createState() => _CanvasOverlayState();
}

class _CanvasOverlayState extends State<CanvasOverlay> {
  WebViewController? _controller; // Nullable for web platform
  String? _loadedUrl;
  bool _initialized = false;
  bool _shouldLoad = false; // Lazy loading flag
  bool _isLoading = false; // Loading state for spinner
  final GlobalKey<CanvasWebViewState> _webViewKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _setupNativeController();
    } else {
      _setupWebIframe();
    }
  }

  void _setupNativeController() {
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
    canvas.setWebViewController(_controller!);

    // Load initial URL if available
    final url = canvas.currentUrl;
    if (url != null && url.isNotEmpty) {
      _loadedUrl = url;
      _controller!.loadRequest(Uri.parse(url));
    }

    _initialized = true;
  }

  void _setupWebIframe() {
    // Register the web view state with canvas service after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final canvas = context.read<CanvasService>();
      if (_webViewKey.currentState != null) {
        canvas.registerWebViewState(_webViewKey.currentState);
      }
      // Trigger load if canvas is already visible
      if (canvas.isVisible && _loadedUrl != null) {
        setState(() {
          _shouldLoad = true;
          _isLoading = true;
        });
      }
    });
    _initialized = true;
  }

  @override
  void didUpdateWidget(CanvasOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final canvas = context.read<CanvasService>();
    
    // Trigger lazy load when canvas becomes visible
    if (canvas.isVisible && !_shouldLoad && _loadedUrl != null) {
      setState(() {
        _shouldLoad = true;
        _isLoading = true;
      });
    }
    
    // Clear load flag when canvas is hidden (not just minimized)
    if (!canvas.isVisible && _shouldLoad) {
      setState(() {
        _shouldLoad = false;
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    // Clear the controller reference from CanvasService
    try {
      final canvas = context.read<CanvasService>();
      if (!kIsWeb) {
        canvas.clearWebViewController();
      }
    } catch (_) {
      // Context may not be available during dispose
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canvas = context.watch<CanvasService>();

    // Handle URL changes
    if (_initialized && canvas.currentUrl != null && canvas.currentUrl != _loadedUrl) {
      _loadedUrl = canvas.currentUrl;
      if (kIsWeb) {
        // For web, rebuild with new iframe (will trigger lazy load if visible)
        setState(() {
          if (canvas.isVisible) {
            _shouldLoad = true;
            _isLoading = true;
          }
        });
      } else {
        if (_controller != null && canvas.isVisible) {
          _controller!.loadRequest(Uri.parse(canvas.currentUrl!));
        }
      }
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
                  // Minimize button
                  IconButton(
                    icon: const Icon(Icons.minimize, color: Colors.white38, size: 18),
                    onPressed: () => canvas.minimize(),
                    tooltip: 'Minimize',
                  ),
                  // Refresh button
                  IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.white38, size: 18),
                    onPressed: () {
                      if (_loadedUrl != null) {
                        if (kIsWeb) {
                          setState(() {}); // Rebuild iframe
                        } else {
                          _controller?.loadRequest(Uri.parse(_loadedUrl!));
                        }
                      }
                    },
                    tooltip: 'Reload',
                  ),
                ],
              ),
            ),
            // WebView or Iframe
            Expanded(
              child: kIsWeb
                  ? _buildWebIframe()
                  : (_shouldLoad || !kIsWeb)
                      ? WebViewWidget(controller: _controller!)
                      : const Center(
                          child: CircularProgressIndicator(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebIframe() {
    if (_loadedUrl == null || _loadedUrl!.isEmpty) {
      return const Center(
        child: Text(
          'No canvas URL',
          style: TextStyle(color: Colors.white38),
        ),
      );
    }

    // Show loading indicator until iframe should load
    if (!_shouldLoad) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Use the conditionally imported CanvasWebView with message handling
    final canvas = context.read<CanvasService>();
    return Stack(
      children: [
        CanvasWebView(
          key: _webViewKey,
          url: _loadedUrl!,
          onMessage: (message) {
            canvas.handleCanvasMessage(message);
            // Clear loading state when canvas sends ready message
            if (_isLoading && message['type'] == 'ready') {
              setState(() => _isLoading = false);
            }
          },
        ),
        // Show loading overlay until ready
        if (_isLoading)
          Container(
            color: Colors.black.withValues(alpha: 0.7),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Loading canvas...',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
