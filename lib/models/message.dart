/// Connection state enum.
enum GatewayConnectionState {
  disconnected,
  connecting,
  authenticating,
  pairingPending,
  connected,
  error,
}

/// A message or event from the gateway.
class GatewayMessage {
  final String type;
  final Map<String, dynamic> payload;
  final DateTime timestamp;

  const GatewayMessage({
    required this.type,
    required this.payload,
    required this.timestamp,
  });

  factory GatewayMessage.fromJson(Map<String, dynamic> json) {
    return GatewayMessage(
      type: json['type'] as String? ?? 'unknown',
      payload: json,
      timestamp: DateTime.now(),
    );
  }
}
