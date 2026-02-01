/// Gateway connection configuration.
class GatewayConfig {
  final String url;
  final String token;
  final String nodeName;
  final bool autoReconnect;
  final int reconnectDelayMs;

  const GatewayConfig({
    required this.url,
    required this.token,
    this.nodeName = 'ClawReach',
    this.autoReconnect = true,
    this.reconnectDelayMs = 5000,
  });

  /// WebSocket URL derived from gateway URL.
  String get wsUrl {
    final uri = Uri.parse(url);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${uri.host}:${uri.port}/ws/node';
  }

  /// Copy with modifications.
  GatewayConfig copyWith({
    String? url,
    String? token,
    String? nodeName,
    bool? autoReconnect,
    int? reconnectDelayMs,
  }) {
    return GatewayConfig(
      url: url ?? this.url,
      token: token ?? this.token,
      nodeName: nodeName ?? this.nodeName,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      reconnectDelayMs: reconnectDelayMs ?? this.reconnectDelayMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'url': url,
        'token': token,
        'nodeName': nodeName,
        'autoReconnect': autoReconnect,
        'reconnectDelayMs': reconnectDelayMs,
      };

  factory GatewayConfig.fromJson(Map<String, dynamic> json) => GatewayConfig(
        url: json['url'] as String? ?? '',
        token: json['token'] as String? ?? '',
        nodeName: json['nodeName'] as String? ?? 'ClawReach',
        autoReconnect: json['autoReconnect'] as bool? ?? true,
        reconnectDelayMs: json['reconnectDelayMs'] as int? ?? 5000,
      );
}
