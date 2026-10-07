import 'l10n/l10n.dart';

import 'services/answer_signals.dart';
import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/push_service.dart';
import 'widgets/in_app_banner.dart';
import 'theme/app_colors.dart';
import 'widgets/skeleton.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AnswerSignals.init();
  await PushService.instance.init();
  await loadAppLanguage();
  runApp(const GuyoApp());
}

class GuyoApp extends StatelessWidget {
  const GuyoApp({super.key});

  @override
  Widget build(BuildContext context) {
    // A language change rebuilds the whole app from scratch, so every
    // screen picks up the new strings (see l10n/l10n.dart).
    return ValueListenableBuilder<String>(
      valueListenable: appLanguage,
      builder: (context, lang, _) => MaterialApp(
        key: ValueKey(lang),
        title: 'GuYo',
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const _StartupGate(),
      ),
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
          return const Scaffold(
            backgroundColor: AppColors.canvas,
            body: SafeArea(child: SkeletonDashboard()),
          );
        }
        return (snapshot.data ?? false) ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
