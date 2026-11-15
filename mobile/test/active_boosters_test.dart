// The doublers running in the top bar: rings with the time left, the alarm under 5 minutes, the sheet.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:guyo_app/models/chest.dart';
import 'package:guyo_app/theme/app_colors.dart';
import 'package:guyo_app/widgets/active_boosters_button.dart';
import 'package:http/http.dart' as http;

BoosterState _state({Duration? chest, Duration? xp}) {
  Map<String, dynamic> kind(Duration? left) => {
        'items': <Object>[],
        'active_until': left == null ? null : DateTime.now().add(left).toUtc().toIso8601String(),
      };
  return BoosterState.fromJson({
    'items': <Object>[],
    'active_until': chest == null ? null : DateTime.now().add(chest).toUtc().toIso8601String(),
    'kinds': {'rating': kind(null), 'xp': kind(xp)},
  });
}

Future<void> _pump(WidgetTester tester, BoosterState state) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: ActiveBoostersButton(initial: state)))));
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  }

  testWidgets('nothing runs: nothing is drawn', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _state());
      expect(find.byKey(const ValueKey('boosters-button')), findsNothing);
      await finish(tester);
    }, demoClient);
  });

  testWidgets('two kinds run side by side, each with its own time', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _state(chest: const Duration(minutes: 12, seconds: 40), xp: const Duration(minutes: 47)));
      expect(find.byKey(const ValueKey('booster-time-chest')), findsOneWidget);
      expect(find.byKey(const ValueKey('booster-time-xp')), findsOneWidget);
      expect(find.byKey(const ValueKey('booster-time-rating')), findsNothing);
      expect(tester.widget<Text>(find.byKey(const ValueKey('booster-time-chest'))).data, matches(RegExp(r'^12:(39|40)$')));
      await finish(tester);
    }, demoClient);
  });

  testWidgets('under 5 minutes the time turns red; above, it does not', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _state(chest: const Duration(minutes: 4, seconds: 12), xp: const Duration(minutes: 47)));
      Color colorOf(String key) => tester.widget<Text>(find.byKey(ValueKey(key))).style!.color!;
      expect(colorOf('booster-time-chest').r, AppColors.danger.r);
      expect(colorOf('booster-time-xp'), AppColors.primaryDark);
      await finish(tester);
    }, demoClient);
  });

  testWidgets('a tap opens «Идут сейчас» with every running doubler', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _state(chest: const Duration(minutes: 12), xp: const Duration(minutes: 47)));
      await tester.tap(find.byKey(const ValueKey('boosters-button')));
      await tester.pumpAndSettle();
      expect(find.text('Идут сейчас'), findsWidgets);
      expect(find.text('Удвоитель сундуков'), findsOneWidget);
      expect(find.text('Удвоитель пропуска'), findsOneWidget);
      expect(find.byKey(const ValueKey('sheet-time-chest')), findsOneWidget);
      expect(find.byKey(const ValueKey('boosters-stock')), findsOneWidget);
      await finish(tester);
    }, demoClient);
  });
}
