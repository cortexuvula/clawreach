import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import '../services/chat_service.dart';
import '../services/gateway_service.dart';
import '../services/node_connection_service.dart';
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
  final _focusNode = FocusNode();
  int _prevMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _loadConfigAndAutoConnect();
    // Scroll when keyboard appears
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      _scrollToBottom(delay: 300);
    }
  }

  void _scrollToBottom({int delay = 100}) {
    Future.delayed(Duration(milliseconds: delay), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _loadConfigAndAutoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final configStr = prefs.getString('gateway_config');
    if (configStr != null) {
      final config = GatewayConfig.fromJson(
        jsonDecode(configStr) as Map<String, dynamic>,
      );
      setState(() => _config = config);

      // Auto-connect both operator (chat) and node (camera) connections
      final gateway = context.read<GatewayService>();
      final nodeConn = context.read<NodeConnectionService>();
      if (!gateway.isConnected) {
        gateway.connect(config);
      }
      if (!nodeConn.isConnected) {
        nodeConn.connect(config);
      }
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
    _scrollToBottom();
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

  Widget _buildAppBarStatus(GatewayService gateway, ChatService chat, NodeConnectionService nodeConn) {
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
                ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 6)]
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
        ),
        // Camera indicator
        if (nodeConn.isConnected) ...[
          const SizedBox(width: 8),
          Icon(Icons.camera_alt, size: 14, color: Colors.green.withValues(alpha: 0.8)),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final gateway = context.watch<GatewayService>();
    final chat = context.watch<ChatService>();
    final nodeConn = context.watch<NodeConnectionService>();

    // Auto-scroll when new messages arrive or streaming updates
    if (chat.messages.length != _prevMessageCount) {
      _prevMessageCount = chat.messages.length;
      _scrollToBottom();
    } else if (chat.isStreaming) {
      _scrollToBottom(delay: 50);
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🦊 ', style: TextStyle(fontSize: 24)),
            const Text('ClawReach'),
            const SizedBox(width: 12),
            _buildAppBarStatus(gateway, chat, nodeConn),
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
                        focusNode: _focusNode,
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
