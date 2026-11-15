import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../screens/chest_list_screen.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';

/// The doublers running right now, in the top bar: each one is its icon inside a ring that empties
/// with the time, the time left small under it. Doublers of different kinds run side by side, each
/// with its own ring. With under [alarmBelow] left, the ring and the time turn red and blink.
/// Nothing is drawn while no doubler runs. A tap opens the sheet «Идут сейчас».
class ActiveBoostersButton extends StatefulWidget {
  /// The state to start from (tests); otherwise the remembered one.
  final BoosterState? initial;
  const ActiveBoostersButton({super.key, this.initial});

  static const Duration alarmBelow = Duration(minutes: 5);
  static const List<String> kinds = ['chest', 'rating', 'xp'];

  @override
  State<ActiveBoostersButton> createState() => _ActiveBoostersButtonState();
}

String boosterTimeLeft(Duration left) {
  final s = left.inSeconds.clamp(0, 1 << 30);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

String boosterName(String kind) => switch (kind) {
      'rating' => tr('Удвоитель рейтинга'),
      'xp' => tr('Удвоитель пропуска'),
      _ => tr('Удвоитель сундуков'),
    };

String boosterNote(String kind) => switch (kind) {
      'rating' => tr('Все очки рейтинга удваиваются, пока идёт время.'),
      'xp' => tr('Вся энергия пропуска удваивается, пока идёт время.'),
      _ => tr('Призы из сундуков удваиваются, пока идёт время.'),
    };

class _ActiveBoostersButtonState extends State<ActiveBoostersButton> with SingleTickerProviderStateMixin {
  late BoosterState? _state = widget.initial ?? ApiClient.instance.cachedBoosters();
  Timer? _tick;
  late final AnimationController _blink = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  /// The longest the running ticket had left when first seen: the ring's full circle.
  final Map<String, ({DateTime until, int seconds})> _span = {};

  @override
  void initState() {
    super.initState();
    dailyGoalTick.addListener(_load);
    if (widget.initial == null) _load();
    _sync();
  }

  @override
  void dispose() {
    dailyGoalTick.removeListener(_load);
    _tick?.cancel();
    _blink.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await ApiClient.instance.fetchBoosters();
    if (mounted && s != null) {
      setState(() => _state = s);
      _sync();
    }
  }

  List<String> get _running => [for (final k in ActiveBoostersButton.kinds) if (_state?.of(k).running ?? false) k];

  Duration _left(String kind) {
    final until = _state?.of(kind).activeUntil;
    return until == null ? Duration.zero : until.difference(DateTime.now());
  }

  /// Ticks once a second while something runs; blinks while something is about to end.
  void _sync() {
    final running = _running;
    if (running.isEmpty) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_running.isEmpty) _sync();
        setState(() {});
        _syncBlink();
      });
    }
    _syncBlink();
  }

  void _syncBlink() {
    final alarm = _running.any((k) => _left(k) < ActiveBoostersButton.alarmBelow);
    if (alarm && !_blink.isAnimating) {
      _blink.repeat(reverse: true);
    } else if (!alarm && _blink.isAnimating) {
      _blink.stop();
      _blink.value = 0;
    }
  }

  double _fraction(String kind) {
    final until = _state?.of(kind).activeUntil;
    if (until == null) return 0;
    final left = _left(kind).inSeconds;
    final known = _span[kind];
    // A new ticket moves `until` later: the ring's full circle is then what is left now.
    if (known == null || known.until.isBefore(until) && left > known.seconds) {
      _span[kind] = (until: until, seconds: math.max(left, 1));
    }
    final span = _span[kind]!.seconds;
    return (left / span).clamp(0.0, 1.0);
  }

  Future<void> _open() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (_) => _BoostersSheet(state: _state, left: _left, fraction: _fraction),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final running = _running;
    if (running.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Semantics(
        button: true,
        label: tr('Идут сейчас'),
        child: GestureDetector(
          key: const ValueKey('boosters-button'),
          behavior: HitTestBehavior.opaque,
          onTap: _open,
          child: SizedBox(
            height: 58,
            child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (var i = 0; i < running.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                _Ring(kind: running[i], left: _left(running[i]), fraction: _fraction(running[i]), blink: _blink),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  final String kind;
  final Duration left;
  final double fraction;
  final Animation<double> blink;
  const _Ring({required this.kind, required this.left, required this.fraction, required this.blink});

  @override
  Widget build(BuildContext context) {
    final alarm = left < ActiveBoostersButton.alarmBelow;
    return AnimatedBuilder(
      animation: blink,
      builder: (_, __) {
        final fade = alarm ? 1 - 0.75 * blink.value : 1.0;
        final color = alarm ? AppColors.danger : AppColors.primary;
        return SizedBox(
          width: 46,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 42,
              height: 42,
              child: CustomPaint(
                painter: _RingPainter(fraction: fraction, color: color.withValues(alpha: fade), track: AppColors.progressTrack),
                child: Center(child: BoosterIcon(size: 24, kind: kind)),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              boosterTimeLeft(left),
              key: ValueKey('booster-time-$kind'),
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: alarm ? AppColors.danger.withValues(alpha: fade) : AppColors.primaryDark,
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  final Color color;
  final Color track;
  const _RingPainter({required this.fraction, required this.color, required this.track});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(2);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, base..color = track);
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * fraction, false, base..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.fraction != fraction || old.color != color || old.track != track;
}

/// «Идут сейчас»: every running doubler with its own bar and time left; below, what is in stock
/// and the way into the chests screen, where tickets are switched on.
class _BoostersSheet extends StatefulWidget {
  final BoosterState? state;
  final Duration Function(String) left;
  final double Function(String) fraction;
  const _BoostersSheet({required this.state, required this.left, required this.fraction});

  @override
  State<_BoostersSheet> createState() => _BoostersSheetState();
}

class _BoostersSheetState extends State<_BoostersSheet> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _openChests() async {
    final bank = ApiClient.instance.cachedChests();
    final nav = Navigator.of(context);
    nav.pop();
    if (bank != null) await nav.push(MaterialPageRoute(builder: (_) => ChestListScreen(bank: bank)));
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final running = [for (final k in ActiveBoostersButton.kinds) if (state?.of(k).running ?? false) k];
    final stock = [for (final k in ActiveBoostersButton.kinds) state?.of(k).total ?? 0].fold<int>(0, (a, b) => a + b);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.progressTrack, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 14),
          Text(tr('Идут сейчас'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.primaryDark)),
          const SizedBox(height: 10),
          for (final k in running) ...[
            _BoosterRow(kind: k, left: widget.left(k), fraction: widget.fraction(k)),
            const SizedBox(height: 8),
          ],
          InkWell(
            key: const ValueKey('boosters-stock'),
            borderRadius: BorderRadius.circular(18),
            onTap: _openChests,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(tr('В запасе'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
                    Text('$stock', style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
                  ]),
                ),
                Text(tr('Все бонусы'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BoosterRow extends StatelessWidget {
  final String kind;
  final Duration left;
  final double fraction;
  const _BoosterRow({required this.kind, required this.left, required this.fraction});

  @override
  Widget build(BuildContext context) {
    final alarm = left < ActiveBoostersButton.alarmBelow;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.cardBorder)),
      child: Row(children: [
        BoosterIcon(size: 40, kind: kind),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(boosterName(kind), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.primaryDark)),
            Text(boosterNote(kind), maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: SizedBox(
                height: 4,
                child: Stack(children: [
                  Positioned.fill(child: ColoredBox(color: AppColors.progressTrack)),
                  FractionallySizedBox(widthFactor: fraction, child: ColoredBox(color: alarm ? AppColors.danger : AppColors.primary)),
                ]),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 10),
        Text(
          boosterTimeLeft(left),
          key: ValueKey('sheet-time-$kind'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()], color: alarm ? AppColors.danger : AppColors.primaryDark),
        ),
      ]),
    );
  }
}
