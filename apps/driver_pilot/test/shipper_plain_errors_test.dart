// PR 10 of the redesign: when a request fails on a shipper screen, the screen says what failed in
// plain words, never "HTTP 500", a server address or an exception's text (decisions.md 7).
import 'package:driver_pilot/shipper/erp_integrations.dart';
import 'package:driver_pilot/shipper/shipper_sign_in.dart';
import 'package:driver_pilot/shipper/shipper_team.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

/// Shows [screen] at [path], [width] wide, with a server that refuses everything with a 500,
/// except the paths in [working], which answer as given.
Future<void> showWithFailingServer(
    WidgetTester tester, String path, Widget screen,
    {Map<String, Object> working = const {}, double width = 360}) async {
  tester.view.physicalSize = Size(width, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
  api = Api('http://test');
  api.dio.httpClientAdapter = MockApiAdapter((request) {
    final answer = working[request.uri.path];
    return answer == null
        ? jsonResponse({'error': 'boom', 'detail': 'stack trace'}, 500)
        : jsonResponse(answer);
  });
  final router = GoRouter(
      initialLocation: path,
      routes: [GoRoute(path: path, builder: (_, __) => screen)]);
  addTearDown(router.dispose);
  await tester.pumpWidget(
      MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
  await tester.pumpAndSettle();
}

void expectPlainSentence(String sentence) {
  expect(find.text(sentence), findsOneWidget,
      reason: 'a failure says what failed in plain words');
  expect(find.textContaining(RegExp(r'HTTP:? *\d')), findsNothing,
      reason: 'decisions.md 7: no "HTTP 500" in the app');
  expect(find.textContaining('Exception'), findsNothing,
      reason: 'decisions.md 7: no exception text in the app');
}

void main() {
  tearDown(() {
    CustomerSession.skipRefreshInTests = false;
    CustomerSession.clear();
  });

  testWidgets(
      'sign in: a code that cannot be sent, then a code that cannot be checked',
      (tester) async {
    await showWithFailingServer(
        tester, '/customer/login', const CustomerLoginScreen());
    await tester.enterText(find.byType(TextField), '9845012345');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expectPlainSentence(
        'Could not send the code. Check your connection, then try again.');

    await showWithFailingServer(
        tester, '/customer/login', const CustomerLoginScreen(),
        working: {
          '/v1/auth/otp/start': {
            'challengeId': 'challenge-1',
            'retryAfterMs': 0
          }
        });
    await tester.enterText(find.byType(TextField), '9845012345');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '482190');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expectPlainSentence(
        'Could not sign you in. Check your connection, then try again.');
  });

  testWidgets('a teammate phone is written the one way the app writes phones',
      (tester) async {
    CustomerSession.skipRefreshInTests = true;
    CustomerSession.applyForTest(
        userFullName: 'Priya Raman',
        userPhone: '9845012345',
        customerOrgId: 'org-sharma',
        customerOrgName: 'Sharma Textiles',
        customerRole: 'CUSTOMER_ADMIN');
    await showWithFailingServer(
        tester, '/customer/team', const CustomerTeamScreen(),
        working: {
          '/v1/pilot/customer/members': {
            'members': [
              {
                'user': {'fullName': 'Arjun Mehta', 'phone': '9845067890'},
                'membership': {'role': 'CUSTOMER_MEMBER'}
              },
            ]
          }
        });
    expect(find.textContaining('+91 98450 67890 · '), findsOneWidget,
        reason:
            'copy.md formats: one way to write a phone, as on every other screen');
    expect(find.textContaining('9845067890'), findsNothing);
  });

  testWidgets('team and ERP integrations that cannot load', (tester) async {
    CustomerSession.skipRefreshInTests = true;
    CustomerSession.applyForTest(
        userFullName: 'Priya Raman',
        userPhone: '9845012345',
        customerOrgId: 'org-sharma',
        customerOrgName: 'Sharma Textiles',
        customerRole: 'CUSTOMER_ADMIN');
    await showWithFailingServer(
        tester, '/customer/team', const CustomerTeamScreen());
    expectPlainSentence(
        'Could not load your team. Check your connection, then try again.');

    await showWithFailingServer(
        tester, '/customer/integrations', const CustomerIntegrationsScreen(),
        width: 1280);
    expectPlainSentence(
        'Could not load the integration settings. Check your connection, then try again.');
  });
}
