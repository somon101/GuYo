// Basic smoke test for the login screen's layout. The full app entry point
// (GuyoApp) first checks secure storage for a session token, which needs a
// real platform channel that isn't available under `flutter test` -- so
// this test pumps LoginScreen directly instead of routing through that
// startup check.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:guyo_app/screens/login_screen.dart';

void main() {
  testWidgets('Login screen shows the expected fields', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('GuYo'), findsOneWidget);
    expect(find.text('Вход'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Логин'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Пароль'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Войти'), findsOneWidget);
  });
}
