// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Web-specific location service using Geolocation API.
class LocationServiceWeb extends ChangeNotifier {
  bool _initialized = false;

  bool get isInitialized => _initialized;

  /// Initialize location service (web doesn't require pre-init).
  Future<void> init() async {
    _initialized = true;
    debugPrint('📍 Location service initialized (web)');
    notifyListeners();
  }

  /// Handle location.get command using browser Geolocation API.
  Future<Map<String, dynamic>> handleLocationGet(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final desiredAccuracy = params['desiredAccuracy'] as String? ?? 'balanced';
    final maxAgeMs = params['maxAgeMs'] as num?;
    final timeoutMs = params['timeoutMs'] as num? ?? 10000;

    debugPrint('📍 Web location requested: accuracy=$desiredAccuracy timeout=${timeoutMs}ms');

    // Map accuracy to enableHighAccuracy
    final enableHighAccuracy = switch (desiredAccuracy) {
      'precise' => true,
      'balanced' => true,
      'coarse' => false,
      _ => true,
    };

    try {
      final position = await html.window.navigator.geolocation.getCurrentPosition(
            enableHighAccuracy: enableHighAccuracy,
            timeout: Duration(milliseconds: timeoutMs.toInt()),
            maximumAge: Duration(milliseconds: maxAgeMs?.toInt() ?? 0),
          );

      final coords = position.coords;
      
      final lat = coords?.latitude ?? 0.0;
      final lon = coords?.longitude ?? 0.0;
      final accuracy = coords?.accuracy ?? 0.0;
      
      debugPrint('📍 Got position: $lat,$lon ±${accuracy}m');

      return {
        'lat': lat,
        'lon': lon,
        'accuracyMeters': accuracy,
        'altitudeMeters': coords?.altitude ?? 0.0,
        'speedMps': coords?.speed ?? 0.0,
        'headingDegrees': coords?.heading ?? 0.0,
        'timestamp': DateTime.fromMillisecondsSinceEpoch(
          position.timestamp ?? DateTime.now().millisecondsSinceEpoch
        ).toIso8601String(),
      };
    } catch (e) {
      debugPrint('❌ Web geolocation error: $e');
      
      // Provide helpful error messages
      final errorStr = e.toString();
      if (errorStr.contains('PERMISSION_DENIED') || 
          errorStr.contains('User denied')) {
        throw Exception('Location permission denied. Please allow location access in your browser.');
      } else if (errorStr.contains('POSITION_UNAVAILABLE')) {
        throw Exception('Location unavailable. Please check GPS/location services.');
      } else if (errorStr.contains('TIMEOUT')) {
        throw Exception('Location request timed out after ${timeoutMs}ms');
      }
      
      rethrow;
    }
  }
}
