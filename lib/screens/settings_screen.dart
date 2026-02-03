import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gateway_config.dart';
import '../services/discovery_service.dart';
import 'qr_scan_screen.dart';

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

  String? _validateUrl(String url) {
    if (url.isEmpty) return 'URL is required';
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return 'Enter a valid URL (e.g. ws://192.168.1.100:18789)';
    }
    return null;
  }

  Future<void> _discoverGateway() async {
    final result = await showDialog<DiscoveredGateway>(
      context: context,
      builder: (ctx) => const _DiscoveryDialog(),
    );
    if (result != null && mounted) {
      _urlController.text = result.wsUrl;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Found gateway: ${result.wsUrl}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _scanQrCode() async {
    final config = await Navigator.push<GatewayConfig>(
      context,
      MaterialPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (config != null && mounted) {
      _urlController.text = config.url;
      _fallbackUrlController.text = config.fallbackUrl ?? '';
      _tokenController.text = config.token;
      _nameController.text = config.nodeName;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('QR code scanned — review settings and tap Save'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _save() async {
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();

    // Validate
    final urlError = _validateUrl(url);
    if (urlError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(urlError), backgroundColor: Colors.red[700]),
      );
      return;
    }
    if (token.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gateway token is required'), backgroundColor: Colors.red[700]),
      );
      return;
    }

    final config = GatewayConfig(
      url: url,
      fallbackUrl: _fallbackUrlController.text.trim().isEmpty
          ? null
          : _fallbackUrlController.text.trim(),
      token: token,
      nodeName: _nameController.text.trim(),
      autoReconnect: _autoReconnect,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gateway_config', jsonEncode(config.toJson()));

    widget.onSave(config);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved — connecting...'), duration: Duration(seconds: 2)),
      );
      Navigator.of(context).pop();
    }
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
          // Quick setup buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _discoverGateway,
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('Discover'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Local URL
          const Text('Local URL (WiFi)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: 'ws://your-gateway-ip:port',
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
              hintText: 'ws://hostname.your-tailnet.ts.net:port',
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

/// Dialog that shows mDNS + subnet scan results as they arrive.
class _DiscoveryDialog extends StatefulWidget {
  const _DiscoveryDialog();

  @override
  State<_DiscoveryDialog> createState() => _DiscoveryDialogState();
}

class _DiscoveryDialogState extends State<_DiscoveryDialog> {
  final List<DiscoveredGateway> _gateways = [];
  bool _scanning = true;
  StreamSubscription<DiscoveredGateway>? _sub;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  void _startDiscovery() {
    _gateways.clear();
    _scanning = true;
    _sub?.cancel();
    _sub = DiscoveryService.discover().listen(
      (gw) {
        if (mounted) setState(() => _gateways.add(gw));
      },
      onDone: () {
        if (mounted) setState(() => _scanning = false);
      },
      onError: (e) {
        debugPrint('🔍 Discovery error: $e');
        if (mounted) setState(() => _scanning = false);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.wifi_find, size: 22),
          const SizedBox(width: 8),
          const Text('Discover Gateway'),
          if (_scanning) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: _gateways.isEmpty
            ? Center(
                child: _scanning
                    ? const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Scanning network...'),
                        ],
                      )
                    : const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wifi_off, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text('No gateways found',
                              style: TextStyle(color: Colors.grey)),
                          SizedBox(height: 4),
                          Text(
                            'Make sure gateway is running\non the same network',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _gateways.length,
                itemBuilder: (context, index) {
                  final gw = _gateways[index];
                  return ListTile(
                    leading: Icon(
                      gw.source == 'mdns'
                          ? Icons.dns
                          : Icons.lan,
                      color: gw.source == 'mdns'
                          ? Colors.green
                          : Colors.orange,
                    ),
                    title: Text(gw.name ?? gw.host),
                    subtitle: Text(
                      '${gw.wsUrl}  •  ${gw.source == 'mdns' ? 'mDNS' : 'Port scan'}',
                    ),
                    onTap: () => Navigator.of(context).pop(gw),
                  );
                },
              ),
      ),
      actions: [
        if (!_scanning)
          TextButton(
            onPressed: () => setState(() => _startDiscovery()),
            child: const Text('Retry'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
