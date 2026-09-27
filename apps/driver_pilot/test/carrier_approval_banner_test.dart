import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/carrier_approval_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  void signInCarrier({required String? kycStatus, required bool owner}) {
    AuthorizationSession.clear();
    AuthorizationSession.user = {'id': 'user-a'};
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': ['load.read', if (owner) 'bank_account.create_token'],
    };
    AuthorizationSession.organizations = [
      {'id': 'carrier-a', 'displayName': 'Carrier A', 'kycStatus': kycStatus}
    ];
  }

  Future<GoRouter> showBanner(WidgetTester tester,
      {String at = '/driver/loads'}) async {
    Widget bannerAt(String path) =>
        Scaffold(body: CarrierApprovalBanner(currentPath: path));
    final router = GoRouter(initialLocation: at, routes: [
      for (final path in ['/driver', '/driver/loads'])
        GoRoute(path: path, builder: (_, __) => bannerAt(path)),
      GoRoute(
          path: '/driver/payout-setup',
          builder: (_, __) => bannerAt('/driver/payout-setup')),
    ]);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    return router;
  }

  // The router's sign-in check reads the location below. A push leaves it on the
  // screen underneath; a go moves it to the form.
  String signInCheckSees(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.path;

  testWidgets('from Loads the form opens on top, and Back returns to Loads',
      (tester) async {
    signInCarrier(kycStatus: 'NOT_STARTED', owner: true);
    final router = await showBanner(tester);
    expect(find.textContaining('Add your bank details'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Add bank details'));
    await tester.pumpAndSettle();
    // The form shows the banner without its button, so no button means the form is open.
    expect(find.byType(FilledButton), findsNothing);
    expect(signInCheckSees(router), '/driver/loads');
    router.pop();
    await tester.pumpAndSettle();
    expect(
        find.widgetWithText(FilledButton, 'Add bank details'), findsOneWidget);
  });

  testWidgets('from Home the sign-in check sees the form, not public Home',
      (tester) async {
    signInCarrier(kycStatus: 'NOT_STARTED', owner: true);
    final router = await showBanner(tester, at: '/driver');
    await tester.tap(find.widgetWithText(FilledButton, 'Add bank details'));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
    expect(signInCheckSees(router), '/driver/payout-setup');
  });

  testWidgets('no button to the bank form while already on it', (tester) async {
    signInCarrier(kycStatus: 'NOT_STARTED', owner: true);
    await showBanner(tester, at: '/driver/payout-setup');
    expect(find.textContaining('Add your bank details'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('driver without bank details is told to ask the owner',
      (tester) async {
    signInCarrier(kycStatus: 'NOT_STARTED', owner: false);
    await showBanner(tester);
    expect(find.textContaining('Ask the carrier owner to add bank details'),
        findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('submitted carrier is told it is waiting for review, no button',
      (tester) async {
    signInCarrier(kycStatus: 'SUBMITTED', owner: true);
    await showBanner(tester);
    expect(find.textContaining('waiting for NaviG8r operations to review'),
        findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('rejected owner can submit bank details again', (tester) async {
    signInCarrier(kycStatus: 'REJECTED', owner: true);
    await showBanner(tester);
    expect(find.textContaining("you can't accept shipments or start trips"),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit bank details again'),
        findsOneWidget);
  });

  testWidgets('rejected driver is told to ask the owner to resubmit, no button',
      (tester) async {
    signInCarrier(kycStatus: 'REJECTED', owner: false);
    await showBanner(tester);
    expect(find.textContaining('Ask the carrier owner to submit bank details'),
        findsOneWidget);
    expect(find.textContaining("you can't accept shipments or start trips"),
        findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('approved carrier sees no banner', (tester) async {
    signInCarrier(kycStatus: 'APPROVED', owner: true);
    await showBanner(tester);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('banner follows a status change without leaving the screen',
      (tester) async {
    signInCarrier(kycStatus: 'NOT_STARTED', owner: true);
    await showBanner(tester);
    expect(find.textContaining('Add your bank details'), findsOneWidget);

    AuthorizationSession.organizations.first['kycStatus'] = 'SUBMITTED';
    AuthorizationSession.revision.value++;
    await tester.pump();
    expect(find.textContaining('waiting for NaviG8r operations to review'),
        findsOneWidget);

    AuthorizationSession.organizations.first['kycStatus'] = 'APPROVED';
    AuthorizationSession.revision.value++;
    await tester.pump();
    expect(find.byType(Text), findsNothing);
  });

  test('every approval status has plain words', () {
    expect(approvalStatusInWords('APPROVED'), 'Approved');
    expect(approvalStatusInWords('SUBMITTED'), 'Waiting for NaviG8r review');
    expect(approvalStatusInWords('REJECTED'), 'Not approved');
    expect(approvalStatusInWords('NOT_STARTED'), 'Bank details not added yet');
    expect(approvalStatusInWords(null), 'Bank details not added yet');
  });
}
