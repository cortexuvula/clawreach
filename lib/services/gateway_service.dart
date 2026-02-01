import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import 'crypto_service.dart';

/// Manages WebSocket connection to OpenClaw gateway.
class GatewayService extends ChangeNotifier {
  final CryptoService _crypto;
  static const _uuid = Uuid();
  static const _protocolVersion = 3;

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

      if (type == 'event') {
        final event = json['event'] as String? ?? '';
        if (event == 'connect.challenge') {
          _handleChallenge(json);
          return;
        }
      } else if (type == 'res') {
        // Response to our connect request
        final ok = json['ok'] as bool? ?? false;
        if (ok && _state == msg.GatewayConnectionState.authenticating) {
          _handleConnectOk(json);
          return;
        } else if (!ok && _state == msg.GatewayConnectionState.authenticating) {
          _handleConnectError(json);
          return;
        }
      }

      // All other messages
      _messages.add(msg.GatewayMessage.fromJson(json));
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Message parse error: $e');
    }
  }

  Future<void> _handleChallenge(Map<String, dynamic> json) async {
    final payload = json['payload'] as Map<String, dynamic>?;
    _nonce = payload?['nonce'] as String?;
    if (_nonce == null) {
      debugPrint('❌ No nonce in challenge');
      _errorMessage = 'Invalid challenge from gateway';
      _setState(msg.GatewayConnectionState.error);
      return;
    }

    debugPrint('🔐 Got challenge nonce: ${_nonce!.substring(0, 8)}...');

    try {
      final publicKeyB64Url = await _crypto.getPublicKeyBase64Url();
      final publicKeyRaw = await _crypto.getPublicKeyRaw();

      // Device ID = SHA-256 hex of raw public key bytes
      final deviceId = sha256.convert(publicKeyRaw).toString();
      final signedAtMs = DateTime.now().millisecondsSinceEpoch;
      final token = _config?.token ?? '';
      final nodeName = _config?.nodeName ?? 'ClawReach';

      // Build device auth payload: v2|deviceId|clientId|clientMode|role|scopes|signedAtMs|token|nonce
      // Must match exactly what the server rebuilds from connect params
      const clientId = 'openclaw-android';
      const clientMode = 'node';
      const role = 'node';
      const scopesList = <String>[]; // empty for node role
      final scopesStr = scopesList.join(',');
      final authPayload =
          'v2|$deviceId|$clientId|$clientMode|$role|$scopesStr|$signedAtMs|$token|$_nonce';

      debugPrint('🔐 Auth payload: ${authPayload.substring(0, 40)}...');

      // Sign the payload string (UTF-8 encoded)
      final signature = await _crypto.signString(authPayload);

      final connectMsg = {
        'type': 'req',
        'method': 'connect',
        'id': _uuid.v4(),
        'params': {
          'minProtocol': _protocolVersion,
          'maxProtocol': _protocolVersion,
          'client': {
            'id': clientId,
            'displayName': nodeName,
            'version': '0.1.0',
            'platform': 'Android',
            'mode': clientMode,
          },
          'role': role,
          'scopes': scopesList,
          'caps': ['camera', 'canvas', 'notifications'],
          'auth': {
            'token': token,
          },
          'device': {
            'id': deviceId,
            'publicKey': publicKeyB64Url,
            'signature': signature,
            'signedAt': signedAtMs,
            'nonce': _nonce,
          },
        },
      };

      _channel?.sink.add(jsonEncode(connectMsg));
      debugPrint('🔐 Sent connect request with device auth');
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
    final error = json['error'] as Map<String, dynamic>?;
    final message = error?['message'] as String? ?? 'Unknown error';
    debugPrint('❌ Connect error: $message');
    _errorMessage = message;
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
