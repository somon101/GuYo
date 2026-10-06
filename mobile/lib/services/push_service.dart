import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../widgets/in_app_banner.dart';

/// Push notifications through Firebase Cloud Messaging. The server sends a
/// push for every inbox notification; this side only tells the server
/// which phone to send to. Every failure here is swallowed: push is a
/// convenience on top of the in-app inbox, never a reason to break the app.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _ready = false;

  /// Bumped when a push arrives while the app is open (the system shows
  /// nothing then -- InAppBanner does), so the bell can re-check its dot.
  final ValueNotifier<int> foregroundMessages = ValueNotifier<int>(0);

  Future<void> init() async {
    // Firebase is only set up for the phone apps; on the web it can't
    // start and would hold up the whole app.
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      _ready = true;
      FirebaseMessaging.onMessage.listen((message) {
        foregroundMessages.value++;
        final notification = message.notification;
        if (notification?.body != null) {
          InAppBanner.show(title: notification!.title, body: notification.body!);
        }
      });
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (await ApiClient.instance.isLoggedIn) await _report(token);
      });
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// Call once a user is logged in. Asks for permission on Android 13+.
  Future<void> registerCurrentUser() async {
    if (!_ready) return;
    try {
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _report(token);
    } catch (e) {
      debugPrint('Push registration failed: $e');
    }
  }

  /// Call before logging out, while the session token is still valid.
  Future<void> unregisterCurrentUser() async {
    if (!_ready) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await ApiClient.instance.unregisterPushToken(token);
    } catch (e) {
      debugPrint('Push unregistration failed: $e');
    }
  }

  Future<void> _report(String token) => ApiClient.instance.registerPushToken(token);
}
