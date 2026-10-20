import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../screens/login_screen.dart';
import 'in_app_banner.dart' show appNavigatorKey;

bool _handling = false;

/// The server rejected the saved sign-in (expired, or ended with "log out on
/// other devices"). Whatever screen is open, the person lands on the login
/// screen with one clear message, instead of "check your internet" everywhere.
void sessionExpired() {
  final nav = appNavigatorKey.currentState;
  final context = appNavigatorKey.currentContext;
  if (nav == null || context == null || _handling) return;
  _handling = true;
  nav.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx != null) {
      ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(SnackBar(content: Text(tr('Войдите заново'))));
    }
    _handling = false;
  });
}
