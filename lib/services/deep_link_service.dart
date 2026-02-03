import 'dart:async';
import 'dart:convert';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import '../models/gateway_config.dart';

/// Handles incoming deep links for auto-configuration.
///
/// Supported formats:
///   clawreach://connect?url=ws://...&token=...&fallback=ws://...&name=...
///   JSON: {"url":"...","token":"...","fallbackUrl":"...","nodeName":"..."}
class DeepLinkService {
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  /// Callback when a valid config is received via deep link.
  void Function(GatewayConfig config)? onConfigReceived;

  /// Initialize and start listening for deep links.
  Future<void> init() async {
    // Handle link that launched the app (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('🔗 Initial deep link: $initialUri');
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('🔗 No initial deep link: $e');
    }

    // Handle links while app is running (warm start)
    _sub = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('🔗 Incoming deep link: $uri');
      _handleUri(uri);
    });
  }

  void _handleUri(Uri uri) {
    final config = parseUri(uri);
    if (config != null) {
      debugPrint('🔗 Parsed config from deep link: ${config.url}');
      onConfigReceived?.call(config);
    } else {
      debugPrint('🔗 Could not parse deep link: $uri');
    }
  }

  /// Parse a deep link URI into a GatewayConfig.
  /// Format: clawreach://connect?url=...&token=...&fallback=...&name=...
  static GatewayConfig? parseUri(Uri uri) {
    if (uri.scheme != 'clawreach') return null;
    if (uri.host != 'connect' && uri.path != '/connect') return null;

    final url = uri.queryParameters['url'];
    final token = uri.queryParameters['token'];
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      return null;
    }

    return GatewayConfig(
      url: url,
      fallbackUrl: uri.queryParameters['fallback'],
      token: token,
      nodeName: uri.queryParameters['name'] ?? 'ClawReach',
    );
  }

  /// Parse a JSON string (from QR code) into a GatewayConfig.
  /// Format: {"url":"...","token":"...","fallbackUrl":"...","nodeName":"..."}
  static GatewayConfig? parseJson(String raw) {
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final url = json['url'] as String?;
      final token = json['token'] as String?;
      if (url == null || url.isEmpty || token == null || token.isEmpty) {
        return null;
      }
      return GatewayConfig(
        url: url,
        fallbackUrl: json['fallbackUrl'] as String?,
        token: token,
        nodeName: json['nodeName'] as String? ?? 'ClawReach',
      );
    } catch (_) {
      return null;
    }
  }

  /// Try to parse a string as either a deep link URI or JSON config.
  static GatewayConfig? parseAny(String raw) {
    // Try as URI first
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.scheme == 'clawreach') {
      return parseUri(uri);
    }
    // Try as JSON
    return parseJson(raw);
  }

  void dispose() {
    _sub?.cancel();
  }
}
