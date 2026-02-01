import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'node_connection_service.dart';

/// Handles camera.snap and camera.list commands from the gateway.
class CameraService extends ChangeNotifier {
  final NodeConnectionService _nodeConnection;
  List<CameraDescription> _cameras = [];
  bool _initialized = false;

  CameraService(this._nodeConnection) {
    // Register command handlers
    _nodeConnection.registerHandler('camera.snap', _handleSnap);
    _nodeConnection.registerHandler('camera.list', _handleList);
  }

  bool get isInitialized => _initialized;
  List<CameraDescription> get cameras => _cameras;

  /// Initialize available cameras.
  Future<void> init() async {
    try {
      _cameras = await availableCameras();
      _initialized = _cameras.isNotEmpty;
      debugPrint('📷 Found ${_cameras.length} cameras');
      for (final cam in _cameras) {
        debugPrint('  - ${cam.name} (${cam.lensDirection})');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Camera init error: $e');
    }
  }

  /// Handle camera.list command.
  Future<Map<String, dynamic>> _handleList(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final cameraList = _cameras.map((c) => {
      'id': c.name,
      'facing': c.lensDirection == CameraLensDirection.front ? 'front' : 'back',
      'sensorOrientation': c.sensorOrientation,
    }).toList();

    return {'cameras': cameraList};
  }

  /// Handle camera.snap command.
  Future<Map<String, dynamic>> _handleSnap(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    // Check permission
    final status = await Permission.camera.status;
    if (!status.isGranted) {
      final result = await Permission.camera.request();
      if (!result.isGranted) {
        throw Exception('Camera permission denied');
      }
    }

    final facing = params['facing'] as String? ?? 'back';
    final maxWidth = params['maxWidth'] as num?;
    final quality = params['quality'] as num? ?? 85;
    final delayMs = params['delayMs'] as num?;
    final format = params['format'] as String? ?? 'jpg';

    debugPrint('📷 Snap requested: facing=$facing maxWidth=$maxWidth quality=$quality');

    // Find the right camera
    final lensDirection = facing == 'front'
        ? CameraLensDirection.front
        : CameraLensDirection.back;

    final camera = _cameras.firstWhere(
      (c) => c.lensDirection == lensDirection,
      orElse: () => _cameras.first,
    );

    // Create controller and capture
    final controller = CameraController(
      camera,
      maxWidth != null && maxWidth <= 640
          ? ResolutionPreset.low
          : maxWidth != null && maxWidth <= 1280
              ? ResolutionPreset.medium
              : ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();

      // Optional delay (e.g. for flash/autofocus)
      if (delayMs != null && delayMs > 0) {
        await Future.delayed(Duration(milliseconds: delayMs.toInt()));
      }

      // Take picture
      final xFile = await controller.takePicture();
      final bytes = await xFile.readAsBytes();

      debugPrint('📷 Captured ${bytes.length} bytes from ${camera.name}');

      // Decode to get dimensions using callback-based API
      final completer = Completer<ui.Image>();
      ui.decodeImageFromList(bytes, completer.complete);
      final decoded = await completer.future;
      final int finalWidth = decoded.width;
      final int finalHeight = decoded.height;
      decoded.dispose();

      final Uint8List finalBytes = bytes;

      // Base64 encode
      final base64Data = base64Encode(finalBytes);

      debugPrint('📷 Sending ${finalWidth}x$finalHeight $format (${(base64Data.length / 1024).round()}KB base64)');

      // Clean up temp file
      try { await File(xFile.path).delete(); } catch (_) {}

      return {
        'format': format == 'png' ? 'png' : 'jpg',
        'base64': base64Data,
        'width': finalWidth,
        'height': finalHeight,
      };
    } finally {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
