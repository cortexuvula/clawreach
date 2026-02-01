import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import '../services/gateway_service.dart';
import 'settings_screen.dart';

/// Main home screen showing connection status and messages.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GatewayConfig? _config;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString('gateway_config');
    if (configStr != null) {
      setState(() {
        _config = GatewayConfig.fromJson(
          jsonDecode(configStr) as Map<String, dynamic>,
        );
      });
    }
  }

  void _onConfigSaved(GatewayConfig config) {
    setState(() => _config = config);
  }

  /// Connection indicator dot + route label for the app bar.
  Widget _buildAppBarStatus(GatewayService gateway) {
    final (color, label) = switch (gateway.state) {
      msg.GatewayConnectionState.disconnected => (Colors.grey, 'Offline'),
      msg.GatewayConnectionState.connecting => (Colors.orange, 'Connecting'),
      msg.GatewayConnectionState.authenticating => (Colors.amber, 'Auth...'),
      msg.GatewayConnectionState.connected => (Colors.green, _routeLabel(gateway.activeUrl)),
      msg.GatewayConnectionState.error => (Colors.red, 'Error'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: gateway.state == msg.GatewayConnectionState.connected
                ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  String _routeLabel(String? url) {
    if (url == null || url.isEmpty) return 'Connected';
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Connected';
    final host = uri.host;
    if (host.startsWith('192.168.') || host.startsWith('10.') || host.startsWith('172.')) {
      return 'Local';
    } else if (host.contains('.ts.net') || host.startsWith('100.')) {
      return 'Tailscale';
    }
    return 'Connected';
  }

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayService>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🦊 ', style: TextStyle(fontSize: 24)),
            const Text('ClawReach'),
            const SizedBox(width: 12),
            _buildAppBarStatus(gateway),
          ],
        ),
        actions: [
          // Connect/disconnect toggle in app bar
          if (_config != null)
            IconButton(
              icon: Icon(
                gateway.state == msg.GatewayConnectionState.connected
                    ? Icons.link_off
                    : Icons.link,
                color: gateway.state == msg.GatewayConnectionState.connected
                    ? Colors.green
                    : null,
              ),
              onPressed: () {
                if (gateway.state == msg.GatewayConnectionState.connected) {
                  gateway.disconnect();
                } else if (gateway.state == msg.GatewayConnectionState.disconnected ||
                    gateway.state == msg.GatewayConnectionState.error) {
                  gateway.connect(_config!);
                }
              },
              tooltip: gateway.state == msg.GatewayConnectionState.connected
                  ? 'Disconnect'
                  : 'Connect',
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  currentConfig: _config,
                  onSave: _onConfigSaved,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Show error bar if there's an error
          if (gateway.state == msg.GatewayConnectionState.error &&
              gateway.errorMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.red.withValues(alpha: 0.15),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[300], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      gateway.errorMessage!,
                      style: TextStyle(color: Colors.red[300], fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: _config != null ? () => gateway.connect(_config!) : null,
                    child: const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Configure prompt if no config
          if (_config == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: FilledButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      currentConfig: _config,
                      onSave: _onConfigSaved,
                    ),
                  ),
                ),
                icon: const Icon(Icons.settings),
                label: const Text('Configure Gateway'),
              ),
            ),

          // Messages / Events
          Expanded(
            child: gateway.messages.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox, size: 48, color: Colors.grey),
                        SizedBox(height: 8),
                        Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(8),
                    itemCount: gateway.messages.length,
                    itemBuilder: (context, index) {
                      final message =
                          gateway.messages[gateway.messages.length - 1 - index];
                      return Card(
                        child: ListTile(
                          leading: const Icon(Icons.message),
                          title: Text(message.type),
                          subtitle: Text(
                            message.payload.toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Text(
                            '${message.timestamp.hour}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
