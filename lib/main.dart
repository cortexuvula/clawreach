import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/chat_service.dart';
import 'services/crypto_service.dart';
import 'services/gateway_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize crypto (load or generate Ed25519 keys)
  final crypto = CryptoService();
  await crypto.init();

  // Create services
  final gateway = GatewayService(crypto);
  final chat = ChatService(gateway);

  // Wire raw gateway messages to chat service
  gateway.onRawMessage = chat.handleGatewayMessage;

  runApp(ClawReachApp(crypto: crypto, gateway: gateway, chat: chat));
}

class ClawReachApp extends StatelessWidget {
  final CryptoService crypto;
  final GatewayService gateway;
  final ChatService chat;

  const ClawReachApp({
    super.key,
    required this.crypto,
    required this.gateway,
    required this.chat,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: crypto),
        ChangeNotifierProvider.value(value: gateway),
        ChangeNotifierProvider.value(value: chat),
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
