// Web-specific implementation for canvas service using postMessage
import 'dart:html' show window;
import 'dart:async';
import 'dart:convert';

/// Web-specific canvas utilities using postMessage bridge
class CanvasWebBridge {
  static final Map<String, Completer<dynamic>> _pendingRequests = {};
  static int _requestIdCounter = 0;

  /// Send a command to the canvas and wait for response
  static Future<dynamic> sendCommand(String command, Map<String, dynamic> params) async {
    final requestId = 'req_${_requestIdCounter++}_${DateTime.now().millisecondsSinceEpoch}';
    final completer = Completer<dynamic>();
    _pendingRequests[requestId] = completer;

    // Send message to canvas iframe
    final message = {
      'source': 'openclaw-app',
      'type': command,
      'requestId': requestId,
      'params': params,
    };

    window.postMessage(jsonEncode(message), '*');

    // Set timeout for response
    Future.delayed(const Duration(seconds: 5), () {
      if (!completer.isCompleted) {
        _pendingRequests.remove(requestId);
        completer.completeError(TimeoutException('Canvas command timeout: $command'));
      }
    });

    return completer.future;
  }

  /// Handle response from canvas
  static void handleResponse(String requestId, dynamic result, String? error) {
    final completer = _pendingRequests.remove(requestId);
    if (completer == null) return;

    if (error != null) {
      completer.completeError(Exception(error));
    } else {
      completer.complete(result);
    }
  }

  /// Execute JavaScript in the canvas
  static Future<String> eval(String js) async {
    final result = await sendCommand('eval', {'js': js});
    return result.toString();
  }

  /// Take a snapshot of the canvas
  static Future<Map<String, dynamic>> snapshot({String format = 'png', double quality = 0.9}) async {
    final result = await sendCommand('snapshot', {
      'format': format,
      'quality': quality,
    });
    return result as Map<String, dynamic>;
  }

  /// Send data to canvas
  static void sendData(String key, dynamic value) {
    final message = {
      'source': 'openclaw-app',
      'type': 'data',
      'key': key,
      'value': value,
    };
    window.postMessage(jsonEncode(message), '*');
  }

  /// Send control command to canvas
  static void sendControl(String action, Map<String, dynamic>? params) {
    final message = {
      'source': 'openclaw-app',
      'type': 'control',
      'action': action,
      'params': params ?? {},
    };
    window.postMessage(jsonEncode(message), '*');
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);
  
  @override
  String toString() => message;
}
