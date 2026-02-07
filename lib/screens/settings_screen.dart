import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gateway_config.dart';
import '../services/discovery_service.dart';
import '../services/foreground_service.dart';
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
  
  // Validation state
  String? _urlError;
  String? _fallbackUrlError;
  String? _tokenError;
  String? _nameError;
  
  // Test connection state
  bool _isTesting = false;
  String? _testResult;

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

  String? _validateUrl(String url, {bool required = true}) {
    if (url.trim().isEmpty) {
      return required ? 'URL is required' : null;
    }
    
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return 'Invalid URL format';
    }
    
    if (!uri.hasScheme) {
      return 'URL must include protocol (ws:// or wss://)';
    }
    
    if (uri.scheme != 'ws' && uri.scheme != 'wss') {
      return 'Protocol must be ws:// or wss://';
    }
    
    if (!uri.hasAuthority) {
      return 'URL must include host (e.g. 192.168.1.100:18789)';
    }
    
    if (!uri.hasPort) {
      return 'URL must include port (e.g. :18789)';
    }
    
    return null;
  }
  
  String? _validateToken(String token) {
    if (token.trim().isEmpty) {
      return 'Gateway token is required';
    }
    
    if (token.length < 10) {
      return 'Token seems too short (need full token)';
    }
    
    return null;
  }
  
  String? _validateName(String name) {
    if (name.trim().isEmpty) {
      return 'Node name is required';
    }
    
    if (name.length > 50) {
      return 'Name too long (max 50 characters)';
    }
    
    return null;
  }
  
  void _validateAll() {
    setState(() {
      _urlError = _validateUrl(_urlController.text);
      _fallbackUrlError = _validateUrl(_fallbackUrlController.text, required: false);
      _tokenError = _validateToken(_tokenController.text);
      _nameError = _validateName(_nameController.text);
    });
  }
  
  bool get _hasErrors => 
      _urlError != null || 
      _fallbackUrlError != null || 
      _tokenError != null || 
      _nameError != null;

  Future<void> _discoverGateway() async {
    final result = await showDialog<DiscoveredGateway>(
      context: context,
      builder: (ctx) => const _DiscoveryDialog(),
    );
    if (result != null && mounted) {
      setState(() {
        _urlController.text = result.wsUrl;
        _urlError = _validateUrl(result.wsUrl);
        _testResult = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Found: ${result.wsUrl}'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Test',
            onPressed: _testConnection,
          ),
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
      setState(() {
        _urlController.text = config.url;
        _fallbackUrlController.text = config.fallbackUrl ?? '';
        _tokenController.text = config.token;
        _nameController.text = config.nodeName;
        
        // Validate imported config
        _validateAll();
        _testResult = null;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('✅ QR code scanned — review settings below'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Test',
            onPressed: _testConnection,
          ),
        ),
      );
    }
  }

  Future<void> _testConnection() async {
    _validateAll();
    if (_hasErrors) {
      setState(() {
        _testResult = '❌ Fix validation errors first';
      });
      return;
    }
    
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    
    final url = _urlController.text.trim();
    
    try {
      debugPrint('🧪 Testing connection to: $url');
      
      // Try to connect with timeout
      final socket = await WebSocket.connect(
        url,
        headers: {'Authorization': 'Bearer ${_tokenController.text.trim()}'},
      ).timeout(const Duration(seconds: 5));
      
      // Connection successful
      debugPrint('✅ Connection test succeeded');
      setState(() {
        _testResult = '✅ Connection successful!';
        _isTesting = false;
      });
      
      // Close the socket
      await socket.close();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Connection successful!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } on TimeoutException {
      debugPrint('❌ Connection test timed out');
      setState(() {
        _testResult = '❌ Connection timed out (5s)';
        _isTesting = false;
      });
    } on SocketException catch (e) {
      debugPrint('❌ Socket error: $e');
      setState(() {
        _testResult = '❌ Cannot reach gateway';
        _isTesting = false;
      });
    } on WebSocketException catch (e) {
      debugPrint('❌ WebSocket error: $e');
      setState(() {
        _testResult = '❌ WebSocket error: ${e.message}';
        _isTesting = false;
      });
    } catch (e) {
      debugPrint('❌ Connection test failed: $e');
      setState(() {
        _testResult = '❌ Connection failed: $e';
        _isTesting = false;
      });
    }
  }
  
  Future<void> _save() async {
    _validateAll();
    if (_hasErrors) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fix validation errors'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

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
    final configJson = jsonEncode(config.toJson());
    await prefs.setString('gateway_config', configJson);
    debugPrint('💾 Saved config to SharedPreferences: ${configJson.length} chars');
    debugPrint('💾 Config URL: ${config.url}');

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
          // Quick setup help
          Card(
            color: Colors.blue.withValues(alpha: 0.05),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: Colors.blue[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Use QR code or network discovery for quick setup',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Quick setup buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanQrCode,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan QR'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _discoverGateway,
                  icon: const Icon(Icons.wifi_find),
                  label: const Text('Discover'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Local URL
          const Text('Local URL (WiFi)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(
              hintText: 'ws://192.168.1.100:18789',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.wifi),
              helperText: _urlError == null ? 'Tried first — fast on local network' : null,
              errorText: _urlError,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (value) {
              setState(() {
                _urlError = _validateUrl(value);
                _testResult = null; // Clear test result on change
              });
            },
          ),
          const SizedBox(height: 20),

          // Fallback URL
          const Text('Fallback URL (Tailscale) - Optional',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _fallbackUrlController,
            decoration: InputDecoration(
              hintText: 'wss://hostname.your-tailnet.ts.net:443',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.vpn_lock),
              helperText: _fallbackUrlError == null ? 'Used when local is unreachable (cellular/remote)' : null,
              errorText: _fallbackUrlError,
            ),
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (value) {
              setState(() {
                _fallbackUrlError = _validateUrl(value, required: false);
              });
            },
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
              errorText: _tokenError,
            ),
            obscureText: _obscureToken,
            autocorrect: false,
            onChanged: (value) {
              setState(() {
                _tokenError = _validateToken(value);
                _testResult = null; // Clear test result on change
              });
            },
          ),
          const SizedBox(height: 20),

          // Node Name
          const Text('Node Name',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              hintText: 'ClawReach',
              border: const OutlineInputBorder(),
              prefixIcon: const Icon(Icons.smartphone),
              helperText: _nameError == null ? 'How this device appears in gateway' : null,
              errorText: _nameError,
            ),
            onChanged: (value) {
              setState(() {
                _nameError = _validateName(value);
              });
            },
          ),
          const SizedBox(height: 24),

          // Test Connection Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isTesting ? null : _testConnection,
              icon: _isTesting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: Text(_isTesting ? 'Testing connection...' : 'Test Connection'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _testResult?.startsWith('✅') ?? false
                    ? Colors.green
                    : null,
              ),
            ),
          ),
          
          // Test result
          if (_testResult != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.startsWith('✅')
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testResult!.startsWith('✅')
                      ? Colors.green
                      : Colors.red,
                  width: 1,
                ),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.startsWith('✅')
                      ? Colors.green[700]
                      : Colors.red[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 20),

          // Auto-reconnect
          SwitchListTile(
            title: const Text('Auto-reconnect'),
            subtitle: const Text('Reconnect automatically with smart fallback'),
            value: _autoReconnect,
            onChanged: (v) => setState(() => _autoReconnect = v),
          ),

          // Background service
          SwitchListTile(
            title: const Text('Background service'),
            subtitle: const Text('Keep connection alive when app is closed'),
            value: ForegroundServiceManager.isRunning,
            onChanged: (v) async {
              if (v) {
                final success = await ForegroundServiceManager.start();
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to start background service. Grant notification and battery optimization permissions.'),
                      duration: Duration(seconds: 5),
                    ),
                  );
                }
              } else {
                await ForegroundServiceManager.stop();
              }
              if (mounted) setState(() {});
            },
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
