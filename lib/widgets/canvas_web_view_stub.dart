// Stub for non-web platforms
import 'package:flutter/material.dart';

class CanvasWebView extends StatefulWidget {
  final String url;
  final Function(Map<String, dynamic>)? onMessage;

  const CanvasWebView({super.key, required this.url, this.onMessage});

  @override
  State<CanvasWebView> createState() => CanvasWebViewState();
}

class CanvasWebViewState extends State<CanvasWebView> {
  @override
  Widget build(BuildContext context) {
    // This should never be called on native platforms
    return const SizedBox.shrink();
  }
  
  // Stub method for compatibility
  void sendMessage(Map<String, dynamic> message) {}
}
