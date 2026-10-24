// The carrier office bugs the 23 Oct 2026 hunt confirmed (C2 to C12), each on the screens as the office uses them.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:driver_pilot/ui/nv_step_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/carrier_app.dart';
import 'support/carrier_fixtures.dart';
import 'support/carrier_office_bookings.dart';
import 'support/eway_bill_fixtures.dart' show finalBill;
import 'support/mock_api.dart';

/// Signs in as the owner of carrier-a with its approval at [kycStatus].
CarrierServer signInAtApproval(String kycStatus,
    {List<Map<String, dynamic>> trips = const [],
    List<Map<String, dynamic>> bookings = const []}) {
  final organization = {...carrierOrganization, 'kycStatus': kycStatus};
  final server = CarrierServer(
      allowed: ownerAllowed,
      subrole: 'OWNER',
      trips: trips,
      bookings: bookings,
      extraAnswers: {
        '/v1/auth/me': {
          'user': {'id': 'carrier-person'},
          'organizations': [organization],
          'principal': {
            'organizationId': 'carrier-a',
            'roles': ['CARRIER'],
            'subrole': 'OWNER',
            'permissions': ownerAllowed,
          },
        },
      });
  signInToCarrierApp(server);
  AuthorizationSession.organizations = [organization];
  return server;
}

Future<void> mountBookingScreen(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: DriverTheme.theme(),
      home: const Scaffold(
          body: DriverShipmentDetailScreen(shipmentId: 'shipment-a'))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'C2: a closed booking, left behind at the start or not, says Closed with no steps and no amount',
      (tester) async {
    final closed = {
      ...shipmentOnTripA(
          status: 'FAILED_CARRIER_REFUNDED', netToCarrierPaise: 450000),
      'id': 'shipment-a',
      'assignedTruckNumber': 'KA01AB1234',
    };
    for (final booking in [
      closed,
      {...closed, 'leftBehindAtUtcMs': 1760000000000},
    ]) {
      signInAsOwner();
      answer(bookings: [
        booking
      ], trips: [
        trip(status: 'IN_PROGRESS', truck: 'KA01AB1234', driverName: 'Prakash')
      ]);
      await mountBookingScreen(tester);
      expect(find.text('Closed'), findsOneWidget);
      expect(find.text('This booking is closed.'), findsOneWidget);
      expect(find.textContaining('Accepted'), findsNothing);
      expect(find.byType(NvStepList), findsNothing,
          reason: 'no steps after the booking card');
      expect(find.textContaining('₹'), findsNothing);
      expect(find.textContaining('You receive'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'C3: Earnings that fail to load show the error and Try again, never ₹0',
      (tester) async {
    var fails = true;
    final server = signInToCarrierApp(
        CarrierServer(allowed: ownerAllowed, subrole: 'OWNER'));
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path == '/v1/pilot/carrier/earnings') {
        return fails
            ? jsonResponse({'error': 'unavailable'}, 500)
            : jsonResponse({
                'summary': {'pendingAccruedPaise': 120000, 'paidPaise': 0}
              });
      }
      return server.answer(request);
    });
    await mountCarrierApp(tester, '/driver/earnings',
        size: const Size(400, 1600));
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text('Earned, not paid yet'), findsNothing);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    fails = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('₹1,200'), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsNothing,
        reason: 'the error from the failed load goes once a load works');
  });

  testWidgets(
      'C3: Payments to you that fail to load show the error and Try again, never No payments yet',
      (tester) async {
    var fails = true;
    final server = signInToCarrierApp(
        CarrierServer(allowed: ownerAllowed, subrole: 'OWNER'));
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path == '/v1/pilot/carrier/payout-batches') {
        return fails
            ? jsonResponse({'error': 'unavailable'}, 500)
            : jsonResponse({
                'payoutBatches': [
                  {
                    'totalNetToCarrierPaise': 250000,
                    'lineIds': ['l1']
                  }
                ]
              });
      }
      return server.answer(request);
    });
    await mountCarrierApp(tester, '/driver/payout-history',
        size: const Size(400, 1600));
    expect(find.textContaining('No payments yet'), findsNothing);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);

    fails = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('₹2,500'), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsNothing);
  });

  for (final kycStatus in ['APPROVED', 'NOT_STARTED']) {
    testWidgets(
        'C4: the bank details screen at 360 dp and 200% text scrolls to Save (approval $kycStatus)',
        (tester) async {
      final server = signInAtApproval(kycStatus);
      await mountCarrierApp(tester, '/driver/payout-setup',
          size: const Size(360, 800), textScale: 2);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Save bank details'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save bank details'));
      await tester.pumpAndSettle();
      expect(
          server.sent
              .where((sent) => sent.path == '/v1/pilot/carrier/payout-setup'),
          hasLength(1));
    });
  }

  testWidgets(
      'C5: at 200% text the approval banner keeps to its share and the trip screen keeps Start on screen',
      (tester) async {
    signInAtApproval('SUBMITTED', trips: [
      {
        ...carrierTrip('trip-open', from: 'Krishnagiri', to: 'Coimbatore'),
        'assignedDriverUserId': null,
        'assignedDriverName': null,
      }
    ], bookings: [
      for (final (index, name) in [
        'Sharma Textiles Private Limited',
        'Mehta Hardware and Sanitary Stores',
        'Lakshmi Foods and Beverages',
      ].indexed)
        carrierBooking('trip-open', 'b$index', shipper: name, drop: 'Hosur'),
      {
        ...carrierBooking('trip-open', 'w1',
            shipper: 'Ravi Traders Wholesale',
            drop: 'Hosur',
            status: 'PENDING_CARRIER_ACCEPT'),
        'readyToAccept': true,
      },
    ]);
    await mountCarrierApp(tester, '/driver/trip/trip-open/active',
        size: const Size(360, 800), textScale: 2);
    expect(tester.takeException(), isNull);
    const bannerWords =
        'NaviG8r is checking your company. Until it is approved, you cannot accept bookings or start trips.';
    expect(find.text(bannerWords), findsOneWidget, reason: 'all text is kept');
    final bannerBox = tester.getRect(find
        .ancestor(of: find.text(bannerWords), matching: find.byType(Scrollable))
        .first);
    expect(bannerBox.height, lessThanOrEqualTo(800 / 4));
    final start = tester.getRect(find.text('Start trip'));
    expect(start.bottom, lessThanOrEqualTo(800),
        reason: 'Start trip is on screen');
  });

  testWidgets('C7: after a Start that works, the trip bookings load again',
      (tester) async {
    final server = signInToCarrierApp(CarrierServer(
      allowed: ownerAllowed,
      subrole: 'OWNER',
      trips: [carrierTrip('trip-today')],
      bookings: [
        carrierBooking('trip-today', 'guindy',
            shipper: 'Sharma Textiles', drop: 'Guindy', bill: finalBill())
      ],
    ));
    final asked = <String>[];
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      asked.add('${request.method} ${request.path}');
      if (request.path == '/v1/pilot/anchor-trips/trip-today/start') {
        return jsonResponse({
          'trip': {...server.trips.first, 'status': 'IN_PROGRESS'}
        });
      }
      return server.answer(request);
    });
    await mountCarrierApp(tester, '/driver/trip/trip-today/active',
        size: const Size(400, 1600));
    await tester.tap(find.text('Start trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start trip').last);
    await tester.pumpAndSettle();
    final started =
        asked.indexOf('POST /v1/pilot/anchor-trips/trip-today/start');
    expect(started, isNot(-1));
    expect(asked.sublist(started + 1),
        contains('GET /v1/pilot/carrier/shipments'));
  });

  testWidgets(
      'C8: Home does not ask a company NaviG8r has not approved to accept a booking',
      (tester) async {
    signInAtApproval('SUBMITTED', trips: [
      carrierTrip('trip-today')
    ], bookings: [
      carrierBooking('trip-today', 'waiting',
          shipper: 'Sharma Textiles',
          drop: 'Hosur',
          status: 'PENDING_CARRIER_ACCEPT'),
    ]);
    await mountCarrierApp(tester, '/driver', size: const Size(400, 1600));
    expect(find.text('Accept a booking'), findsNothing);
  });

  testWidgets(
      'C9: a booking whose trip already names its truck says Accept, not choose the truck',
      (tester) async {
    signInToCarrierApp(CarrierServer(
      allowed: ownerAllowed,
      subrole: 'OWNER',
      trips: [carrierTrip('trip-today')],
      bookings: [
        carrierBooking('trip-today', 'waiting',
            shipper: 'Sharma Textiles',
            drop: 'Hosur',
            status: 'PENDING_CARRIER_ACCEPT'),
      ],
    ));
    final router = await mountCarrierApp(tester, '/driver/shipments',
        size: const Size(400, 1600));
    expect(screenWords(tester), contains('Next: accept.'));
    expect(screenWords(tester), isNot(contains('choose the truck')));

    await openPath(tester, router, '/driver/shipment/waiting');
    final steps = tester.widget<NvStepList>(find.byType(NvStepList)).steps;
    expect(steps.first.title, 'Accept');
  });

  testWidgets(
      'C10: Trips does not say the truck is chosen at the first accept once a booking was accepted',
      (tester) async {
    signInToCarrierApp(CarrierServer(
      allowed: ownerAllowed,
      subrole: 'OWNER',
      trips: [carrierTrip('trip-today', truck: '')],
      bookings: [
        carrierBooking('trip-today', 'accepted',
            shipper: 'Sharma Textiles', drop: 'Hosur'),
      ],
    ));
    await mountCarrierApp(tester, '/driver/loads', size: const Size(400, 1600));
    expect(find.text('You choose the truck when you accept the first booking'),
        findsNothing);
  });

  testWidgets(
      'C10 (D11): Trips never tells a driver they choose the truck',
      (tester) async {
    signInToCarrierApp(CarrierServer(
      allowed: driverAllowed,
      subrole: 'DRIVER',
      trips: [carrierTrip('trip-today', truck: '')],
    ));
    await mountCarrierApp(tester, '/driver/loads', size: const Size(400, 1600));
    expect(find.text('Bengaluru to Chennai'), findsOneWidget);
    expect(find.text('You choose the truck when you accept the first booking'),
        findsNothing);
  });

  testWidgets(
      'C11: inviting a dispatcher says so, and the form clears its role and capacity',
      (tester) async {
    signInToCarrierApp(CarrierServer(allowed: ownerAllowed, subrole: 'OWNER'));
    await mountCarrierApp(tester, '/driver/fleet', size: const Size(400, 1600));
    final phone =
        find.widgetWithText(TextField, "Driver's mobile number (10 digits)");

    await tester.enterText(phone, '9845012399');
    await tester.tap(find.text('Dispatcher'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite dispatcher'));
    await tester.pumpAndSettle();
    expect(find.text('Dispatcher invited to your company.'), findsOneWidget);
    expect(find.text('Driver invited to your company.'), findsNothing);
    expect(find.text('Invite dispatcher'), findsNothing,
        reason: 'the role is cleared, so the button reads Invite');
    expect(find.text('Invite'), findsOneWidget);
    // The next snack bar waits for this one to go.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.enterText(phone, '9845012400');
    await tester.tap(find.text('Driver'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck registration number'),
        'KA01AB9999');
    await tester.tap(find.text('Medium'));
    await tester.enterText(
        find.widgetWithText(TextField, 'Truck capacity (kg)'), '1000');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invite driver'));
    await tester.pumpAndSettle();
    expect(find.text('Driver invited to your company.'), findsOneWidget);
    await tester.tap(find.text('Driver'));
    await tester.pumpAndSettle();
    final capacity = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Truck capacity (kg)'));
    expect(capacity.controller!.text, isEmpty);
  });

  testWidgets(
      'C12: a transporter ID that failed to load has Try again, which loads it',
      (tester) async {
    var fails = true;
    final server = signInToCarrierApp(
        CarrierServer(allowed: ownerAllowed, subrole: 'OWNER'));
    api.dio.httpClientAdapter = MockApiAdapter((request) {
      if (request.path == '/v1/pilot/me') {
        return fails
            ? jsonResponse({'error': 'unavailable'}, 500)
            : jsonResponse({
                'organizations': [
                  {...carrierOrganization, 'transporterId': '29ABCDE1234F1Z5'}
                ],
              });
      }
      return server.answer(request);
    });
    await mountCarrierApp(tester, '/driver/profile',
        size: const Size(400, 2400));
    expect(find.text('Could not load the transporter ID.'), findsOneWidget);
    expect(find.textContaining('Go back, then open this page again'),
        findsNothing);

    fails = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load the transporter ID.'), findsNothing);
    expect(find.text('29ABCDE1234F1Z5'), findsOneWidget);
    expect(find.text('Change transporter ID'), findsOneWidget);
  });
}

