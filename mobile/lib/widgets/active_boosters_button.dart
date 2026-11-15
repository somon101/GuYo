import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../models/reward_spec.dart';
import '../services/streak_state.dart';
import '../theme/app_colors.dart';
import 'game_icons.dart';
import 'reward_claim_effect.dart';

/// The doublers in the top bar of «Уроки»: all three kinds are always there. A kind with tickets
/// shows its icon and how many; a running one is its icon in a ring that empties with the time,
/// the time left small under it (under [alarmBelow] ring and time turn red and blink); a kind with
/// nothing is a pale icon. A tap opens the sheet where a ticket is switched on.
/// Doublers of different kinds run side by side; one more ticket of the same kind adds its time.
class BoostersBar extends StatefulWidget {
  /// The state to start from (tests); otherwise the remembered one.
  final BoosterState? initial;
  const BoostersBar({super.key, this.initial});

  static const Duration alarmBelow = Duration(minutes: 5);
  static const List<String> kinds = ['chest', 'rating', 'xp'];

  @override
  State<BoostersBar> createState() => _BoostersBarState();
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

String boosterEffectTitle(String kind) => switch (kind) {
      'rating' => tr('Очки рейтинга ×2'),
      'xp' => tr('Энергия пропуска ×2'),
      _ => tr('Награды ×2'),
    };

String ticketMinutes(int m) => m >= 60 && m % 60 == 0 ? tr('{0} ч', [m ~/ 60]) : tr('{0} мин', [m]);

class _BoostersBarState extends State<BoostersBar> with SingleTickerProviderStateMixin {
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

  bool _isRunning(String kind) => _state?.of(kind).running ?? false;
  int _held(String kind) => _state?.of(kind).total ?? 0;

  Duration _left(String kind) {
    final until = _state?.of(kind).activeUntil;
    return until == null ? Duration.zero : until.difference(DateTime.now());
  }

  /// Ticks once a second while something runs; blinks while something is about to end.
  void _sync() {
    final anyRunning = BoostersBar.kinds.any(_isRunning);
    if (!anyRunning) {
      _tick?.cancel();
      _tick = null;
    } else {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (!BoostersBar.kinds.any(_isRunning)) _sync();
        setState(() {});
        _syncBlink();
      });
    }
    _syncBlink();
  }

  void _syncBlink() {
    final alarm = BoostersBar.kinds.any((k) => _isRunning(k) && _left(k) < BoostersBar.alarmBelow);
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
    return (left / _span[kind]!.seconds).clamp(0.0, 1.0);
  }

  /// Switches a ticket on, with the effect; a failure is said in a notice.
  Future<void> _activate(String kind, int minutes) async {
    try {
      final b = await ApiClient.instance.activateBooster(minutes, kind: kind);
      if (!mounted) return;
      setState(() => _state = b);
      _sync();
      dailyGoalTick.value++;
      await showRewardClaimEffect(context, title: boosterEffectTitle(kind), rewards: [RewardSpec(type: 'booster', amount: minutes, kind: kind)]);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(tr('Не удалось. Проверьте интернет.'))));
    }
  }

  Future<void> _open(String kind) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheet) => _BoosterSheet(
        kind: kind,
        stateOf: () => _state?.of(kind),
        left: () => _left(kind),
        fraction: () => _fraction(kind),
        onActivate: (minutes) {
          Navigator.of(sheet).pop();
          _activate(kind, minutes);
        },
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: SizedBox(
        height: 58,
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < BoostersBar.kinds.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            _Slot(
              kind: BoostersBar.kinds[i],
              running: _isRunning(BoostersBar.kinds[i]),
              held: _held(BoostersBar.kinds[i]),
              left: _left(BoostersBar.kinds[i]),
              fraction: _fraction(BoostersBar.kinds[i]),
              blink: _blink,
              onTap: () => _open(BoostersBar.kinds[i]),
            ),
          ],
        ]),
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  final String kind;
  final bool running;
  final int held;
  final Duration left;
  final double fraction;
  final Animation<double> blink;
  final VoidCallback onTap;
  const _Slot({required this.kind, required this.running, required this.held, required this.left, required this.fraction, required this.blink, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final alarm = running && left < BoostersBar.alarmBelow;
    final none = !running && held == 0;
    return Semantics(
      button: true,
      label: boosterName(kind),
      child: GestureDetector(
        key: ValueKey('booster-$kind'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedBuilder(
          animation: blink,
          builder: (_, _) {
            final fade = alarm ? 1 - 0.75 * blink.value : 1.0;
            return SizedBox(
              width: 42,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                    if (running)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _RingPainter(fraction: fraction, color: (alarm ? AppColors.danger : AppColors.primary).withValues(alpha: fade), track: AppColors.progressTrack),
                        ),
                      ),
                    Opacity(opacity: none ? 0.3 : 1, child: BoosterIcon(size: running ? 24 : 30, kind: kind)),
                    if (!running && held > 0)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          key: ValueKey('booster-count-$kind'),
                          constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99), border: Border.all(color: AppColors.canvas, width: 2)),
                          child: Text('$held', style: const TextStyle(fontSize: 10, height: 1.1, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ),
                  ]),
                ),
                if (running)
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
        ),
      ),
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
    final r = (Offset.zero & size).deflate(2);
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

/// One kind's sheet: the icon, the name and what it does; if it runs, the time left; then the
/// tickets held, one per row with «Включить». With none held: a plain «Билетов нет» and where they come from.
class _BoosterSheet extends StatefulWidget {
  final String kind;
  final BoosterState? Function() stateOf;
  final Duration Function() left;
  final double Function() fraction;
  final void Function(int minutes) onActivate;
  const _BoosterSheet({required this.kind, required this.stateOf, required this.left, required this.fraction, required this.onActivate});

  @override
  State<_BoosterSheet> createState() => _BoosterSheetState();
}

class _BoosterSheetState extends State<_BoosterSheet> {
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

  @override
  Widget build(BuildContext context) {
    final state = widget.stateOf();
    final running = state?.running ?? false;
    final left = widget.left();
    final alarm = running && left < BoostersBar.alarmBelow;
    final held = [for (final e in (state?.items.entries ?? const <MapEntry<int, int>>[])) if (e.value > 0) e]..sort((a, b) => a.key.compareTo(b.key));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.progressTrack, borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 14),
          Row(children: [
            BoosterIcon(size: 44, kind: widget.kind),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(boosterName(widget.kind), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, color: AppColors.primaryDark)),
                Text(boosterNote(widget.kind), style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText)),
              ]),
            ),
          ]),
          if (running) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(tr('Идёт удвоение. Ещё один билет прибавит время.'), style: TextStyle(fontSize: 13, color: AppColors.secondaryText))),
                  const SizedBox(width: 10),
                  Text(
                    boosterTimeLeft(left),
                    key: const ValueKey('sheet-time'),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()], color: alarm ? AppColors.danger : AppColors.primaryDark),
                  ),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: SizedBox(
                    height: 4,
                    child: Stack(children: [
                      Positioned.fill(child: ColoredBox(color: AppColors.progressTrack)),
                      FractionallySizedBox(widthFactor: widget.fraction(), child: ColoredBox(color: alarm ? AppColors.danger : AppColors.primary)),
                    ]),
                  ),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 12),
          if (held.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(tr('Билетов нет. Их можно получить в сундуках и наградах.'), key: const ValueKey('booster-none'), style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.secondaryText)),
            )
          else
            for (final e in held) ...[
              Container(
                padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.cardBorder)),
                child: Row(children: [
                  Text(ticketMinutes(e.key), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                  const SizedBox(width: 8),
                  Text('×${e.value}', style: TextStyle(fontSize: 13.5, color: AppColors.secondaryText)),
                  const Spacer(),
                  GestureDetector(
                    key: ValueKey('boost-on-${widget.kind}-${e.key}'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onActivate(e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                      child: Text(tr('Включить'), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ]),
              ),
            ],
        ]),
      ),
    );
  }
}
