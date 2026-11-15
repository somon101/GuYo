// «Подарки» on Главная, the pass button in the top bar and the duel entry in «Уроки».

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:guyo_app/widgets/duel_card.dart';
import 'package:guyo_app/widgets/home_tiles.dart';
import 'package:guyo_app/widgets/pass_header_button.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);

  testWidgets('«Подарки» opens on tap; a waiting chest of the day shows «Забрать»', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HomeGiftsCard(sub: 'Мои сундуки', count: 3, ready: false, onTap: () => taps++)),
    ));
    expect(find.text('Подарки'), findsOneWidget);
    expect(find.byKey(const ValueKey('tile-claim')), findsNothing);
    await tester.tap(find.text('Подарки'));
    expect(taps, 1);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: HomeGiftsCard(sub: 'Сундук дня ждёт', count: 3, plus: '+1', ready: true, onTap: () {})),
    ));
    expect(find.byKey(const ValueKey('tile-claim')), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
  });

  testWidgets('the pass button shows the level and the energy and the rewards waiting', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Center(child: PassHeaderButton(fallback: Text('GuYo'))))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Пропуск'), findsOneWidget);
      expect(find.byKey(const ValueKey('pass-button-sub')), findsOneWidget);
      expect(find.text('GuYo'), findsNothing);
      await tester.pump(const Duration(seconds: 30)); // lets the request timeouts run out
    }, demoClient);
  });

  testWidgets('the duel entry in «Уроки» is one compact card', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SingleChildScrollView(child: DuelEntryCard()))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('duel-entry')), findsOneWidget);
      expect(find.text('Дуэль недели'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    }, demoClient);
  });
}
