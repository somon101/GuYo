// The doublers in the top bar of «Уроки»: always three, with the tickets held, rings while running,
// pale with nothing, the alarm under 5 minutes, and the sheet where a ticket is switched on.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:guyo_app/models/chest.dart';
import 'package:guyo_app/theme/app_colors.dart';
import 'package:guyo_app/widgets/active_boosters_button.dart';
import 'package:http/http.dart' as http;

BoosterState _state({Duration? chest, Duration? xp, int chestTickets = 0, int ratingTickets = 0}) {
  Map<String, dynamic> kind(Duration? left, int tickets) => {
        'items': tickets == 0 ? <Object>[] : [{'minutes': 30, 'qty': tickets}],
        'active_until': left == null ? null : DateTime.now().add(left).toUtc().toIso8601String(),
      };
  final c = kind(chest, chestTickets);
  return BoosterState.fromJson({...c, 'kinds': {'rating': kind(null, ratingTickets), 'xp': kind(xp, 0)}});
}

Future<void> _pump(WidgetTester tester, BoosterState state) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: BoostersBar(initial: state)))));
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

  testWidgets('all three kinds are always there; a count shows only for tickets held, a kind with none is pale', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _state(chestTickets: 2));
      expect(find.byKey(const ValueKey('booster-chest')), findsOneWidget);
      expect(find.byKey(const ValueKey('booster-rating')), findsOneWidget);
      expect(find.byKey(const ValueKey('booster-xp')), findsOneWidget);
      expect(find.byKey(const ValueKey('booster-count-chest')), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.byKey(const ValueKey('booster-count-rating')), findsNothing);
      // The kind with nothing is drawn at 30% opacity.
      final pale = find.descendant(of: find.byKey(const ValueKey('booster-xp')), matching: find.byType(Opacity));
      expect(tester.widget<Opacity>(pale.first).opacity, closeTo(0.3, 0.001));
      await finish(tester);
    }, demoClient);
  });

  testWidgets('a running kind shows its time instead of a count; two kinds run side by side', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _state(chest: const Duration(minutes: 12, seconds: 40), xp: const Duration(minutes: 47), chestTickets: 2));
      expect(tester.widget<Text>(find.byKey(const ValueKey('booster-time-chest'))).data, matches(RegExp(r'^12:(39|40)$')));
      expect(find.byKey(const ValueKey('booster-time-xp')), findsOneWidget);
      expect(find.byKey(const ValueKey('booster-time-rating')), findsNothing);
      expect(find.byKey(const ValueKey('booster-count-chest')), findsNothing);
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

  testWidgets('a tap opens the kind sheet with its tickets and a switch-on; none held says so', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _state(chestTickets: 2));
      await tester.tap(find.byKey(const ValueKey('booster-chest')));
      await tester.pumpAndSettle();
      expect(find.text('Удвоитель сундуков'), findsOneWidget);
      expect(find.byKey(const ValueKey('boost-on-chest-30')), findsOneWidget);
      await tester.tapAt(const Offset(20, 40)); // the scrim closes it
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('booster-xp')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('booster-none')), findsOneWidget);
      expect(find.byKey(const ValueKey('boost-on-xp-30')), findsNothing);
      await finish(tester);
    }, demoClient);
  });

  testWidgets('«Включить» switches the ticket on: the kind then shows its time', (tester) async {
    await http.runWithClient(() async {
      await _pump(tester, _state(chestTickets: 2));
      await tester.tap(find.byKey(const ValueKey('booster-rating')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(20, 40));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('booster-chest')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('boost-on-chest-30')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pump(const Duration(milliseconds: 400));
      // The answer (the demo's own doublers) replaced the state: the chest kind now runs.
      expect(find.byKey(const ValueKey('booster-time-chest')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // lets the reward effect play out
      await finish(tester);
    }, demoClient);
  });

  test('the ring is green with time to spare, yellow under 10 minutes, red under 5', () {
    expect(BoostersBar.colorFor(const Duration(minutes: 43)), AppColors.action);
    expect(BoostersBar.colorFor(const Duration(minutes: 10)), AppColors.action, reason: 'ten minutes exactly is still green');
    expect(BoostersBar.colorFor(const Duration(minutes: 9, seconds: 59)), AppColors.warning);
    expect(BoostersBar.colorFor(const Duration(minutes: 5)), AppColors.warning);
    expect(BoostersBar.colorFor(const Duration(minutes: 4, seconds: 59)), AppColors.danger);
    expect(BoostersBar.colorFor(Duration.zero), AppColors.danger);
  });
}
