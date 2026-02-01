import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/crypto_service.dart';
import 'services/gateway_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize crypto (load or generate Ed25519 keys)
  final crypto = CryptoService();
  await crypto.init();

  runApp(ClawReachApp(crypto: crypto));
}

class ClawReachApp extends StatelessWidget {
  final CryptoService crypto;

  const ClawReachApp({super.key, required this.crypto});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: crypto),
        ChangeNotifierProvider(
          create: (_) => GatewayService(crypto),
        ),
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
