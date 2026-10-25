// The server limits sign-ups per phone and per connection and answers 429 rate_limited.
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
  testWidgets('a sign-up refused for too many tries says to wait',
      (tester) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    AuthorizationSession.clear();
    api.dio.httpClientAdapter = MockApiAdapter((request) =>
        request.path == '/v1/pilot/customer/register'
            ? jsonResponse({'error': 'rate_limited'}, 429)
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
        find.widgetWithText(TextField, 'Mobile number (10 digits)'), '9845012345');
    await tester.enterText(
        find.widgetWithText(TextField, 'Company name'), 'Sharma Textiles');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Too many tries. Wait a few minutes, then try again.'),
        findsOneWidget);
  });
}
