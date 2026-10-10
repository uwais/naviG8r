import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/carrier_approval_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  void signInCarrier(
      {required String? kycStatus,
      required bool owner,
      Object? rejectionReasonCode,
      bool approvalTakenBack = false}) {
    AuthorizationSession.clear();
    AuthorizationSession.user = {'id': 'user-a'};
    AuthorizationSession.principal = {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'permissions': ['load.read', if (owner) 'bank_account.create_token'],
    };
    AuthorizationSession.organizations = [
      {
        'id': 'carrier-a',
        'displayName': 'Carrier A',
        'kycStatus': kycStatus,
        if (rejectionReasonCode != null)
          'rejectionReasonCode': rejectionReasonCode,
        if (approvalTakenBack) 'approvalTakenBack': true,
      }
    ];
  }

  // The banner's sentence is the first Text; a button's label comes after it.
  String bannerMessage(WidgetTester tester) =>
      tester.widget<Text>(find.byType(Text).first).data!;

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

  testWidgets(
      'submitted carrier is told it is waiting for review, with no claim about bank details and no button',
      (tester) async {
    signInCarrier(kycStatus: 'SUBMITTED', owner: true);
    await showBanner(tester);
    expect(find.textContaining('waiting for NaviG8r operations to review'),
        findsOneWidget);
    // Test data can start a carrier waiting for review with no bank details saved.
    expect(find.textContaining(RegExp('bank', caseSensitive: false)),
        findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
      'rejected owner with no reason on record is offered the bank form, with no "again"',
      (tester) async {
    signInCarrier(kycStatus: 'REJECTED', owner: true);
    await showBanner(tester);
    expect(
        bannerMessage(tester),
        "NaviG8r operations did not approve this carrier. You can submit your bank details for another review. "
        "While this carrier is not approved, you can't accept shipments or start trips.");
    expect(find.widgetWithText(FilledButton, 'Submit bank details'),
        findsOneWidget);
  });

  testWidgets(
      'rejected driver with no reason on record is told to ask the owner, no button',
      (tester) async {
    signInCarrier(kycStatus: 'REJECTED', owner: false);
    await showBanner(tester);
    expect(
        bannerMessage(tester),
        "NaviG8r operations did not approve this carrier. Ask the carrier owner to submit bank details for another review. "
        "While this carrier is not approved, you can't accept shipments or start trips.");
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
      'each shared reason reads the same to owner and driver, and only the bank reason offers the bank form',
      (tester) async {
    const reasons = {
      'DOCUMENTS_MISSING': 'NaviG8r needs documents from this carrier.',
      'BANK_DETAILS_MISMATCH':
          "The name entered as the bank account holder doesn't match the carrier's name.",
      'DUPLICATE_ACCOUNT': 'NaviG8r already has an account for this carrier.',
      'NOT_A_CARRIER': 'NaviG8r decided this is not a carrier business.',
    };
    for (final MapEntry(key: code, value: words) in reasons.entries) {
      for (final owner in [true, false]) {
        signInCarrier(
            kycStatus: 'REJECTED', owner: owner, rejectionReasonCode: code);
        await showBanner(tester);
        final which = '$code, owner: $owner';
        expect(bannerMessage(tester), contains('Reason: $words'),
            reason: which);
        expect(bannerMessage(tester), isNot(contains('again')), reason: which);
        expect(find.widgetWithText(FilledButton, 'Submit bank details'),
            code == 'BANK_DETAILS_MISMATCH' && owner ? findsOneWidget : findsNothing,
            reason: which);
      }
    }
  });

  testWidgets(
      'documents and not-a-carrier say the app cannot help, and a duplicate points to the organization menu',
      (tester) async {
    for (final code in ['DOCUMENTS_MISSING', 'NOT_A_CARRIER']) {
      signInCarrier(kycStatus: 'REJECTED', owner: true, rejectionReasonCode: code);
      await showBanner(tester);
      expect(bannerMessage(tester),
          contains("You can't send documents or contact NaviG8r from the app."),
          reason: code);
      expect(bannerMessage(tester), isNot(contains('bank details')), reason: code);
    }
    signInCarrier(
        kycStatus: 'REJECTED', owner: true, rejectionReasonCode: 'DUPLICATE_ACCOUNT');
    await showBanner(tester);
    expect(bannerMessage(tester),
        contains('choose it in the organization menu at the top of the screen'));
    expect(bannerMessage(tester), isNot(contains("You can't send documents")));
  });

  testWidgets(
      'a carrier whose approval was taken back is told so, not that it was never approved',
      (tester) async {
    signInCarrier(kycStatus: 'REJECTED', owner: true, approvalTakenBack: true);
    await showBanner(tester);
    expect(bannerMessage(tester),
        startsWith("NaviG8r operations took back this carrier's approval."));
    expect(bannerMessage(tester), isNot(contains('did not approve')));
  });

  testWidgets(
      'an unknown or malformed reason code shows no reason and keeps the bank form',
      (tester) async {
    for (final code in <Object>['SOMETHING_NEW', 42]) {
      signInCarrier(kycStatus: 'REJECTED', owner: true, rejectionReasonCode: code);
      await showBanner(tester);
      expect(bannerMessage(tester), isNot(contains('Reason:')), reason: '$code');
      expect(find.widgetWithText(FilledButton, 'Submit bank details'),
          findsOneWidget,
          reason: '$code');
    }
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
