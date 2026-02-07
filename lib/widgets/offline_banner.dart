import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/chat_service.dart';
import '../services/gateway_service.dart';

/// Banner shown when app is offline or has queued messages
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayService>();
    final chat = context.watch<ChatService>();

    final isConnected = gateway.isConnected;
    final queueSize = chat.queueSize;

    // Don't show banner if connected and no queued messages
    if (isConnected && queueSize == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isConnected ? Colors.orange[700] : Colors.red[700],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              isConnected ? Icons.hourglass_empty : Icons.cloud_off,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isConnected
                    ? 'Sending $queueSize queued ${queueSize == 1 ? 'message' : 'messages'}...'
                    : queueSize > 0
                        ? 'Offline - $queueSize ${queueSize == 1 ? 'message' : 'messages'} queued'
                        : 'Offline - Messages will be queued',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (!isConnected)
              Icon(
                Icons.wifi_off,
                color: Colors.white.withValues(alpha: 0.8),
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}
