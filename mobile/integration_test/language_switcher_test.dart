// Covers the language switcher's contract with the backend as the sole
// source of truth for what's published:
//   - 2+ published languages -> a real dropdown (arrow, tappable, lists all
//     of them, none of them hardcoded).
//   - exactly 1 published language -> shown plainly, no dropdown at all.
//   - 0 published languages -> no switcher, a clean "nothing available"
//     state instead of a crash or a guessed-at language.
//   - unpublishing the currently selected language and refreshing makes the
//     app fall back to another published one on its own.
//
// Run with:
//   flutter test integration_test/language_switcher_test.dart -d windows --dart-define=API_BASE_URL=http://127.0.0.1:8000
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';

import 'package:guyo_app/config.dart';
import 'package:guyo_app/main.dart';

Future<String> _adminToken() async {
  final res = await http.post(
    Uri.parse('$apiBaseUrl/auth/admin/login'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'login': 'admin', 'password': '123456'}),
  );
  return (jsonDecode(res.body) as Map)['access_token'] as String;
}

Future<Map<String, dynamic>> _dictionaryByLanguage(String token, String language) async {
  final res = await http.get(
    Uri.parse('$apiBaseUrl/dictionaries'),
    headers: {'Authorization': 'Bearer $token'},
  );
  final all = jsonDecode(res.body) as List;
  return all.firstWhere((d) => d['language'] == language) as Map<String, dynamic>;
}

Future<void> _setPublished(String token, int dictionaryId, bool published) async {
  final res = await http.patch(
    Uri.parse('$apiBaseUrl/dictionaries/$dictionaryId'),
    headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
    body: jsonEncode({'is_published': published}),
  );
  if (res.statusCode != 200) {
    throw StateError('failed to set published=$published on $dictionaryId: ${res.body}');
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('switcher reflects only published languages, with 0/1/2+ behavior', (tester) async {
    final token = await _adminToken();
    final english = await _dictionaryByLanguage(token, 'en');
    final russian = await _dictionaryByLanguage(token, 'ru');
    final chinese = await _dictionaryByLanguage(token, 'zh');
    final englishId = english['id'] as int;
    final russianId = russian['id'] as int;
    final chineseId = chinese['id'] as int;

    // Known starting point regardless of whatever this dev DB had before:
    // English + Russian published, Chinese a draft.
    await _setPublished(token, englishId, true);
    await _setPublished(token, russianId, true);
    await _setPublished(token, chineseId, false);

    await tester.pumpWidget(const GuyoApp());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // integration_test keeps the same app process (and its real secure
    // storage) across every testWidgets case, so a session left behind by
    // an earlier run/file would otherwise skip straight past the login
    // screen here. Start from a clean, logged-out state.
    if (find.text('Главная').evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Выйти'));
      await tester.pumpAndSettle();
    }

    await tester.enterText(find.byType(TextField).at(0), 'testuser');
    await tester.enterText(find.byType(TextField).at(1), '123456');
    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // There's no manual refresh button by design -- the screen re-checks
    // what's published on its own whenever the app comes back to the
    // foreground (WidgetsBindingObserver.didChangeAppLifecycleState). Drive
    // that exact mechanism here instead of a UI control that doesn't exist.
    Future<void> refresh() async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    await refresh();

    print('== 1. two published languages: dropdown arrow present ==');
    expect(find.text('English'), findsOneWidget, reason: 'English should be the current selection');
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget, reason: '2 options should show a dropdown');

    print('== 2. dropdown lists exactly the published ones, never the draft ==');
    await tester.tap(find.byTooltip('Выбрать язык'));
    await tester.pumpAndSettle();
    expect(find.text('Русский'), findsOneWidget);
    expect(find.text('中文'), findsNothing, reason: '中文 is still a draft, must not be offered');
    await tester.tap(find.text('Русский'));
    await tester.pumpAndSettle();
    expect(find.text('Русский'), findsWidgets, reason: 'switching should select Русский');

    print('== 3. unpublish the CURRENTLY SELECTED language (Русский); after refresh, falls back automatically ==');
    await _setPublished(token, russianId, false);
    await refresh();
    expect(find.text('English'), findsOneWidget, reason: 'should fall back to the remaining published language');
    expect(find.text('Русский'), findsNothing, reason: 'unpublished language must disappear entirely');

    print('== 4. exactly ONE published language left: no dropdown arrow, plain label ==');
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing, reason: 'a single option should not look like a dropdown');
    expect(find.byTooltip('Выбрать язык'), findsNothing, reason: 'no switcher control at all with only one option');

    print('== 5. unpublish the LAST remaining language -> zero published, clean empty state ==');
    await _setPublished(token, englishId, false);
    await refresh();
    expect(find.text('English'), findsNothing);
    expect(find.text('Пока нет доступных словарей'), findsOneWidget);
    expect(find.byTooltip('Выбрать язык'), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);

    print('== 6. republishing brings the switcher back correctly (2 languages again) ==');
    await _setPublished(token, englishId, true);
    await _setPublished(token, chineseId, true);
    await refresh();
    final bodyHasEnglishOrChinese =
        find.text('English').evaluate().isNotEmpty || find.text('中文').evaluate().isNotEmpty;
    expect(bodyHasEnglishOrChinese, isTrue, reason: 'switcher should recover once something is published again');
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget, reason: '2 published languages again -> dropdown back');

    // Restore the dev DB to its normal state for everything else.
    await _setPublished(token, russianId, true);

    print('\nALL LANGUAGE SWITCHER CHECKS PASSED');
  });
}
