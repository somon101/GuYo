// Basic smoke test for the login screen's layout. The full app entry point
// (GuyoApp) first checks secure storage for a session token, which needs a
// real platform channel that isn't available under `flutter test` -- so
// this test pumps LoginScreen directly instead of routing through that
// startup check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/screens/login_screen.dart';

void main() {
  testWidgets('Login screen: the greeting first, then the two fields', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // The greeting has no fields.
    expect(find.text('GuYo'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Войти'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Создать аккаунт'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Войти'));
    await tester.pump();
    expect(find.text('Вход'), findsOneWidget);
    // The field names are the fields' own hints.
    expect(find.text('Логин'), findsOneWidget);
    expect(find.text('Пароль'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
