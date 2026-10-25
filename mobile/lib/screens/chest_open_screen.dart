import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../services/chest_queue.dart';
import '../services/chest_sound.dart';
import '../services/streak_state.dart';
import '../widgets/game_icons.dart';
import '../widgets/reward_chips.dart' show boosterShort;

/// Opens [count] (1, 5 or 10) chests of one kind: three taps, each shakes the
/// chest, the third bursts it open; the chest leaves and the prizes (one for a
/// single chest, one per chest for a batch) fly out and settle in the middle.
/// Pops with the refreshed bank when the person takes the prizes.
class ChestOpenScreen extends StatefulWidget {
  final ChestBank bank;

  /// The chests to open (one kind). When each carries its sealed prize, the opening
  /// needs no network at all: it is shown at once and the server is told afterwards.
  final List<BankChest> chests;

  /// Replace the server calls (tests).
  final Future<(List<ChestPrize>, ChestBank)> Function(String key, int count)? opener;

  const ChestOpenScreen({super.key, required this.bank, required this.chests, this.opener});

  String get chestKey => chests.first.chestKey;
  int get count => chests.length;

  @override
  State<ChestOpenScreen> createState() => _ChestOpenScreenState();
}

class _ChestOpenScreenState extends State<ChestOpenScreen> with TickerProviderStateMixin {
  static const _tapsNeeded = 3;
  late ChestBank _bank = widget.bank;
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.count > 1 ? 3800 : 2200),
  );
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  int _taps = 0;
  bool _busy = false;
  bool _opening = false;
  Future<(List<ChestPrize>, ChestBank)>? _pending;
  List<ChestPrize>? _prizes;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.opener == null) unawaited(ChestSound.warmUp());
    // Decode the pictures the opening needs now, so the burst never waits on them.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      precacheGame(context, 'assets/chests/${widget.chestKey}_open.png', 260);
      for (final a in const ['diamond', 'freeze', 'merge', 'points']) {
        for (final s in widget.count > 1 ? const [46.0, 26.0] : const [150.0]) {
          precacheGame(context, 'assets/icons/$a.png', s);
        }
      }
    });
  }

  @override
  void dispose() {
    _burst.dispose();
    ChestSound.stop();
    _float.dispose();
    _shake.dispose();
    _reveal.dispose();
    super.dispose();
  }

  /// A single chest plays its show to the end. With several, a tap skips the rest only once the
  /// first prize has flown out (before that the opening animation just plays).
  void _skipShow() {
    final prizes = _prizes;
    if (prizes == null || prizes.length < 2) return;
    if (_reveal.value < 0.44 || _reveal.value >= 1) return;
    _reveal.value = 1;
  }

  Future<void> _tap() async {
    if (_prizes != null) {
      _skipShow();
      return;
    }
    if (_opening) return;
    setState(() {
      _taps++;
      _error = null;
    });
    _shake.forward(from: 0);
    // The last tap bursts the chest: it gets the long rumble, not the short tap buzz.
    if (_taps < _tapsNeeded) ChestSound.buzzTap();
    if (widget.opener == null) unawaited(ChestSound.tap());
    if (_taps < _tapsNeeded) {
      // Without sealed prizes the answer is fetched one tap early, so it is ready at the burst.
      if (_taps == _tapsNeeded - 1 && !_local) _pending = (widget.opener ?? _openOnServer)(widget.chestKey, widget.count);
      return;
    }
    _opening = true;
    // Burst at once: flash, rumble and sound do not wait for anything.
    _burst.forward(from: 0);
    ChestSound.buzzOpen();
    if (widget.opener == null) unawaited(ChestSound.open());
    if (_local) {
      // Everything is known already: show the prizes now and tell the server later.
      final ids = [for (final c in widget.chests) c.id];
      // A running "x2" ticket doubles every prize but a ticket itself (the server checks the same moment).
      final twice = widget.bank.boosterRunning;
      final prizes = [
        for (final c in widget.chests)
          ChestPrize(
            chestKey: c.chestKey,
            kind: c.prizeKind!,
            amount: twice && c.prizeKind != 'booster' ? c.prizeAmount! * 2 : c.prizeAmount!,
            doubled: twice && c.prizeKind != 'booster',
          ),
      ];
      if (widget.opener == null) ChestQueue.opened([for (final p in prizes.indexed) (ids[p.$1], p.$2.kind, p.$2.amount)]);
      dailyGoalTick.value++;
      setState(() {
        _prizes = prizes;
        _bank = _bank.without(ids.toSet());
      });
      _reveal.forward(from: 0);
      return;
    }
    _pending ??= (widget.opener ?? _openOnServer)(widget.chestKey, widget.count);
    try {
      final (prizes, bank) = await _pending!;
      if (widget.opener == null) ApiClient.instance.fetchEconomy();
      dailyGoalTick.value++;
      if (!mounted) return;
      setState(() {
        _prizes = prizes;
        _bank = bank;
      });
      _reveal.forward(from: 0);
    } on ApiException catch (e) {
      _failed(e.message);
    } catch (_) {
      _failed(tr('Не удалось. Проверьте интернет.'));
    }
  }

  bool get _local => widget.chests.every((c) => c.hasPrize);

  void _failed(String message) {
    ChestSound.stop();
    _pending = null;
    _opening = false;
    _taps = 0;
    if (mounted) setState(() => _error = message);
  }

  Future<(List<ChestPrize>, ChestBank)> _openOnServer(String key, int count) async {
    if (count == 1) {
      final (prize, bank) = await ApiClient.instance.openChest(widget.chests.first.id);
      return ([prize], bank);
    }
    return ApiClient.instance.openManyChests(key, count);
  }

  @override
  Widget build(BuildContext context) {
    final type = _bank.type(widget.chestKey);
    final color = Color(type?.color ?? 0xFFA0693B);
    return Scaffold(
      backgroundColor: const Color(0xFF14103A),
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.1),
            radius: 1.1,
            colors: [Color.lerp(const Color(0xFF14103A), color, 0.35)!, const Color(0xFF0B0824)],
          ),
        ),
        child: SafeArea(
          child: Stack(children: [
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                key: const ValueKey('chest-close'),
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(_bank),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                key: const ValueKey('chest-skip'),
                behavior: HitTestBehavior.translucent,
                // While the prizes are still arriving, a tap shows the result at once.
                onTap: _skipShow,
                child: _stage(color, type?.name ?? tr('Сундук')),
              ),
            ),
            if (widget.bank.boosterRunning)
              Positioned(
                top: 8,
                right: 12,
                child: Container(
                  key: const ValueKey('boost-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(99), border: Border.all(color: const Color(0xFFFFD54F), width: 1.5)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const BoosterIcon(size: 24),
                    const SizedBox(width: 4),
                    Text(tr('Награды ×2'), style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.w900, fontSize: 13)),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _stage(Color color, String name) {
    return AnimatedBuilder(
      animation: Listenable.merge([_float, _shake, _reveal, _burst]),
      builder: (context, _) {
        final r = _reveal.value;
        final prizes = _prizes;
        final batch = widget.count > 1;
        final bob = math.sin(_float.value * 2 * math.pi) * 8;
        final decay = 1 - _shake.value;
        final angle = math.sin(_shake.value * math.pi * 6) * 0.13 * decay;
        final grow = 1 + 0.08 * _taps * (prizes == null ? 1 : 0);
        // The chest bursts open first and then leaves downwards (a batch reveal is longer, so scale the times).
        final k = batch ? 2200 / 3800 : 1.0;
        final leave = prizes == null ? 0.0 : Curves.easeIn.transform(((r - 0.2 * k) / (0.3 * k)).clamp(0.0, 1.0));
        final flash = prizes == null ? (_opening ? math.sin(_burst.value * math.pi) : 0.0) : math.sin((r / (0.35 * k)).clamp(0.0, 1.0) * math.pi);
        final shine = prizes == null ? 0.0 : Curves.easeOutBack.transform(((r - 0.3 * k) / (0.35 * k)).clamp(0.0, 1.0));
        return Stack(alignment: Alignment.center, children: [
          if (prizes != null)
            Opacity(
              opacity: shine.clamp(0.0, 1.0),
              child: Transform.rotate(angle: r * 2.2, child: CustomPaint(size: const Size(360, 360), painter: _RaysPainter(color))),
            ),
          if (prizes == null || leave < 1)
            Opacity(
              opacity: 1 - leave,
              child: Transform.translate(
                offset: Offset(0, bob + 220 * leave),
                child: Transform.rotate(
                  angle: angle,
                  child: Transform.scale(
                    scale: grow * (1 - 0.35 * leave),
                    child: GestureDetector(
                      key: const ValueKey('chest-tap'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _tap,
                      child: ChestImage(widget.chestKey, open: prizes != null || (_opening && _burst.value > 0.45), size: 260),
                    ),
                  ),
                ),
              ),
            ),
          if (flash > 0)
            IgnorePointer(
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [Colors.white.withValues(alpha: 0.9 * flash), Colors.white.withValues(alpha: 0)]),
                ),
              ),
            ),
          if (prizes != null && !batch)
            Opacity(
              opacity: shine.clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.6 + 0.4 * shine, child: _prizeView(prizes.first)),
            ),
          if (prizes != null && batch) ..._flyingPrizes(prizes, r),
          if (prizes != null && batch) _totals(prizes, r),
          if (prizes == null)
            Positioned(
              bottom: 56,
              child: Column(children: [
                Text(
                  widget.count > 1 ? '$name ×${widget.count}' : name,
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                Text(tr('Нажмите на сундук 3 раза'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 12),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < _tapsNeeded; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: i < _taps ? const Color(0xFFFFD54F) : Colors.white24),
                    ),
                ]),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80)))),
              ]),
            ),
          if (prizes != null && r <= 0.75)
            Positioned(
              bottom: 56,
              child: Text(tr('Нажмите, чтобы пропустить'), style: const TextStyle(color: Colors.white38, fontSize: 13)),
            ),
          if (prizes != null && r > 0.75)
            Positioned(
              bottom: 40,
              child: FilledButton(
                key: const ValueKey('chest-collect'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3FD43A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                onPressed: () => Navigator.of(context).pop(_bank),
                child: Text(tr('Забрать')),
              ),
            ),
        ]);
      },
    );
  }

  /// One prize per chest, flying out of the chest one after another into a grid.
  List<Widget> _flyingPrizes(List<ChestPrize> prizes, double r) {
    final n = prizes.length;
    final cols = n > 5 ? 5 : n;
    final rows = (n / cols).ceil();
    const cell = 68.0;
    final out = <Widget>[];
    for (var i = 0; i < n; i++) {
      final col = i % cols, row = i ~/ cols;
      final tx = (col - (cols - 1) / 2) * cell;
      final ty = (row - (rows - 1) / 2) * (cell + 24) - 40;
      // each prize starts a little after the previous one
      final start = 0.16 + i * 0.035;
      final p = ((r - start) / 0.28).clamp(0.0, 1.0);
      if (p == 0) continue;
      final ease = Curves.easeOutCubic.transform(p);
      final scale = p < 0.6 ? 0.1 + 1.15 * (p / 0.6) : 1.25 - 0.25 * ((p - 0.6) / 0.4);
      out.add(Transform.translate(
        offset: Offset(tx * ease, -70 + (ty + 70) * ease - 50 * math.sin(p * math.pi)),
        child: Opacity(
          opacity: (p * 4).clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: _smallPrize(prizes[i])),
        ),
      ));
    }
    return out;
  }

  Widget _smallPrize(ChestPrize p) => SizedBox(
        width: 64,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _prizeIcon(p.kind, 46),
          const SizedBox(height: 2),
          Text(
            _amountText(p),
            style: TextStyle(
              color: p.doubled ? const Color(0xFFFFD54F) : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              shadows: p.doubled ? const [Shadow(color: Color(0xCCFFC83C), blurRadius: 10)] : null,
            ),
          ),
        ]),
      );

  Widget _totals(List<ChestPrize> prizes, double r) {
    final sums = <String, int>{};
    for (final p in prizes) {
      sums[p.kind] = (sums[p.kind] ?? 0) + p.amount;
    }
    final t = ((r - 0.62) / 0.15).clamp(0.0, 1.0);
    return Positioned(
      bottom: 110,
      child: Opacity(
        opacity: t,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text('${tr('Всего')}', style: const TextStyle(color: Colors.white70, fontSize: 14)),
            if (prizes.any((p) => p.doubled)) ...[const SizedBox(width: 4), const BoosterIcon(size: 24)],
            const Text(':', style: TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final e in sums.entries)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  _prizeIcon(e.key, 26),
                  const SizedBox(width: 3),
                  Text(
                    e.key == 'booster' ? '×${prizes.where((p) => p.kind == 'booster').length}' : '+${e.key == 'diamonds' ? compactNumber(e.value) : e.value}',
                    style: TextStyle(color: prizes.any((p) => p.doubled && p.kind == e.key) ? const Color(0xFFFFD54F) : Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ]),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _prizeIcon(String kind, double size) {
    switch (kind) {
      case 'freeze':
        return FreezeIcon(size: size);
      case 'merge':
        return MergeIcon(size: size);
      case 'points':
        return PointsIcon(size: size);
      case 'booster':
        return BoosterIcon(size: size);
      default:
        return DiamondIcon(size: size);
    }
  }

  String _amountText(ChestPrize p) =>
      p.kind == 'booster' ? boosterShort(p.amount) : '+${p.kind == 'diamonds' ? compactNumber(p.amount) : p.amount}';

  Widget _prizeView(ChestPrize p) {
    final String label;
    switch (p.kind) {
      case 'freeze':
        label = tr('Заморозки серии');
        break;
      case 'merge':
        label = tr('Объединители серии');
        break;
      case 'points':
        label = tr('Очки рейтинга');
        break;
      case 'booster':
        label = tr('Удвоитель наград');
        break;
      default:
        label = tr('Бриллианты');
    }
    final big = TextStyle(color: Colors.white, fontSize: p.kind == 'booster' ? 40 : 52, fontWeight: FontWeight.w900, height: 1);
    // With a ticket running the plain number shows first, the ticket flies in and it turns into the doubled gold one.
    final t = _reveal.value;
    double span(double a, double b) => ((t - a) / (b - a)).clamp(0.0, 1.0);
    final Widget amount;
    if (p.doubled) {
      final k = widget.count > 1 ? 1.0 : 1.0;
      final ticket = Curves.easeOutBack.transform(span(0.62 * k, 0.78 * k));
      final fin = Curves.easeOutBack.transform(span(0.78 * k, 0.9 * k));
      amount = SizedBox(
        height: 70,
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
          Opacity(
            opacity: (1 - 0.55 * fin).clamp(0.0, 1.0),
            child: Transform.scale(
              scale: 1 - 0.3 * fin,
              child: Text('+${p.kind == 'diamonds' ? compactNumber(p.baseAmount) : p.baseAmount}', style: big.copyWith(fontSize: 30, color: Colors.white70, decoration: fin > 0.1 ? TextDecoration.lineThrough : null)),
            ),
          ),
          Opacity(opacity: ticket.clamp(0.0, 1.0), child: Transform.scale(scale: ticket, child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: BoosterIcon(size: 58)))),
          Opacity(
            opacity: fin.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: fin,
              child: Text(
                '+${p.kind == 'diamonds' ? compactNumber(p.amount) : p.amount}',
                key: const ValueKey('chest-prize'),
                style: big.copyWith(color: const Color(0xFFFFD54F), fontSize: 56, shadows: const [Shadow(color: Color(0xE6FFC83C), blurRadius: 18)]),
              ),
            ),
          ),
        ]),
      );
    } else {
      amount = Text(_amountText(p), key: const ValueKey('chest-prize'), style: big);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _prizeIcon(p.kind, 150),
      const SizedBox(height: 10),
      amount,
      const SizedBox(height: 4),
      Text(label, style: const TextStyle(color: Colors.white70, fontSize: 17, fontWeight: FontWeight.w700)),
    ]);
  }
}

class _RaysPainter extends CustomPainter {
  final Color color;
  const _RaysPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final paint = Paint()
      ..shader = RadialGradient(colors: [Colors.white.withValues(alpha: 0.55), color.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: c, radius: size.width / 2));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final path = Path()
        ..moveTo(c.dx, c.dy)
        ..lineTo(c.dx + math.cos(a - 0.08) * size.width / 2, c.dy + math.sin(a - 0.08) * size.width / 2)
        ..lineTo(c.dx + math.cos(a + 0.08) * size.width / 2, c.dy + math.sin(a + 0.08) * size.width / 2)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_RaysPainter old) => old.color != color;
}
