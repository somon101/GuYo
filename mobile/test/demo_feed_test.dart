// The demo build's «Лента»: likes and ready-made comments, who liked, a person's profile, friend
// requests, and teams (join an open one, ask a closed one, make one), plus the fake server's teams.
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:guyo_app/api/api_client.dart';
import 'package:guyo_app/demo/demo_feed.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:guyo_app/demo/demo_social.dart';

DemoSocial get s => DemoSocial.instance;

/// Puts the demo's people and teams back as they start.
void _reset() {
  s.friends
    ..clear()
    ..addAll({101, 102});
  s.friendRequests.clear();
  s.teamRequests.clear();
  s.hiddenCards.clear();
  for (final c in s.cards) {
    c.liked = false;
    c.myComment = null;
  }
  for (final t in s.teams.values.toList()) {
    t.members.remove(DemoSocial.me);
    if (t.members.isEmpty) s.teams.remove(t.id);
  }
}

Future<void> _open(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pump();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    _reset();
  });

  testWidgets('a like and a ready-made comment', (tester) async {
    await _open(tester, DemoFeedTab(goTo: (_) {}));
    expect(find.text('ДРУЗЬЯ'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('like-1')));
    await tester.pump();
    expect(s.cards.first.liked, isTrue);
    expect(find.text('21'), findsOneWidget); // 20 + yours

    await tester.tap(find.byKey(const ValueKey('comment-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('phrase-Огонь!')));
    await tester.pumpAndSettle();
    expect(s.cards.first.myComment, 'Огонь!');
    expect(find.textContaining('Огонь!'), findsWidgets);
  });

  testWidgets('who liked: friends marked, the green add sends a request, a second tap takes it back', (tester) async {
    await _open(tester, DemoFeedTab(goTo: (_) {}));
    await tester.tap(find.byKey(const ValueKey('likers-1')));
    await tester.pumpAndSettle();
    expect(find.text('Друг'), findsWidgets); // Madina is a friend
    await tester.tap(find.byKey(const ValueKey('relation-103')));
    await tester.pump();
    expect(s.friendRequests, contains(103));
    final icon = tester.widget<Icon>(find.descendant(of: find.byKey(const ValueKey('relation-103')), matching: find.byType(Icon)));
    expect(icon.icon, Icons.schedule_rounded);
    await tester.tap(find.byKey(const ValueKey('relation-103')));
    await tester.pump();
    expect(s.friendRequests, isNot(contains(103)));
  });

  testWidgets('the «Рейтинг» switch is at the top of the tab', (tester) async {
    await _open(tester, DemoFeedTab(goTo: (_) {}));
    expect(find.byKey(const ValueKey('feed-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('feed-switch-1')), findsOneWidget);
  });

  testWidgets('a person: no friend → the green add; a friend → the duel and the red remove', (tester) async {
    await _open(tester, const DemoPersonScreen(103));
    expect(find.text('Rustam'), findsOneWidget);
    expect(find.text('Очки за неделю'), findsOneWidget);
    expect(find.text('Достижения'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('person-add')));
    await tester.pump();
    expect(find.text('Запрос отправлен'), findsOneWidget);

    await _open(tester, const DemoPersonScreen(102));
    expect(find.byKey(const ValueKey('person-duel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('person-unfriend')));
    await tester.pump();
    expect(s.isFriend(102), isFalse);
    expect(find.byKey(const ValueKey('person-add')), findsOneWidget);
  });

  testWidgets('a closed team takes a request (the owner decides); an open one is joined at once', (tester) async {
    await _open(tester, const DemoMyTeamCard());
    expect(find.text('Играйте вместе'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('my-team-find')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('teams-list-2'))); // «Ночные совы», by request
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-request')));
    await tester.pump();
    expect(s.teamRequests, contains(2));
    expect(find.text('Запрос отправлен'), findsOneWidget);
    Navigator.of(tester.element(find.byKey(const ValueKey('team-request')))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('teams-list-1'))); // «Словарный взвод», open
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-join')));
    await tester.pump();
    expect(s.myTeam?.id, 1);
    expect(find.text('Это ваша команда.'), findsOneWidget);
  });

  testWidgets('a new team from the profile, then leaving it', (tester) async {
    await _open(tester, const DemoMyTeamCard());
    await tester.tap(find.byKey(const ValueKey('my-team-create')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('team-name')), 'Мои львы');
    await tester.tap(find.byKey(const ValueKey('team-open')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('team-create')));
    await tester.pumpAndSettle();
    expect(s.myTeam?.name, 'Мои львы');
    expect(s.myTeam?.isOpen, isFalse);
    expect(find.text('Команда «Мои львы»'), findsOneWidget);
    s.leave();
    await tester.pump();
    expect(find.text('Играйте вместе'), findsOneWidget);
  });

  testWidgets('leaving a team: a card in the middle says so, with the ways on (find, create), not a grey line', (tester) async {
    await _open(tester, const DemoMyTeamCard());
    await tester.tap(find.byKey(const ValueKey('my-team-find')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('teams-list-1'))); // «Словарный взвод», open
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('team-join')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('team-leave')));
    await tester.pumpAndSettle();
    expect(s.myTeam, isNull);
    expect(find.byKey(const ValueKey('team-gone')), findsOneWidget);
    expect(find.text('Вы вышли из команды «Словарный взвод»'), findsOneWidget);
    expect(find.byKey(const ValueKey('team-gone-create')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('team-gone-find')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-gone')), findsNothing, reason: 'the card closes');
    expect(find.byKey(const ValueKey('teams-list-1')), findsWidgets, reason: 'and the list of teams opens');
  });

  testWidgets('a team the creator closed while its sheet was open: the same card says it is gone', (tester) async {
    await _open(tester, const DemoMyTeamCard());
    await tester.tap(find.byKey(const ValueKey('my-team-find')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('teams-list-2')));
    await tester.pumpAndSettle();
    s.teams.remove(2);
    s.touch();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('team-gone')), findsOneWidget);
    expect(find.textContaining('больше нет'), findsOneWidget);
    expect(find.textContaining('Создатель закрыл её'), findsOneWidget);
  });

  test('the fake server answers for teams the way the app reads them', () async {
    await http.runWithClient(() async {
      final api = ApiClient.instance;
      expect((await api.fetchMyTeam())?.team, isNull);
      final open = await api.fetchOpenTeams();
      expect(open.map((t) => t.name), containsAll(['Словарный взвод']));
      final joined = await api.joinTeam(1);
      expect(joined.team?.name, 'Словарный взвод');
      expect(joined.team?.members.where((m) => m.isOwner).single.login, 'Aziz');
      await expectLater(api.joinTeam(4), throwsA(anything)); // already in a team
      final left = await api.leaveTeam();
      expect(left.team, isNull);
      final made = await api.createTeam('Наша', isOpen: true);
      expect(made.team?.isOwner, isTrue);
      await api.leaveTeam();
    }, demoClient);
  });
}
