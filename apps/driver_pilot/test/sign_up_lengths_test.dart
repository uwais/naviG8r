// The server caps sign-up names and company names at 100 characters and the phone at 20.
import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/shipper/shipper_register.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

Future<void> showScreen(WidgetTester tester, Widget screen,
    {ResponseBody Function(RequestOptions request)? answer}) async {
  tester.view.physicalSize = const Size(360, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({});
  api = Api('http://test');
  AuthorizationSession.clear();
  api.dio.httpClientAdapter =
      MockApiAdapter((request) => answer?.call(request) ?? jsonResponse({}));
  final router = GoRouter(
      initialLocation: '/sign-up',
      routes: [GoRoute(path: '/sign-up', builder: (_, __) => screen)]);
  addTearDown(router.dispose);
  await tester.pumpWidget(
      MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
  await tester.pumpAndSettle();
}

int? maxLengthOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(find.widgetWithText(TextField, label)).maxLength;

void main() {
  test('a sign-up length refusal reads as the server sentence', () {
    api = Api('http://test');
    DioException refused(String code, String detail) => DioException(
          requestOptions: RequestOptions(path: '/v1/pilot/customer/register'),
          response: Response(
            requestOptions:
                RequestOptions(path: '/v1/pilot/customer/register'),
            statusCode: 400,
            data: {'error': code, 'detail': detail},
          ),
        );
    for (final (code, detail) in [
      ('invalid_fullName', 'A name can have at most 100 characters.'),
      (
        'invalid_orgDisplayName',
        'A company name can have at most 100 characters.'
      ),
      ('invalid_phone', 'A phone number can have at most 20 characters.'),
    ]) {
      expect(formatApiError(refused(code, detail)), detail);
    }
  });

  testWidgets('the shipper sign-up shows the server sentence, not the connection',
      (tester) async {
    await showScreen(tester, const CustomerRegisterScreen(),
        answer: (_) => jsonResponse({
              'error': 'invalid_orgDisplayName',
              'detail': 'A company name can have at most 100 characters.',
              'field': 'orgDisplayName'
            }, 400));
    await tester.enterText(
        find.widgetWithText(TextField, 'Your name'), 'Priya Raman');
    await tester.enterText(
        find.widgetWithText(TextField, 'Mobile number (10 digits)'),
        '9845012345');
    await tester.enterText(
        find.widgetWithText(TextField, 'Company name'), 'Sharma Textiles');
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('A company name can have at most 100 characters.'),
        findsOneWidget);
    expect(find.textContaining('connection'), findsNothing);
  });

  testWidgets('each sign-up screen stops names at 100 and the phone at 20',
      (tester) async {
    for (final (screen, labels) in [
      (
        const CustomerRegisterScreen(),
        ['Your name', 'Mobile number (10 digits)', 'Company name']
      ),
      (
        const CustomerRegisterUserScreen(),
        ['Your name', 'Mobile number (10 digits)']
      ),
      (
        const DriverRegisterScreen(),
        ['Your name', 'Mobile number (10 digits)', 'Company name']
      ),
      (
        const DriverJoinScreen(),
        ['Your name', 'Mobile number (10 digits)']
      ),
    ]) {
      await showScreen(tester, screen);
      for (final label in labels) {
        expect(maxLengthOf(tester, label), label.startsWith('Mobile') ? 20 : 100,
            reason: '${screen.runtimeType}: $label');
      }
    }
  });
}
