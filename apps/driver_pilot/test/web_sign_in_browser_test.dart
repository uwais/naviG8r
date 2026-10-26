// Runs only in a browser: flutter test --platform chrome test/web_sign_in_browser_test.dart
@TestOn('browser')
library;

import 'dart:html' as html;
import 'dart:js_util' as js_util;

import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/customer_flow.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/firebase_app.dart';
import 'package:driver_pilot/firebase_phone_auth.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/runtime_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/fake_phone_auth.dart';
import 'support/mock_api.dart';

void main() {
  test('Firebase settings are read from runtime-config.js', () {
    js_util.setProperty(
        html.window,
        '__NAVI8R_CONFIG__',
        js_util.jsify({
          'MAPS_API_KEY': 'maps-sample',
          'FIREBASE_PROJECT_ID': 'navig8r-sample',
          'FIREBASE_WEB_API_KEY': 'AIza${'0' * 35}',
          'FIREBASE_WEB_APP_ID': '1:123456789012:web:0123456789abcdef012345',
          'FIREBASE_MESSAGING_SENDER_ID': '123456789012',
        }));
    addTearDown(() => js_util.setProperty(html.window, '__NAVI8R_CONFIG__', null));
    expect(firebaseWebOptions(runtimeConfigValue)?.projectId, 'navig8r-sample');
  });

  test('a page with no runtime settings keeps the old code sign-in', () {
    js_util.setProperty(html.window, '__NAVI8R_CONFIG__', null);
    expect(firebaseWebOptions(runtimeConfigValue), isNull);
  });

  test('the old code sign-in is off once Firebase is ready', () {
    firebasePhoneAuthAvailable = false;
    expect(legacyOtpFallbackEnabled, isTrue);
    firebasePhoneAuthAvailable = true;
    addTearDown(() => firebasePhoneAuthAvailable = false);
    expect(legacyOtpFallbackEnabled, isFalse);
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
            path: '/driver/onboarding/phone',
            builder: (_, __) => const DriverPhoneScreen()),
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

    testWidgets('shipper sign-in sends the code through Firebase',
        (tester) async {
      await open(tester, '/customer/login');
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(phoneAuth.codeRequestsFor, ['+919876543210']);
      expect(serverCodeRequests, isEmpty);
    });

    testWidgets('driver sign-in sends the code through Firebase',
        (tester) async {
      await open(tester, '/driver/onboarding/phone');
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.enterText(find.byType(TextField).first, '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(find.byType(SwitchListTile), findsNothing);
      expect(phoneAuth.codeRequestsFor, ['+919876543210']);
      expect(serverCodeRequests, isEmpty);
    });
  });
}
