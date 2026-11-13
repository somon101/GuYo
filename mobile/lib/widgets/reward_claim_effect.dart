import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/reward_spec.dart';
import '../services/chest_sound.dart';
import '../theme/app_colors.dart';
import 'reward_chips.dart';

/// The moment a reward is taken (light screen): a soft glow, the rewards pop into soft slots and
/// sparkles twinkle around them; no picture of a gift. Sound and rumble start with it and stop when it closes.
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
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();

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

  // Sparkles around the rewards: (x, y as a fraction of the screen, size, appears at, gold or indigo).
  static const _stars = <(double, double, double, double, bool)>[
    (0.18, 0.30, 22, 0.48, true),
    (0.80, 0.27, 16, 0.54, false),
    (0.12, 0.52, 14, 0.58, false),
    (0.86, 0.50, 24, 0.52, true),
    (0.30, 0.68, 12, 0.62, true),
    (0.72, 0.70, 16, 0.66, false),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final halo = Curves.easeOut.transform(_span(t, 0.0, 0.35));
          final show = Curves.easeOutBack.transform(_span(t, 0.12, 0.32));
          final rewardsIn = Curves.easeOutBack.transform(_span(t, 0.22, 0.45));
          final button = _span(t, 0.7, 0.8);
          final size = MediaQuery.sizeOf(context);
          return SafeArea(
            child: Stack(alignment: Alignment.center, children: [
              // The soft glow behind the rewards.
              Opacity(
                opacity: halo.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.6 + 0.4 * halo,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [AppColors.violetSurface, AppColors.violetSurface.withValues(alpha: 0)])),
                  ),
                ),
              ),
              for (final (x, y, sz, at, gold) in _stars)
                Positioned(
                  left: size.width * x - sz / 2,
                  top: size.height * y - sz / 2,
                  child: Builder(builder: (_) {
                    final p = Curves.easeOutBack.transform(_span(t, at, at + 0.14));
                    // After arriving, each star slowly twinkles.
                    final twinkle = 0.75 + 0.25 * math.sin(t * 18 + x * 10);
                    return Opacity(
                      opacity: (p * twinkle).clamp(0.0, 1.0),
                      child: Transform.scale(scale: p, child: CustomPaint(size: Size(sz, sz), painter: _Star(gold ? const Color(0xFFF2B33D) : AppColors.primary))),
                    );
                  }),
                ),
              Positioned(
                top: 90,
                left: 16,
                right: 16,
                child: Opacity(
                  opacity: show.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.8 + 0.2 * show,
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
                  child: Wrap(spacing: 14, runSpacing: 18, alignment: WrapAlignment.center, children: [
                    for (final r in widget.rewards) RewardSlot(reward: r, side: 96, soft: true),
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

/// A four-point sparkle.
class _Star extends CustomPainter {
  final Color color;
  const _Star(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final path = Path()
      ..moveTo(c.dx, c.dy - r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx + r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + r)
      ..quadraticBezierTo(c.dx, c.dy, c.dx - r, c.dy)
      ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - r);
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Star old) => old.color != color;
}
