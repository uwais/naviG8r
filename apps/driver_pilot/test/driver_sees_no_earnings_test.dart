// Owner decision, 15 Oct 2026: a driver never sees carrier earnings. The server leaves the amounts out for a
// driver and refuses the earnings routes; these check the app shows no made-up zero and no way in.
import 'package:driver_pilot/authorization_session.dart';
import 'package:driver_pilot/driver_flow.dart';
import 'package:driver_pilot/driver_theme.dart';
import 'package:driver_pilot/pilot_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'support/eway_bill_fixtures.dart';
import 'support/mock_api.dart';

/// Any word about the carrier's pay, whatever its case: a check by exact text passed with payment words on screen.
final paymentWords = RegExp(
    r'payment|ledger|earn|net to carrier|net-to-carrier',
    caseSensitive: false);

/// Every word the screen shows right now, snackbars included.
String screenWords(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
    .join('\n');

const carrierOrganization = {
  'id': 'carrier-a',
  'kind': 'CARRIER_FLEET',
  'displayName': 'Synthetic Carrier A',
  'kycStatus': 'APPROVED',
};

/// A driver holds no payment.read; the carrier office does.
Map<String, dynamic> carrierPrincipal({required bool office}) => {
      'organizationId': 'carrier-a',
      'roles': ['CARRIER'],
      'subrole': office ? 'OWNER' : 'DRIVER',
      'permissions': [
        'organization.profile.read',
        'load.read',
        if (office) 'payment.read',
      ],
    };

void signInAsCarrierLogin({required bool office}) {
  FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
  api = Api('http://test');
  AuthorizationSession.clear();
  AuthorizationSession.user = {'id': 'carrier-person'};
  AuthorizationSession.principal = carrierPrincipal(office: office);
  AuthorizationSession.organizations = [carrierOrganization];
  api.selectOrganization('carrier-a');
}

Map<String, dynamic> bookedShipment({int? netToCarrierPaise}) => {
      ...shipment(),
      'anchorTripId': 'trip-a',
      'weightKg': 120,
      'pickupAddress': 'Peenya, Bengaluru',
      'dropAddress': 'Hosur',
      if (netToCarrierPaise != null) 'netToCarrierPaise': netToCarrierPaise,
    };

Future<void> mountScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(theme: DriverTheme.theme(), home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

void main() {
  group('The shipment screen', () {
    testWidgets('shows no net line at all when the amount is not sent',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [bookedShipment()]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Drop: Hosur'), findsOneWidget,
          reason: 'the shipment loaded');
      expect(find.textContaining('Net to carrier'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('shows the amount to the office, who is sent it',
        (tester) async {
      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [bookedShipment(netToCarrierPaise: 4500)]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Net to carrier: ₹45'), findsOneWidget);
    });

    /// What the server sends after proof of delivery; it leaves the payment hold out for a driver.
    Map<String, dynamic> deliveredShipment({required bool withPaymentHold}) => {
          ...bookedShipment(),
          'status': 'PENDING_RELEASE',
          'podAtUtcMs': 1760500000000,
          if (withPaymentHold) ...{
            'paymentReady': false,
            'paymentHoldUntilUtcMs': 1760672800000,
          },
        };

    testWidgets(
        'tells a driver delivery was confirmed, without the payment hold or release lines',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [deliveredShipment(withPaymentHold: false)]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Proof of delivery submitted'), findsOneWidget);
      for (final payout in [
        'Payment on hold',
        'Ready for Finance review',
        'Payment released'
      ]) {
        expect(find.textContaining(payout), findsNothing, reason: payout);
      }
    });

    testWidgets('tells the office when the payment is held', (tester) async {
      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [deliveredShipment(withPaymentHold: true)]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Proof of delivery submitted'), findsOneWidget);
      expect(find.textContaining('Payment on hold until'), findsOneWidget);
    });
  });

  group('The trip screen', () {
    MockApiAdapter tripServer(Map<String, dynamic> onTrip) => MockApiAdapter(
        (request) => request.path == '/v1/pilot/anchor-trips/trip-a'
            ? jsonResponse({
                'trip': {'id': 'trip-a', 'status': 'OPEN'}
              })
            : jsonResponse({
                'shipments': [onTrip]
              }));

    testWidgets('lists a shipment by its status alone when no amount is sent',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = tripServer(bookedShipment());
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('adds the amount for the office', (tester) async {
      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter =
          tripServer(bookedShipment(netToCarrierPaise: 4500));
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(find.text('Accepted · ₹45 net'), findsOneWidget);
    });
  });

  group('The Profile screen', () {
    /// The screen refreshes the session first, so the server answers with the same login.
    MockApiAdapter profileServer({required bool office}) =>
        MockApiAdapter((request) => request.path == '/v1/auth/me'
            ? jsonResponse({
                'user': {
                  'id': 'carrier-person',
                  'fullName': 'Synthetic Person'
                },
                'organizations': [carrierOrganization],
                'principal': carrierPrincipal(office: office),
              })
            : jsonResponse({
                'driverProfile': {'primaryVehicleId': 'vehicle-1'},
                'vehicles': [
                  {
                    'id': 'vehicle-1',
                    'registrationNumber': 'KA01AB1234',
                    'vehicleClass': 'MEDIUM',
                    'capacityKg': 1000
                  }
                ],
              }));

    testWidgets('has no way into earnings or payouts for a driver',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = profileServer(office: false);
      await mountScreen(tester, const DriverProfileScreen());
      expect(find.text('Your vehicle'), findsOneWidget,
          reason: 'the screen loaded');
      expect(find.text('Earnings & payouts'), findsNothing);
    });

    testWidgets('keeps it for the office', (tester) async {
      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter = profileServer(office: true);
      await mountScreen(tester, const DriverProfileScreen());
      expect(find.text('Earnings & payouts'), findsOneWidget);
    });
  });

  test(
      'a driver reads statuses without payment; the office reads them as before',
      () {
    expect(shipmentStatusLabel('PENDING_RELEASE', seesPayment: false),
        'Delivery confirmed');
    expect(shipmentStatusLabel('FAILED_CARRIER_REFUNDED', seesPayment: false),
        'Cancelled');
    expect(shipmentStatusLabel('PENDING_RELEASE'), 'Awaiting payment release');
    expect(shipmentStatusLabel('FAILED_CARRIER_REFUNDED'),
        'FAILED_CARRIER_REFUNDED');
  });

  group('No payment word reaches a driver, and the office keeps its wording',
      () {
    final delivered = <String, dynamic>{
      ...bookedShipment(),
      'status': 'PENDING_RELEASE',
      'podAtUtcMs': 1760500000000,
    };

    testWidgets('on the shipment screen', (tester) async {
      for (final office in [false, true]) {
        signInAsCarrierLogin(office: office);
        api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
              'shipments': [
                {
                  ...delivered,
                  if (office) ...{
                    'paymentReady': false,
                    'paymentHoldUntilUtcMs': 1760672800000,
                  },
                }
              ]
            }));
        await mountScreen(
            tester,
            DriverShipmentDetailScreen(
                key: ValueKey(office), shipmentId: 'shipment-a'));
        final words = screenWords(tester);
        if (office) {
          expect(words, contains('Status: Awaiting payment release'));
          expect(words, contains('Payment on hold until'));
        } else {
          expect(words, contains('Status: Delivery confirmed'));
          expect(paymentWords.hasMatch(words), isFalse, reason: words);
        }
      }
    });

    testWidgets('on the Shipments list', (tester) async {
      for (final office in [false, true]) {
        signInAsCarrierLogin(office: office);
        api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
              'shipments': [delivered]
            }));
        await mountScreen(tester, DriverShipmentsScreen(key: ValueKey(office)));
        final words = screenWords(tester);
        if (office) {
          expect(
              words, contains('Awaiting payment release · Peenya, Bengaluru'));
        } else {
          expect(words, contains('Delivery confirmed · Peenya, Bengaluru'));
          expect(paymentWords.hasMatch(words), isFalse, reason: words);
        }
      }
    });

    testWidgets('on the trip screen', (tester) async {
      for (final office in [false, true]) {
        signInAsCarrierLogin(office: office);
        api.dio.httpClientAdapter = MockApiAdapter(
            (request) => request.path == '/v1/pilot/anchor-trips/trip-a'
                ? jsonResponse({
                    'trip': {'id': 'trip-a', 'status': 'OPEN'}
                  })
                : jsonResponse({
                    'shipments': [delivered]
                  }));
        await mountScreen(tester,
            DriverActiveTripScreen(key: ValueKey(office), tripId: 'trip-a'));
        final words = screenWords(tester);
        if (office) {
          expect(words, contains('Awaiting payment release'));
          expect(words, contains('Payment pending'));
        } else {
          expect(words, contains('Delivery confirmed'));
          expect(paymentWords.hasMatch(words), isFalse, reason: words);
        }
      }
    });

    testWidgets('on the proof of delivery screen', (tester) async {
      for (final office in [false, true]) {
        signInAsCarrierLogin(office: office);
        await mountScreen(tester,
            DriverPodScreen(key: ValueKey(office), shipmentId: 'shipment-a'));
        final words = screenWords(tester);
        if (office) {
          expect(
              words,
              contains(
                  'Ops will release customer payment to your carrier ledger after review.'));
        } else {
          expect(
              words,
              contains(
                  'Confirming delivery sends your proof of delivery to naviG8r.'));
          expect(paymentWords.hasMatch(words), isFalse, reason: words);
        }
      }
    });

    /// The proof of delivery screen pushed over the trip, as in the app, so confirming can go back to it.
    Future<String> wordsAfterConfirming(WidgetTester tester) async {
      api.dio.httpClientAdapter =
          MockApiAdapter((_) => jsonResponse({'shipment': delivered}));
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('Trip')),
            routes: [
              GoRoute(
                  path: 'pod',
                  builder: (_, __) => const Scaffold(
                      body: DriverPodScreen(shipmentId: 'shipment-a'))),
            ]),
      ]);
      await tester.pumpWidget(
          MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
      router.push('/pod');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm POD'));
      await tester.pumpAndSettle();
      return screenWords(tester);
    }

    testWidgets('in the message after a driver confirms delivery',
        (tester) async {
      signInAsCarrierLogin(office: false);
      final words = await wordsAfterConfirming(tester);
      expect(words, contains('Delivery confirmed.'));
      expect(paymentWords.hasMatch(words), isFalse, reason: words);
    });

    testWidgets('in the message after the office confirms delivery',
        (tester) async {
      signInAsCarrierLogin(office: true);
      final words = await wordsAfterConfirming(tester);
      expect(
          words,
          contains(
              'Delivery confirmed. Payment will be released after ops review.'));
    });
  });
}
