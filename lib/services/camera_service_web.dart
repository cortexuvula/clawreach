import 'dart:async';
// ignore: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart';

/// Web-specific camera service using getUserMedia API.
class CameraServiceWeb extends ChangeNotifier {
  html.MediaStream? _currentStream;
  bool _initialized = false;

  bool get isInitialized => _initialized;
  List<Map<String, dynamic>> get cameras => [
    {'id': 'user', 'facing': 'front', 'name': 'Front Camera'},
    {'id': 'environment', 'facing': 'back', 'name': 'Back Camera'},
  ];

  /// Initialize camera (web doesn't require pre-init).
  Future<void> init() async {
    _initialized = true;
    debugPrint('📷 Camera service initialized (web)');
    notifyListeners();
  }

  /// Handle camera.list command.
  Future<Map<String, dynamic>> handleList(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    return {'cameras': cameras};
  }

  /// Handle camera.snap command using getUserMedia.
  Future<Map<String, dynamic>> handleSnap(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final facing = params['facing'] as String? ?? 'back';
    final maxWidth = params['maxWidth'] as num? ?? 1920;
    final quality = params['quality'] as num? ?? 85;
    final delayMs = params['delayMs'] as num?;
    final format = params['format'] as String? ?? 'jpg';

    debugPrint('📷 Web snap requested: facing=$facing maxWidth=$maxWidth quality=$quality');

    // Request camera permission and stream
    final facingMode = facing == 'front' ? 'user' : 'environment';
    
    try {
      final constraints = {
        'video': {
          'facingMode': facingMode,
          'width': {'ideal': maxWidth.toInt()},
        }
      };

      final stream = await html.window.navigator.mediaDevices!
          .getUserMedia(constraints);
      
      _currentStream = stream;

      // Create video element
      final videoElement = html.VideoElement()
        ..srcObject = stream
        ..autoplay = true
        ..setAttribute('playsinline', 'true');

      // Wait for video to be ready
      await videoElement.onLoadedMetadata.first;
      await Future.delayed(const Duration(milliseconds: 100)); // Let it stabilize

      // Optional delay for focus/exposure
      if (delayMs != null && delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs.toInt()));
      }

      // Create canvas and capture frame
      final canvas = html.CanvasElement(
        width: videoElement.videoWidth,
        height: videoElement.videoHeight,
      );
      
      final context = canvas.context2D;
      context.drawImageScaled(videoElement, 0, 0, 
        videoElement.videoWidth.toDouble(), 
        videoElement.videoHeight.toDouble());

      // Stop the stream
      stream.getTracks().forEach((track) => track.stop());
      _currentStream = null;

      // Get image data
      final mimeType = format == 'png' ? 'image/png' : 'image/jpeg';
      final dataUrl = canvas.toDataUrl(mimeType, quality.toDouble() / 100.0);
      
      // Extract base64 data (remove data:image/jpeg;base64, prefix)
      final base64Data = dataUrl.split(',')[1];

      debugPrint('📷 Captured ${videoElement.videoWidth}x${videoElement.videoHeight} '
          '$format (${(base64Data.length / 1024).round()}KB base64)');

      return {
        'format': format == 'png' ? 'png' : 'jpg',
        'base64': base64Data,
        'width': videoElement.videoWidth,
        'height': videoElement.videoHeight,
      };
    } catch (e) {
      debugPrint('❌ Web camera error: $e');
      
      // Clean up stream if error
      if (_currentStream != null) {
        _currentStream!.getTracks().forEach((track) => track.stop());
        _currentStream = null;
      }
      
      // Provide helpful error messages
      if (e.toString().contains('NotAllowedError')) {
        throw Exception('Camera permission denied. Please allow camera access in your browser.');
      } else if (e.toString().contains('NotFoundError')) {
        throw Exception('No camera found on this device.');
      } else if (e.toString().contains('NotReadableError')) {
        throw Exception('Camera is already in use by another application.');
      }
      
      rethrow;
    }
  }

  @override
  void dispose() {
    // Clean up any active streams
    if (_currentStream != null) {
      _currentStream!.getTracks().forEach((track) => track.stop());
      _currentStream = null;
    }
    super.dispose();
  }
}
