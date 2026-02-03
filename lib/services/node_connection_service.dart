import 'dart:async';
import 'dart:convert';
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
  bool _pairingPending = false;
  Timer? _pairingRetryTimer;
  int _pairingRetryCount = 0;
  static const _maxPairingRetries = 60; // 5 min at 5s intervals

  /// Register command handlers here.
  final Map<String, InvokeHandler> _handlers = {};

  NodeConnectionService(this._crypto);

  bool get isConnected => _connected;
  bool get isPairingPending => _pairingPending;
  String? get nodeId => _nodeId;
  GatewayConfig? get activeConfig => _config;

  /// Register a handler for a node command (e.g. 'camera.snap').
  void registerHandler(String command, InvokeHandler handler) {
    _handlers[command] = handler;
  }

  bool _connecting = false;

  /// Connect as node role.
  Future<void> connect(GatewayConfig config) async {
    if (_connecting) {
      debugPrint('⚠️ [Node] connect() already in progress, skipping');
      return;
    }
    _connecting = true;
    _config = config;
    _reconnectTimer?.cancel();

    // Always close old channel — even if handshake never completed
    await _closeChannel();

    // Try local first, then fallback (same as operator connection)
    final localWs = config.wsUrl;
    debugPrint('🔌 [Node] Trying local: $localWs');

    if (await _tryConnect(localWs, config.localTimeoutMs)) {
      _activeUrl = config.url;
      _connecting = false;
      return;
    }

    if (config.hasFallback) {
      final fallbackWs = config.fallbackWsUrl!;
      debugPrint('🔌 [Node] Trying fallback: $fallbackWs');
      if (await _tryConnect(fallbackWs, 10000)) {
        _activeUrl = config.fallbackUrl;
        _connecting = false;
        return;
      }
    }

    debugPrint('❌ [Node] All connection attempts failed');
    _connecting = false;
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
      // Capture reference for zombie detection in callbacks
      final thisChannel = channel;
      _channel!.stream.listen(
        _onMessage,
        onDone: () => _onDone(thisChannel),
        onError: (e) => _onError(e, thisChannel),
      );
      return true;
    } catch (e) {
      debugPrint('❌ [Node] Connect error: $e');
      return false;
    }
  }

  /// Close the underlying WebSocket without cancelling reconnect timers.
  Future<void> _closeChannel() async {
    final old = _channel;
    _channel = null;
    _connected = false;
    _activeUrl = null;
    try {
      await old?.sink.close();
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _connecting = false;
    _reconnectTimer?.cancel();
    _pairingRetryTimer?.cancel();
    await _closeChannel();
    _pairingPending = false;
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
            _pairingPending = false;
            _pairingRetryCount = 0;
            _pairingRetryTimer?.cancel();
            debugPrint('✅ [Node] Connected as node');
            notifyListeners();
          } else {
            final error = json['error'] as Map<String, dynamic>?;
            final errorMsg = error?['message'] as String? ?? '';
            debugPrint('❌ [Node] Connect rejected: $errorMsg');
            if (errorMsg.contains('pairing required')) {
              // Gateway already created a pending request in devices/pending.json
              // during the connect handshake. Don't send node.pair.request —
              // the connection is closing. Just enter pairing-pending state
              // and retry connect periodically until approved.
              _enterPairingPendingState();
            } else {
              _scheduleReconnect();
            }
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
          'caps': ['camera', 'notifications', 'location', 'canvas'],
          'commands': [
            'camera.snap', 'camera.list',
            'system.notify', 'location.get',
            'canvas.present', 'canvas.hide', 'canvas.navigate',
            'canvas.eval', 'canvas.snapshot',
            'canvas.a2ui.push', 'canvas.a2ui.pushJSONL', 'canvas.a2ui.reset',
          ],
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

      debugPrint('🔐 [Node] Device ID: $deviceId');
      debugPrint('🔐 [Node] Sent node connect request');
    } catch (e) {
      debugPrint('❌ [Node] Auth failed: $e');
    }
  }

  /// Enter pairing-pending state: the gateway already has our pending request
  /// in devices/pending.json (created during the connect handshake).
  /// We just need to retry connecting periodically until it's approved.
  void _enterPairingPendingState() {
    if (_pairingPending && _pairingRetryTimer?.isActive == true) {
      return; // Already in pairing-pending state
    }

    _pairingPending = true;
    _pairingRetryCount = 0;
    notifyListeners();

    debugPrint('🔗 [Node] Pairing pending — gateway has our request. '
        'Retrying connect every 5s until approved...');

    _pairingRetryTimer?.cancel();
    _pairingRetryTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _pairingRetryCount++;
      if (_pairingRetryCount > _maxPairingRetries) {
        debugPrint('❌ [Node] Pairing timed out after $_maxPairingRetries retries');
        timer.cancel();
        _pairingPending = false;
        notifyListeners();
        return;
      }

      if (_connected) {
        timer.cancel();
        return;
      }

      debugPrint('🔗 [Node] Pairing retry $_pairingRetryCount/$_maxPairingRetries...');
      if (_config != null) {
        connect(_config!);
      }
    });
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

  /// Send a node event to the gateway (e.g. user actions from canvas).
  void sendNodeEvent(String event, Map<String, dynamic> payload) {
    if (!_connected) {
      debugPrint('⚠️ [Node] Cannot send event while disconnected');
      return;
    }
    _send({
      'type': 'req',
      'method': 'node.event',
      'id': _uuid.v4(),
      'params': {
        'event': event,
        'payload': payload,
      },
    });
    debugPrint('📤 [Node] Sent event: $event');
  }

  void _onDone(WebSocketChannel caller) {
    // Ignore callbacks from zombie (replaced) channels
    if (caller != _channel) {
      debugPrint('👻 [Node] Ignoring _onDone from zombie channel');
      return;
    }
    debugPrint('🔌 [Node] WebSocket closed');
    _connected = false;
    _activeUrl = null;
    notifyListeners();
    _scheduleReconnect();
  }

  void _onError(dynamic error, WebSocketChannel caller) {
    if (caller != _channel) {
      debugPrint('👻 [Node] Ignoring _onError from zombie channel');
      return;
    }
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
    _pairingRetryTimer?.cancel();
    _channel?.sink.close();
    super.dispose();
  }
}
