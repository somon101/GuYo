// The demo backend's answers must parse with the app's own models.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/api/api_client.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);

  test('every main-screen answer parses', () async {
    await http.runWithClient(() async {
      final api = ApiClient.instance;
      await api.login('demo', 'demo'); // any login gets in
      expect(await api.token, 'demo');
      expect((await api.fetchMyProfile()).login, 'Demo');
      expect(await api.fetchDictionaries(), isNotEmpty);
      expect((await api.fetchDailyGoal())?.goal, 20);
      expect((await api.fetchChests())?.chests.length, 6);
      expect(await api.fetchBoosters(), isNotNull);
      expect((await api.fetchDuels())?.current, isNotNull);
      expect((await api.fetchSeasonPass())?.level, 4);
      expect((await api.fetchSeasonQuestOverview(1)).questsTotal, 5);
      expect((await api.fetchPremiumStatus()).isPremium, true);
      expect((await api.fetchMyStreak()).currentStreakDays, 13);
      expect((await api.fetchReviewDue(1)).$1, 12);
      expect(await api.fetchLanguages(), isNotEmpty);
      expect((await api.fetchMyRating()).totalPoints, 1240);
      expect(await api.fetchMyAchievements(), hasLength(5));
      expect((await api.fetchMyRankLeaderboard()).entries, isNotEmpty);
      expect(await api.fetchWordLevels(), hasLength(4));
      expect((await api.fetchMyStats(7)).accuracy, 87);
      final shop = await api.buyShopProduct(1);
      expect(shop['diamonds'], 190);
      expect(shop['streak_freezes'], 2);
      expect((await api.fetchStreakHistory(DateTime.now()))['days'], isNotEmpty);
      expect(await api.fetchWords(1), hasLength(20));
      expect(await api.fetchLearnedWords(1, includeInProgress: true), hasLength(14));
      expect(await api.fetchLearnedCategories(1), isNotEmpty);
      expect(await api.fetchAvailablePhrases(2), hasLength(3));
      expect((await api.fetchStatusOptions()).premium, true);
    }, demoClient);
  });

  test('a lesson can be made, played and finished', () async {
    await http.runWithClient(() async {
      final api = ApiClient.instance;
      expect(await api.fetchLessons(1), hasLength(2));
      final cand = await api.fetchLessonCandidateWords(1);
      expect(cand.words, isNotEmpty);
      final lesson = await api.createLesson(dictionaryId: 1, wordIds: cand.words.take(3).map((w) => w.id).toList());
      expect(lesson.words, hasLength(3));
      await api.startLessonPass(lesson.id);
      expect((await api.fetchLessonTrueOrFalseRound(lesson.id)).items, hasLength(3));
      expect(await api.fetchLessonMatchingWords(lesson.id), hasLength(3));
      expect((await api.fetchLessonBuildWordRound(lesson.id)).items, hasLength(3));
      expect((await api.fetchLessonSpeakingWordRound(lesson.id)).items, hasLength(3));
      expect((await api.fetchLessonListenWordRound(lesson.id)).items, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final r = await api.submitLessonAnswer(lesson.id, 'true_or_false', wordId: lesson.words.first.wordId, isCorrect: true);
        if (i == 2) expect(r.isLearned, true);
      }
      final (done, stats) = await api.finishLessonPass(lesson.id);
      expect(done.isCompleted, true);
      expect(stats?.totalAnswers, 3);
      expect((await api.fetchDailyGoal())?.done, 13);
      expect((await api.fetchActiveLesson(1)), isNull);
    }, demoClient);
  });

  test('a call made later from a timer still gets the demo answer', () async {
    await http.runWithClient(() async {
      // Work scheduled inside the zone keeps the fake client (as taps and timers do in the demo app).
      final done = Future<void>.delayed(const Duration(milliseconds: 10), () async {
        expect((await ApiClient.instance.fetchMyProfile()).login, 'Demo');
      });
      await done;
    }, demoClient);
  });
}
