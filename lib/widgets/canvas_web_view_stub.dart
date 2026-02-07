// Stub for non-web platforms
import 'package:flutter/material.dart';

class CanvasWebView extends StatelessWidget {
  final String url;

  const CanvasWebView({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    // This should never be called on native platforms
    return const SizedBox.shrink();
  }
}
