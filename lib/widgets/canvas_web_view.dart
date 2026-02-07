// Web-specific canvas implementation using iframes
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';

class CanvasWebView extends StatelessWidget {
  final String url;

  const CanvasWebView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    // Create a unique view type for this iframe
    final viewType = 'canvas-iframe-${url.hashCode}';
    
    // Register the iframe factory (idempotent - won't fail if already registered)
    try {
      ui_web.platformViewRegistry.registerViewFactory(
        viewType,
        (int viewId) {
          final iframe = html.IFrameElement()
            ..src = url
            ..style.border = 'none'
            ..style.height = '100%'
            ..style.width = '100%'
            ..allow = 'autoplay; fullscreen'
            ..setAttribute('loading', 'eager');

          return iframe;
        },
      );
    } catch (e) {
      // View already registered, that's fine
    }

    return HtmlElementView(viewType: viewType);
  }
}
