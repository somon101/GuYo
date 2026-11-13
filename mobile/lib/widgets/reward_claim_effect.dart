import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/reward_spec.dart';
import '../services/chest_sound.dart';
import '../theme/app_colors.dart';
import 'reward_chips.dart';

/// The moment a reward is taken (light screen): a soft glow, the rewards pop into soft slots and
/// big sparkles twinkle around them; no picture of a gift. Short (about a second and a half) and
/// smooth: only opacity and scale are animated, everything else is drawn once.
/// Sound and rumble start right after the first frame and stop when it closes.
Future<void> showRewardClaimEffect(BuildContext context, {required String title, required List<RewardSpec> rewards}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 160),
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

/// A sparkle: (x, y as fractions of the screen, size, when it appears 0..1, gold or indigo).
typedef _StarSpec = (double, double, double, double, bool);

class _RewardClaimScreenState extends State<_RewardClaimScreen> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..forward();
  // A slow, light breathing of the sparkles once they are in.
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat(reverse: true);

  static const _stars = <_StarSpec>[
    (0.16, 0.27, 44, 0.22, true),
    (0.82, 0.24, 34, 0.30, false),
    (0.10, 0.50, 30, 0.38, false),
    (0.88, 0.47, 56, 0.28, true),
    (0.24, 0.67, 38, 0.44, true),
    (0.77, 0.69, 46, 0.36, false),
    (0.50, 0.17, 32, 0.50, true),
    (0.56, 0.79, 30, 0.54, false),
  ];

  late final Animation<double> _glow = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic));
  late final Animation<double> _titleIn = CurvedAnimation(parent: _c, curve: const Interval(0.07, 0.37, curve: Curves.easeOutCubic));
  late final Animation<double> _rewardsFade = CurvedAnimation(parent: _c, curve: const Interval(0.14, 0.40, curve: Curves.easeOut));
  late final Animation<double> _rewardsPop = CurvedAnimation(parent: _c, curve: const Interval(0.14, 0.55, curve: Curves.easeOutBack));
  late final Animation<double> _buttonIn = CurvedAnimation(parent: _c, curve: const Interval(0.4, 0.62, curve: Curves.easeOut));

  @override
  void initState() {
    super.initState();
    // The sound and rumble are platform calls: let the first frame be drawn before them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ChestSound.buzzOpen();
      // ignore: unawaited_futures
      ChestSound.open();
    });
  }

  @override
  void dispose() {
    ChestSound.stop();
    _c.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        child: Stack(fit: StackFit.expand, children: [
          // The soft glow behind the rewards, in the middle of the screen.
          Center(
            child: FadeTransition(
              opacity: _glow,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.6, end: 1).animate(_glow),
                child: RepaintBoundary(
                  child: Container(
                    width: 340,
                    height: 340,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [AppColors.violetSurface, AppColors.violetSurface.withValues(alpha: 0)])),
                  ),
                ),
              ),
            ),
          ),
          // Sparkles: placed by fractions of the screen, so they sit the same on any phone.
          for (final s in _stars) _Sparkle(spec: s, controller: _c, pulse: _pulse),
          // The content: centred, then the button at the bottom.
          Column(children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    FadeTransition(
                      opacity: _titleIn,
                      child: SlideTransition(
                        position: Tween<Offset>(begin: const Offset(0, 0.25), end: Offset.zero).animate(_titleIn),
                        child: Column(children: [
                          Text(widget.title, textAlign: TextAlign.center, style: TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w800, fontSize: 24, letterSpacing: -0.5)),
                          const SizedBox(height: 4),
                          Text(tr('Вы получили'), style: TextStyle(color: AppColors.secondaryText, fontSize: 14)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 36),
                    FadeTransition(
                      opacity: _rewardsFade,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.55, end: 1).animate(_rewardsPop),
                        child: Wrap(spacing: 14, runSpacing: 18, alignment: WrapAlignment.center, children: [
                          for (final r in widget.rewards) RewardSlot(reward: r, side: 96, soft: true),
                        ]),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
              child: FadeTransition(
                opacity: _buttonIn,
                child: GestureDetector(
                  key: const ValueKey('claim-done'),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 52,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                    child: Text(tr('Забрать'), style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// One sparkle: pops in at its moment, then breathes a little. The star itself is drawn once.
class _Sparkle extends StatelessWidget {
  final _StarSpec spec;
  final Animation<double> controller;
  final Animation<double> pulse;
  const _Sparkle({required this.spec, required this.controller, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final (x, y, size, at, gold) = spec;
    final pop = CurvedAnimation(parent: controller, curve: Interval(at, (at + 0.25).clamp(0.0, 1.0), curve: Curves.easeOutBack));
    return Align(
      alignment: Alignment(x * 2 - 1, y * 2 - 1),
      child: AnimatedBuilder(
        animation: Listenable.merge([pop, pulse]),
        child: RepaintBoundary(child: CustomPaint(size: Size(size, size), painter: _Star(gold ? const Color(0xFFF2B33D) : AppColors.primary))),
        builder: (_, star) {
          final p = pop.value.clamp(0.0, 1.0);
          return Opacity(
            opacity: p * (0.8 + 0.2 * pulse.value),
            child: Transform.scale(scale: p * (0.92 + 0.12 * pulse.value), child: star),
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
