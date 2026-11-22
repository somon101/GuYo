// The «Подарки» tab (variant Б): the four chests on top, the chosen one large with its «Открыть ×N»,
// what waits below, and the number for the red badge of the bottom bar.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:guyo_app/screens/gifts_screen.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  final bank = {
    'types': [
      {'key': 'wood', 'name': 'Деревянный', 'color': '#8B5A2B'},
      {'key': 'silver', 'name': 'Серебряный', 'color': '#B0B8C4'},
      {'key': 'purple', 'name': 'Фиолетовый', 'color': '#7B3FE4'},
      {'key': 'gold', 'name': 'Золотой', 'color': '#E7B73C'},
    ],
    'chests': [for (var i = 1; i <= 6; i++) {'id': i, 'chest_key': 'wood', 'source': 'lesson', 'prize_kind': 'diamonds', 'prize_amount': 5}, {'id': 7, 'chest_key': 'silver', 'source': 'lesson', 'prize_kind': 'diamonds', 'prize_amount': 9}],
    'daily': {'enabled': true, 'available': true, 'claimed': false, 'chest_key': 'wood', 'conditions': 'Пройдите урок'},
  };
  final inbox = {
    'items': [
      {'id': 1, 'title': 'Подарок от GuYo', 'body': 'Спасибо, что вы с нами', 'source': 'manual', 'is_read': false, 'read_at': null, 'created_at': '2026-11-20T10:00:00Z', 'action': 'claim_gift:9', 'payload': [{'type': 'diamonds', 'amount': 50}]},
      {'id': 2, 'title': 'Новость', 'body': 'Просто сообщение', 'source': 'manual', 'is_read': false, 'read_at': null, 'created_at': '2026-11-20T10:00:00Z'},
    ],
    'unread_count': 2,
  };
  final client = MockClient((req) async {
    final path = req.url.path;
    http.Response ok(Object o) => http.Response(_json(o), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    if (path == '/chests') return ok(bank);
    if (path == '/notifications') return ok(inbox);
    return http.Response('{}', 404);
  });

  testWidgets('chests on top, the chosen one large, the waiting gifts below, the number for the badge', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: GiftsScreen())));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Подарки'), findsWidgets);
      expect(find.byKey(const ValueKey('gift-hero-wood')), findsOneWidget); // the first kind that is held
      expect(find.text('В запасе: 6'), findsOneWidget);
      expect(find.byKey(const ValueKey('gift-mode-wood-5')), findsOneWidget); // 6 chests: ×5 offered, ×10 not
      expect(find.byKey(const ValueKey('gift-mode-wood-10')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('gift-mode-wood-5')));
      await tester.pump();
      expect(find.text('ОТКРЫТЬ ×5'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gift-kind-gold')));
      await tester.pump();
      expect(find.byKey(const ValueKey('gift-hero-gold')), findsOneWidget);
      expect(find.text('Пока таких сундуков нет'), findsWidgets);
      expect(find.byKey(const ValueKey('gift-open-gold')), findsNothing);

      // What waits: the chest of the day and the gift; a plain message is not a gift.
      expect(find.text('Ждут вас'), findsOneWidget);
      expect(find.byKey(const ValueKey('gift-daily')), findsOneWidget);
      expect(find.byKey(const ValueKey('gift-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('gift-2')), findsNothing);
      expect(giftsWaiting.value, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    }, () => client);
  });
}

String _json(Object o) => jsonEncode(o);
