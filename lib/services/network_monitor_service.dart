import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Monitors network connectivity changes and triggers reconnects.
///
/// When the network changes (WiFi → cellular, or reconnects after loss),
/// fires a callback so services can reconnect immediately instead of
/// waiting for the backoff timer.
class NetworkMonitorService extends ChangeNotifier {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _currentState = [];
  bool _hasNetwork = false;

  /// Callback fired when network changes and we should reconnect.
  void Function()? onNetworkReconnect;

  bool get hasNetwork => _hasNetwork;
  bool get isWifi => _currentState.contains(ConnectivityResult.wifi);
  bool get isCellular => _currentState.contains(ConnectivityResult.mobile);
  String get networkType {
    if (isWifi) return 'WiFi';
    if (isCellular) return 'Cellular';
    if (_hasNetwork) return 'Other';
    return 'None';
  }

  /// Start monitoring network changes.
  Future<void> init() async {
    // Get initial state
    _currentState = await _connectivity.checkConnectivity();
    _hasNetwork = _hasConnectivity(_currentState);
    debugPrint('📶 Network init: $networkType (${_currentState.map((r) => r.name).join(", ")})');

    // Listen for changes
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final hadNetwork = _hasNetwork;
      final wasWifi = isWifi;
      _currentState = results;
      _hasNetwork = _hasConnectivity(results);

      debugPrint('📶 Network changed: $networkType (${results.map((r) => r.name).join(", ")})');

      // Trigger reconnect on:
      // 1. Network restored after loss
      // 2. WiFi ↔ cellular switch (IP changes, need new connection)
      if ((!hadNetwork && _hasNetwork) || (wasWifi != isWifi && _hasNetwork)) {
        debugPrint('📶 Network transition — triggering reconnect');
        onNetworkReconnect?.call();
        notifyListeners();
      }
    });
  }

  bool _hasConnectivity(List<ConnectivityResult> results) {
    return results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
