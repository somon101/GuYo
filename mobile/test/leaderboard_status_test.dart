// Leaderboard statuses: the emoji badge on an avatar, the phrase bubble on
// tap, your own row opening the picker, and the picker saving a choice.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:guyo_app/models/status.dart';
import 'package:guyo_app/models/user_rating.dart';
import 'package:guyo_app/screens/rating_screen.dart';
import 'package:guyo_app/screens/status_picker_sheet.dart';
import 'package:guyo_app/widgets/leaderboard_status.dart';

LeaderboardEntry _entry({bool me = false, String? emoji, String? text}) => LeaderboardEntry.fromJson({
      'position': 5,
      'user_id': me ? 1 : 2,
      'login': me ? 'me' : 'firdavs',
      'avatar_url': null,
      'total_points': 1795,
      'rank': null,
      'is_me': me,
      'status_emoji_url': emoji,
      'status_text': text,
    });

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 380, child: child))));

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('a status shows as a badge on the avatar and its phrase on tap', (tester) async {
    await tester.pumpWidget(_host(LeaderboardRow(
      entry: _entry(emoji: '/media/status/emojis/fire.png', text: 'Я буду первым!'),
      accentColor: Colors.blue,
    )));
    expect(find.byType(StatusEmojiBadge), findsOneWidget);
    expect(find.byType(StatusPhraseHint), findsOneWidget);
    expect(find.text('Я буду первым!'), findsNothing, reason: 'compact: only the badge until tapped');

    await tester.tap(find.text('firdavs'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Я буду первым!'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('no status: no badge, nothing on tap', (tester) async {
    await tester.pumpWidget(_host(LeaderboardRow(entry: _entry(), accentColor: Colors.blue)));
    expect(find.byType(StatusEmojiBadge), findsNothing);
    expect(find.byType(StatusPhraseHint), findsNothing);
  });

  testWidgets('your own row opens the picker', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_host(LeaderboardRow(
      entry: _entry(me: true),
      accentColor: Colors.blue,
      onEditMyStatus: () => opened++,
    )));
    await tester.tap(find.text('me'));
    expect(opened, 1);
  });

  testWidgets('the picker saves one emoji and one phrase', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? sent;
    final client = MockClient((req) async {
      if (req.method == 'GET') {
        return http.Response.bytes(
            utf8.encode(jsonEncode({
              'emojis': [
                {'id': 1, 'name': 'Огонь', 'image_url': '/media/a.png'},
                {'id': 2, 'name': 'Корона', 'image_url': '/media/b.png'},
              ],
              'phrases': [
                {'id': 7, 'text': 'Я буду первым!'},
                {'id': 8, 'text': 'Меня не догнать'},
              ],
              'mine': {'emoji_id': null, 'emoji_url': null, 'phrase_id': null, 'text': null},
            })),
            200);
      }
      sent = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response.bytes(
          utf8.encode(jsonEncode({'emoji_id': 2, 'emoji_url': '/media/b.png', 'phrase_id': 8, 'text': 'Меня не догнать'})),
          200);
    });

    MyStatus? result;
    await http.runWithClient(() async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () async => result = await showStatusPicker(context), child: const Text('open')),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Статус не выбран'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('status-emoji-2')));
      await tester.tap(find.byKey(const ValueKey('status-phrase-8')));
      await tester.pump();
      expect(find.text('Меня не догнать'), findsNWidgets(2), reason: 'the preview shows the choice');

      await tester.tap(find.byKey(const ValueKey('status-save')));
      await tester.pumpAndSettle();
    }, () => client);
    expect(sent, {'emoji_id': 2, 'phrase_id': 8});
    expect(result?.text, 'Меня не догнать');
  });
}
