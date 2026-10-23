// Inviting a number with no account, or one already in the company, was refused with a reason, and
// the invite screen showed "Could not invite this teammate. Check your connection, then try again."
import 'package:dio/dio.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/plain_error_sentence.dart';
import 'package:driver_pilot/shipper/shipper_team.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/carrier_app.dart';
import 'support/mock_api.dart';

Future<void> _inviteAndRead(WidgetTester tester, String refusal) async {
  tester.view.physicalSize = const Size(360, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues({'access_token': 'synthetic'});
  api = Api('http://test');
  CustomerSession.skipRefreshInTests = true;
  addTearDown(() => CustomerSession.skipRefreshInTests = false);
  CustomerSession.applyForTest(
      userFullName: 'Priya Raman',
      customerOrgId: 'org-sharma',
      customerOrgName: 'Sharma Textiles',
      customerRole: 'CUSTOMER_ADMIN');
  AuthorizationSession.principal!['permissions'] = [
    ...AuthorizationSession.principal!['permissions'] as List,
    'organization.member.invite',
  ];
  api.dio.httpClientAdapter = MockApiAdapter((request) =>
      request.path == '/v1/pilot/customer/members/invite'
          ? jsonResponse({'error': refusal}, 400)
          : jsonResponse({'members': <Object>[]}));
  final router = GoRouter(initialLocation: '/customer/team', routes: [
    GoRoute(
        path: '/customer/team', builder: (_, __) => const CustomerTeamScreen()),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(
      MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
  await tester.pumpAndSettle();
  await tester.enterText(
      find.widgetWithText(TextField, "Teammate's mobile number (10 digits)"),
      '9845012399');
  await tester.tap(find.text('Invite to company'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a number with no account says to register first', (tester) async {
    await _inviteAndRead(tester, 'user_not_found');
    expect(
        find.text(
            'No account uses this number. Ask them to register their phone first, then invite them.'),
        findsOneWidget);
    expect(find.textContaining('Check your connection'), findsNothing);
  });

  testWidgets('a number already in the company says so', (tester) async {
    await _inviteAndRead(tester, 'membership_already_exists');
    expect(find.text('This number is already in your company.'), findsOneWidget);
  });

  _carrierInviteRefusals();
}

void _carrierInviteRefusals() {
  testWidgets('the carrier invite screen also says to register first',
      (tester) async {
    final carrier = signInToCarrierApp(
        CarrierServer(allowed: ownerAllowed, subrole: 'OWNER'));
    api.dio.httpClientAdapter = MockApiAdapter((request) =>
        request.path == '/v1/pilot/carrier/drivers/invite'
            ? jsonResponse({'error': 'user_not_found'}, 400)
            : carrier.answer(request));
    final router = await mountCarrierApp(tester, '/driver/fleet',
        size: const Size(360, 1600));
    await tester.enterText(
        find.widgetWithText(TextField, "Driver's mobile number (10 digits)"),
        '9845012399');
    await tester.tap(find.text('Dispatcher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite dispatcher'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'No account uses this number. Ask them to register their phone first, then invite them.'),
        findsOneWidget);
    router.go('/');
    await tester.pumpAndSettle();
  });

  test('outside an invite, no account for a number does not say to invite',
      () {
    api = Api('http://test');
    final request = RequestOptions(path: '/v1/anything');
    final refusal = DioException(
        requestOptions: request,
        response: Response(
            requestOptions: request,
            statusCode: 400,
            data: {'error': 'user_not_found'}));
    expect(plainErrorSentence(refusal, 'Could not do that.'),
        isNot(contains('invite')),
        reason: 'the app-wide words are for every screen, not only invites');
  });
}
