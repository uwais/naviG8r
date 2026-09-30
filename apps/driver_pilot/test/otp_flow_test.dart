import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/customer_flow.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/mock_api.dart';

void main() {
  test('OTP API errors are actionable', () {
    api = Api('http://test');
    DioException error(String code) => DioException(
          requestOptions: RequestOptions(path: '/v1/auth/otp/verify'),
          response: Response(
            requestOptions: RequestOptions(path: '/v1/auth/otp/verify'),
            statusCode: 400,
            data: {'error': code},
          ),
        );
    expect(formatApiError(error('otp_expired')), contains('expired'));
    expect(formatApiError(error('otp_incorrect')), contains('incorrect'));
    expect(formatApiError(error('otp_challenge_invalid')),
        contains('Request a new code'));
    expect(formatApiError(error('otp_challenge_not_found')),
        contains('Request a new code'));
    expect(formatApiError(error('otp_challenge_mismatch')),
        contains('Request a new code'));
  });

  testWidgets('customer resend clears the previous code when debug is absent',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationSession.clear();
    api = Api('http://test');
    var starts = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        starts++;
        return jsonResponse({
          'challengeId': 'customer-$starts',
          'expiresAtUtcMs': DateTime.now().millisecondsSinceEpoch + 600000,
          if (starts == 1) 'debugCode': '000042'
        });
      }
      return jsonResponse({});
    });
    final router = GoRouter(initialLocation: '/customer/login', routes: [
      GoRoute(
          path: '/customer/login',
          builder: (_, __) => const CustomerLoginScreen())
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8000000001');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(find.text('Debug OTP: 000042'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '000042');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(find.text('Debug OTP: 000042'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty);
  });

  GoRouter testRouter() => GoRouter(routes: [
        GoRoute(
          path: '/driver/onboarding/otp',
          builder: (_, __) => const DriverOtpScreen(),
        ),
      ]);

  testWidgets('deep-link OTP fallback starts one challenge', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    var starts = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        starts++;
        return jsonResponse(
            {'challengeId': 'fallback-1', 'expiresAtUtcMs': 2000000});
      }
      return jsonResponse({});
    });
    final router = testRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/driver/onboarding/otp?phone=9876543210');
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('fallback-1'), findsOneWidget);
  });

  testWidgets('resend replaces stale debug code and challenge state',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    var starts = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        starts++;
        return jsonResponse(starts == 1
            ? {
                'challengeId': 'old',
                'expiresAtUtcMs': 2000000,
                'debugCode': '001122'
              }
            : {'challengeId': 'new', 'expiresAtUtcMs': 3000000});
      }
      return jsonResponse({});
    });
    final router = testRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/driver/onboarding/otp?phone=9876543210');
    await tester.pumpAndSettle();
    expect(find.text('Debug OTP: 001122'), findsOneWidget);
    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(find.text('Debug OTP: 001122'), findsNothing);
    expect(find.text('new'), findsOneWidget);
    expect(find.textContaining('Expires at'), findsOneWidget);
    final codeField = tester.widget<TextField>(find.byType(TextField).at(1));
    expect(codeField.controller?.text, isEmpty);
  });

  testWidgets('driver login carries the first OTP challenge to verification',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    var starts = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/me') return jsonResponse({}, 401);
      if (request.uri.path == '/v1/auth/otp/start') {
        starts++;
        return jsonResponse({
          'challengeId': 'challenge-first',
          'expiresAtUtcMs': DateTime.now().millisecondsSinceEpoch + 600000,
          'debugCode': '004201',
        });
      }
      return jsonResponse({});
    });
    AuthorizationSession.clear();
    AuthorizationSession.initialized = false;
    await tester.pumpWidget(const DriverPilotApp());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('Sign in with phone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('Debug OTP: 004201'), findsOneWidget);
    expect(find.text('challenge-first'), findsOneWidget);
    expect(find.text('Code sent to 9876543210'), findsOneWidget);
  });
}
