import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/reward_spec.dart';
import '../services/chest_sound.dart';
import 'counted_chest.dart';
import 'game_icons.dart';
import 'reward_chips.dart';

/// The moment a reward is taken: the gift pops and bursts in a flash of light, and the
/// rewards appear in slots. Sound and rumble start with it and stop when it closes.
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
      backgroundColor: const Color(0xFF0B0824),
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
              Opacity(
                opacity: _span(t, 0.3, 0.5),
                child: Transform.rotate(angle: t * 6, child: CustomPaint(size: const Size(420, 420), painter: _Rays())),
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
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.9 * flash), Colors.white.withValues(alpha: 0)])),
                  ),
                ),
              Positioned(
                top: 90,
                left: 16,
                right: 16,
                child: Opacity(
                  opacity: show.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * show,
                    child: Text(widget.title.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w900, fontSize: 20, letterSpacing: 1.5)),
                  ),
                ),
              ),
              Opacity(
                opacity: rewardsIn.clamp(0.0, 1.0),
                child: Transform.scale(
                  scale: 0.5 + 0.5 * rewardsIn,
                  child: Wrap(spacing: 14, runSpacing: 14, alignment: WrapAlignment.center, children: [
                    for (final r in widget.rewards) RewardSlot(reward: r, side: 78),
                  ]),
                ),
              ),
              Positioned(
                bottom: 48,
                child: Opacity(
                  opacity: button,
                  child: IgnorePointer(
                    ignoring: button < 0.9,
                    child: GreenButton(key: const ValueKey('claim-done'), label: tr('Забрать'), onTap: () => Navigator.of(context).pop(), padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 14)),
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

class _Rays extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()..shader = RadialGradient(colors: [const Color(0x99FFE28C), const Color(0x00FFE28C)]).createShader(Rect.fromCircle(center: c, radius: size.width / 2));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      canvas.drawPath(
        Path()
          ..moveTo(c.dx, c.dy)
          ..lineTo(c.dx + math.cos(a - 0.08) * size.width / 2, c.dy + math.sin(a - 0.08) * size.width / 2)
          ..lineTo(c.dx + math.cos(a + 0.08) * size.width / 2, c.dy + math.sin(a + 0.08) * size.width / 2)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Rays old) => false;
}
