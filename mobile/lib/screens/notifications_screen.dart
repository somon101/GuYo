import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import '../api/api_client.dart';
import '../services/streak_state.dart';
import '../widgets/counted_chest.dart' show GreenButton;
import '../widgets/reward_chips.dart';
import '../widgets/reward_claim_effect.dart';
import '../models/notification.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';
import '../widgets/skeleton.dart';

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

class _NotificationsScreenState extends State<NotificationsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)..addListener(() => setState(() {}));

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

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  /// Rewards waiting to be taken (an admin's gift or an unclaimed daily goal) live in «Награды».
  List<AppNotification> get _gifts => [for (final n in _items) if (n.action != null) n];
  List<AppNotification> get _messages => [for (final n in _items) if (n.action == null) n];

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
        _loadError = tr('Не удалось загрузить уведомления');
      });
    }
  }

  /// «Получить» on a message that carries a daily-goal reward.
  Future<void> _takeReward(AppNotification item) async {
    final id = int.tryParse((item.action ?? '').split(':').last);
    if (id == null) return;
    final isGift = (item.action ?? '').startsWith('claim_gift:');
    try {
      if (isGift) {
        await ApiClient.instance.claimGift(id);
      } else {
        await ApiClient.instance.claimDailyGoal(id);
      }
      if (!mounted) return;
      ApiClient.instance.fetchEconomy();
      await showRewardClaimEffect(context, title: isGift ? tr('Подарок получен!') : tr('Цель дня выполнена!'), rewards: item.payload);
      dailyGoalTick.value++;
    } on ApiException catch (_) {
      // Already taken somewhere else: the list below simply loses its button.
    } catch (_) {
      return;
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr('Уведомления'),
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        iconTheme: IconThemeData(color: AppColors.primaryDark),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.secondaryText,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(key: const ValueKey('tab-messages'), text: tr('Уведомления')),
            Tab(key: const ValueKey('tab-gifts'), text: _gifts.isEmpty ? tr('Награды') : '${tr('Награды')} · ${_gifts.length}'),
          ],
        ),
      ),
      body: SafeArea(child: RefreshIndicator(onRefresh: _load, child: _buildBody())),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const SkeletonList(avatar: false);
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
                FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
              ],
            ),
          ),
        ],
      );
    }
    final onGifts = _tabs.index == 1;
    final shown = onGifts ? _gifts : _messages;
    if (shown.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 70),
          GuyoEmptyState(
            icon: onGifts ? Icons.card_giftcard_rounded : Icons.notifications_none_rounded,
            title: onGifts ? tr('Наград пока нет') : tr('Пока нет уведомлений'),
            message: onGifts ? tr('Подарки и награды, которые ждут, будут здесь') : tr('Здесь появятся сообщения от GuYo'),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final item in shown) ...[
          _NotificationCard(
            notification: item,
            isNew: _newOnThisVisit.contains(item.id),
            onAction: item.action == null ? null : () => _takeReward(item),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;

  /// Pressed on a message that carries a reward (e.g. the daily goal's «Получить»).
  final VoidCallback? onAction;

  /// Unread when this screen opened -- not the row's current state, which
  /// is already "read" by the time it renders.
  final bool isNew;

  const _NotificationCard({required this.notification, required this.isNew, this.onAction});

  @override
  Widget build(BuildContext context) {
    final title = notification.title;
    return GuyoCard(
      color: isNew ? AppColors.violetSurface : AppColors.surface,
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RoundIconChip(
            icon: Icons.notifications_rounded,
            size: 40,
            background: isNew ? AppColors.surface : AppColors.violetSurface,
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
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  notification.body,
                  style: TextStyle(fontSize: 14, color: AppColors.primaryDark, height: 1.35),
                ),
                if (notification.payload.isNotEmpty) RewardChips(rewards: notification.payload, size: 22),
                if (notification.action != null && onAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: GreenButton(key: ValueKey('notification-action-${notification.id}'), label: tr('Получить'), onTap: onAction, compact: true),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      formatNotificationMoment(notification.createdAt),
                      style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
                    ),
                    if (isNew) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(AppShapes.pillRadius),
                        ),
                        child: Text(
                          tr('Новое'),
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
  final months = [
    tr('янв.'), tr('февр.'), tr('марта'), tr('апр.'), tr('мая'), tr('июня'),
    tr('июля'), tr('авг.'), tr('сент.'), tr('окт.'), tr('нояб.'), tr('дек.'),
  ];
  final minute = moment.minute.toString().padLeft(2, '0');
  return '${moment.day} ${months[moment.month - 1]}, ${moment.hour}:$minute';
}
