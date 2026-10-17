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

OutlinedButton sendNewCodeButton(WidgetTester tester) =>
    tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Send a new code'));

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
    expect(formatApiError(error('otp_expired')),
        'This code has expired. Send a new code.',
        reason: 'copy.md: code errors, verbatim');
    expect(formatApiError(error('otp_incorrect')),
        'That code is not right. Check the SMS and type it again, or send a new code.',
        reason: 'copy.md: code errors, verbatim');
    expect(formatApiError(error('otp_challenge_invalid')),
        contains('Request a new code'));
    expect(formatApiError(error('otp_challenge_not_found')),
        contains('Request a new code'));
    expect(formatApiError(error('otp_challenge_mismatch')),
        contains('Request a new code'));
    final limited = DioException(
      requestOptions: RequestOptions(path: '/v1/auth/otp/start'),
      response: Response(
        requestOptions: RequestOptions(path: '/v1/auth/otp/start'),
        statusCode: 429,
        data: {'error': 'otp_rate_limited', 'retryAfterMs': 45000},
      ),
    );
    expect(formatApiError(limited), contains('45 seconds'));
  });

  testWidgets('customer resend cooldown disables button and counts down',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationSession.clear();
    api = Api('http://test');
    var starts = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        starts++;
        return jsonResponse({
          'challengeId': 'customer-cooldown',
          'expiresAtUtcMs': DateTime.now().millisecondsSinceEpoch + 600000,
          'retryAfterMs': 1200,
          'debugCode': '000042',
        });
      }
      if (request.uri.path == '/v1/auth/me') return jsonResponse({}, 401);
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
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(starts, 1);
    expect(find.text('No SMS yet? You can ask for a new code in 0:02.'),
        findsOneWidget,
        reason: 'copy.md: the wait is the server\'s, shown as a real timer');
    expect(sendNewCodeButton(tester).onPressed, isNull,
        reason: 'no new code until the server allows one');
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('No SMS yet?'), findsNothing);
    expect(sendNewCodeButton(tester).onPressed, isNotNull,
        reason: 'the new-code button opens once the wait is over');
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
    await tester.tap(find.text('Send a new code'));
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(find.text('Debug OTP: 000042'), findsNothing);
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        isEmpty);
  });

  testWidgets('customer same-challenge cooldown retry preserves entered OTP',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationSession.clear();
    api = Api('http://test');
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        return jsonResponse({
          'challengeId': 'same-customer-challenge',
          'expiresAtUtcMs': DateTime.now().millisecondsSinceEpoch + 600000,
          'retryAfterMs': 0,
        });
      }
      if (request.uri.path == '/v1/auth/me') return jsonResponse({}, 401);
      return jsonResponse({});
    });
    final router = GoRouter(initialLocation: '/customer/login', routes: [
      GoRoute(
          path: '/customer/login',
          builder: (_, __) => const CustomerLoginScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '8000000001');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Send a new code'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '123456');
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
    Object? verified;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        starts++;
        return jsonResponse(
            {'challengeId': 'fallback-1', 'expiresAtUtcMs': 2000000});
      }
      if (request.uri.path == '/v1/auth/otp/verify') verified = request.data;
      return jsonResponse({});
    });
    final router = testRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/driver/onboarding/otp?phone=9876543210');
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('fallback-1'), findsNothing,
        reason: 'PR 3: the code request id stays in state, never on screen');
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect((verified as Map)['challengeId'], 'fallback-1',
        reason: 'the hidden id is still the one sent with the code');
  });

  testWidgets('driver resend countdown disables the resend action',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        return jsonResponse({
          'challengeId': 'driver-cooldown',
          'expiresAtUtcMs': DateTime.now().millisecondsSinceEpoch + 600000,
          'retryAfterMs': 1200,
        });
      }
      return jsonResponse({});
    });
    final router = GoRouter(
        initialLocation: '/driver/onboarding/otp?phone=9876543210',
        routes: [
          GoRoute(
              path: '/driver/onboarding/otp',
              builder: (_, __) => const DriverOtpScreen()),
        ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('No SMS yet? You can ask for a new code in 0:02.'),
        findsOneWidget,
        reason: 'copy.md: the wait is the server\'s, shown as a real timer');
    expect(sendNewCodeButton(tester).onPressed, isNull,
        reason: 'no new code until the server allows one');
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('No SMS yet?'), findsNothing);
    expect(sendNewCodeButton(tester).onPressed, isNotNull,
        reason: 'the new-code button opens once the wait is over');
  });

  testWidgets('driver same-challenge retry preserves entered OTP without debug',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        return jsonResponse({
          'challengeId': 'same-driver-challenge',
          'expiresAtUtcMs': DateTime.now().millisecondsSinceEpoch + 600000,
          'retryAfterMs': 0,
        });
      }
      return jsonResponse({});
    });
    final router = GoRouter(
        initialLocation: '/driver/onboarding/otp?phone=9876543210',
        routes: [
          GoRoute(
              path: '/driver/onboarding/otp',
              builder: (_, __) => const DriverOtpScreen()),
        ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Send a new code'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField).last).controller!.text,
        '123456');
  });

  testWidgets('resend replaces stale debug code and challenge state',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    var starts = 0;
    Object? verified;
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
      if (request.uri.path == '/v1/auth/otp/verify') verified = request.data;
      return jsonResponse({});
    });
    final router = testRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.go('/driver/onboarding/otp?phone=9876543210');
    await tester.pumpAndSettle();
    expect(find.text('Debug OTP: 001122'), findsOneWidget);
    await tester.tap(find.text('Send a new code'));
    await tester.pumpAndSettle();
    expect(starts, 2);
    expect(find.text('Debug OTP: 001122'), findsNothing);
    final codeField = tester.widget<TextField>(find.byType(TextField).last);
    expect(codeField.controller?.text, isEmpty);
    await tester.enterText(find.byType(TextField).last, '654321');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect((verified as Map)['challengeId'], 'new',
        reason: 'the newest code request is the one verified');
  });

  testWidgets('driver login carries the first OTP challenge to verification',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    var starts = 0;
    Object? verified;
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
      if (request.uri.path == '/v1/auth/otp/verify') verified = request.data;
      return jsonResponse({});
    });
    AuthorizationSession.clear();
    AuthorizationSession.initialized = false;
    await tester.pumpWidget(const DriverPilotApp());
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.text('I carry goods'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(starts, 1);
    expect(find.text('Debug OTP: 004201'), findsOneWidget);
    expect(find.text('Challenge id'), findsNothing,
        reason: 'PR 3: no "Challenge id" field; the id stays in state');
    expect(find.text('challenge-first'), findsNothing,
        reason: 'PR 3: the code request id is never shown');
    expect(
        find.text('We sent a 6-digit code to +91 98765 43210.'), findsOneWidget,
        reason: 'copy.md: the code screen names the full number');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect((verified as Map)['challengeId'], 'challenge-first',
        reason: 'the first code request is carried to verification');
  });
}
