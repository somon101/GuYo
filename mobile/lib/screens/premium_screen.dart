import '../l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/api_client.dart';
import '../models/premium.dart';
import '../theme/app_colors.dart';
import '../widgets/guyo_ui.dart';
import '../widgets/premium_ui.dart';
import '../widgets/skeleton.dart';

/// "GuYo Premium": what it gives, whether the user has it, and how to pay.
///
/// Payment happens outside the app -- the user transfers money following
/// the admin's own instructions and puts their 9-digit ID in the comment;
/// the admin then switches Premium on in Admin Web and the user gets a
/// notification. Every text about price and payment comes from the
/// backend, so changing them never needs a new build.
class PremiumScreen extends StatefulWidget {
  const PremiumScreen({super.key});

  @override
  State<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends State<PremiumScreen> {
  PremiumStatus? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final status = await ApiClient.instance.fetchPremiumStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = tr('Не удалось загрузить данные'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('GuYo Premium'), backgroundColor: AppColors.canvas),
      body: RefreshIndicator(
        onRefresh: _load,
        child: status == null
            ? ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: _error == null
                          ? const SizedBox(height: 360, child: SkeletonForm(fields: 3))
                          : Column(
                              children: [
                                Text(_error!),
                                const SizedBox(height: 12),
                                FilledButton(onPressed: _load, child: Text(tr('Повторить'))),
                              ],
                            ),
                    ),
                  ),
                ],
              )
            : _Body(status: status, onPromoUsed: _load),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final PremiumStatus status;

  /// Called after returning from the promo screen, which may have just
  /// started or extended Premium.
  final VoidCallback onPromoUsed;

  const _Body({required this.status, required this.onPromoUsed});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        _StatusHeader(status: status),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              await openPromoScreen(context);
              onPromoUsed();
            },
            icon: const Icon(Icons.confirmation_number_rounded, size: 18),
            label: Text(tr('Есть промокод или ссылка на видео?')),
          ),
        ),
        const SizedBox(height: 4),
        _Benefits(status: status),
        if (!status.isPremium || status.priceText.isNotEmpty) ...[
          const SizedBox(height: 14),
          _HowToPay(status: status),
        ],
      ],
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final PremiumStatus status;
  const _StatusHeader({required this.status});

  @override
  Widget build(BuildContext context) {
    final until = status.premiumUntil;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: AppColors.premiumGradient,
        ),
        borderRadius: BorderRadius.circular(AppShapes.bannerRadius),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: const Icon(Icons.workspace_premium_rounded, size: 34, color: AppColors.rewardText),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  status.isPremium ? tr('Premium активен') : tr('Учитесь без ограничений'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
                ),
                const SizedBox(height: 3),
                Text(
                  status.isPremium
                      ? (until == null ? tr('Спасибо за поддержку!') : tr('До {0}', [formatPremiumDate(until)]))
                      : tr('Сейчас у вас бесплатный доступ'),
                  style: const TextStyle(fontSize: 13.5, color: AppColors.rewardText, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Benefits extends StatelessWidget {
  final PremiumStatus status;
  const _Benefits({required this.status});

  @override
  Widget build(BuildContext context) {
    final quota = status.lessons;
    final freeLimits = <String>[
      if (!status.isPremium && quota.dailyLimit != null) tr('{0} в день', [quota.dailyLimit]),
      if (!status.isPremium && quota.weeklyLimit != null) tr('{0} в неделю', [quota.weeklyLimit]),
    ];
    return GuyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('Что даёт Premium'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 12),
          _BenefitRow(
            icon: Icons.all_inclusive_rounded,
            title: tr('Уроки без ограничений'),
            subtitle: freeLimits.isEmpty
                ? tr('Создавайте столько уроков, сколько хотите')
                : tr('Без Premium — не больше {0}', [freeLimits.join(' и ')]),
          ),
          if (status.adaptiveLessonsPremiumOnly)
            _BenefitRow(
              icon: Icons.autorenew_rounded,
              title: tr('Автоуроки для закрепления'),
              subtitle: tr('Слова, которые даются трудно, сами соберутся в урок'),
            ),
          if (status.personalQuestsPremiumOnly)
            _BenefitRow(
              icon: Icons.flag_rounded,
              title: tr('Персональные квесты'),
              subtitle: tr('Задания под ваши слабые места с бонусными очками'),
            ),
        ],
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _BenefitRow({required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: AppColors.secondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowToPay extends StatelessWidget {
  final PremiumStatus status;
  const _HowToPay({required this.status});

  @override
  Widget build(BuildContext context) {
    final id = status.publicId.toString();
    return GuyoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            status.isPremium ? tr('Продлить Premium') : tr('Как подключить'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.primaryDark),
          ),
          if (status.priceText.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              status.priceText,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.rewardText),
            ),
          ],
          const SizedBox(height: 10),
          Text(
            status.paymentInstructions.isNotEmpty
                ? status.paymentInstructions
                : tr('Способ оплаты скоро появится здесь.'),
            style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.primaryDark),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: AppColors.violetSurface,
              borderRadius: BorderRadius.circular(AppShapes.rowRadius),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Ваш ID'), style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
                      Text(
                        id,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: AppColors.primaryDark,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: id));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('ID скопирован'))));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(tr('Копировать')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            tr('Укажите ID в комментарии к переводу. После проверки оплаты Premium ') +
                tr('{0}, и вам придёт уведомление.', [status.isPremium ? tr('продлится') : tr('включится')]),
            style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.secondaryText),
          ),
        ],
      ),
    );
  }
}
