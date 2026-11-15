// The first screen: the greeting with three ways in and no fields; the fields come on a second step.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:guyo_app/demo/demo_server.dart';
import 'package:guyo_app/screens/login_screen.dart';
import 'package:guyo_app/screens/register_screen.dart';
import 'package:guyo_app/services/google_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the greeting has no fields: «Войти», «Создать аккаунт» and the language chip in the corner', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.byKey(const ValueKey('login-start')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-register')), findsOneWidget);
    expect(find.byKey(const ValueKey('ui-language-chip')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-field-login')), findsNothing);
    expect(find.byKey(const ValueKey('login-field-password')), findsNothing);
    expect(find.byKey(const ValueKey('login-google-button')).evaluate().length, googleSignInEnabled ? 1 : 0);
    // The chip sits in the right corner.
    expect(tester.getCenter(find.byKey(const ValueKey('ui-language-chip'))).dx, greaterThan(300));
  });

  testWidgets('«Войти» opens the two fields; back returns to the greeting', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.tap(find.byKey(const ValueKey('login-start')));
    await tester.pump();
    expect(find.byKey(const ValueKey('login-field-login')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-field-password')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey('ui-language-chip')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('login-back')));
    await tester.pump();
    expect(find.byKey(const ValueKey('login-field-login')), findsNothing);
    expect(find.byKey(const ValueKey('login-start')), findsOneWidget);
  });

  testWidgets('a wrong password shows the server\'s words under the fields', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final client = MockClient((req) async => http.Response(jsonEncode({'detail': 'Неверный логин или пароль'}), 401, headers: {'content-type': 'application/json; charset=utf-8'}));
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.tap(find.byKey(const ValueKey('login-start')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('login-field-login')), 'demo');
      await tester.enterText(find.byKey(const ValueKey('login-field-password')), 'wrong');
      await tester.tap(find.byKey(const ValueKey('login-submit')));
      await settle(tester);
      expect(find.text('Неверный логин или пароль'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    }, () => client);
  });

  testWidgets('«Создать аккаунт» opens the registration', (tester) async {
    tester.view.physicalSize = const Size(1080, 2200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.tap(find.byKey(const ValueKey('login-register')));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300)); // the route's page is built a frame after it is pushed
      tester.takeException();
      expect(find.byType(RegisterScreen), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
    }, demoClient);
  });

  testWidgets('a narrow phone shows both steps without overflow', (tester) async {
    tester.view.physicalSize = const Size(960, 1920); // 320x640
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('login-start')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
