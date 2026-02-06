import 'package:flutter/material.dart';
import '../models/message.dart' as msg;

/// Visual connection status badge with active URL indicator.
class ConnectionBadge extends StatelessWidget {
  final msg.GatewayConnectionState state;
  final String? errorMessage;
  final String? activeUrl;

  const ConnectionBadge({
    super.key,
    required this.state,
    this.errorMessage,
    this.activeUrl,
  });

  String _urlLabel(String? url) {
    if (url == null || url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final host = uri.host;
    // Show "Local" for private IPs, "Tailscale" for .ts.net
    if (host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.')) {
      return '📶 Local';
    } else if (host.contains('.ts.net')) {
      return '🔒 Tailscale';
    } else if (host.startsWith('100.')) {
      return '🔒 Tailscale';
    }
    return host;
  }

  @override
  Widget build(BuildContext context) {
    final (color, icon, label) = switch (state) {
      msg.GatewayConnectionState.disconnected => (
          Colors.grey,
          Icons.cloud_off,
          'Disconnected'
        ),
      msg.GatewayConnectionState.connecting => (
          Colors.orange,
          Icons.sync,
          'Connecting...'
        ),
      msg.GatewayConnectionState.authenticating => (
          Colors.amber,
          Icons.lock_open,
          'Authenticating...'
        ),
      msg.GatewayConnectionState.pairingPending => (
          Colors.blue,
          Icons.phonelink_lock,
          'Pairing...'
        ),
      msg.GatewayConnectionState.connected => (
          Colors.green,
          Icons.cloud_done,
          'Connected'
        ),
      msg.GatewayConnectionState.error => (
          Colors.red,
          Icons.error_outline,
          'Error'
        ),
    };

    final urlTag = state == msg.GatewayConnectionState.connected
        ? _urlLabel(activeUrl)
        : '';

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
                urlTag.isNotEmpty ? '$label  $urlTag' : label,
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
