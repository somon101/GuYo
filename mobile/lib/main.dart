import 'l10n/l10n.dart';

import 'theme/app_theme.dart';
import 'services/disk_cache.dart';
import 'services/error_reporter.dart';
import 'services/answer_signals.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  ErrorReporter.install();
  // Portrait only: the app's screens are laid out for a phone held upright.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Content runs under the system bars, like Telegram: no grey strip behind
  // Android's navigation buttons (see _systemBarsStyle).
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await PushService.instance.init();
  await loadAppLanguage();
  await loadAppTheme();
  await DiskCache.load();
  runApp(const GuyoApp());
}

class GuyoApp extends StatefulWidget {
  const GuyoApp({super.key});

  @override
  State<GuyoApp> createState() => _GuyoAppState();
}

class _GuyoAppState extends State<GuyoApp> with WidgetsBindingObserver {
  /// Bumped when the phone switches light/dark while the choice is "system".
  final ValueNotifier<int> _systemTheme = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    if (applyAppTheme()) _systemTheme.value++;
  }

  @override
  Widget build(BuildContext context) {
    // A language or theme change rebuilds the whole app from scratch, so
    // every screen picks up the new strings and colours (see
    // l10n/l10n.dart, theme/app_theme.dart).
    return ListenableBuilder(
      listenable: Listenable.merge([appLanguage, appThemeChoice, _systemTheme]),
      builder: (context, _) => MaterialApp(
        key: ValueKey('${appLanguage.value}-${AppColors.dark}'),
        title: 'GuYo',
        navigatorKey: appNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(value: _systemBarsStyle(), child: child!),
        home: const _StartupGate(),
      ),
    );
  }
}

/// Transparent status and navigation bars, with their icons light on the
/// dark theme and dark on the light one. Contrast enforcement off: that is
/// what made Android paint its own grey scrim behind the buttons.
SystemUiOverlayStyle _systemBarsStyle() {
  final iconBrightness = AppColors.dark ? Brightness.light : Brightness.dark;
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: iconBrightness,
    statusBarBrightness: AppColors.dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: iconBrightness,
    systemNavigationBarContrastEnforced: false,
    systemStatusBarContrastEnforced: false,
  );
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
          return Scaffold(
            backgroundColor: AppColors.canvas,
            body: SafeArea(child: SkeletonDashboard()),
          );
        }
        return (snapshot.data ?? false) ? const HomeScreen() : const LoginScreen();
      },
    );
  }
}
