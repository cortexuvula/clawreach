import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gateway_config.dart';

/// Settings screen for gateway connection configuration.
class SettingsScreen extends StatefulWidget {
  final GatewayConfig? currentConfig;
  final Function(GatewayConfig) onSave;

  const SettingsScreen({
    super.key,
    this.currentConfig,
    required this.onSave,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _urlController;
  late TextEditingController _fallbackUrlController;
  late TextEditingController _tokenController;
  late TextEditingController _nameController;
  bool _autoReconnect = true;
  bool _obscureToken = true;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: widget.currentConfig?.url ?? '',
    );
    _fallbackUrlController = TextEditingController(
      text: widget.currentConfig?.fallbackUrl ?? '',
    );
    _tokenController = TextEditingController(
      text: widget.currentConfig?.token ?? '',
    );
    _nameController = TextEditingController(
      text: widget.currentConfig?.nodeName ?? 'ClawReach',
    );
    _autoReconnect = widget.currentConfig?.autoReconnect ?? true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _fallbackUrlController.dispose();
    _tokenController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = GatewayConfig(
      url: _urlController.text.trim(),
      fallbackUrl: _fallbackUrlController.text.trim().isEmpty
          ? null
          : _fallbackUrlController.text.trim(),
      token: _tokenController.text.trim(),
      nodeName: _nameController.text.trim(),
      autoReconnect: _autoReconnect,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gateway_config', jsonEncode(config.toJson()));

    widget.onSave(config);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          TextButton(
            onPressed: _save,
            child: const Text('Save',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Local URL
          const Text('Local URL (WiFi)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: 'http://192.168.1.171:18789',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.wifi),
              helperText: 'Tried first — fast on local network',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 20),

          // Fallback URL
          const Text('Fallback URL (Tailscale)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _fallbackUrlController,
            decoration: const InputDecoration(
              hintText: 'http://cortex-home.tail161478.ts.net:18789',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.vpn_lock),
              helperText: 'Used when local is unreachable (cellular/remote)',
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 20),

          // Gateway Token
          const Text('Gateway Token',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _tokenController,
            decoration: InputDecoration(
              hintText: 'Paste your gateway token',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(
                    _obscureToken ? Icons.visibility : Icons.visibility_off),
                onPressed: () =>
                    setState(() => _obscureToken = !_obscureToken),
              ),
            ),
            obscureText: _obscureToken,
            autocorrect: false,
          ),
          const SizedBox(height: 20),

          // Node Name
          const Text('Node Name',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              hintText: 'ClawReach',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.smartphone),
            ),
          ),
          const SizedBox(height: 20),

          // Auto-reconnect
          SwitchListTile(
            title: const Text('Auto-reconnect'),
            subtitle: const Text('Reconnect automatically with smart fallback'),
            value: _autoReconnect,
            onChanged: (v) => setState(() => _autoReconnect = v),
          ),

          const SizedBox(height: 16),
          // Connection flow explanation
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Connection Flow',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  Text('1. Try local URL (3s timeout)\n'
                      '2. If local fails → try Tailscale URL\n'
                      '3. On disconnect → retry from step 1\n\n'
                      '📶 WiFi: connects via local (fast)\n'
                      '📱 Cellular: falls back to Tailscale'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
