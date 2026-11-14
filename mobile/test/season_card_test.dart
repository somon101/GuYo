// The season in one card: season line, the three numbers, the quest of the day, and the taps.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/quest.dart';
import 'package:guyo_app/widgets/season_card.dart';

SeasonQuestOverview _overview({bool season = true}) => SeasonQuestOverview.fromJson({
      'season': season ? {'id': 1, 'name': 'Осень', 'icon_url': null, 'starts_at': '2026-11-03T00:00:00Z', 'ends_at': '2026-12-13T00:00:00Z'} : null,
      'days_left': season ? 30 : null,
      'days_total': season ? 40 : null,
      'points_today': 60,
      'total_points': 1240,
      'rank': null,
      'rank_position': 7,
      'quests_done_today': 3,
      'quests_total': 5,
      'points_per_learned_word': 5,
      'words_learned_today': 12,
      'quests': <Object>[],
    });

void main() {
  testWidgets('shows the season, the numbers and the quest of the day; each part is tappable', (tester) async {
    var points = 0, rating = 0, quests = 0, day = 0, header = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SeasonCard(
            overview: _overview(),
            onOpenHeader: () => header++,
            onOpenPoints: () => points++,
            onOpenRating: () => rating++,
            onOpenQuests: () => quests++,
            onQuestOfDay: () => day++,
          ),
        ),
      ),
    ));
    expect(find.text('Квесты сезона'), findsOneWidget);
    expect(find.text('Осень'), findsOneWidget);
    expect(find.text('+60'), findsOneWidget);
    expect(find.text('#7'), findsOneWidget);
    expect(find.text('3/5'), findsOneWidget);
    expect(find.text('Квест дня'), findsOneWidget);
    expect(find.text('Сегодня изучено: 12'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('season-header')));
    await tester.tap(find.byKey(const ValueKey('stat-points-today')));
    await tester.tap(find.byKey(const ValueKey('stat-rank')));
    await tester.tap(find.byKey(const ValueKey('stat-quests')));
    await tester.tap(find.byKey(const ValueKey('quest-of-day')));
    expect([header, points, rating, quests, day], [1, 1, 1, 1, 1]);
  });

  testWidgets('with no season it says so and still shows the numbers', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: SeasonCard(overview: _overview(season: false), large: true, onQuestOfDay: () {}))),
    ));
    expect(find.text('Сейчас нет активного сезона'), findsOneWidget);
    expect(find.text('+60'), findsOneWidget);
  });
}
