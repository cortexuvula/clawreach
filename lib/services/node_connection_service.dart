import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/gateway_config.dart';
import 'crypto_service.dart';

/// Callback for incoming node invoke requests.
typedef InvokeHandler = Future<Map<String, dynamic>> Function(
  String requestId,
  String command,
  Map<String, dynamic> params,
);

/// Lightweight second WebSocket connection as node role.
/// Handles camera.snap, camera.list, and other node commands.
class NodeConnectionService extends ChangeNotifier {
  final CryptoService _crypto;
  static const _uuid = Uuid();
  static const _protocolVersion = 3;

  WebSocketChannel? _channel;
  bool _connected = false;
  String? _activeUrl;
  String? _nodeId;
  Timer? _reconnectTimer;
  GatewayConfig? _config;
  String? _nonce;

  /// Register command handlers here.
  final Map<String, InvokeHandler> _handlers = {};

  NodeConnectionService(this._crypto);

  bool get isConnected => _connected;
  String? get nodeId => _nodeId;

  /// Register a handler for a node command (e.g. 'camera.snap').
  void registerHandler(String command, InvokeHandler handler) {
    _handlers[command] = handler;
  }

  /// Connect as node role.
  Future<void> connect(GatewayConfig config) async {
    _config = config;
    _reconnectTimer?.cancel();

    if (_connected) await disconnect();

    // Try local first, then fallback (same as operator connection)
    final localWs = config.wsUrl;
    debugPrint('🔌 [Node] Trying local: $localWs');

    if (await _tryConnect(localWs, config.localTimeoutMs)) {
      _activeUrl = config.url;
      return;
    }

    if (config.hasFallback) {
      final fallbackWs = config.fallbackWsUrl!;
      debugPrint('🔌 [Node] Trying fallback: $fallbackWs');
      if (await _tryConnect(fallbackWs, 10000)) {
        _activeUrl = config.fallbackUrl;
        return;
      }
    }

    debugPrint('❌ [Node] All connection attempts failed');
    _scheduleReconnect();
  }

  Future<bool> _tryConnect(String wsUrl, int timeoutMs) async {
    try {
      final channel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        protocols: ['openclaw-node'],
      );

      await channel.ready.timeout(
        Duration(milliseconds: timeoutMs),
        onTimeout: () => throw TimeoutException('Timeout after ${timeoutMs}ms'),
      );

      _channel = channel;
      _channel!.stream.listen(_onMessage, onDone: _onDone, onError: _onError);
      return true;
    } catch (e) {
      debugPrint('❌ [Node] Connect error: $e');
      return false;
    }
  }

  Future<void> disconnect() async {
    _reconnectTimer?.cancel();
    await _channel?.sink.close();
    _channel = null;
    _connected = false;
    _activeUrl = null;
    notifyListeners();
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void _onMessage(dynamic data) {
    try {
      final json = jsonDecode(data as String) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      if (type == 'event') {
        final event = json['event'] as String? ?? '';
        if (event == 'connect.challenge') {
          _handleChallenge(json);
        } else if (event == 'node.invoke.request') {
          _handleInvokeRequest(json);
        }
      } else if (type == 'res') {
        final ok = json['ok'] as bool? ?? false;
        if (!_connected) {
          if (ok) {
            _connected = true;
            debugPrint('✅ [Node] Connected as node');
            notifyListeners();
          } else {
            final error = json['error'] as Map<String, dynamic>?;
            debugPrint('❌ [Node] Connect rejected: ${error?['message']}');
            _scheduleReconnect();
          }
        }
      }
    } catch (e) {
      debugPrint('❌ [Node] Message parse error: $e');
    }
  }

  Future<void> _handleChallenge(Map<String, dynamic> json) async {
    final payload = json['payload'] as Map<String, dynamic>?;
    _nonce = payload?['nonce'] as String?;
    if (_nonce == null) return;

    try {
      final publicKeyB64Url = await _crypto.getPublicKeyBase64Url();
      final publicKeyRaw = await _crypto.getPublicKeyRaw();
      final deviceId = sha256.convert(publicKeyRaw).toString();
      _nodeId = deviceId;

      final signedAtMs = DateTime.now().millisecondsSinceEpoch;
      final token = _config?.token ?? '';
      final nodeName = _config?.nodeName ?? 'ClawReach';

      const clientId = 'openclaw-android';
      const clientMode = 'node';
      const role = 'node';
      final scopesStr = ''; // nodes have no scopes

      final authPayload =
          'v2|$deviceId|$clientId|$clientMode|$role|$scopesStr|$signedAtMs|$token|$_nonce';

      final signature = await _crypto.signString(authPayload);

      _send({
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
          'scopes': <String>[],
          'caps': ['camera', 'notifications'],
          'commands': ['camera.snap', 'camera.list', 'system.notify'],
          'auth': {'token': token},
          'device': {
            'id': deviceId,
            'publicKey': publicKeyB64Url,
            'signature': signature,
            'signedAt': signedAtMs,
            'nonce': _nonce,
          },
        },
      });

      debugPrint('🔐 [Node] Sent node connect request');
    } catch (e) {
      debugPrint('❌ [Node] Auth failed: $e');
    }
  }

  Future<void> _handleInvokeRequest(Map<String, dynamic> json) async {
    final payload = json['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    final requestId = payload['id'] as String? ?? '';
    final command = payload['command'] as String? ?? '';
    final paramsJSON = payload['paramsJSON'] as String?;
    final params = paramsJSON != null
        ? (jsonDecode(paramsJSON) as Map<String, dynamic>)
        : <String, dynamic>{};

    debugPrint('📥 [Node] Invoke: $command (id=$requestId)');

    final handler = _handlers[command];
    if (handler == null) {
      debugPrint('⚠️ [Node] No handler for: $command');
      _sendInvokeResult(requestId, false, error: 'Unsupported command: $command');
      return;
    }

    try {
      final result = await handler(requestId, command, params);
      _sendInvokeResult(requestId, true, payload: result);
    } catch (e) {
      debugPrint('❌ [Node] Handler error: $e');
      _sendInvokeResult(requestId, false, error: e.toString());
    }
  }

  void _sendInvokeResult(String requestId, bool ok,
      {Map<String, dynamic>? payload, String? error}) {
    _send({
      'type': 'req',
      'method': 'node.invoke.result',
      'id': _uuid.v4(),
      'params': {
        'id': requestId,
        'nodeId': _nodeId ?? '',
        'ok': ok,
        if (payload != null) 'payload': payload,
        if (error != null) 'error': {'code': 'ERROR', 'message': error},
      },
    });
  }

  void _onDone() {
    debugPrint('🔌 [Node] WebSocket closed');
    _connected = false;
    _activeUrl = null;
    notifyListeners();
    _scheduleReconnect();
  }

  void _onError(dynamic error) {
    debugPrint('❌ [Node] WebSocket error: $error');
    _connected = false;
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_config?.autoReconnect != true) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      if (_config != null) connect(_config!);
    });
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
