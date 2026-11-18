import 'dart:async';

import '../api/api_client.dart';
import '../models/chest.dart';
import '../models/lesson.dart';
import '../models/season_pass.dart';
import '../models/user_rating.dart';
import '../services/chest_queue.dart';
import '../services/streak_state.dart';
import 'lesson_results_flow.dart';

/// The numbers of the end of a lesson from the real server. Everything is fetched in parallel with a
/// short wait, so the results never hold the player back: what did not arrive in time is left out
/// (a block that cannot be shown honestly is hidden, never made up).
class AppResultsSource extends ResultsSource {
  static const Duration _wait = Duration(milliseconds: 1800);

  /// The chest of the day, once handed out into the bank.
  ChestBank? _bank;
  String _chestKey = 'wood';

  @override
  String get dailyChestKey => _chestKey;

  Future<T?> _safe<T>(Future<T?> f) => f.timeout(_wait, onTimeout: () => null).catchError((Object _) => null);

  @override
  Future<ResultsOutcome> outcome(Lesson lesson, LessonPassStats? stats) async {
    final api = ApiClient.instance;
    // What the app last knew BEFORE this lesson counted (the screens keep these on the phone).
    final goalBefore = api.cachedDailyGoal();
    final passBefore = api.cachedSeasonPass();
    final ratingBefore = api.cachedMyRating();

    final learned = lesson.words.where((w) => w.isLearned).length;
    final total = lesson.words.length;
    final passed = lesson.isCompleted || (total > 0 && learned == total);

    final got = await Future.wait<Object?>([
      _safe(api.fetchDailyGoal()),
      _safe(api.fetchSeasonPass()),
      _safe<UserRating>(api.fetchMyRating()),
      _safe(api.fetchChests()),
    ]);
    final goal = got[0] as dynamic;
    final pass = got[1] as SeasonPass?;
    final rating = got[2] as UserRating?;
    final bank = got[3] as ChestBank?;
    _bank = bank;
    _chestKey = bank?.daily.chestKey ?? 'wood';

    final goalOf = (goal?.goal as int?) ?? goalBefore?.goal ?? 0;
    final goalTo = ((goal?.done as int?) ?? goalBefore?.done ?? 0).clamp(0, goalOf == 0 ? 1 << 30 : goalOf);
    final goalFrom = (goalTo - (stats?.newlyLearned ?? 0)).clamp(0, goalTo);

    int sizeOf(SeasonPass p) => (p.xpForNext ?? (p.xpIntoLevel > 0 ? p.xpIntoLevel : 1));
    final hasPass = pass != null;
    final levelTo = pass?.level ?? 0;
    final xpTo = pass?.xpIntoLevel ?? 0;
    final sizeTo = pass == null ? 1 : sizeOf(pass);
    final from = passBefore ?? pass;
    final levelFrom = from?.level ?? 0;
    final xpFrom = from?.xpIntoLevel ?? 0;
    final sizeFrom = from == null ? 1 : sizeOf(from);

    final rankTo = rating?.rankPosition ?? 0;
    var rankFrom = ratingBefore?.rankPosition ?? rankTo;
    if (rankFrom == 0) rankFrom = rankTo;
    // «Вы обошли …»: the person now just below the player, when the lesson moved the player up.
    var rival = '';
    if (passed && rankTo > 0 && rankTo < rankFrom) {
      final board = await _safe<Leaderboard>(api.fetchMyRankLeaderboard());
      for (final e in board?.entries ?? const <LeaderboardEntry>[]) {
        if (e.position == rankTo + 1 && !e.isMe) rival = e.login;
      }
    }

    final streak = lastLessonStreak;
    final grew = passed && (streak?.litNow ?? false);
    final chestReady = passed && bank != null && bank.daily.enabled && bank.daily.available && !bank.daily.claimed;

    return ResultsOutcome(
      number: lesson.number,
      left: total - learned,
      passed: passed,
      showStreak: grew,
      showChest: chestReady,
      total: stats?.scoreGained ?? 0,
      pLesson: stats?.pointsLesson,
      pAccuracy: stats?.pointsAccuracy,
      pSpeed: stats?.pointsSpeed,
      afterLesson: stats?.pointsAfter,
      goalFrom: goalFrom,
      goalTo: goalTo,
      goalOf: goalOf,
      hasPass: hasPass,
      levelFrom: levelFrom,
      levelTo: levelTo,
      xpFrom: xpFrom,
      xpTo: xpTo,
      sizeFrom: sizeFrom,
      sizeTo: sizeTo,
      rankFrom: rankFrom,
      rankTo: rankTo,
      rival: rival,
    );
  }

  @override
  StreakView streak() {
    final s = lastLessonStreak;
    final days = s?.days ?? streakDays.value ?? 1;
    return StreakView(before: days - 1, grew: true);
  }

  @override
  Future<DailyPrize?> openDailyChest() async {
    final api = ApiClient.instance;
    final known = {for (final c in _bank?.chests ?? const <BankChest>[]) c.id};
    final bank = await api.claimDailyChest();
    BankChest? chest;
    for (final c in bank.chests) {
      if (!known.contains(c.id) && c.source == 'daily') chest = c;
    }
    chest ??= bank.chests.where((c) => c.source == 'daily').lastOrNull;
    if (chest == null) return null;
    final kind = chest.prizeKind;
    final amount = chest.prizeAmount;
    if (kind != null && amount != null) {
      // The prize is sealed on the chest: shown at once, the server is told afterwards.
      ChestQueue.opened([(chest.id, kind, amount)]);
      return DailyPrize(kind, amount);
    }
    final (prize, _) = await api.openChest(chest.id);
    return DailyPrize(prize.kind, prize.amount, doubled: prize.doubled);
  }
}
