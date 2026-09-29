import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/models/user_profile.dart';
import 'package:guyo_app/screens/achievements_screen.dart';

UserAchievement _a(int id, {String? title, String? description, int? goal, bool earned = false, int? current}) {
  return UserAchievement.fromJson({
    'id': id,
    'title': title,
    'description': description,
    'icon_url': null,
    'color': '#5862DD',
    'condition_type': title == null ? null : 'words_learned',
    'condition_value': goal,
    'earned': earned,
    'earned_at': earned ? '2026-09-21T10:00:00Z' : null,
    'current_value': current,
  });
}

void main() {
  final achievements = [
    _a(1, title: 'Первые слова', description: 'Выучить 5 слов', goal: 5, earned: true),
    _a(2, title: 'Очень длинное название достижения на две строки', description: 'Выучить сто слов в разных темах и не сдаваться никогда', goal: 100, current: 42),
    _a(3), // hidden
    _a(4, title: 'Серия', description: '7 дней подряд', goal: 7, current: 3),
  ];

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: AchievementsScreen(achievements: achievements)));
    await tester.pump();
  }

  testWidgets('shows a three-per-row badge wall with goals and a summary', (tester) async {
    await pump(tester, const Size(360, 800));
    expect(find.text('Получено 1 из 4'), findsOneWidget);
    expect(find.text('Первые слова'), findsOneWidget);
    expect(find.text('Скрытое'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    // Three per row: the first three badges share a row.
    final y1 = tester.getTopLeft(find.byKey(const ValueKey('achievement-1'))).dy;
    final y3 = tester.getTopLeft(find.byKey(const ValueKey('achievement-3'))).dy;
    final y4 = tester.getTopLeft(find.byKey(const ValueKey('achievement-4'))).dy;
    expect(y1, y3);
    expect(y4, greaterThan(y1));
  });

  testWidgets('tapping a badge in progress shows its progress', (tester) async {
    await pump(tester, const Size(360, 800));
    await tester.tap(find.byKey(const ValueKey('achievement-2')));
    await tester.pumpAndSettle();
    expect(find.text('42 из 100'), findsOneWidget);
  });

  testWidgets('tapping an earned badge shows when it was earned', (tester) async {
    await pump(tester, const Size(360, 800));
    await tester.tap(find.byKey(const ValueKey('achievement-1')));
    await tester.pumpAndSettle();
    expect(find.text('Получено 21 сентября 2026'), findsOneWidget);
  });

  testWidgets('fits a narrow phone without overflow', (tester) async {
    await pump(tester, const Size(320, 640));
    expect(tester.takeException(), isNull);
  });
}
