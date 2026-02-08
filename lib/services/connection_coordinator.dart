import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/gateway_config.dart';
import '../models/message.dart' as msg;
import 'gateway_service.dart';
import 'node_connection_service.dart';

/// Coordinates reconnection between operator and node connections.
/// Ensures proper sequencing to avoid double pairing requests.
class ConnectionCoordinator extends ChangeNotifier {
  final GatewayService _gateway;
  final NodeConnectionService _node;
  
  bool _isReconnecting = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  
  ConnectionCoordinator(this._gateway, this._node) {
    // Listen to gateway disconnections to trigger coordinated reconnect
    _gateway.addListener(_onGatewayStateChanged);
    _node.addListener(_onNodeStateChanged);
  }
  
  bool get isReconnecting => _isReconnecting;
  int get reconnectAttempts => _reconnectAttempts;
  
  void _onGatewayStateChanged() {
    final state = _gateway.state;
    
    // If operator disconnects, cancel node reconnect timer
    // We'll reconnect both in sequence
    if (state == msg.GatewayConnectionState.disconnected ||
        state == msg.GatewayConnectionState.error) {
      debugPrint('🔗 Gateway disconnected, will coordinate reconnect');
    }
    
    // If operator connects, connect node
    if (state == msg.GatewayConnectionState.connected && !_node.isConnected) {
      debugPrint('🔗 Gateway connected, connecting node...');
      _connectNode();
    }
  }
  
  void _onNodeStateChanged() {
    // Monitor node connection state
    if (_node.isConnected) {
      _reconnectAttempts = 0; // Reset counter on successful connection
      _isReconnecting = false;
      notifyListeners();
    }
  }
  
  /// Connect both services in sequence (operator → node)
  Future<void> connectAll(GatewayConfig config) async {
    debugPrint('🔗 Coordinated connect: operator → node');
    _isReconnecting = true;
    notifyListeners();
    
    try {
      // Connect operator first
      await _gateway.connect(config);
      
      // Wait for operator to be fully connected
      final connected = await _waitForGatewayConnection(timeout: Duration(seconds: 10));
      
      if (connected) {
        debugPrint('🔗 Operator connected, connecting node...');
        await _connectNode();
      } else {
        debugPrint('⚠️ Operator connection timeout, node will retry later');
      }
    } finally {
      _isReconnecting = false;
      notifyListeners();
    }
  }
  
  /// Connect only the node service
  Future<void> _connectNode() async {
    final config = _gateway.activeConfig;
    if (config != null) {
      _node.connect(config);
    }
  }
  
  /// Wait for gateway to reach connected state
  Future<bool> _waitForGatewayConnection({required Duration timeout}) async {
    if (_gateway.isConnected) return true;
    
    final completer = Completer<bool>();
    Timer? timeoutTimer;
    
    void listener() {
      if (_gateway.isConnected) {
        _gateway.removeListener(listener);
        timeoutTimer?.cancel();
        if (!completer.isCompleted) completer.complete(true);
      }
    }
    
    _gateway.addListener(listener);
    
    timeoutTimer = Timer(timeout, () {
      _gateway.removeListener(listener);
      if (!completer.isCompleted) completer.complete(false);
    });
    
    return completer.future;
  }
  
  /// Manually trigger reconnection (for UI button)
  Future<void> reconnect() async {
    final config = _gateway.activeConfig;
    if (config == null) {
      debugPrint('⚠️ No config available for reconnect');
      return;
    }
    
    debugPrint('🔄 Manual reconnect triggered');
    _reconnectAttempts = 0;
    await connectAll(config);
  }
  
  /// Disconnect both services
  Future<void> disconnectAll() async {
    debugPrint('🔗 Coordinated disconnect');
    _reconnectTimer?.cancel();
    _isReconnecting = false;
    _reconnectAttempts = 0;
    
    await _node.disconnect();
    await _gateway.disconnect();
    
    notifyListeners();
  }
  
  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _gateway.removeListener(_onGatewayStateChanged);
    _node.removeListener(_onNodeStateChanged);
    super.dispose();
  }
}
