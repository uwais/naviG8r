// A number that already has an account was refused with a 409, and the register screen read it as a
// connection problem: "Could not register your company. Check your connection, then try again."
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/shipper/shipper_register.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

void main() {
  testWidgets('registering a number that has an account says to sign in',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    AuthorizationSession.clear();
    api.dio.httpClientAdapter = MockApiAdapter((request) =>
        request.path == '/v1/pilot/customer/register'
            ? jsonResponse({'error': 'phone_already_registered'}, 409)
            : jsonResponse({}));
    final router = GoRouter(initialLocation: '/customer/register', routes: [
      GoRoute(
          path: '/customer/register',
          builder: (_, __) => const CustomerRegisterScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(
        MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Your name'), 'Priya Raman');
    await tester.enterText(
        find.widgetWithText(TextField, 'Phone (10 digits)'), '9845012345');
    await tester.enterText(
        find.widgetWithText(TextField, 'Company name'), 'Sharma Textiles');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('This number already has an account. Sign in instead.'),
        findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing,
        reason: 'the server answered; the connection is fine');
  });
}
