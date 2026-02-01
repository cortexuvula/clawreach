import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'node_connection_service.dart';

/// Handles location.get commands from the gateway.
class LocationService extends ChangeNotifier {
  final NodeConnectionService _nodeConnection;
  bool _initialized = false;

  LocationService(this._nodeConnection) {
    _nodeConnection.registerHandler('location.get', _handleLocationGet);
  }

  bool get isInitialized => _initialized;

  /// Check and request location permissions.
  Future<void> init() async {
    final status = await Permission.location.status;
    if (!status.isGranted) {
      await Permission.location.request();
    }
    _initialized = true;
    debugPrint('📍 Location service initialized');
    notifyListeners();
  }

  /// Handle location.get command from gateway.
  Future<Map<String, dynamic>> _handleLocationGet(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final desiredAccuracy = params['desiredAccuracy'] as String? ?? 'balanced';
    final maxAgeMs = params['maxAgeMs'] as num?;
    final timeoutMs = params['timeoutMs'] as num? ?? 10000;

    debugPrint('📍 Location requested: accuracy=$desiredAccuracy timeout=${timeoutMs}ms');

    // Check permission
    final permission = await Permission.location.status;
    if (!permission.isGranted) {
      final result = await Permission.location.request();
      if (!result.isGranted) {
        throw Exception('Location permission denied');
      }
    }

    // Check if location services are enabled
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Location services disabled');
    }

    // Map accuracy
    final accuracy = switch (desiredAccuracy) {
      'coarse' => LocationAccuracy.low,
      'balanced' => LocationAccuracy.medium,
      'precise' => LocationAccuracy.best,
      _ => LocationAccuracy.medium,
    };

    // Try cached location first if maxAgeMs specified
    if (maxAgeMs != null) {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        final ageMs = DateTime.now().difference(lastKnown.timestamp).inMilliseconds;
        if (ageMs <= maxAgeMs.toInt()) {
          debugPrint('📍 Using cached location (age: ${ageMs}ms)');
          return _positionToPayload(lastKnown);
        }
      }
    }

    // Get fresh position
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        timeLimit: Duration(milliseconds: timeoutMs.toInt()),
      ),
    );

    debugPrint('📍 Got position: ${position.latitude},${position.longitude} ±${position.accuracy}m');

    return _positionToPayload(position);
  }

  Map<String, dynamic> _positionToPayload(Position position) {
    return {
      'lat': position.latitude,
      'lon': position.longitude,
      'accuracyMeters': position.accuracy,
      'altitudeMeters': position.altitude,
      'speedMps': position.speed,
      'headingDegrees': position.heading,
      'timestamp': position.timestamp.toIso8601String(),
    };
  }
}
