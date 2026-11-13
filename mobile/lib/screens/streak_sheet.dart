import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../l10n/l10n.dart';
import '../widgets/game_icons.dart';
import '../widgets/animated_fire.dart';
import '../services/session_cache.dart';
import '../theme/app_colors.dart';
import 'economy_screens.dart';
import 'stats_screen.dart' show UserStats;

const _fire = Color(0xFFFF8A3D);
const _ice = Color(0xFF4FB8EA);

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
  int _freezes = 0;
  int _mergeItems = 0;
  int _mergedDays = 0;
  int? _best; // the record, from the statistics

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
    _freezes = data.freezes;
    _mergeItems = data.mergeItems;
    _mergedDays = data.mergedDays;
  }

  Future<void> _load() async {
    final cachedStats = SessionCache.get<UserStats>('stats-7');
    if (cachedStats != null) _best = cachedStats.bestStreak;
    ApiClient.instance.fetchMyStats(7).then((st) {
      SessionCache.put('stats-7', st);
      if (mounted) setState(() => _best = st.bestStreak);
    }).catchError((_) {});
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
      message = tr('Начните серию сегодня — пройдите урок, практику или квест');
    } else if (activeToday) {
      message = tr('Вы в ударе! Возвращайтесь завтра, чтобы огонь не погас');
    } else {
      message = tr('Пройдите сегодня урок, практику или квест, чтобы огонь загорелся');
    }
    final best = _best == null ? '—' : '${_best! < _streak ? _streak : _best}';

    Widget cell(String value, String label) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20)),
            child: Column(children: [
              Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.primaryDark)),
              Text(label, style: TextStyle(fontSize: 12, color: AppColors.secondaryText)),
            ]),
          ),
        );

    return SafeArea(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(color: AppColors.canvas, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Stack(alignment: Alignment.center, children: [
              Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.progressTrack, borderRadius: BorderRadius.circular(99))),
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.close_rounded, size: 22, color: AppColors.secondaryText)),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(26)),
              child: Row(children: [
                Container(
                  width: 70,
                  height: 70,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.violetSurface, borderRadius: BorderRadius.circular(22)),
                  child: AnimatedFire(size: 52, lit: activeToday),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$_streak', style: TextStyle(fontSize: 56, height: 1, fontWeight: FontWeight.w800, letterSpacing: -2, color: AppColors.primaryDark)),
                    Text(streakDaysLabel(_streak), style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.secondaryText)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24)),
              child: _today != null ? _Week(today: _today!, active: _active, frozen: _frozen) : const SizedBox(height: 52),
            ),
            const SizedBox(height: 10),
            Row(children: [
              cell('$_streak', tr('сейчас')),
              const SizedBox(width: 8),
              cell(best, tr('рекорд')),
              const SizedBox(width: 8),
              cell('$_freezes', tr('заморозок')),
            ]),
            const SizedBox(height: 12),
            if (_frozen.isNotEmpty) ...[
              Text(tr('Пропущенный день заморожен — серия сохранена'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ice)),
              const SizedBox(height: 6),
            ],
            Text(message, textAlign: TextAlign.center, style: TextStyle(fontSize: 14.5, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.primaryDark)),
            const SizedBox(height: 6),
            Text(
              tr('Заморозка сама спасёт серию, если пропущено больше одного дня. Их дают в пропуске сезона'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.secondaryText),
            ),
            if (_mergedDays > 0 || _mergeItems > 0) ...[
              const SizedBox(height: 6),
              Text('${tr('Объединённых дней')}: $_mergedDays  •  ${tr('Объединителей')}: $_mergeItems', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.secondaryText)),
            ],
            const SizedBox(height: 14),
            GestureDetector(
              key: const ValueKey('streak-history'),
              onTap: () => openStreakHistory(context),
              child: Container(
                height: 50,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(99)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.calendar_month_rounded, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(tr('История'), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
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
  const _Week({
    required this.today,
    required this.active,
    this.frozen = const {},
  });

  @override
  Widget build(BuildContext context) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(monday.year, monday.month, monday.day + i),
    ];
    final letters = [
      tr('Пн'),
      tr('Вт'),
      tr('Ср'),
      tr('Чт'),
      tr('Пт'),
      tr('Сб'),
      tr('Вс'),
    ];
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
                    color: days[i] == today ? _fire : AppColors.secondaryText,
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

  Widget _band(bool visible) => Container(
    height: 28,
    color: visible ? _fire.withValues(alpha: 0.16) : Colors.transparent,
  );

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
        child: const Padding(padding: EdgeInsets.all(3), child: FreezeIcon(size: 24)),
      );
    }
    if (active.contains(d)) {
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _fire,
          border: isToday ? Border.all(color: AppColors.surface, width: 2) : null,
          boxShadow: isToday ? [const BoxShadow(color: _fire, spreadRadius: 2)] : null,
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
        color: AppColors.violetSurface,
        border: isToday ? Border.all(color: _fire, width: 1.6) : null,
      ),
      child: Text(
        '${d.day}',
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: future || isToday ? AppColors.primaryDark : AppColors.secondaryText,
        ),
      ),
    );
  }
}
