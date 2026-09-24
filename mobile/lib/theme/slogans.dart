import 'dart:math';

/// Where the greeting's one-line slogan on Главная comes from.
///
/// An interface, not a list, so the greeting never knows where its line
/// came from. Today [BackendSloganSource] asks the admin-curated set and
/// falls back to [LocalSloganSource]; a per-language or seasonal source
/// later is a new implementation handed to the greeting, with no change
/// to the widget that renders it.
abstract class SloganSource {
  /// The line to show today. Must never return null or empty: the
  /// greeting always has a second row.
  Future<String> today();
}

/// The real source: whatever an admin curated, with the built-in list
/// underneath it.
///
/// The backend is what actually picks and pins a slogan for the day (see
/// backend/app/slogans/), so asking twice on the same day returns the same
/// line and a new day brings a new one. This falls back when the admin has
/// no enabled slogans OR the call fails -- a greeting with a missing
/// second row would look broken, and there is a perfectly good local list
/// to use instead.
class BackendSloganSource implements SloganSource {
  final Future<String?> Function() fetch;
  final SloganSource fallback;

  const BackendSloganSource({required this.fetch, this.fallback = const LocalSloganSource()});

  @override
  Future<String> today() async {
    try {
      final text = await fetch();
      if (text != null && text.trim().isNotEmpty) return text.trim();
    } catch (_) {
      // Fall through -- see the class note.
    }
    return fallback.today();
  }
}

/// The built-in slogans -- the floor under [BackendSloganSource], used
/// when no admin-curated line is available.
///
/// Picked deterministically by the day so the line stays put while the
/// user is using the app (a random pick per rebuild would make it flicker
/// on every setState) but still varies day to day.
class LocalSloganSource implements SloganSource {
  static const List<String> slogans = [
    'Давай учиться сегодня!',
    'Пара слов в день — и язык твой.',
    'Сегодня отличный день для нового слова.',
    'Продолжай — у тебя получается.',
    'Немного практики каждый день.',
  ];

  final DateTime Function() _now;

  const LocalSloganSource({DateTime Function()? now}) : _now = now ?? DateTime.now;

  @override
  Future<String> today() async {
    final day = _now();
    // Day-of-epoch, so the index advances exactly once per calendar day.
    final index = (day.difference(DateTime(2020)).inDays).abs() % slogans.length;
    return slogans[index];
  }
}

/// A source that always returns the same line -- used by tests that need
/// the greeting's second row to be predictable.
class FixedSloganSource implements SloganSource {
  final String slogan;
  const FixedSloganSource(this.slogan);

  @override
  Future<String> today() async => slogan;
}

/// Picks one of [LocalSloganSource.slogans] at random. Not used by the app
/// itself; kept as the shape a future server-driven source would take.
class RandomSloganSource implements SloganSource {
  final Random _random;
  RandomSloganSource([Random? random]) : _random = random ?? Random();

  @override
  Future<String> today() async => LocalSloganSource.slogans[_random.nextInt(LocalSloganSource.slogans.length)];
}
