import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import '../services/gateway_service.dart';
import '../widgets/connection_badge.dart';
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

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayService>();

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Text('🦊 ', style: TextStyle(fontSize: 24)),
            Text('ClawReach'),
          ],
        ),
        actions: [
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
          // Connection status
          Container(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                ConnectionBadge(
                  state: gateway.state,
                  errorMessage: gateway.errorMessage,
                ),
                const SizedBox(height: 16),

                // Connect/Disconnect button
                if (_config != null) ...[
                  if (gateway.state == msg.GatewayConnectionState.disconnected ||
                      gateway.state == msg.GatewayConnectionState.error)
                    FilledButton.icon(
                      onPressed: () => gateway.connect(_config!),
                      icon: const Icon(Icons.power),
                      label: const Text('Connect'),
                    )
                  else if (gateway.state == msg.GatewayConnectionState.connected)
                    OutlinedButton.icon(
                      onPressed: () => gateway.disconnect(),
                      icon: const Icon(Icons.power_off),
                      label: const Text('Disconnect'),
                    )
                  else
                    const CircularProgressIndicator(),
                ] else
                  FilledButton.icon(
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
              ],
            ),
          ),

          const Divider(),

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
                      final message = gateway.messages[
                          gateway.messages.length - 1 - index];
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
