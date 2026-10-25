import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../models/chest.dart';
import '../services/chest_sound.dart';
import '../services/streak_state.dart';
import '../widgets/game_icons.dart';

/// Opens the person's chests one after another: three taps, each shakes the
/// chest, the third bursts it open; the chest leaves and the prize shines in
/// the middle.
class ChestOpenScreen extends StatefulWidget {
  final ChestBank bank;

  /// Replaces the server call (tests).
  final Future<(ChestPrize, ChestBank)> Function(int id)? opener;
  const ChestOpenScreen({super.key, required this.bank, this.opener});

  @override
  State<ChestOpenScreen> createState() => _ChestOpenScreenState();
}

class _ChestOpenScreenState extends State<ChestOpenScreen> with TickerProviderStateMixin {
  static const _tapsNeeded = 3;
  late ChestBank _bank = widget.bank;
  late final AnimationController _float = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200));
  int _taps = 0;
  bool _busy = false;
  ChestPrize? _prize;
  String? _error;

  BankChest? get _current => _bank.chests.isEmpty ? null : _bank.chests.first;

  @override
  void dispose() {
    ChestSound.stop();
    _float.dispose();
    _shake.dispose();
    _reveal.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    final chest = _current;
    if (chest == null || _busy || _prize != null) return;
    setState(() {
      _taps++;
      _error = null;
    });
    _shake.forward(from: 0);
    ChestSound.buzzTap();
    if (widget.opener == null) unawaited(ChestSound.tap());
    if (_taps < _tapsNeeded) return;
    _busy = true;
    try {
      final (prize, bank) = await (widget.opener ?? ApiClient.instance.openChest)(chest.id);
      if (widget.opener == null) ApiClient.instance.fetchEconomy();
      dailyGoalTick.value++;
      if (!mounted) return;
      setState(() {
        _prize = prize;
        _bank = bank;
      });
      _reveal.forward(from: 0);
      ChestSound.buzzOpen();
      if (widget.opener == null) unawaited(ChestSound.open());
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      _taps = 0;
    } catch (_) {
      if (mounted) setState(() => _error = tr('Не удалось. Проверьте интернет.'));
      _taps = 0;
    } finally {
      _busy = false;
    }
  }

  void _next() {
    if (_bank.chests.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _prize = null;
      _taps = 0;
    });
    _reveal.reset();
  }

  @override
  Widget build(BuildContext context) {
    final chest = _current ?? (_prize == null ? null : BankChest(id: 0, chestKey: _prize!.chestKey, source: ''));
    final key = _prize?.chestKey ?? chest?.chestKey ?? 'wood';
    final type = _bank.type(key);
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
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned.fill(child: _stage(key, color, type?.name ?? tr('Сундук'))),
          ]),
        ),
      ),
    );
  }

  Widget _stage(String key, Color color, String name) {
    return AnimatedBuilder(
      animation: Listenable.merge([_float, _shake, _reveal]),
      builder: (context, _) {
        final r = _reveal.value;
        final prize = _prize;
        final bob = math.sin(_float.value * 2 * math.pi) * 8;
        final decay = 1 - _shake.value;
        final angle = math.sin(_shake.value * math.pi * 6) * 0.13 * decay;
        final grow = 1 + 0.08 * _taps * (prize == null ? 1 : 0);
        // The chest bursts at 0..0.2 and then leaves downwards.
        final leave = prize == null ? 0.0 : Curves.easeIn.transform(((r - 0.2) / 0.3).clamp(0.0, 1.0));
        final flash = prize == null ? 0.0 : math.sin((r / 0.35).clamp(0.0, 1.0) * math.pi);
        final shine = prize == null ? 0.0 : Curves.easeOutBack.transform(((r - 0.3) / 0.35).clamp(0.0, 1.0));
        return Stack(alignment: Alignment.center, children: [
          if (prize != null)
            Opacity(
              opacity: shine.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: r * 2.2,
                child: CustomPaint(size: const Size(360, 360), painter: _RaysPainter(color)),
              ),
            ),
          if (prize == null || leave < 1)
            Opacity(
              opacity: 1 - leave,
              child: Transform.translate(
                offset: Offset(0, bob + 220 * leave),
                child: Transform.rotate(
                  angle: angle,
                  child: Transform.scale(
                    scale: (grow * (1 - 0.35 * leave)),
                    child: GestureDetector(
                      key: const ValueKey('chest-tap'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _tap,
                      child: ChestImage(key, open: prize != null, size: 260),
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
          if (prize != null)
            Opacity(
              opacity: shine.clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.6 + 0.4 * shine, child: _prizeView(prize)),
            ),
          if (prize == null)
            Positioned(
              bottom: 56,
              child: Column(children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(tr('Нажмите на сундук 3 раза'), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 12),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < _tapsNeeded; i++)
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _taps ? const Color(0xFFFFD54F) : Colors.white24,
                      ),
                    ),
                ]),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFFF8A80))),
                  ),
              ]),
            ),
          if (prize != null && r > 0.75)
            Positioned(
              bottom: 56,
              child: FilledButton(
                key: const ValueKey('chest-collect'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFFC53D),
                  foregroundColor: const Color(0xFF3B2600),
                  padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 14),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                onPressed: _next,
                child: Text(_bank.chests.isEmpty ? tr('Забрать') : tr('Следующий сундук')),
              ),
            ),
        ]);
      },
    );
  }

  Widget _prizeView(ChestPrize p) {
    final Widget icon;
    final String label;
    switch (p.kind) {
      case 'freeze':
        icon = const FreezeIcon(size: 150);
        label = tr('Заморозки серии');
        break;
      case 'merge':
        icon = const MergeIcon(size: 150);
        label = tr('Объединители серии');
        break;
      case 'points':
        icon = const PointsIcon(size: 150);
        label = tr('Очки рейтинга');
        break;
      default:
        icon = const DiamondIcon(size: 150);
        label = tr('Бриллианты');
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      icon,
      const SizedBox(height: 10),
      Text(
        '+${p.kind == 'diamonds' ? compactNumber(p.amount) : p.amount}',
        key: const ValueKey('chest-prize'),
        style: const TextStyle(color: Colors.white, fontSize: 52, fontWeight: FontWeight.w900, height: 1),
      ),
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
