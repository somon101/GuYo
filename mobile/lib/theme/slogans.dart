import 'dart:math';

/// Where the greeting's one-line slogan on Главная comes from.
///
/// Today it is a fixed local list. The point of the interface is that
/// swapping in an admin-managed set later -- a `GET /slogans` call, a
/// per-language list, a seasonal one -- means writing a new
/// implementation and handing it to the greeting, with no change to the
/// widget that renders it.
abstract class SloganSource {
  /// The line to show right now. Must never return null or empty: the
  /// greeting always has a second line.
  String current();
}

/// The built-in slogans, picked deterministically by the day so the line
/// stays put while the user is using the app (a random pick per rebuild
/// would make it flicker on every setState) but still varies day to day.
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
  String current() {
    final day = _now();
    // Day-of-epoch, so the index advances exactly once per calendar day.
    final index = (day.difference(DateTime(2020)).inDays).abs() % slogans.length;
    return slogans[index];
  }
}

/// A source that always returns the same line -- used by tests that need
/// the greeting's second line to be predictable.
class FixedSloganSource implements SloganSource {
  final String slogan;
  const FixedSloganSource(this.slogan);

  @override
  String current() => slogan;
}

/// Picks one of [LocalSloganSource.slogans] at random. Not used by the app
/// itself; kept as the shape a future server-driven source would take.
class RandomSloganSource implements SloganSource {
  final Random _random;
  RandomSloganSource([Random? random]) : _random = random ?? Random();

  @override
  String current() => LocalSloganSource.slogans[_random.nextInt(LocalSloganSource.slogans.length)];
}
