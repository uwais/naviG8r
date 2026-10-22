// Owner decision, 21 Oct 2026: a company needs NaviG8r's approval to see prices or book.
import 'package:driver_pilot/customer_flow.dart';
import 'package:driver_pilot/customer_session.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/mock_api.dart';

/// The book screen for a signed-in shipper whose company has [kycStatus], or for no shipper when [shipper] is false.
Future<void> mountBookScreen(WidgetTester tester, String? kycStatus,
    {bool shipper = true}) async {
  api = Api('http://test');
  api.dio.httpClientAdapter =
      MockApiAdapter((_) => jsonResponse({'error': 'unexpected'}, 500));
  if (shipper) {
    CustomerSession.applyForTest(
      userPhone: '9111009902',
      customerOrgId: 'org_test',
      customerOrgName: 'Synthetic Shipper',
      customerRole: 'CUSTOMER_ADMIN',
      kycStatus: kycStatus,
    );
  }
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp.router(
    theme: DriverTheme.theme(),
    routerConfig: GoRouter(initialLocation: '/customer/book', routes: [
      GoRoute(
          path: '/customer/book',
          builder: (_, __) => const CustomerBookShipmentScreen()),
    ]),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    CustomerSession.clear();
    CustomerSession.skipRefreshInTests = true;
  });

  tearDown(() {
    CustomerSession.skipRefreshInTests = false;
    CustomerSession.clear();
  });

  for (final status in [null, 'NOT_STARTED', 'SUBMITTED', 'REJECTED']) {
    testWidgets(
        'a shipper whose company is ${status ?? "not yet reviewed"} sees no Get quote or Book & pay',
        (tester) async {
      await mountBookScreen(tester, status);
      expect(find.text('Get quote'), findsNothing);
      expect(find.text('Book & pay'), findsNothing);
      expect(
          find.text(
              'NaviG8r has to approve your company before you can see prices or book. Contact NaviG8r.'),
          findsOneWidget);
    });
  }

  testWidgets('a shipper whose company is approved can quote and book',
      (tester) async {
    await mountBookScreen(tester, 'APPROVED');
    expect(find.text('Get quote'), findsOneWidget);
    expect(find.text('Book & pay'), findsOneWidget);
    expect(find.textContaining('has to approve your company'), findsNothing);
  });

  testWidgets(
      'with no signed-in shipper company, the book screen asks to sign in as a shipper and offers no Get quote or Book & pay',
      (tester) async {
    await mountBookScreen(tester, null, shipper: false);
    expect(find.text('Get quote'), findsNothing);
    expect(find.text('Book & pay'), findsNothing);
    expect(find.text('Sign in as a shipper to see prices and book.'),
        findsOneWidget);
  });
}
