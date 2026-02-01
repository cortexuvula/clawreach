import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import 'crypto_service.dart';

/// Manages WebSocket connection to OpenClaw gateway with smart URL fallback.
class GatewayService extends ChangeNotifier {
  final CryptoService _crypto;
  static const _uuid = Uuid();
  static const _protocolVersion = 3;

  WebSocketChannel? _channel;
  msg.GatewayConnectionState _state = msg.GatewayConnectionState.disconnected;
  String? _errorMessage;
  String? _activeUrl; // Which URL we're currently connected to
  final List<msg.GatewayMessage> _messages = [];
  Timer? _reconnectTimer;
  GatewayConfig? _config;
  String? _nonce;

  /// Callback for raw messages (used by ChatService).
  void Function(Map<String, dynamic>)? onRawMessage;

  GatewayService(this._crypto);

  msg.GatewayConnectionState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get activeUrl => _activeUrl;
  bool get isConnected => _state == msg.GatewayConnectionState.connected;
  List<msg.GatewayMessage> get messages => List.unmodifiable(_messages);

  /// Connect to the gateway with smart URL fallback.
  /// Tries local URL first (fast timeout), falls back to Tailscale.
  Future<void> connect(GatewayConfig config) async {
    _config = config;
    _reconnectTimer?.cancel();

    if (_state == msg.GatewayConnectionState.connecting ||
        _state == msg.GatewayConnectionState.connected) {
      await disconnect();
    }

    _setState(msg.GatewayConnectionState.connecting);
    _errorMessage = null;

    // Try local URL first
    final localWs = config.wsUrl;
    debugPrint('🔌 Trying local: $localWs');

    if (await _tryConnect(localWs, config.localTimeoutMs)) {
      _activeUrl = config.url;
      debugPrint('✅ Connected via local URL');
      return;
    }

    // Fall back to Tailscale if available
    if (config.hasFallback) {
      final fallbackWs = config.fallbackWsUrl!;
      debugPrint('🔌 Local failed, trying fallback: $fallbackWs');
      _errorMessage = null; // Clear local error

      if (await _tryConnect(fallbackWs, 10000)) {
        _activeUrl = config.fallbackUrl;
        debugPrint('✅ Connected via fallback URL');
        return;
      }
    }

    // Both failed
    debugPrint('❌ All connection attempts failed');
    _setState(msg.GatewayConnectionState.error);
    _scheduleReconnect();
  }

  /// Attempt WebSocket connection to a specific URL with timeout.
  Future<bool> _tryConnect(String wsUrl, int timeoutMs) async {
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: ['openclaw-node'],
      );

      // Wait for connection with timeout
      await channel.ready.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () {
          throw TimeoutException('Connection timeout after ${timeoutMs}ms');
        },
      );

      debugPrint('🔌 WebSocket connected to $wsUrl, waiting for challenge...');
      _channel = channel;
      _setState(msg.GatewayConnectionState.authenticating);

      _channel!.stream.listen(
        _onMessage,
        onDone: _onDone,
        onError: _onError,
      );

      return true;
    } on TimeoutException catch (e) {
      debugPrint('⏱️ Timeout connecting to $wsUrl: $e');
      _errorMessage = 'Local connection timeout';
      return false;
    } on SocketException catch (e) {
      debugPrint('🔌 Socket error connecting to $wsUrl: $e');
      _errorMessage = 'Cannot reach $wsUrl';
      return false;
    } catch (e) {
      debugPrint('❌ Failed connecting to $wsUrl: $e');
      _errorMessage = e.toString();
      return false;
    }
  }

  /// Disconnect from the gateway.
  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _activeUrl = null;
    _setState(msg.GatewayConnectionState.disconnected);
  }

  /// Send a JSON message to the gateway.
  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  /// Send a typed request to the gateway.
  void sendRequest({
    required String method,
    required String id,
    required Map<String, dynamic> params,
  }) {
    send({
      'type': 'req',
      'method': method,
      'id': id,
      'params': params,
    });
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
        final ok = json['ok'] as bool? ?? false;
        if (_state == msg.GatewayConnectionState.authenticating) {
          if (ok) { _handleConnectOk(json); } else { _handleConnectError(json); }
          return;
        }
        // Forward non-connect responses to chat/listeners
        onRawMessage?.call(json);
        return;
      }

      // Forward events to listeners (ChatService etc.)
      onRawMessage?.call(json);

      // Store in raw message feed
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

      // Build device auth payload — must match what server rebuilds
      const clientId = 'openclaw-android';
      const clientMode = 'webchat';
      const role = 'operator';
      const scopesList = <String>['operator.admin'];
      final scopesStr = scopesList.join(',');
      final authPayload =
          'v2|$deviceId|$clientId|$clientMode|$role|$scopesStr|$signedAtMs|$token|$_nonce';

      debugPrint('🔐 Signing auth payload...');
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
      debugPrint('🔐 Sent connect request');
    } catch (e) {
      debugPrint('❌ Auth failed: $e');
      _errorMessage = 'Authentication failed: $e';
      _setState(msg.GatewayConnectionState.error);
    }
  }

  String? _mainSessionKey;
  String? get mainSessionKey => _mainSessionKey;

  void _handleConnectOk(Map<String, dynamic> json) {
    // Extract session key from hello-ok payload
    final payload = json['payload'] as Map<String, dynamic>?;
    final snapshot = payload?['snapshot'] as Map<String, dynamic>?;
    final sessionDefaults = snapshot?['sessionDefaults'] as Map<String, dynamic>?;
    _mainSessionKey = sessionDefaults?['mainSessionKey'] as String?;
    debugPrint('✅ Connected to gateway via ${_activeUrl ?? "unknown"}! session=$_mainSessionKey');
    _setState(msg.GatewayConnectionState.connected);
  }

  void _handleConnectError(Map<String, dynamic> json) {
    final error = json['error'] as Map<String, dynamic>?;
    final message = error?['message'] as String? ?? 'Unknown error';
    debugPrint('❌ Connect error: $message');

    if (message.contains('pairing required')) {
      _errorMessage = 'Waiting for pairing approval...';
      _setState(msg.GatewayConnectionState.pairingPending);
      // Retry periodically — approval will let us through
      _scheduleReconnect(delayMs: 3000);
    } else {
      _errorMessage = message;
      _setState(msg.GatewayConnectionState.error);
      _scheduleReconnect();
    }
  }

  void _onDone() {
    debugPrint('🔌 WebSocket closed');
    _activeUrl = null;
    _setState(msg.GatewayConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _onError(dynamic error) {
    debugPrint('❌ WebSocket error: $error');
    _errorMessage = error.toString();
    _activeUrl = null;
    _setState(msg.GatewayConnectionState.error);
    _scheduleReconnect();
  }

  void _scheduleReconnect({int? delayMs}) {
    if (_config?.autoReconnect != true) return;
    final delay = delayMs ?? _config?.reconnectDelayMs ?? 5000;
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
