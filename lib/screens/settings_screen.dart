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
    _tokenController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final config = GatewayConfig(
      url: _urlController.text.trim(),
      token: _tokenController.text.trim(),
      nodeName: _nameController.text.trim(),
      autoReconnect: _autoReconnect,
    );

    // Persist
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
            child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Gateway URL
          const Text('Gateway URL', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: 'https://your-gateway:3000',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.link),
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
          ),
          const SizedBox(height: 20),

          // Gateway Token
          const Text('Gateway Token', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _tokenController,
            decoration: InputDecoration(
              hintText: 'Paste your gateway token',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.key),
              suffixIcon: IconButton(
                icon: Icon(_obscureToken ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscureToken = !_obscureToken),
              ),
            ),
            obscureText: _obscureToken,
            autocorrect: false,
          ),
          const SizedBox(height: 20),

          // Node Name
          const Text('Node Name', style: TextStyle(fontWeight: FontWeight.w600)),
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
            subtitle: const Text('Automatically reconnect on disconnect'),
            value: _autoReconnect,
            onChanged: (v) => setState(() => _autoReconnect = v),
          ),
        ],
      ),
    );
  }
}
