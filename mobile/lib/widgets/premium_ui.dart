import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../models/premium.dart';
import '../screens/premium_screen.dart';
import '../screens/promo_screen.dart';
import '../theme/app_colors.dart';
import 'guyo_ui.dart';

/// Opens the Premium screen -- the one way into it, from Главная's counter,
/// the lesson-limit dialog and the profile badge alike.
Future<void> openPremiumScreen(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
}

/// Opens the "Промокод" screen -- from the app bar's "⋮" menu and from
/// the Premium screen.
Future<void> openPromoScreen(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PromoScreen()));
}

/// The small gold "Premium" pill.
class PremiumBadge extends StatelessWidget {
  final String label;
  const PremiumBadge({super.key, this.label = 'Premium'});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.rewardBackground,
        borderRadius: BorderRadius.circular(AppShapes.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded, size: 14, color: AppColors.rewardText),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.rewardText),
          ),
        ],
      ),
    );
  }
}

/// "Уроки сегодня: 1 из 3" on Главная.
///
/// Loads its own numbers (GET /premium/me) and reloads whenever a lesson
/// is created anywhere in the app (ApiClient.lessonQuotaRevision), so it
/// stays right while the user moves between tabs. Hides itself if the
/// counter can't be loaded -- Главная must never break over it.
class LessonQuotaCard extends StatefulWidget {
  const LessonQuotaCard({super.key});

  @override
  State<LessonQuotaCard> createState() => LessonQuotaCardState();
}

class LessonQuotaCardState extends State<LessonQuotaCard> {
  PremiumStatus? _status;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.lessonQuotaRevision.addListener(reload);
    reload();
  }

  @override
  void dispose() {
    ApiClient.instance.lessonQuotaRevision.removeListener(reload);
    super.dispose();
  }

  Future<void> reload() async {
    try {
      final status = await ApiClient.instance.fetchPremiumStatus();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {
      // Keep whatever was shown last; nothing at all on a first failure.
    }
  }

  Future<void> _open() async {
    await openPremiumScreen(context);
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    if (status == null) return const SizedBox.shrink();
    final quota = status.lessons;

    return GuyoCard(
      onTap: _open,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: status.isPremium ? AppColors.rewardBackground : AppColors.violetSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              status.isPremium ? Icons.workspace_premium_rounded : Icons.auto_stories_rounded,
              color: status.isPremium ? AppColors.rewardText : AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: status.isPremium && quota.isUnlimited ? _premiumText(status) : _counterText(quota)),
          const SizedBox(width: 8),
          if (!status.isPremium) const PremiumBadge() else const Icon(Icons.chevron_right, color: AppColors.muted),
        ],
      ),
    );
  }

  Widget _premiumText(PremiumStatus status) {
    final until = status.premiumUntil;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Уроки без ограничений',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 2),
        Text(
          until == null ? 'GuYo Premium' : 'GuYo Premium до ${formatPremiumDate(until)}',
          style: const TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
        ),
      ],
    );
  }

  Widget _counterText(LessonQuota quota) {
    final blocked = quota.blockedBy;
    final String title;
    final String subtitle;
    // The count shown is the limit that matters right now: the week's once
    // that is what blocks, otherwise today's.
    if (quota.dailyLimit != null && blocked != 'week') {
      title = 'Уроки сегодня: ${quota.dailyUsed} из ${quota.dailyLimit}';
    } else if (quota.weeklyLimit != null) {
      title = 'Уроки на неделе: ${quota.weeklyUsed} из ${quota.weeklyLimit}';
    } else {
      title = 'Уроки без ограничений';
    }
    if (blocked == 'week') {
      subtitle = 'Новые уроки — с понедельника';
    } else if (blocked == 'day') {
      subtitle = 'Новые уроки — завтра';
    } else if (quota.dailyLimit != null && quota.weeklyLimit != null) {
      subtitle = 'На этой неделе: ${quota.weeklyUsed} из ${quota.weeklyLimit}';
    } else {
      subtitle = 'С Premium — без ограничений';
    }

    // The bar follows the limit that is actually closest to running out.
    final double progress;
    if (quota.dailyLimit != null && quota.dailyLimit! > 0 && blocked != 'week') {
      progress = quota.dailyUsed / quota.dailyLimit!;
    } else if (quota.weeklyLimit != null && quota.weeklyLimit! > 0) {
      progress = quota.weeklyUsed / quota.weeklyLimit!;
    } else {
      progress = blocked != null ? 1 : 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.progressTrack,
            color: blocked != null ? AppColors.danger : AppColors.primary,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 12.5,
            color: blocked != null ? AppColors.danger : AppColors.secondaryText,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Shown when POST /lessons answers 429: the backend's own reason, and a
/// way to Premium.
Future<void> showLessonLimitDialog(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.hourglass_bottom_rounded, color: AppColors.primary),
      title: const Text('Лимит уроков'),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Понятно')),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            openPremiumScreen(context);
          },
          icon: const Icon(Icons.workspace_premium_rounded, size: 18),
          label: const Text('GuYo Premium'),
        ),
      ],
    ),
  );
}
