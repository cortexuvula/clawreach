import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import 'crypto_service.dart';

/// Manages WebSocket connection to OpenClaw gateway.
class GatewayService extends ChangeNotifier {
  final CryptoService _crypto;

  WebSocketChannel? _channel;
  msg.GatewayConnectionState _state = msg.GatewayConnectionState.disconnected;
  String? _errorMessage;
  final List<msg.GatewayMessage> _messages = [];
  Timer? _reconnectTimer;
  GatewayConfig? _config;
  String? _nonce;

  GatewayService(this._crypto);

  msg.GatewayConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  List<msg.GatewayMessage> get messages => List.unmodifiable(_messages);

  /// Connect to the gateway.
  Future<void> connect(GatewayConfig config) async {
    _config = config;
    _reconnectTimer?.cancel();

    if (_state == msg.GatewayConnectionState.connecting ||
        _state == msg.GatewayConnectionState.connected) {
      await disconnect();
    }

    _setState(msg.GatewayConnectionState.connecting);
    _errorMessage = null;

    try {
      final wsUrl = config.wsUrl;
      debugPrint('🔌 Connecting to $wsUrl');

      _channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: ['openclaw-node'],
      );

      await _channel!.ready;
      debugPrint('🔌 WebSocket connected, waiting for challenge...');
      _setState(msg.GatewayConnectionState.authenticating);

      _channel!.stream.listen(
        _onMessage,
        onDone: _onDone,
        onError: _onError,
      );
    } catch (e) {
      debugPrint('❌ Connection failed: $e');
      _errorMessage = e.toString();
      _setState(msg.GatewayConnectionState.error);
      _scheduleReconnect();
    }
  }

  /// Disconnect from the gateway.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _setState(msg.GatewayConnectionState.disconnected);
  }

  /// Send a JSON message to the gateway.
  void send(Map<String, dynamic> message) {
    if (_state != msg.GatewayConnectionState.connected) {
      debugPrint('⚠️ Cannot send — not connected');
      return;
    }
    _channel?.sink.add(jsonEncode(message));
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      debugPrint('📨 Received: $type');

      switch (type) {
        case 'connect.challenge':
          _handleChallenge(json);
          break;
        case 'connect.ok':
          _handleConnectOk(json);
          break;
        case 'connect.error':
          _handleConnectError(json);
          break;
        default:
          _messages.add(msg.GatewayMessage.fromJson(json));
          notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Message parse error: $e');
    }
  }

  Future<void> _handleChallenge(Map<String, dynamic> json) async {
    _nonce = json['nonce'] as String?;
    if (_nonce == null) {
      debugPrint('❌ No nonce in challenge');
      _errorMessage = 'Invalid challenge from gateway';
      _setState(msg.GatewayConnectionState.error);
      return;
    }

    debugPrint('🔐 Got challenge, signing nonce...');

    try {
      final publicKey = await _crypto.getPublicKeyHex();
      final signature = await _crypto.sign(_nonce!);

      final connectMsg = {
        'type': 'connect',
        'token': _config?.token ?? '',
        'publicKey': publicKey,
        'signature': signature,
        'nonce': _nonce,
        'name': _config?.nodeName ?? 'ClawReach',
        'platform': 'flutter',
        'capabilities': ['camera', 'canvas', 'notifications'],
      };

      _channel?.sink.add(jsonEncode(connectMsg));
      debugPrint('🔐 Sent connect with signature');
    } catch (e) {
      debugPrint('❌ Auth failed: $e');
      _errorMessage = 'Authentication failed: $e';
      _setState(msg.GatewayConnectionState.error);
    }
  }

  void _handleConnectOk(Map<String, dynamic> json) {
    debugPrint('✅ Connected to gateway!');
    _setState(msg.GatewayConnectionState.connected);
  }

  void _handleConnectError(Map<String, dynamic> json) {
    final error = json['error'] as String? ?? 'Unknown error';
    debugPrint('❌ Connect error: $error');
    _errorMessage = error;
    _setState(msg.GatewayConnectionState.error);
    _scheduleReconnect();
  }

  void _onDone() {
    debugPrint('🔌 WebSocket closed');
    _setState(msg.GatewayConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _onError(dynamic error) {
    debugPrint('❌ WebSocket error: $error');
    _errorMessage = error.toString();
    _setState(msg.GatewayConnectionState.error);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_config?.autoReconnect != true) return;
    final delay = _config?.reconnectDelayMs ?? 5000;
    debugPrint('🔄 Reconnecting in ${delay}ms...');
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delay), () {
      if (_config != null) connect(_config!);
    });
  }

  void _setState(msg.GatewayConnectionState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
