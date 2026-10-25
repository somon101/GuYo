import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/season_pass.dart';
import 'game_icons.dart';
import 'user_avatar.dart' show frameColors;

/// The hero gradient of the season pass: deep violet into electric blue.
List<Color> passHeroGradient(bool dark) => dark
    ? const [Color(0xFF3B2D96), Color(0xFF1D4FA3)]
    : const [Color(0xFF6A4CFF), Color(0xFF2F7CF6)];

/// How one kind of reward looks: its gradient, icon and name. Every place
/// that draws a reward takes it from here, so a new kind is added once.
class RewardStyle {
  final List<Color> colors;
  final IconData icon;
  final String label;

  /// The game's own picture (diamond, freeze or merge) drawn instead of [icon].
  final String? asset;
  const RewardStyle(this.colors, this.icon, this.label, {this.asset});

  Color get glow => colors.last;
}

RewardStyle rewardStyle(PassReward r) {
  if (r.type == 'badge') {
    final look = badgeLook(r.key ?? 'crown');
    return RewardStyle(
      look.colors,
      look.icon ?? Icons.military_tech_rounded,
      (r.text ?? '').isEmpty ? tr('Значок') : r.text!,
    );
  }
  switch (r.type) {
    case 'premium_days':
      return RewardStyle(
        const [Color(0xFFFFD54F), Color(0xFFFF9800)],
        Icons.workspace_premium_rounded,
        tr('Дни Premium'),
      );
    case 'streak_freeze':
      return RewardStyle(
        const [Color(0xFF7FDBFF), Color(0xFF3A7BFF)],
        Icons.ac_unit_rounded,
        tr('Заморозка серии'),
        asset: 'freeze',
      );
    case 'diamonds':
      return RewardStyle(
        const [Color(0xFF87EFFF), Color(0xFF3A7BFF)],
        Icons.diamond_rounded,
        tr('Бриллианты'),
        asset: 'diamond',
      );
    case 'chest':
      return RewardStyle(
        const [Color(0xFFFFB86B), Color(0xFFB4541F)],
        Icons.inventory_2_rounded,
        tr('Сундук'),
        asset: 'chest:${r.key ?? 'wood'}',
      );
    case 'booster':
      return RewardStyle(
        const [Color(0xFFB07CFF), Color(0xFF5B2EE0)],
        Icons.confirmation_number_rounded,
        tr('Удвоитель'),
        asset: 'booster',
      );
    case 'frame':
      return RewardStyle(
        frameColors(r.key ?? 'gold').take(2).toList(),
        Icons.account_circle_outlined,
        (r.text ?? '').isEmpty ? tr('Рамка') : r.text!,
      );
    case 'title':
      return RewardStyle(
        const [Color(0xFF6EE7B7), Color(0xFF0E9F6E)],
        Icons.badge_rounded,
        (r.text ?? '').isEmpty ? tr('Титул') : r.text!,
      );
    default:
      return RewardStyle(
        const [Color(0xFFA48BFF), Color(0xFF5862DD)],
        Icons.star_rounded,
        tr('Звёзды рейтинга'),
        asset: 'points',
      );
  }
}

/// "+20" for counted rewards; a badge or title shows its own name instead.
String rewardAmountText(PassReward r) {
  if (r.type == 'badge' || r.type == 'title' || r.type == 'frame' || r.type == 'chest') return '';
  if (r.type == 'booster') return r.amount >= 60 && r.amount % 60 == 0 ? '${r.amount ~/ 60}ч' : '${r.amount}м';
  return r.type == 'diamonds' ? '+${compactNumber(r.amount)}' : '+${r.amount}';
}

/// A round progress ring with the level in the middle.
class LevelRing extends StatelessWidget {
  final double size;
  final double progress;
  final int level;
  final double stroke;
  final bool compact;

  const LevelRing({
    super.key,
    required this.size,
    required this.progress,
    required this.level,
    this.stroke = 10,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(progress.clamp(0.0, 1.0), stroke),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!compact)
                Text(
                  tr('Уровень').toUpperCase(),
                  style: TextStyle(
                    fontSize: size * 0.1,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
              Text(
                '$level',
                style: TextStyle(
                  fontSize: size * (compact ? 0.4 : 0.38),
                  height: 1.05,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double stroke;
  _RingPainter(this.progress, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.22);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);
    if (progress <= 0) return;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: [Color(0xFFFFF3A8), Color(0xFFFFB300)],
        transform: GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.stroke != stroke;
}

/// One reward as a coloured card. States, from the person's side: claimed (check,
/// dimmed), claimable (glows and pulses, "Забрать"), waiting for a level to be
/// reached (faded) and locked behind Premium (a lock).
class RewardCard extends StatelessWidget {
  final PassReward reward;
  final bool reached;
  final Animation<double> pulse;
  final bool busy;
  final VoidCallback onClaim;

  const RewardCard({
    super.key,
    required this.reward,
    required this.reached,
    required this.pulse,
    required this.busy,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final style = rewardStyle(reward);
    final claimable = reward.claimable;
    final dim = reward.claimed || (!reached && !claimable);
    final colors = [
      for (final c in style.colors)
        dim
            ? Color.lerp(
                c,
                const Color(0xFF8A8FA8),
                reward.claimed ? 0.5 : 0.3,
              )!
            : c,
    ];
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final glow = claimable ? pulse.value : 0.0;
        return Container(
          constraints: const BoxConstraints(minHeight: 112),
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: colors,
            ),
            border: claimable
                ? Border.all(color: Colors.white, width: 2)
                : null,
            boxShadow: [
              if (claimable)
                BoxShadow(
                  color: style.glow.withValues(alpha: 0.35 + 0.35 * glow),
                  blurRadius: 10 + 12 * glow,
                  spreadRadius: 1 + 2 * glow,
                )
              else
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Icon(
                    style.icon,
                    size: 54,
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (style.asset != null)
                      gameAsset(style.asset!, 46)
                    else if (reward.type == 'badge')
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                        child: BadgeGlyph(
                          badgeKey: reward.key ?? 'crown',
                          size: 34,
                        ),
                      )
                    else
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.25),
                        ),
                        child: Icon(style.icon, size: 22, color: Colors.white),
                      ),
                    const SizedBox(height: 4),
                    if (rewardAmountText(reward).isNotEmpty)
                      Text(
                        rewardAmountText(reward),
                        style: const TextStyle(
                          fontSize: 21,
                          height: 1.1,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                    Text(
                      style.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize:
                            (reward.type == 'badge' || reward.type == 'title')
                            ? 13
                            : 11.5,
                        fontWeight:
                            (reward.type == 'badge' || reward.type == 'title')
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    if (claimable) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 28,
                        child: FilledButton(
                          onPressed: busy ? null : onClaim,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: style.glow,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            minimumSize: Size.zero,
                          ),
                          child: Text(
                            tr('Забрать'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (reward.claimed)
                const Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.check_circle_rounded,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
              if (reward.lockedByPremium)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black38,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A burst of sparkles around the middle, driven by a 0..1 animation.
class SparklePainter extends CustomPainter {
  final double t;
  final List<Color> colors;
  SparklePainter(this.t, this.colors);

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rnd = math.Random(7);
    for (var i = 0; i < 26; i++) {
      final angle = rnd.nextDouble() * math.pi * 2;
      final speed = 0.45 + rnd.nextDouble() * 0.55;
      final dist =
          (size.shortestSide * 0.55) * speed * Curves.easeOutCubic.transform(t);
      final pos = center + Offset(math.cos(angle), math.sin(angle)) * dist;
      final fade = (1 - t).clamp(0.0, 1.0);
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: fade);
      final r = 2.5 + rnd.nextDouble() * 4;
      if (i % 3 == 0) {
        canvas.drawCircle(pos, r, paint);
      } else {
        final path = Path()
          ..moveTo(pos.dx, pos.dy - r * 1.6)
          ..lineTo(pos.dx + r * 0.5, pos.dy - r * 0.5)
          ..lineTo(pos.dx + r * 1.6, pos.dy)
          ..lineTo(pos.dx + r * 0.5, pos.dy + r * 0.5)
          ..lineTo(pos.dx, pos.dy + r * 1.6)
          ..lineTo(pos.dx - r * 0.5, pos.dy + r * 0.5)
          ..lineTo(pos.dx - r * 1.6, pos.dy)
          ..lineTo(pos.dx - r * 0.5, pos.dy - r * 0.5)
          ..close();
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(SparklePainter old) => old.t != t;
}

/// "Награда получена!": the reward pops in with a burst of sparkles.
Future<void> showRewardDialog(
  BuildContext context, {
  required RewardStyle style,
  required String title,
  required String text,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Закрыть'),
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 450),
    pageBuilder: (_, __, ___) =>
        RewardDialogView(style: style, title: title, text: text),
    transitionBuilder: (context, anim, _, child) => ScaleTransition(
      scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
      child: FadeTransition(opacity: anim, child: child),
    ),
  );
}

class RewardDialogView extends StatefulWidget {
  final RewardStyle style;
  final String title;
  final String text;
  const RewardDialogView({
    super.key,
    required this.style,
    required this.title,
    required this.text,
  });

  @override
  State<RewardDialogView> createState() => RewardDialogViewState();
}

class RewardDialogViewState extends State<RewardDialogView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _burst = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..forward();

  @override
  void dispose() {
    _burst.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    return Center(
      child: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 300,
          height: 340,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _burst,
                  builder: (_, __) => CustomPaint(
                    painter: SparklePainter(_burst.value, [
                      const Color(0xFFFFE066),
                      style.colors.first,
                      Colors.white,
                      style.colors.last,
                    ]),
                  ),
                ),
              ),
              Container(
                width: 270,
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: style.colors,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: style.glow.withValues(alpha: 0.6),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.style.asset != null)
                      gameAsset(widget.style.asset!, 112)
                    else
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.28),
                        ),
                        child: Icon(style.icon, size: 48, color: Colors.white),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.text,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: style.glow,
                        ),
                        child: Text(
                          tr('Отлично!'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How one badge looks: its colours and an icon (the crown is drawn by hand).
class BadgeLook {
  final List<Color> colors;
  final IconData? icon; // null: the crown, painted
  const BadgeLook(this.colors, this.icon);
}

BadgeLook badgeLook(String key) {
  switch (key) {
    case 'champion':
      return const BadgeLook([
        Color(0xFFFFD54F),
        Color(0xFFFF8F00),
      ], Icons.emoji_events_rounded);
    case 'medal':
      return const BadgeLook([
        Color(0xFF90CAF9),
        Color(0xFF3F7CFF),
      ], Icons.military_tech_rounded);
    case 'flame':
      return const BadgeLook([
        Color(0xFFFFA06B),
        Color(0xFFE5391F),
      ], Icons.local_fire_department_rounded);
    case 'star':
      return const BadgeLook([
        Color(0xFFFFE066),
        Color(0xFFFFA000),
      ], Icons.star_rounded);
    case 'diamond':
      return const BadgeLook([
        Color(0xFF7FDBFF),
        Color(0xFF7C4DFF),
      ], Icons.diamond_rounded);
    case 'rocket':
      return const BadgeLook([
        Color(0xFFFF8AB8),
        Color(0xFF8E3CFF),
      ], Icons.rocket_launch_rounded);
    case 'shield':
      return const BadgeLook([
        Color(0xFF6EE7B7),
        Color(0xFF0E9F6E),
      ], Icons.shield_rounded);
    case 'bolt':
      return const BadgeLook([
        Color(0xFFFFF176),
        Color(0xFFFFA000),
      ], Icons.bolt_rounded);
    case 'heart':
      return const BadgeLook([
        Color(0xFFFF8A8A),
        Color(0xFFD62F4F),
      ], Icons.favorite_rounded);
    case 'leaf':
      return const BadgeLook([
        Color(0xFFA5E887),
        Color(0xFF2E9E4F),
      ], Icons.eco_rounded);
    default: // crown
      return const BadgeLook([Color(0xFFFFE066), Color(0xFFFF9800)], null);
  }
}

/// A small round badge: the icon on its gradient. Shown next to a name and in
/// the collection.
class BadgeGlyph extends StatelessWidget {
  final String badgeKey;
  final double size;
  const BadgeGlyph({super.key, required this.badgeKey, required this.size});

  @override
  Widget build(BuildContext context) {
    final look = badgeLook(badgeKey);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: look.colors,
        ),
        boxShadow: [
          BoxShadow(
            color: look.colors.last.withValues(alpha: 0.4),
            blurRadius: size * 0.3,
          ),
        ],
      ),
      child: look.icon == null
          ? CustomPaint(painter: _CrownPainter())
          : Icon(look.icon, size: size * 0.62, color: Colors.white),
    );
  }
}

class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(w * 0.2, h * 0.68)
      ..lineTo(w * 0.14, h * 0.36)
      ..lineTo(w * 0.34, h * 0.5)
      ..lineTo(w * 0.5, h * 0.28)
      ..lineTo(w * 0.66, h * 0.5)
      ..lineTo(w * 0.86, h * 0.36)
      ..lineTo(w * 0.8, h * 0.68)
      ..close();
    final fill = Paint()..color = Colors.white;
    canvas.drawPath(path, fill);
    canvas.drawRRect(
      RRect.fromLTRBR(
        w * 0.2,
        h * 0.72,
        w * 0.8,
        h * 0.8,
        Radius.circular(w * 0.04),
      ),
      fill,
    );
  }

  @override
  bool shouldRepaint(_CrownPainter old) => false;
}
