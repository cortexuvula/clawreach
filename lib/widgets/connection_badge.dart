import 'package:flutter/material.dart';
import '../models/message.dart' as msg;

/// Visual connection status badge.
class ConnectionBadge extends StatelessWidget {
  final msg.GatewayConnectionState state;
  final String? errorMessage;

  const ConnectionBadge({
    super.key,
    required this.state,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (state) {
      msg.GatewayConnectionState.disconnected => (Colors.grey, Icons.cloud_off, 'Disconnected'),
      msg.GatewayConnectionState.connecting => (Colors.orange, Icons.sync, 'Connecting...'),
      msg.GatewayConnectionState.authenticating => (Colors.amber, Icons.lock_open, 'Authenticating...'),
      msg.GatewayConnectionState.connected => (Colors.green, Icons.cloud_done, 'Connected'),
      msg.GatewayConnectionState.error => (Colors.red, Icons.error_outline, 'Error'),
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (state == msg.GatewayConnectionState.error && errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              errorMessage!,
              style: TextStyle(color: Colors.red[300], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
