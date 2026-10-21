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

import 'support/carrier_fixtures.dart';
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

Future<void> mountScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(theme: DriverTheme.theme(), home: Scaffold(body: screen)));
  await tester.pumpAndSettle();
}

void main() {
  group('The home screen', () {
    testWidgets('promises a signed-in driver no pay', (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = MockApiAdapter(
          (_) => jsonResponse({'shipments': <Object>[], 'trips': <Object>[]}));
      await mountScreen(tester, const DriverWelcomeScreen());
      expect(find.text('No trip today.'), findsOneWidget,
          reason: 'PR 8: a driver\'s home is Today (dr-today)');
      final words = screenWords(tester);
      expect(words.contains('paid'), isFalse, reason: words);
      expect(words.contains('cooling-off'), isFalse, reason: words);
    });

    testWidgets(
        'shows a signed-out visitor the sign-in, and the office its Home',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      api = Api('http://test');
      AuthorizationSession.clear();
      await mountScreen(
          tester, const DriverWelcomeScreen(key: ValueKey('signed out')));
      expect(find.text('Sign in with your phone'), findsOneWidget,
          reason: 'PR 3: signed out, Home is the sign-in');
      expect(paymentWords.hasMatch(screenWords(tester)), isFalse,
          reason: 'the sign-in promises no pay');

      signInAsCarrierLogin(office: true);
      api.dio.httpClientAdapter = MockApiAdapter(
          (_) => jsonResponse({'shipments': <Object>[], 'trips': <Object>[]}));
      await mountScreen(
          tester, const DriverWelcomeScreen(key: ValueKey('office')));
      expect(find.text('Nothing needs you right now.'), findsOneWidget,
          reason: 'ca-home: signed in, the office gets its Home');
      expect(find.text('Sign in with phone'), findsNothing,
          reason: 'copy.md: the signed-in home has no sign-in links');
    });
  });

  group('The shipment screen', () {
    testWidgets('shows no net line at all when the amount is not sent',
        (tester) async {
      signInAsCarrierLogin(office: false);
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [shipmentOnTripA()]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Hosur'), findsOneWidget,
          reason: 'the shipment loaded (PR 8: Drop is a fact row)');
      expect(find.textContaining('Net to carrier'), findsNothing);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets('shows the amount to the owner, who is sent it',
        (tester) async {
      signInAsCarrierOwner();
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [shipmentOnTripA(netToCarrierPaise: 4500)]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('You receive'), findsOneWidget,
          reason: 'ca-booking-owner: the amount the carrier API sends');
      expect(find.text('₹45'), findsOneWidget);
    });

    /// What the server sends after proof of delivery; it leaves the payment hold out for a driver.
    Map<String, dynamic> deliveredShipment({required bool withPaymentHold}) => {
          ...shipmentOnTripA(),
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
      expect(find.text('Delivery confirmed'), findsOneWidget,
          reason: 'PR 8: the status word says the delivery is confirmed');
      for (final payout in [
        'Payment on hold',
        'NaviG8r checks it, then pays the carrier',
        'Paid to the carrier',
        'Payment released'
      ]) {
        expect(find.textContaining(payout), findsNothing, reason: payout);
      }
    });

    testWidgets('tells the owner the payment waits for release',
        (tester) async {
      signInAsCarrierOwner();
      api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
            'shipments': [deliveredShipment(withPaymentHold: true)]
          }));
      await mountScreen(
          tester, const DriverShipmentDetailScreen(shipmentId: 'shipment-a'));
      expect(find.text('Delivery confirmed'), findsOneWidget,
          reason: 'the delivery step is done');
      expect(
          find.text(
              'NaviG8r checks the delivery, then sends the payment to your bank account.'),
          findsOneWidget,
          reason:
              'copy.md payment (owner only), without the bank digits the API does not send');
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
      api.dio.httpClientAdapter = tripServer(shipmentOnTripA());
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.textContaining('₹'), findsNothing);
    });

    testWidgets(
        'shows the office each booking by its status word, with no amount (PR 7, ca-trip)',
        (tester) async {
      signInAsCarrierOwner();
      api.dio.httpClientAdapter =
          tripServer(shipmentOnTripA(netToCarrierPaise: 4500));
      await mountScreen(tester, const DriverActiveTripScreen(tripId: 'trip-a'));
      expect(find.text('Accepted'), findsOneWidget,
          reason: 'ca-trip: a status word on each booking');
      expect(find.textContaining('₹'), findsNothing,
          reason: 'ca-trip shows no amounts; the booking screen has them');
    });
  });

  group('The Profile screen', () {
    /// The screen refreshes the session first, so the server answers with the same login.
    MockApiAdapter profileServer(
            {required bool office, List<String> alsoAllowed = const []}) =>
        MockApiAdapter((request) => request.path == '/v1/auth/me'
            ? jsonResponse({
                'user': {
                  'id': 'carrier-person',
                  'fullName': 'Synthetic Person'
                },
                'organizations': [carrierOrganization],
                'principal':
                    carrierPrincipal(office: office, alsoAllowed: alsoAllowed),
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
      expect(find.text('Your truck'), findsOneWidget,
          reason: 'the screen loaded');
      expect(find.text('Earnings and payments'), findsNothing);
    });

    testWidgets(
        'keeps it for the owner only, beside the bank details (PR 7: dispatchers do not see payments)',
        (tester) async {
      const office = ['trip.assign'];
      const owner = [...office, 'bank_account.create_token'];
      for (final allowed in [owner, office]) {
        signInAsCarrierLogin(office: true, alsoAllowed: allowed);
        api.dio.httpClientAdapter =
            profileServer(office: true, alsoAllowed: allowed);
        await mountScreen(
            tester, DriverProfileScreen(key: ValueKey(allowed.length)));
        expect(find.text('Earnings and payments'),
            allowed == owner ? findsOneWidget : findsNothing,
            reason: allowed == owner ? 'owner' : 'dispatcher');
      }
    });
  });

  group('No payment word reaches a driver, and the office keeps its wording',
      () {
    final delivered = <String, dynamic>{
      ...shipmentOnTripA(),
      'status': 'PENDING_RELEASE',
      'podAtUtcMs': 1760500000000,
    };

    testWidgets('on the shipment screen', (tester) async {
      for (final office in [false, true]) {
        office ? signInAsCarrierOwner() : signInAsCarrierLogin(office: false);
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
          expect(words, contains('Waiting for payment'));
          expect(words, contains('sends the payment to your bank account'));
        } else {
          expect(words, contains('Delivery confirmed'));
          expect(paymentWords.hasMatch(words), isFalse, reason: words);
        }
      }
    });

    testWidgets('on the Bookings list', (tester) async {
      for (final office in [false, true]) {
        office ? signInAsCarrierOwner() : signInAsCarrierLogin(office: false);
        api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
              'shipments': [delivered]
            }));
        await mountScreen(tester, DriverShipmentsScreen(key: ValueKey(office)));
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        final words = screenWords(tester);
        expect(words, contains('Bengaluru to Hosur'),
            reason: 'the delivered booking is under Done');
        if (office) {
          expect(words, contains('Waiting for payment'));
        } else {
          expect(words, contains('Delivery confirmed'));
          expect(paymentWords.hasMatch(words), isFalse, reason: words);
        }
      }
    });

    testWidgets('on the trip screen', (tester) async {
      for (final office in [false, true]) {
        // The owner, since PR 6 words the status for owners only (ca-booking-owner).
        office ? signInAsCarrierOwner() : signInAsCarrierLogin(office: false);
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
          expect(words, contains('Waiting for payment'));
        } else {
          expect(words, contains('Delivery confirmed'));
          expect(paymentWords.hasMatch(words), isFalse, reason: words);
        }
      }
    });

    testWidgets('on the proof of delivery screen', (tester) async {
      // PR 8 words them as copy.md does: the owner is told about the payment, a dispatcher that the owner sees
      // it, a driver neither.
      for (final (reader, signIn, expected) in [
        (
          'owner',
          () => signInAsCarrierOwner(),
          'NaviG8r checks the delivery, then sends the payment to your bank account.'
        ),
        (
          'dispatcher',
          () => signInAsCarrierLogin(office: true),
          'NaviG8r checks the delivery. The owner sees the payment.'
        ),
        (
          'driver',
          () => signInAsCarrierLogin(office: false),
          'This tells NaviG8r the goods are handed over.'
        ),
      ]) {
        signIn();
        api.dio.httpClientAdapter = MockApiAdapter((_) => jsonResponse({
              'shipments': [shipmentOnTripA()]
            }));
        await mountScreen(tester,
            DriverPodScreen(key: ValueKey(reader), shipmentId: 'shipment-a'));
        final words = screenWords(tester);
        expect(words, contains(expected), reason: reader);
        if (reader == 'driver') {
          expect(paymentWords.hasMatch(words), isFalse, reason: words);
        }
      }
    });

    /// Confirm delivery from the booking screen, as in the app, so the booking screen says what happened.
    Future<String> wordsAfterConfirming(WidgetTester tester) async {
      var status = 'BOOKED';
      api.dio.httpClientAdapter = MockApiAdapter((request) {
        if (request.method == 'POST') {
          status = 'PENDING_RELEASE';
          return jsonResponse({'shipment': delivered});
        }
        return jsonResponse({
          'shipments': [shipmentOnTripA(status: status)]
        });
      });
      final router = GoRouter(initialLocation: '/', routes: [
        GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
                body: DriverShipmentDetailScreen(shipmentId: 'shipment-a')),
            routes: [
              GoRoute(
                  path: 'driver/shipment/:id/pod',
                  builder: (_, __) => const Scaffold(
                      body: DriverPodScreen(shipmentId: 'shipment-a'))),
            ]),
      ]);
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp.router(theme: DriverTheme.theme(), routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
      await tester.pumpAndSettle();
      return screenWords(tester);
    }

    testWidgets('in the message after a driver confirms delivery',
        (tester) async {
      signInAsCarrierLogin(office: false, alsoAllowed: ['pod.upload']);
      final words = await wordsAfterConfirming(tester);
      expect(words, contains('Delivery confirmed.'));
      expect(paymentWords.hasMatch(words), isFalse, reason: words);
    });

    testWidgets('in the message after the owner confirms delivery',
        (tester) async {
      signInAsCarrierOwner(alsoAllowed: ['pod.upload']);
      final words = await wordsAfterConfirming(tester);
      expect(
          words,
          contains(
              'Delivery confirmed. NaviG8r checks it, then releases the payment.'),
          reason: 'owners only since PR 8; dispatchers are not told about payments');
    });
  });
}
