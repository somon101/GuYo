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
      expect((await api.fetchStatusOptions()).premium, true);
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
