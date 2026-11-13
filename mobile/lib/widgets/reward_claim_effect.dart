import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/reward_spec.dart';
import '../services/chest_sound.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';
import 'reward_chips.dart';

/// The moment a reward is taken (light screen): the gift pops and bursts in a soft flash, and the
/// rewards appear in soft slots. Sound and rumble start with it and stop when it closes.
Future<void> showRewardClaimEffect(BuildContext context, {required String title, required List<RewardSpec> rewards}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _RewardClaimScreen(title: title, rewards: rewards),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ),
  );
}

class _RewardClaimScreen extends StatefulWidget {
  final String title;
  final List<RewardSpec> rewards;
  const _RewardClaimScreen({required this.title, required this.rewards});

  @override
  State<_RewardClaimScreen> createState() => _RewardClaimScreenState();
}

class _RewardClaimScreenState extends State<_RewardClaimScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3400))..forward();

  @override
  void initState() {
    super.initState();
    ChestSound.buzzOpen();
    // ignore: unawaited_futures
    ChestSound.open();
  }

  @override
  void dispose() {
    ChestSound.stop();
    _c.dispose();
    super.dispose();
  }

  double _span(double t, double from, double to) => ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final gift = _span(t, 0, 0.38);
          final goneGift = Curves.easeIn.transform(_span(t, 0.38, 0.55));
          final flash = math.sin(_span(t, 0.34, 0.5) * math.pi);
          final show = Curves.easeOutBack.transform(_span(t, 0.42, 0.62));
          final rewardsIn = Curves.easeOutBack.transform(_span(t, 0.5, 0.7));
          final button = _span(t, 0.8, 0.9);
          return SafeArea(
            child: Stack(alignment: Alignment.center, children: [
              // A soft glow behind the gift (the light screen's only decoration).
              Positioned(
                top: 90,
                child: Opacity(
                  opacity: (_span(t, 0.0, 0.3) * 0.9).clamp(0.0, 1.0),
                  child: Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [AppColors.violetSurface, AppColors.violetSurface.withValues(alpha: 0)])),
                  ),
                ),
              ),
              if (goneGift < 1)
                Opacity(
                  opacity: 1 - goneGift,
                  child: Transform.translate(
                    offset: Offset(0, -60 * goneGift),
                    child: Transform.rotate(
                      angle: math.sin(gift * math.pi * 3) * 0.2 * (1 - gift),
                      child: Transform.scale(scale: Curves.easeOutBack.transform(gift) * (1 + 0.25 * goneGift), child: const GiftIcon(size: 190)),
                    ),
                  ),
                ),
              if (flash > 0)
                IgnorePointer(
                  child: Container(
                    width: 460,
                    height: 460,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [AppColors.primary.withValues(alpha: 0.28 * flash), AppColors.primary.withValues(alpha: 0)])),
                  ),
                ),
              Positioned(
                top: 90,
                left: 16,
                right: 16,
                child: Opacity(
                  opacity: show.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.7 + 0.3 * show,
                    child: Column(children: [
                      Text(widget.title, textAlign: TextAlign.center, style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
                      const SizedBox(height: 4),
                      Text(tr('Вы получили'), style: TextStyle(color: AppColors.secondaryText, fontSize: 14)),
                    ]),
                  ),
                ),
              ),
              Opacity(
                opacity: rewardsIn.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.5 + 0.5 * rewardsIn,
                  child: Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [
                    for (final r in widget.rewards) RewardSlot(reward: r, side: 78, soft: true),
                  ]),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 28,
                child: Opacity(
                  opacity: button,
                  child: IgnorePointer(
                    ignoring: button < 0.9,
                    child: GestureDetector(
                      key: const ValueKey('claim-done'),
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                        child: Text(tr('Забрать'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
