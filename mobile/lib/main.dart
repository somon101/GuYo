import 'package:flutter/material.dart';
import 'api/api_client.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const GuyoApp());
}

class GuyoApp extends StatelessWidget {
  const GuyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GuYo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const _StartupGate(),
    );
  }
}

/// Decides whether to show the login screen or jump straight to the home
/// screen, based on whether a session token is already stored on-device.
class _StartupGate extends StatefulWidget {
  const _StartupGate();

  @override
  State<_StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<_StartupGate> {
  late Future<bool> _isLoggedInFuture;

  @override
  void initState() {
    super.initState();
    _isLoggedInFuture = ApiClient.instance.isLoggedIn;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isLoggedInFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return (snapshot.data ?? false) ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
