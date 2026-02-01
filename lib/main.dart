import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/camera_service.dart';
import 'services/chat_service.dart';
import 'services/crypto_service.dart';
import 'services/gateway_service.dart';
import 'services/location_service.dart';
import 'services/node_connection_service.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize crypto (load or generate Ed25519 keys)
  final crypto = CryptoService();
  await crypto.init();

  // Create services
  final gateway = GatewayService(crypto); // Operator connection (chat)
  final nodeConnection = NodeConnectionService(crypto); // Node connection (camera)
  final chat = ChatService(gateway);
  final camera = CameraService(nodeConnection);
  final notifications = NotificationService(nodeConnection);
  final location = LocationService(nodeConnection);

  // Wire raw gateway messages to chat service
  gateway.onRawMessage = chat.handleGatewayMessage;

  // Initialize services
  await camera.init();
  await notifications.init();
  await location.init();

  runApp(ClawReachApp(
    crypto: crypto,
    gateway: gateway,
    nodeConnection: nodeConnection,
    chat: chat,
    camera: camera,
    notifications: notifications,
    location: location,
  ));
}

class ClawReachApp extends StatelessWidget {
  final CryptoService crypto;
  final GatewayService gateway;
  final NodeConnectionService nodeConnection;
  final ChatService chat;
  final CameraService camera;
  final NotificationService notifications;
  final LocationService location;

  const ClawReachApp({
    super.key,
    required this.crypto,
    required this.gateway,
    required this.nodeConnection,
    required this.chat,
    required this.camera,
    required this.notifications,
    required this.location,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: crypto),
        ChangeNotifierProvider.value(value: gateway),
        ChangeNotifierProvider.value(value: nodeConnection),
        ChangeNotifierProvider.value(value: chat),
        ChangeNotifierProvider.value(value: camera),
        ChangeNotifierProvider.value(value: notifications),
        ChangeNotifierProvider.value(value: location),
      ],
      child: MaterialApp(
        title: 'ClawReach',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.deepOrange,
          useMaterial3: true,
          brightness: Brightness.dark,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
