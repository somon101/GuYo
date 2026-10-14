import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../api/api_client.dart';
import '../screens/notifications_screen.dart';
import '../widgets/in_app_banner.dart';

/// Push notifications through Firebase Cloud Messaging. The server sends a
/// push for every inbox notification; this side only tells the server
/// which phone to send to. Every failure here is swallowed: push is a
/// convenience on top of the in-app inbox, never a reason to break the app.
///
/// WHILE THE APP IS OPEN the message announces itself one of two ways, and
/// which one is chosen in Admin Web («Уведомления»):
///
/// - "banner" (the default): the app's own card slides down from the top
///   ([InAppBanner]) -- GuYo's own look, tap opens the inbox;
/// - "system": a real Android notification, exactly as if the app had been in
///   the background, so it also lands in the phone's own notification shade.
///
/// The choice travels INSIDE each push (`data.style`), so switching it in the
/// admin takes effect on the very next message -- no new app build and no extra
/// request from the app.
///
/// With the app closed or in the background Android draws the notification
/// itself, and no setting can change that: that is why only the foreground case
/// is choosable here.
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  bool _ready = false;

  /// How the message itself spells the "real system notification" style.
  static const String _styleSystem = 'system';

  /// The Android channel the "system" style is posted on: its own channel, so
  /// these notifications are listed and silenced separately from anything else
  /// the app may ever post.
  static const String _channelId = 'guyo_messages';
  static const String _channelName = 'Уведомления GuYo';

  final _local = FlutterLocalNotificationsPlugin();

  /// Bumped when a push arrives while the app is open, so the bell can
  /// re-check its dot.
  final ValueNotifier<int> foregroundMessages = ValueNotifier<int>(0);

  Future<void> init() async {
    // Firebase is only set up for the phone apps; on the web it can't
    // start and would hold up the whole app.
    if (kIsWeb) return;
    try {
      await Firebase.initializeApp();
      await _initLocalNotifications();
      _ready = true;
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (await ApiClient.instance.isLoggedIn) await _report(token);
      });
    } catch (e) {
      debugPrint('Push disabled: $e');
    }
  }

  /// Only the "system" style needs this -- the banner needs nothing from the
  /// system. Tapping a notification opens the same inbox the banner opens.
  Future<void> _initLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _local.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != 'inbox') return;
        appNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
      },
    );
  }

  Future<void> _onForegroundMessage(RemoteMessage message) async {
    foregroundMessages.value++;
    final notification = message.notification;
    final body = notification?.body;
    if (body == null) return;
    if (message.data['style'] == _styleSystem) {
      await _showSystemNotification(notification!.title, body);
    } else {
      InAppBanner.show(title: notification!.title, body: body);
    }
  }

  Future<void> _showSystemNotification(String? title, String body) async {
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'Сообщения GuYo, когда приложение открыто',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    );
    try {
      await _local.show(
        id: DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
        title: title ?? 'GuYo',
        body: body,
        notificationDetails: details,
        payload: 'inbox',
      );
    } catch (e) {
      // Same rule as everything else here: a notification that could not be
      // shown must never take the app down with it.
      debugPrint('System notification failed: $e');
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
