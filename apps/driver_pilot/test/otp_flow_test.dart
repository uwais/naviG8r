import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/main.dart';
import 'package:driver_pilot/sign_in_screen.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:driver_pilot/shipper/shipper_routes.dart';
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
    final limitedForMinutes = DioException(
      requestOptions: RequestOptions(path: '/v1/auth/otp/start'),
      response: Response(
        requestOptions: RequestOptions(path: '/v1/auth/otp/start'),
        statusCode: 429,
        data: {'error': 'otp_rate_limited', 'retryAfterMs': 60001},
      ),
    );
    expect(formatApiError(limitedForMinutes),
        'Too many code requests. Please wait 2 minutes and try again.',
        reason: 'a wait of a minute or more reads in minutes, rounded up');
  });

  test('a wait of one second reads "1 second"', () {
    final limited = DioException(
      requestOptions: RequestOptions(path: '/v1/auth/otp/start'),
      response: Response(
        requestOptions: RequestOptions(path: '/v1/auth/otp/start'),
        statusCode: 429,
        data: {'error': 'otp_rate_limited', 'retryAfterMs': 400},
      ),
    );
    expect(formatApiError(limited),
        'Too many code requests. Please wait 1 second and try again.',
        reason: 'review: it read "1 seconds"');
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
          builder: (_, __) => const SignInScreen())
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
          builder: (_, __) => const SignInScreen())
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
          builder: (_, __) => const SignInScreen()),
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

  testWidgets('resend replaces stale debug code and challenge state',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationSession.clear();
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
    final router = GoRouter(initialLocation: '/customer/login', routes: [
      GoRoute(
          path: '/customer/login', builder: (_, __) => const SignInScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.text('Send code'));
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

  testWidgets(
      'a failed account check after a right code keeps the code and retries',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationSession.clear();
    api = Api('http://test');
    var verifies = 0;
    var accountCheckWorks = false;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        return jsonResponse({'challengeId': 'challenge-1', 'retryAfterMs': 0});
      }
      if (request.uri.path == '/v1/auth/otp/verify') {
        verifies++;
        return jsonResponse({'accessToken': 'token-1'});
      }
      if (request.uri.path == '/v1/auth/me') {
        if (!accountCheckWorks) return jsonResponse({}, 503);
        return jsonResponse({
          'user': {'id': 'user-1', 'phone': '9876543210'},
          'organizations': [
            {'id': 'org-1', 'kind': 'CUSTOMER'}
          ],
          'principal': {
            'organizationId': 'org-1',
            'roles': ['SHIPPER'],
            'permissions': []
          },
        });
      }
      return jsonResponse({});
    });
    final router = GoRouter(initialLocation: '/customer/login', routes: [
      GoRoute(
          path: '/customer/login', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/customer', builder: (_, __) => const Text('Home')),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not finish signing in. Check your connection, then try again.'),
        findsOneWidget,
        reason: 'the code was right; saying the number is unknown is untrue');
    expect(find.text('Enter the code'), findsOneWidget,
        reason: 'the code request is kept so Sign in can be tapped again');

    accountCheckWorks = true;
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget,
        reason: 'the retry finishes signing in');
    expect(verifies, 1,
        reason: 'the server spends the code once; the retry repeats only '
            'the account check');
  });

  testWidgets('a verify answer with no access token is not taken as a right code',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationSession.clear();
    api = Api('http://test');
    var verifies = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') {
        return jsonResponse({'challengeId': 'challenge-1', 'retryAfterMs': 0});
      }
      if (request.uri.path == '/v1/auth/otp/verify') {
        verifies++;
        return jsonResponse({});
      }
      if (request.uri.path == '/v1/auth/me') return jsonResponse({}, 401);
      return jsonResponse({});
    });
    final router = GoRouter(initialLocation: '/customer/login', routes: [
      GoRoute(
          path: '/customer/login', builder: (_, __) => const SignInScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Could not sign you in. Check your connection, then try again.'),
        findsOneWidget,
        reason: 'review: with no token the account check could never pass');

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(verifies, 2,
        reason: 'review: the code was marked accepted and never verified again');
  });

  testWidgets('a carrier who just registered finds their number filled in',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    AuthorizationSession.clear();
    api = Api('http://test');
    var starts = 0;
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/otp/start') starts++;
      return jsonResponse({}, 401);
    });
    final router = GoRouter(
        initialLocation: '/customer/login?phone=9876543210',
        routes: customerFlowRoutes());
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '9876543210',
        reason: 'the register screen hands its number to the sign-in');
    expect(starts, 0, reason: 'no SMS goes until the person taps Send code');
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

  testWidgets('driver sign-in starts the wait from the first code request',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    api = Api('http://test');
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.uri.path == '/v1/auth/me') return jsonResponse({}, 401);
      if (request.uri.path == '/v1/auth/otp/start') {
        return jsonResponse({
          'challengeId': 'challenge-first',
          'expiresAtUtcMs': DateTime.now().millisecondsSinceEpoch + 600000,
          'retryAfterMs': 1200,
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
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.tap(find.text('Send code'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('No SMS yet? You can ask for a new code in 0:02.'),
        findsOneWidget,
        reason:
            "the code step shows the server's wait from the first code request");
    expect(sendNewCodeButton(tester).onPressed, isNull,
        reason: 'no new code until the server allows one');
    await tester.pump(const Duration(seconds: 2));
    expect(sendNewCodeButton(tester).onPressed, isNotNull);
  });
}
