import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'node_connection_service.dart';

/// Handles system.notify commands from the gateway and shows local notifications.
class NotificationService extends ChangeNotifier {
  final NodeConnectionService _nodeConnection;
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  int _notificationId = 0;
  bool _isBackgrounded = false;

  NotificationService(this._nodeConnection) {
    _nodeConnection.registerHandler('system.notify', _handleNotify);
  }
  
  /// Update background state
  void setBackgrounded(bool backgrounded) {
    _isBackgrounded = backgrounded;
    debugPrint('🔔 Notification service: backgrounded=$backgrounded');
  }

  bool get isInitialized => _initialized;

  /// Initialize the notification plugin.
  Future<void> init() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Request notification permission (Android 13+)
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }

    _initialized = true;
    debugPrint('🔔 Notification service initialized');
    notifyListeners();
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('🔔 Notification tapped: ${response.payload}');
    // Could navigate to chat or specific content in the future
  }

  /// Handle system.notify command from gateway.
  Future<Map<String, dynamic>> _handleNotify(
    String requestId, String command, Map<String, dynamic> params,
  ) async {
    final title = params['title'] as String? ?? 'Fred 🦊';
    final body = params['body'] as String? ?? '';
    final priority = params['priority'] as String? ?? 'active';
    final sound = params['sound'] as String?;

    debugPrint('🔔 Notify: title="$title" body="$body" priority=$priority');

    if (!_initialized) {
      throw Exception('Notification service not initialized');
    }

    // Map priority to Android importance
    final importance = switch (priority) {
      'timeSensitive' => Importance.max,
      'active' => Importance.high,
      'passive' => Importance.low,
      _ => Importance.defaultImportance,
    };

    final androidDetails = AndroidNotificationDetails(
      'clawreach_notifications',
      'ClawReach',
      channelDescription: 'Notifications from Fred via OpenClaw',
      importance: importance,
      priority: importance == Importance.max ? Priority.max : Priority.high,
      playSound: sound != 'none',
      enableVibration: priority != 'passive',
      styleInformation: body.length > 100
          ? BigTextStyleInformation(body)
          : null,
    );

    final details = NotificationDetails(android: androidDetails);

    _notificationId++;
    await _notifications.show(
      _notificationId,
      title,
      body,
      details,
      payload: 'notify:$requestId',
    );

    return {'delivered': true};
  }

  /// Show notification for new chat message (when backgrounded)
  Future<void> notifyMessage(String senderName, String preview) async {
    if (!_initialized || !_isBackgrounded) return;

    debugPrint('🔔 Message notification: $senderName - $preview');

    final androidDetails = AndroidNotificationDetails(
      'clawreach_messages',
      'Messages',
      channelDescription: 'New messages from Fred',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(preview),
    );

    final details = NotificationDetails(android: androidDetails);

    _notificationId++;
    await _notifications.show(
      _notificationId,
      senderName,
      preview,
      details,
      payload: 'message:new',
    );
  }

  /// Show notification for canvas update (when backgrounded)
  Future<void> notifyCanvasUpdate(String title, String description) async {
    if (!_initialized || !_isBackgrounded) return;

    debugPrint('🔔 Canvas notification: $title');

    final androidDetails = AndroidNotificationDetails(
      'clawreach_canvas',
      'Canvas Updates',
      channelDescription: 'Canvas and A2UI updates',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    final details = NotificationDetails(android: androidDetails);

    _notificationId++;
    await _notifications.show(
      _notificationId,
      title,
      description,
      details,
      payload: 'canvas:update',
    );
  }
}
