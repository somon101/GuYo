import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../models/notification.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';

/// "Уведомления": every message this user has received.
///
/// Opening the screen marks everything read -- that is what clears the
/// bell's dot. The rows still show which ones WERE unread when it opened,
/// from the snapshot loaded before marking, so the user can see what is
/// new on this visit instead of everything going grey the instant they
/// arrive.
///
/// Renders every message identically whatever created it. A message an
/// admin wrote and one a future automatic rule sends are the same row (see
/// backend/app/models/notification.py); nothing here branches on `source`.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool _isLoading = true;
  String? _loadError;
  List<AppNotification> _items = [];

  /// Which messages were unread when this screen opened. Kept separately
  /// because the backend marks them read immediately afterwards.
  Set<int> _newOnThisVisit = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final inbox = await ApiClient.instance.fetchNotifications();
      if (!mounted) return;
      setState(() {
        _items = inbox.items;
        _newOnThisVisit = inbox.items.where((n) => !n.isRead).map((n) => n.id).toSet();
        _isLoading = false;
      });
      // Reading the list IS reading the messages -- done after the list is
      // in hand so the highlight above survives it.
      if (_newOnThisVisit.isNotEmpty) {
        await ApiClient.instance.markAllNotificationsRead();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Не удалось загрузить уведомления';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Уведомления',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: const IconThemeData(color: AppColors.primaryDark),
      ),
      body: SafeArea(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(children: const [SizedBox(height: 200, child: Center(child: CircularProgressIndicator()))]);
    }
    if (_loadError != null) {
      return ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_loadError!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _load, child: const Text('Повторить')),
              ],
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.notifications_none_rounded, size: 56, color: AppColors.muted),
          SizedBox(height: 12),
          Text(
            'Пока нет уведомлений',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryDark),
          ),
          SizedBox(height: 4),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Здесь появятся сообщения от GuYo',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final item in _items) ...[
          _NotificationCard(notification: item, isNew: _newOnThisVisit.contains(item.id)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;

  /// Unread when this screen opened -- not the row's current state, which
  /// is already "read" by the time it renders.
  final bool isNew;

  const _NotificationCard({required this.notification, required this.isNew});

  @override
  Widget build(BuildContext context) {
    final title = notification.title;
    return GuyoCard(
      color: isNew ? AppColors.violetSurface : Colors.white,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoundIconChip(
            icon: Icons.notifications_rounded,
            size: 40,
            background: isNew ? Colors.white : AppColors.violetSurface,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null && title.isNotEmpty) ...[
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  notification.body,
                  style: const TextStyle(fontSize: 14, color: AppColors.primaryDark, height: 1.35),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      formatNotificationMoment(notification.createdAt),
                      style: const TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
                    ),
                    if (isNew) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppShapes.pillRadius),
                        ),
                        child: const Text(
                          'Новое',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "25 сент., 14:03" -- the device's own local time, since the model
/// already converted the timestamp on the way in.
String formatNotificationMoment(DateTime moment) {
  const months = [
    'янв.', 'февр.', 'марта', 'апр.', 'мая', 'июня',
    'июля', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.',
  ];
  final minute = moment.minute.toString().padLeft(2, '0');
  return '${moment.day} ${months[moment.month - 1]}, ${moment.hour}:$minute';
}
