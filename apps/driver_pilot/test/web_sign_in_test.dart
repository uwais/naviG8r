import 'dart:async';

import 'package:dio/dio.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_flow.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/firebase_app.dart';
import 'package:driver_pilot/firebase_phone_auth.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_phone_auth.dart';
import 'support/mock_api.dart';

// Sample values in the shape Firebase uses; none of them belong to a real project.
final sampleWebSettings = {
  'FIREBASE_PROJECT_ID': 'navig8r-sample',
  'FIREBASE_WEB_API_KEY': 'AIza${'0' * 35}',
  'FIREBASE_WEB_APP_ID': '1:123456789012:web:0123456789abcdef012345',
  'FIREBASE_MESSAGING_SENDER_ID': '123456789012',
};

FirebaseOptions? optionsFrom(Map<String, String> settings) =>
    firebaseWebOptions((key) => settings[key] ?? '');

void main() {
  group('web Firebase settings', () {
    test('all four present build the options with the sign-in domain', () {
      final options = optionsFrom(sampleWebSettings)!;
      expect(options.projectId, 'navig8r-sample');
      expect(options.apiKey, sampleWebSettings['FIREBASE_WEB_API_KEY']);
      expect(options.appId, sampleWebSettings['FIREBASE_WEB_APP_ID']);
      expect(options.messagingSenderId, '123456789012');
      expect(options.authDomain, 'navig8r-sample.firebaseapp.com');
    });

    test('any one missing keeps the old code sign-in', () {
      for (final key in sampleWebSettings.keys) {
        final settings = Map.of(sampleWebSettings)..remove(key);
        expect(optionsFrom(settings), isNull, reason: key);
      }
    });

    test('a value outside its pattern keeps the old code sign-in', () {
      final malformed = {
        'FIREBASE_PROJECT_ID': ['Navig8r-Sample', 'navig8r-sample\n', 'a"b'],
        'FIREBASE_WEB_API_KEY': [
          'AIza${'0' * 34}',
          'AIza${'0' * 34}"',
          'BIza${'0' * 35}',
        ],
        'FIREBASE_WEB_APP_ID': [
          '1:123456789012:android:0123456789abcdef',
          '1:123456789012:web:XYZ',
          '1:123456789012:web:0123456789abcdef012345 ',
        ],
        'FIREBASE_MESSAGING_SENDER_ID': ['12345abc', '', '1' * 40],
      };
      malformed.forEach((key, values) {
        for (final value in values) {
          final settings = Map.of(sampleWebSettings)..[key] = value;
          expect(optionsFrom(settings), isNull, reason: '$key=$value');
        }
      });
    });
  });

  group('browser phone sign-in', () {
    test('sends the code through reCAPTCHA and confirms it', () async {
      final auth = FakeBrowserAuth();
      final client = FirebasePhoneAuthClient(auth: auth, browserFlow: true);
      final sent = <String>[];
      await client.requestCode('+919876543210', onCodeSent: sent.add);
      expect(auth.codeRequestsFor, ['+919876543210']);
      expect(sent, ['browser-verification']);
      await client.verifyCode('123456');
      expect(auth.confirmedCodes, ['123456']);
    });

    test('checking a code before one was sent asks for a code first',
        () async {
      final client =
          FirebasePhoneAuthClient(auth: FakeBrowserAuth(), browserFlow: true);
      expect(() => client.verifyCode('123456'), throwsStateError);
    });

    test('hands over the ID token and keeps no Firebase sign-in in the browser',
        () async {
      final auth = FakeBrowserAuth();
      final client = FirebasePhoneAuthClient(auth: auth, browserFlow: true);
      await client.requestCode('+919876543210', onCodeSent: (_) {});
      await client.verifyCode('123456');
      expect(await client.idToken(), 'browser-id-token');
      expect(auth.signedIn, isFalse);
    });
  });

  group('browser Firebase start-up', () {
    tearDown(() {
      firebasePhoneAuthAvailable = false;
      firebasePhoneAuthDiagnostic = null;
    });

    test('a start that never finishes gives up, so the app still opens',
        () async {
      final started = await startFirebaseInBrowser(
          () => Completer<void>().future,
          timeout: const Duration(milliseconds: 10));
      expect(started, isFalse);
      expect(firebasePhoneAuthAvailable, isFalse);
      expect(firebasePhoneAuthDiagnostic,
          'Phone sign-in is not working right now. Please try again later.');
    });

    test('a start that finishes turns phone sign-in on', () async {
      expect(await startFirebaseInBrowser(() async {}), isTrue);
      expect(firebasePhoneAuthAvailable, isTrue);
    });
  });

  group('sign-in error text', () {
    String text(String code) =>
        formatFirebaseAuthError(FirebaseAuthException(code: code));

    test('browser check and setup errors read plainly', () {
      expect(text('captcha-check-failed'),
          'We could not check this browser. Reload the page and try again.');
      expect(text('unauthorized-domain'),
          'Phone sign-in is not working on this site. Please try again later.');
      expect(text('code-expired'), text('session-expired'));
      expect(text('some-new-code'), 'Could not sign in. Please try again.');
    });

    test('a server answer during sign-in uses the server wording', () {
      api = Api('http://test');
      final refused = DioException(
        requestOptions: RequestOptions(path: '/v1/auth/firebase/exchange'),
        response: Response(
          requestOptions: RequestOptions(path: '/v1/auth/firebase/exchange'),
          statusCode: 401,
          data: {'error': 'unauthorized'},
        ),
      );
      expect(formatFirebaseAuthError(refused),
          'Your session has expired. Please sign in again.');
    });

    test('each refusal from the sign-in exchange reads plainly', () {
      api = Api('http://test');
      String refusal(int status, String code) =>
          formatFirebaseAuthError(DioException(
            requestOptions: RequestOptions(path: '/v1/auth/firebase/exchange'),
            response: Response(
              requestOptions:
                  RequestOptions(path: '/v1/auth/firebase/exchange'),
              statusCode: status,
              data: {'error': code},
            ),
          ));
      expect(refusal(400, 'user_not_found'),
          'This phone number has no NaviG8r account. Create an account first.');
      expect(refusal(400, 'account_inactive'),
          'This account is turned off. Contact NaviG8r support.');
      expect(refusal(400, 'firebase_identity_conflict'),
          'This phone number cannot sign in here. Contact NaviG8r support.');
      expect(refusal(400, 'firebase_token_invalid'),
          'Sign-in did not work. Send a new code.');
      expect(refusal(400, 'firebase_phone_provider_required'),
          'Sign-in did not work. Send a new code.');
      expect(refusal(429, 'firebase_exchange_rate_limited'),
          'Too many tries. Please wait a few minutes and try again.');
    });
  });

  group('server code sign-in where the server has retired it', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      AuthorizationSession.clear();
      firebasePhoneAuthAvailable = false;
      api = Api('http://test');
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.uri.path == '/v1/auth/otp/start') {
          return jsonResponse({
            'error': 'otp_sign_in_retired',
            'message': 'This sign-in is no longer used.',
          }, 410);
        }
        if (request.uri.path == '/v1/auth/me') return jsonResponse({}, 401);
        return jsonResponse({});
      });
    });

    testWidgets('shipper sign-in says so in plain words', (tester) async {
      final router = GoRouter(initialLocation: '/customer/login', routes: [
        GoRoute(
            path: '/customer/login',
            builder: (_, __) => const CustomerLoginScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(
          find.text('This sign-in is no longer used. Reload the page or update '
              'the app. If it still fails, try again later.'),
          findsOneWidget);
      expect(find.textContaining('HTTP 410'), findsNothing);
    });
  });

  group('sign-in screens with Firebase ready', () {
    late FakePhoneAuth phoneAuth;
    late List<String> serverCodeRequests;

    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      AuthorizationSession.clear();
      phoneAuth = FakePhoneAuth();
      newPhoneAuthClient = () => phoneAuth;
      firebasePhoneAuthAvailable = true;
      serverCodeRequests = [];
      api = Api('http://test');
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.uri.path == '/v1/auth/otp/start') {
          serverCodeRequests.add(request.uri.path);
          return jsonResponse({'challengeId': 'server-code'});
        }
        if (request.uri.path == '/v1/auth/me') return jsonResponse({}, 401);
        return jsonResponse({});
      });
    });

    tearDown(() {
      firebasePhoneAuthAvailable = false;
      newPhoneAuthClient = FirebasePhoneAuthClient.new;
    });

    Future<void> open(WidgetTester tester, String location) async {
      final router = GoRouter(initialLocation: location, routes: [
        GoRoute(
            path: '/customer/login',
            builder: (_, __) => const CustomerLoginScreen()),
        GoRoute(
            path: '/driver/onboarding/otp',
            builder: (_, __) => const DriverOtpScreen()),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        routerConfig: router,
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('the code screen opened without the Firebase mark uses Firebase',
        (tester) async {
      await open(tester, '/driver/onboarding/otp?phone=9876543210');
      expect(phoneAuth.codeRequestsFor, ['+919876543210']);
      expect(serverCodeRequests, isEmpty);
      expect(find.text('Challenge id'), findsNothing);
    });

    testWidgets('a wrong code on shipper sign-in reads plainly',
        (tester) async {
      phoneAuth.verifyError =
          FirebaseAuthException(code: 'invalid-verification-code');
      await open(tester, '/customer/login');
      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '000000');
      await tester.tap(find.text('Verify and continue'));
      await tester.pumpAndSettle();
      expect(find.text('That code is incorrect. Check it and try again.'),
          findsOneWidget);
      expect(serverCodeRequests, isEmpty);
    });
  });
}
