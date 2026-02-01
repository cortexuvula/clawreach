import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import '../services/chat_service.dart';
import '../services/gateway_service.dart';
import '../widgets/chat_bubble.dart';
import 'settings_screen.dart';

/// Main home screen with chat interface.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GatewayConfig? _config;
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
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

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final chat = context.read<ChatService>();
    chat.sendMessage(text);
    _textController.clear();

    // Scroll to bottom
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _routeLabel(String? url) {
    if (url == null || url.isEmpty) return 'Connected';
    final uri = Uri.tryParse(url);
    if (uri == null) return 'Connected';
    final host = uri.host;
    if (host.startsWith('192.168.') ||
        host.startsWith('10.') ||
        host.startsWith('172.')) {
      return 'Local';
    } else if (host.contains('.ts.net') || host.startsWith('100.')) {
      return 'Tailscale';
    }
    return 'Connected';
  }

  Widget _buildAppBarStatus(GatewayService gateway, ChatService chat) {
    final (color, label) = switch (gateway.state) {
      msg.GatewayConnectionState.disconnected => (Colors.grey, 'Offline'),
      msg.GatewayConnectionState.connecting => (Colors.orange, 'Connecting'),
      msg.GatewayConnectionState.authenticating => (Colors.amber, 'Auth...'),
      msg.GatewayConnectionState.connected => (
          chat.isReady ? Colors.green : Colors.lime,
          chat.isReady
              ? _routeLabel(gateway.activeUrl)
              : 'Syncing...',
        ),
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
            boxShadow: color == Colors.green
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.5), blurRadius: 6)
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayService>();
    final chat = context.watch<ChatService>();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🦊 ', style: TextStyle(fontSize: 24)),
            const Text('ClawReach'),
            const SizedBox(width: 12),
            _buildAppBarStatus(gateway, chat),
          ],
        ),
        actions: [
          if (_config != null)
            IconButton(
              icon: Icon(
                gateway.isConnected ? Icons.link_off : Icons.link,
                color: gateway.isConnected ? Colors.green : null,
              ),
              onPressed: () {
                if (gateway.isConnected) {
                  gateway.disconnect();
                } else if (gateway.state ==
                        msg.GatewayConnectionState.disconnected ||
                    gateway.state == msg.GatewayConnectionState.error) {
                  gateway.connect(_config!);
                }
              },
              tooltip: gateway.isConnected ? 'Disconnect' : 'Connect',
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
          // Error banner
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
                    onPressed:
                        _config != null ? () => gateway.connect(_config!) : null,
                    child: const Text('Retry', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Configure prompt
          if (_config == null)
            Expanded(
              child: Center(
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
            )
          else ...[
            // Chat messages
            Expanded(
              child: chat.messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '🦊',
                            style: TextStyle(fontSize: 48),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            chat.isReady
                                ? 'Say something!'
                                : gateway.isConnected
                                    ? 'Syncing session...'
                                    : 'Connect to start chatting',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: chat.messages.length,
                      itemBuilder: (context, index) {
                        return ChatBubble(message: chat.messages[index]);
                      },
                    ),
            ),

            // Input bar
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        enabled: chat.isReady,
                        decoration: InputDecoration(
                          hintText: chat.isReady
                              ? 'Message Fred...'
                              : 'Connecting...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                          fillColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        maxLines: 4,
                        minLines: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: chat.isReady ? _sendMessage : null,
                      icon: chat.isStreaming
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
