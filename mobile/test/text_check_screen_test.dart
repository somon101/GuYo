// «Проверка текста» (variant C): writing view, the answer with marks in the text, the mistake card.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:guyo_app/screens/text_check_screen.dart';
import 'package:http/http.dart' as http;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
  testWidgets('write, check, see the marks and the fix, switch to the corrected text, edit again', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      // The button is off while the field is empty.
      await tester.pumpWidget(const MaterialApp(home: TextCheckScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Проверка текста'), findsOneWidget);
      expect(find.byKey(const ValueKey('text-check-send')), findsOneWidget);
      expect(find.text('Кому: любому'), findsOneWidget);
      expect(find.text('0 / 500'), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('text-check-input')), 'Я пришёл что бы помочь');
      await tester.pump();
      expect(find.text('22 / 500'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('text-check-send')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 200));

      // The answer: the text with the mistake marked, its explanation and the main button.
      expect(find.byKey(const ValueKey('text-check-original')), findsOneWidget);
      expect(find.byKey(const ValueKey('text-check-mistake')), findsOneWidget);
      expect(find.textContaining('Союз «чтобы» пишется слитно.'), findsOneWidget);
      expect(find.byKey(const ValueKey('text-check-copy')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tc-tab-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('text-check-corrected')), findsOneWidget);
      expect(find.text('Я пришёл чтобы помочь'), findsOneWidget);

      // «Править» brings the checked text back into the field.
      await tester.tap(find.byKey(const ValueKey('text-check-edit')));
      await tester.pump();
      expect(find.byKey(const ValueKey('text-check-input')), findsOneWidget);
      expect(find.text('Я пришёл что бы помочь'), findsOneWidget);
    }, demoClient);
  });

  testWidgets('the settings sheet holds formality, punctuation, language and gender', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: TextCheckScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byKey(const ValueKey('text-check-settings')));
      await tester.pumpAndSettle();
      expect(find.text('Настройки проверки'), findsWidgets);
      expect(find.byKey(const ValueKey('tc-formality')), findsOneWidget);
      expect(find.byKey(const ValueKey('tc-punctuation')), findsOneWidget);
      expect(find.byKey(const ValueKey('text-check-language')), findsOneWidget);
      expect(find.byKey(const ValueKey('tc-gender-female')), findsOneWidget);
    }, demoClient);
  });
}
