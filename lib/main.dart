import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/camera_service.dart';
import 'services/canvas_service.dart';
import 'services/chat_service.dart';
import 'services/connection_coordinator.dart';
import 'services/crypto_service.dart';
import 'services/fcm_service.dart';
import 'services/gateway_service.dart';
import 'services/location_service.dart';
import 'services/node_connection_service.dart';
import 'services/notification_service.dart';
import 'services/cached_tile_provider.dart';
import 'services/hike_service.dart';
import 'services/network_monitor_service.dart';
import 'services/capability_service.dart';
import 'screens/home_screen.dart';

/// True on Android/iOS — platforms with camera, GPS, notifications.
bool get isMobilePlatform =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FCM (before other services)
  if (isMobilePlatform) {
    await FcmService.init();
  }

  // Initialize crypto (load or generate Ed25519 keys)
  final crypto = CryptoService();
  await crypto.init();

  // Create services
  final gateway = GatewayService(crypto); // Operator connection (chat)
  final nodeConnection = NodeConnectionService(crypto); // Node connection (camera)
  final connectionCoordinator = ConnectionCoordinator(gateway, nodeConnection); // Reconnection coordination
  final chat = ChatService(gateway);
  final camera = CameraService(nodeConnection);
  final notifications = NotificationService(nodeConnection);
  final location = LocationService(nodeConnection);
  final canvasService = CanvasService(nodeConnection);
  final hikeService = HikeService();
  hikeService.setNodeConnection(nodeConnection);
  final capabilities = CapabilityService();
  final networkMonitor = NetworkMonitorService();

  // Wire raw gateway messages to chat service
  gateway.onRawMessage = chat.handleGatewayMessage;
  
  // Wire notification service to chat and canvas
  chat.setNotificationService(notifications);
  canvasService.setNotificationService(notifications);
  
  // Register FCM token refresh callback
  if (isMobilePlatform) {
    FcmService.onTokenRefresh = (newToken) {
      if (gateway.isConnected) {
        // Token will be registered in next connection via _handleConnectOk
        debugPrint('🔔 FCM token refreshed, will register on next connection');
      }
    };
  }
  
  // Wire gateway connection to capability probing
  gateway.onConnected = (url) {
    debugPrint('🔍 Gateway connected, probing capabilities...');
    capabilities.probe(url);
  };

  // Wire network monitor to trigger reconnects on network change
  networkMonitor.onNetworkReconnect = () {
    final config = gateway.activeConfig;
    if (!gateway.isConnected && config != null) {
      debugPrint('📶 Network reconnect → gateway');
      gateway.connect(config);
    }
  };
  await networkMonitor.init();

  // Initialize platform-specific services (camera, notifications, location)
  // only on mobile — these plugins crash on desktop/web.
  if (isMobilePlatform) {
    await camera.init();
    await notifications.init();
    await location.init();
  } else {
    debugPrint('🖥️ Desktop/Web — skipping camera, notifications, location init');
  }
  await CachedTileProvider.init();

  runApp(ClawReachApp(
    crypto: crypto,
    gateway: gateway,
    nodeConnection: nodeConnection,
    connectionCoordinator: connectionCoordinator,
    chat: chat,
    camera: camera,
    notifications: notifications,
    location: location,
    canvasService: canvasService,
    hikeService: hikeService,
    capabilities: capabilities,
    networkMonitor: networkMonitor,
  ));
}

class ClawReachApp extends StatelessWidget {
  final CryptoService crypto;
  final GatewayService gateway;
  final NodeConnectionService nodeConnection;
  final ConnectionCoordinator connectionCoordinator;
  final ChatService chat;
  final CameraService camera;
  final NotificationService notifications;
  final LocationService location;
  final CanvasService canvasService;
  final HikeService hikeService;
  final CapabilityService capabilities;
  final NetworkMonitorService networkMonitor;

  const ClawReachApp({
    super.key,
    required this.crypto,
    required this.gateway,
    required this.nodeConnection,
    required this.connectionCoordinator,
    required this.chat,
    required this.camera,
    required this.notifications,
    required this.location,
    required this.canvasService,
    required this.hikeService,
    required this.capabilities,
    required this.networkMonitor,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: crypto),
        ChangeNotifierProvider.value(value: gateway),
        ChangeNotifierProvider.value(value: nodeConnection),
        ChangeNotifierProvider.value(value: connectionCoordinator),
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider.value(value: camera),
        ChangeNotifierProvider.value(value: notifications),
        ChangeNotifierProvider.value(value: location),
        ChangeNotifierProvider.value(value: canvasService),
        ChangeNotifierProvider.value(value: hikeService),
        ChangeNotifierProvider.value(value: capabilities),
        ChangeNotifierProvider.value(value: networkMonitor),
      ],
      child: MaterialApp(
        title: 'ClawReach',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.deepOrange,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const WithForegroundTask(child: HomeScreen()),
      ),
    );
  }
}
