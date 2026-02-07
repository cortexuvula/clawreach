// Web-specific canvas implementation using iframes with postMessage bridge
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'dart:convert';
import 'package:flutter/material.dart';

/// Callback for messages received from the canvas iframe
typedef CanvasMessageCallback = void Function(Map<String, dynamic> message);

class CanvasWebView extends StatefulWidget {
  final String url;
  final CanvasMessageCallback? onMessage;

  const CanvasWebView({
    super.key,
    required this.url,
    this.onMessage,
  });

  @override
  State<CanvasWebView> createState() => CanvasWebViewState();
}

class CanvasWebViewState extends State<CanvasWebView> {
  html.IFrameElement? _iframe;
  html.Subscription? _messageSubscription;

  @override
  void initState() {
    super.initState();
    _setupMessageListener();
  }

  @override
  void dispose() {
    _messageSubscription?.cancel();
    super.dispose();
  }

  void _setupMessageListener() {
    _messageSubscription = html.window.onMessage.listen((html.MessageEvent event) {
      try {
        // Parse message from canvas
        final data = event.data;
        if (data is String) {
          final message = jsonDecode(data) as Map<String, dynamic>;
          
          // Check if this is a canvas message
          if (message['source'] == 'openclaw-canvas') {
            debugPrint('📨 Canvas → App: ${message['type']}');
            widget.onMessage?.call(message);
          }
        }
      } catch (e) {
        debugPrint('⚠️ Canvas message parse error: $e');
      }
    });
  }

  /// Send a message to the canvas iframe
  void sendMessage(Map<String, dynamic> message) {
    if (_iframe?.contentWindow == null) {
      debugPrint('⚠️ Cannot send message: iframe not ready');
      return;
    }

    try {
      final json = jsonEncode(message);
      _iframe!.contentWindow!.postMessage(json, '*');
      debugPrint('📤 App → Canvas: ${message['type']}');
    } catch (e) {
      debugPrint('❌ Failed to send message to canvas: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Create a unique view type for this iframe
    final viewType = 'canvas-iframe-${widget.url.hashCode}';
    
    // Register the iframe factory (idempotent - won't fail if already registered)
    try {
      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (int viewId) {
          _iframe = html.IFrameElement()
            ..src = widget.url
            ..style.border = 'none'
            ..style.height = '100%'
            ..style.width = '100%'
            ..allow = 'autoplay; fullscreen'
            ..setAttribute('loading', 'eager');

          return _iframe!;
        },
      );
    } catch (e) {
      // View already registered, that's fine
    }

    return HtmlElementView(viewType: viewType);
  }
}
