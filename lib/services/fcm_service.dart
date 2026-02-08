import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

/// Handles Firebase Cloud Messaging for push notifications when app is killed
class FcmService {
  static FirebaseMessaging? _messaging;
  static String? _fcmToken;
  static Function(String token)? onTokenRefresh;
  
  static String? get fcmToken => _fcmToken;

  /// Initialize FCM. Call once at app startup.
  static Future<void> init() async {
    try {
      // Initialize Firebase
      await Firebase.initializeApp();
      debugPrint('🔔 Firebase initialized');

      _messaging = FirebaseMessaging.instance;

      // Request notification permission (iOS + Android 13+)
      final settings = await _messaging!.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint('🔔 FCM permission: ${settings.authorizationStatus}');

      // Get FCM token
      _fcmToken = await _messaging!.getToken();
      debugPrint('🔔 FCM token: $_fcmToken');

      // Listen for token refresh
      _messaging!.onTokenRefresh.listen((newToken) {
        debugPrint('🔔 FCM token refreshed: $newToken');
        _fcmToken = newToken;
        onTokenRefresh?.call(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle background message tap
      FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageTap);

      // Handle message that opened app from terminated state
      final initialMessage = await _messaging!.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('🔔 App opened from terminated state via FCM');
        _handleMessageTap(initialMessage);
      }

      // Register background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      debugPrint('✅ FCM service initialized');
    } catch (e) {
      debugPrint('❌ FCM init failed: $e');
    }
  }

  /// Handle message received while app is in foreground
  static void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('🔔 FCM foreground message: ${message.notification?.title}');
    // App is open, message handled by WebSocket already
    // Could show in-app banner here if desired
  }

  /// Handle notification tap (background or terminated)
  static void _handleMessageTap(RemoteMessage message) {
    debugPrint('🔔 FCM notification tapped: ${message.data}');
    // Navigate to chat screen or specific message
    // Implementation depends on your routing setup
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔔 FCM background message: ${message.notification?.title}');
  // Android shows notification automatically
  // This handler is for custom processing (optional)
}
