/// Gateway connection configuration with smart URL fallback.
class GatewayConfig {
  final String url; // Primary URL (local IP)
  final String? fallbackUrl; // Fallback URL (Tailscale)
  final String token;
  final String nodeName;
  final bool autoReconnect;
  final int reconnectDelayMs;
  final int localTimeoutMs; // How long to try local before falling back

  const GatewayConfig({
    required this.url,
    this.fallbackUrl,
    required this.token,
    this.nodeName = 'ClawReach',
    this.autoReconnect = true,
    this.reconnectDelayMs = 5000,
    this.localTimeoutMs = 3000,
  });

  /// Whether a fallback URL is configured.
  bool get hasFallback => fallbackUrl != null && fallbackUrl!.isNotEmpty;

  /// WebSocket URL from a base URL.
  static String toWsUrl(String baseUrl) {
    final uri = Uri.parse(baseUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final port = uri.port > 0 ? uri.port : (uri.scheme == 'https' ? 443 : 80);
    return '$scheme://${uri.host}:$port/ws/node';
  }

  /// Primary WebSocket URL.
  String get wsUrl => toWsUrl(url);

  /// Fallback WebSocket URL.
  String? get fallbackWsUrl => hasFallback ? toWsUrl(fallbackUrl!) : null;

  GatewayConfig copyWith({
    String? url,
    String? fallbackUrl,
    String? token,
    String? nodeName,
    bool? autoReconnect,
    int? reconnectDelayMs,
    int? localTimeoutMs,
  }) {
    return GatewayConfig(
      url: url ?? this.url,
      fallbackUrl: fallbackUrl ?? this.fallbackUrl,
      token: token ?? this.token,
      nodeName: nodeName ?? this.nodeName,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      reconnectDelayMs: reconnectDelayMs ?? this.reconnectDelayMs,
      localTimeoutMs: localTimeoutMs ?? this.localTimeoutMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'fallbackUrl': fallbackUrl,
        'token': token,
        'nodeName': nodeName,
        'autoReconnect': autoReconnect,
        'reconnectDelayMs': reconnectDelayMs,
        'localTimeoutMs': localTimeoutMs,
      };

  factory GatewayConfig.fromJson(Map<String, dynamic> json) => GatewayConfig(
        url: json['url'] as String? ?? '',
        fallbackUrl: json['fallbackUrl'] as String?,
        token: json['token'] as String? ?? '',
        nodeName: json['nodeName'] as String? ?? 'ClawReach',
        autoReconnect: json['autoReconnect'] as bool? ?? true,
        reconnectDelayMs: json['reconnectDelayMs'] as int? ?? 5000,
        localTimeoutMs: json['localTimeoutMs'] as int? ?? 3000,
      );
}
