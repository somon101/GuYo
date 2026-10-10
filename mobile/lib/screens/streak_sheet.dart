import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../widgets/animated_fire.dart';

const _fire = Color(0xFFFF7A29);
const _fireLight = Color(0xFFFFB347);
const _bg = Color(0xFF1C1412);
const _panel = Color(0xFF2A1E1A);
const _ice = Color(0xFF7FD3FF);

/// The streak sheet behind the profile's "Серия" card: a burning 🔥, the
/// streak in big numbers, this week's days with the active ones checked
/// and joined, and a line that says what to do next.
Future<void> showStreakSheet(BuildContext context, {required int streakDays}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    elevation: 0,
    isScrollControlled: true,
    builder: (_) => _StreakSheet(initialStreak: streakDays),
  );
}

class _StreakSheet extends StatefulWidget {
  final int initialStreak;
  const _StreakSheet({required this.initialStreak});

  @override
  State<_StreakSheet> createState() => _StreakSheetState();
}

class _StreakSheetState extends State<_StreakSheet> {
  late int _streak = widget.initialStreak;
  DateTime? _today;
  Set<DateTime> _active = {};
  Set<DateTime> _frozen = {};

  @override
  void initState() {
    super.initState();
    // The week appears at once from the last answer kept on the device.
    final cached = ApiClient.instance.cachedMyStreak();
    if (cached != null) {
      _apply(cached);
      // The card's own number is fresher than a saved answer.
      _streak = widget.initialStreak;
    }
    _load();
  }

  void _apply(StreakInfo data) {
    _streak = data.currentStreakDays;
    _today = data.today;
    _active = data.activeDates.toSet();
    _frozen = data.frozenDates.toSet();
  }

  Future<void> _load() async {
    try {
      final data = await ApiClient.instance.fetchMyStreak();
      if (!mounted) return;
      setState(() => _apply(data));
    } catch (_) {
      // The number on the card is already right; the week just stays empty.
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeToday = _today != null && _active.contains(_today);
    final String message;
    if (_streak == 0) {
      message = tr('Начните серию сегодня — выучите хотя бы одно слово');
    } else if (activeToday) {
      message = tr('Вы в ударе! Возвращайтесь завтра, чтобы огонь не погас');
    } else {
      message = tr('Позанимайтесь сегодня, чтобы не потерять серию');
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const RadialGradient(
              center: Alignment(0, -0.75),
              radius: 1.1,
              colors: [Color(0xFF4A2414), _bg],
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: tr('Закрыть'),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: Colors.white.withValues(alpha: 0.6)),
                ),
              ),
              const AnimatedFire(size: 120),
              const SizedBox(height: 4),
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_fireLight, _fire],
                ).createShader(r),
                child: Text(
                  '$_streak',
                  style: const TextStyle(fontSize: 64, height: 1, fontWeight: FontWeight.w900, color: Colors.white),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                streakDaysLabel(_streak),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _fireLight),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                decoration: BoxDecoration(
                  color: _panel,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  children: [
                    if (_today != null) _Week(today: _today!, active: _active, frozen: _frozen) else const SizedBox(height: 52),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    if (_frozen.isNotEmpty) ...[
                      Text(
                        tr('Пропущенный день заморожен — серия сохранена'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ice),
                      ),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14.5, height: 1.35, color: Colors.white.withValues(alpha: 0.9)),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('Один пропущенный день в неделю прощается автоматически'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.5)),
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

/// "день / дня / дней подряд" for [n].
String streakDaysLabel(int n) {
  final mod10 = n % 10, mod100 = n % 100;
  final String word;
  if (mod10 == 1 && mod100 != 11) {
    word = tr('день');
  } else if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
    word = tr('дня');
  } else {
    word = tr('дней');
  }
  return '$word ${tr('подряд')}';
}

/// Monday to Sunday of the current week: each active day a filled check,
/// neighbouring active days joined by a band, today ringed, days still to
/// come shown by their date.
class _Week extends StatelessWidget {
  final DateTime today;
  final Set<DateTime> active;
  final Set<DateTime> frozen;
  const _Week({required this.today, required this.active, this.frozen = const {}});

  @override
  Widget build(BuildContext context) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
    final letters = [tr('Пн'), tr('Вт'), tr('Ср'), tr('Чт'), tr('Пт'), tr('Сб'), tr('Вс')];
    bool on(DateTime d) => active.contains(d) || frozen.contains(d);

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Column(
              children: [
                Text(
                  letters[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: days[i] == today ? _fireLight : Colors.white.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 34,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // The band joining this day to an active neighbour.
                      if (on(days[i]))
                        Row(
                          children: [
                            Expanded(child: _band(i > 0 && on(days[i - 1]))),
                            Expanded(child: _band(i < 6 && on(days[i + 1]))),
                          ],
                        ),
                      _dot(days[i]),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _band(bool visible) => Container(height: 28, color: visible ? _fire.withValues(alpha: 0.28) : Colors.transparent);

  Widget _dot(DateTime d) {
    final isToday = d == today;
    if (frozen.contains(d)) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _ice.withValues(alpha: 0.18),
          border: Border.all(color: _ice, width: 1.6),
        ),
        child: const Icon(Icons.ac_unit_rounded, size: 17, color: _ice),
      );
    }
    if (active.contains(d)) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [_fireLight, _fire]),
          border: isToday ? Border.all(color: Colors.white, width: 2) : null,
          boxShadow: [BoxShadow(color: _fire.withValues(alpha: 0.45), blurRadius: 10)],
        ),
        child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
      );
    }
    final future = d.isAfter(today);
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: future ? 0.08 : 0.04),
        border: isToday ? Border.all(color: _fireLight, width: 1.6) : null,
      ),
      child: Text(
        '${d.day}',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Colors.white.withValues(alpha: future || isToday ? 0.8 : 0.3),
        ),
      ),
    );
  }
}
