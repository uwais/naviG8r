// PR 3 of the redesign: the sign-in and code screens (mockups c-signin, c-code, c-code-error)
// with copy.md's words and accessibility.md's announcements.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/shipper/shipper_sign_in.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

/// Every announcement a screen reader would get, as (message, assertive).
List<(String, bool)> listenForAnnouncements(WidgetTester tester) {
  final heard = <(String, bool)>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
      SystemChannels.accessibility, (message) async {
    final data = (message as Map)['data'] as Map;
    if (message['type'] == 'announce') {
      heard.add((data['message'] as String, data['assertiveness'] == 1));
    }
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility, null));
  return heard;
}

Future<void> showSignIn(WidgetTester tester, String at,
    {bool codeIsWrong = false}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({});
  AuthorizationSession.clear();
  api = Api('http://test');
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    if (request.uri.path == '/v1/auth/otp/start') {
      return jsonResponse({'challengeId': 'challenge-1', 'retryAfterMs': 0});
    }
    if (request.uri.path == '/v1/auth/otp/verify' && codeIsWrong) {
      return jsonResponse({'error': 'otp_incorrect'}, 400);
    }
    return jsonResponse({}, 401);
  });
  final router = GoRouter(initialLocation: at, routes: [
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
  await tester.pumpWidget(
      MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
  await tester.pumpAndSettle();
}

Future<void> sendCode(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '9845012345');
  await tester.scrollUntilVisible(find.text('Send code'), 200,
      scrollable: find.byType(Scrollable).first);
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the shipper sign-in has c-signin\'s words, nothing preselected',
      (tester) async {
    await showSignIn(tester, '/customer/login');
    expect(find.text('Sign in with your phone'), findsOneWidget,
        reason: 'copy.md: sign-in title');
    expect(find.text('We send a 6-digit code to this number by SMS.'),
        findsOneWidget,
        reason: 'copy.md: sign-in sub');
    expect(find.text('Mobile number'), findsOneWidget,
        reason: 'copy.md: field label');
    expect(find.text('+91'), findsOneWidget,
        reason: 'screens.md: +91 is a fixed prefix');
    expect(
        find.text('10 digits. Standard SMS rates may apply.'), findsOneWidget,
        reason: 'copy.md: field help');
    expect(find.text('Send code'), findsOneWidget,
        reason: 'screens.md: the primary action');
    expect(tester.getRect(find.text('Send code')).bottom, lessThan(800),
        reason: 'decisions.md 8: the primary action shows without scrolling');
    expect(find.text('Signing in to ship goods.'), findsOneWidget,
        reason: 'copy.md: role reminder');
    expect(find.text('I carry goods instead'), findsOneWidget,
        reason: 'copy.md: the other side is one tap away');
    expect(find.text('Register business'), findsOneWidget,
        reason: 'today\'s shipper sign-up stays reachable signed out');
    expect(find.text('Register as teammate'), findsOneWidget,
        reason: 'today\'s teammate sign-up stays reachable signed out');
    expect(find.text('Back'), findsOneWidget,
        reason: 'c-signin: Back returns to the start screen');
    expect(find.byType(NavigationBar), findsNothing,
        reason: 'signed out has no tabs');
  });

  testWidgets('the carrier sign-in says carry goods and keeps carrier sign-up',
      (tester) async {
    await showSignIn(tester, '/driver/onboarding/phone');
    expect(find.text('Sign in with your phone'), findsOneWidget,
        reason: 'copy.md: one sign-in for both sides');
    expect(find.text('Signing in to carry goods.'), findsOneWidget,
        reason: 'the reminder follows the start-screen choice');
    expect(find.text('I ship goods instead'), findsOneWidget,
        reason: 'the other side is one tap away');
    expect(find.text('Register as new carrier'), findsOneWidget,
        reason: 'today\'s carrier sign-up stays reachable signed out');
    expect(find.text('Join a carrier fleet'), findsOneWidget,
        reason: 'today\'s fleet sign-up stays reachable signed out');
  });

  for (final at in ['/customer/login', '/driver/onboarding/phone']) {
    testWidgets(
        'the code screen at $at has c-code\'s words and no Challenge id',
        (tester) async {
      final heard = listenForAnnouncements(tester);
      await showSignIn(tester, at);
      await sendCode(tester);
      expect(heard, contains(('Code sent to +91 98450 12345.', false)),
          reason: 'accessibility.md: Send code is announced politely');
      expect(find.text('Enter the code'), findsOneWidget,
          reason: 'copy.md: code title');
      expect(find.text('We sent a 6-digit code to +91 98450 12345.'),
          findsOneWidget,
          reason: 'copy.md: names the number the code went to');
      expect(find.text('6-digit code'), findsOneWidget,
          reason: 'copy.md: code field label');
      expect(
          find.text('The code fills in by itself if your phone reads the SMS.'),
          findsOneWidget,
          reason: 'copy.md: code field help');
      expect(find.text('Sign in'), findsOneWidget,
          reason: 'screens.md: the primary action is Sign in');
      expect(find.text('Send a new code'), findsOneWidget,
          reason: 'copy.md: resend');
      expect(find.text('Change number'), findsOneWidget,
          reason: 'copy.md: a way back to the number');
      expect(find.text('Challenge id'), findsNothing,
          reason: 'screens.md: no Challenge id field; the id stays in state');
      expect(find.text('challenge-1'), findsNothing,
          reason: 'no raw ids on screen');
      expect(find.byType(TextField), findsOneWidget,
          reason: 'screens.md: one code field');
    });
  }

  testWidgets('a wrong code says so under the field and is announced at once',
      (tester) async {
    final heard = listenForAnnouncements(tester);
    await showSignIn(tester, '/customer/login', codeIsWrong: true);
    await sendCode(tester);
    await tester.enterText(find.byType(TextField), '482190');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    const wrong =
        'That code is not right. Check the SMS and type it again, or send a new code.';
    expect(find.text(wrong), findsOneWidget,
        reason: 'c-code-error: the error sits under the field');
    expect(heard, contains((wrong, true)),
        reason: 'accessibility.md: a wrong code is announced assertively');
  });

  testWidgets('Change number goes back to the phone step', (tester) async {
    await showSignIn(tester, '/customer/login');
    await sendCode(tester);
    await tester.tap(find.text('Change number'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in with your phone'), findsOneWidget,
        reason: 'copy.md: Change number returns to the number');
  });

  testWidgets('both steps fit 360 dp at 200% text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    await showSignIn(tester, '/customer/login');
    expect(tester.takeException(), isNull,
        reason: 'decisions.md 8: works at 360 dp and 200% text');
    await sendCode(tester);
    expect(tester.takeException(), isNull,
        reason: 'decisions.md 8: works at 360 dp and 200% text');
  });
}
