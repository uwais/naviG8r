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
    expect(find.textContaining('so NaviG8r can check your company'), findsOneWidget);
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
    expect(find.textContaining('so NaviG8r can check your company'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('driver without bank details is told to ask the owner',
      (tester) async {
    signInCarrier(kycStatus: 'NOT_STARTED', owner: false);
    await showBanner(tester);
    expect(find.textContaining('Ask the owner to add bank details'),
        findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets(
      'submitted carrier is told it is waiting for review, with no claim about bank details and no button',
      (tester) async {
    signInCarrier(kycStatus: 'SUBMITTED', owner: true);
    await showBanner(tester);
    expect(find.textContaining('NaviG8r is checking your company'),
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
        "NaviG8r did not approve your company. You can send your bank details for a new check. "
        "Until your company is approved, you cannot accept bookings or start trips.");
    expect(find.widgetWithText(FilledButton, 'Send bank details'),
        findsOneWidget);
  });

  testWidgets(
      'a rejected driver sees no reason, only to ask the owner for details, even if a reason arrives',
      (tester) async {
    for (final code in <String?>[
      null,
      'DOCUMENTS_MISSING',
      'BANK_DETAILS_MISMATCH',
      'DUPLICATE_ACCOUNT',
      'NOT_A_CARRIER'
    ]) {
      signInCarrier(
          kycStatus: 'REJECTED', owner: false, rejectionReasonCode: code);
      await showBanner(tester);
      expect(
          bannerMessage(tester),
          "NaviG8r did not approve your company. Ask the owner for details. "
          "Until your company is approved, you cannot accept bookings or start trips.",
          reason: '$code');
      expect(find.byType(FilledButton), findsNothing, reason: '$code');
    }
  });

  testWidgets(
      'the owner reads each reason in plain words, and only the bank reason offers the bank form',
      (tester) async {
    const reasons = {
      'DOCUMENTS_MISSING': 'NaviG8r needs documents from your company.',
      'BANK_DETAILS_MISMATCH':
          "The bank account holder's name does not match your company name.",
      'NOT_A_CARRIER': 'NaviG8r decided this is not a carrier business.',
    };
    // A duplicate reads its own short line, checked in the next test.
    for (final MapEntry(key: code, value: words) in reasons.entries) {
      signInCarrier(kycStatus: 'REJECTED', owner: true, rejectionReasonCode: code);
      await showBanner(tester);
      expect(bannerMessage(tester),
          startsWith('NaviG8r did not approve your company. $words '),
          reason: code);
      expect(bannerMessage(tester), isNot(contains('again')), reason: code);
      expect(find.widgetWithText(FilledButton, 'Send bank details'),
          code == 'BANK_DETAILS_MISMATCH' ? findsOneWidget : findsNothing,
          reason: code);
    }
  });

  testWidgets(
      'documents and not-a-carrier say the app cannot help, and a duplicate points to the company menu',
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
        'NaviG8r did not approve this company: it already has an account. Choose that account in the company menu, or ask its owner to invite you.');
    expect(find.byType(FilledButton), findsNothing);
    expect(bannerMessage(tester), isNot(contains("You can't send documents")));
  });

  testWidgets(
      'owner and driver whose approval was taken back are told so, not that it was never approved',
      (tester) async {
    signInCarrier(kycStatus: 'REJECTED', owner: true, approvalTakenBack: true);
    await showBanner(tester);
    expect(bannerMessage(tester),
        startsWith("NaviG8r took back your company's approval."));
    expect(bannerMessage(tester), isNot(contains('did not approve')));
    signInCarrier(kycStatus: 'REJECTED', owner: false, approvalTakenBack: true);
    await showBanner(tester);
    expect(
        bannerMessage(tester),
        "NaviG8r took back your company's approval. Ask the owner for details. "
        "Until your company is approved, you cannot accept bookings or start trips.");
  });

  testWidgets(
      'an unknown or malformed reason code shows no reason and keeps the bank form',
      (tester) async {
    for (final code in <Object>['SOMETHING_NEW', 42]) {
      signInCarrier(kycStatus: 'REJECTED', owner: true, rejectionReasonCode: code);
      await showBanner(tester);
      expect(
          bannerMessage(tester),
          "NaviG8r did not approve your company. You can send your bank details for a new check. "
          "Until your company is approved, you cannot accept bookings or start trips.",
          reason: '$code');
      expect(find.widgetWithText(FilledButton, 'Send bank details'),
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
    expect(find.textContaining('so NaviG8r can check your company'), findsOneWidget);

    AuthorizationSession.organizations.first['kycStatus'] = 'SUBMITTED';
    AuthorizationSession.revision.value++;
    await tester.pump();
    expect(find.textContaining('NaviG8r is checking your company'),
        findsOneWidget);

    AuthorizationSession.organizations.first['kycStatus'] = 'APPROVED';
    AuthorizationSession.revision.value++;
    await tester.pump();
    expect(find.byType(Text), findsNothing);
  });

  test('every approval status has plain words', () {
    expect(approvalStatusInWords('APPROVED'), 'Approved');
    expect(approvalStatusInWords('SUBMITTED'), 'Waiting for NaviG8r to check');
    expect(approvalStatusInWords('REJECTED'), 'Not approved');
    expect(approvalStatusInWords('NOT_STARTED'), 'Bank details not added yet');
    expect(approvalStatusInWords(null), 'Bank details not added yet');
  });
}
