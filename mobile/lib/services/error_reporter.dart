import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../config.dart';

/// Sends the errors the app catches to the server (POST /client-errors),
/// so problems on users' phones are visible to the team. Best effort and
/// quiet: never throws, skips repeats, at most a handful per session.
class ErrorReporter {
  ErrorReporter._();

  static const _maxPerSession = 15;
  static final Set<String> _sent = {};

  /// Catches Flutter framework errors and uncaught async errors.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true;
    };
  }

  static void report(Object error, StackTrace? stack) {
    if (kDebugMode) return; // a developer sees these in the console
    final message = error.toString();
    if (_sent.length >= _maxPerSession || !_sent.add(message)) return;
    unawaited(_send(message, stack?.toString()));
  }

  static Future<void> _send(String message, String? stack) async {
    try {
      final token = await ApiClient.instance.token;
      await http
          .post(
            Uri.parse('$apiBaseUrl/client-errors'),
            headers: {
              'Content-Type': 'application/json',
              'X-App-Build': '$appBuild',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'message': message.length > 4000 ? message.substring(0, 4000) : message,
              if (stack != null) 'stack': stack.length > 12000 ? stack.substring(0, 12000) : stack,
              'platform': defaultTargetPlatform.name,
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Nowhere to report a failure to report.
    }
  }
}
